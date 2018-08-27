require 'puppet/ssl'
require 'puppet/ssl/key'
require 'puppet/ssl/certificate'
require 'puppet/ssl/certificate_request'
require 'puppet/ssl/certificate_request_attributes'
require 'puppet/rest/errors'
require 'puppet/rest/routes'
require 'puppet/rest/ssl_context'
begin
  # This may fail when being loaded from Puppet Server. However loading the
  # client monkey patches the SSL Store and we need to have those monkey
  # patches in as soon as possible on the agent.
  require 'puppet/rest/client'
rescue LoadError
end

# The class that manages all aspects of our SSL certificates --
# private keys, public keys, requests, etc.
class Puppet::SSL::Host
  # Yay, ruby's strange constant lookups.
  Key = Puppet::SSL::Key
  CA_NAME = Puppet::SSL::CA_NAME
  Certificate = Puppet::SSL::Certificate
  CertificateRequest = Puppet::SSL::CertificateRequest

  attr_reader :name, :crl_path
  attr_accessor :ca

  attr_writer :key, :certificate, :certificate_request, :crl_usage

  # This accessor is used in instances for indirector requests to hold desired state
  attr_accessor :desired_state

  def self.localhost
    return @localhost if @localhost
    @localhost = new
    @localhost.generate unless @localhost.certificate
    @localhost.key
    @localhost
  end

  def self.reset
    @localhost = nil
  end

  # Configure how our various classes interact with their various terminuses.
  def self.configure_indirection(terminus, cache = nil)
    Certificate.indirection.terminus_class = terminus
    CertificateRequest.indirection.terminus_class = terminus

    if cache
      # This is weird; we don't actually cache our keys, we
      # use what would otherwise be the cache as our normal
      # terminus.
      Key.indirection.terminus_class = cache
    else
      Key.indirection.terminus_class = terminus
    end

    if cache
      Certificate.indirection.cache_class = cache
      CertificateRequest.indirection.cache_class = cache
    else
      # Make sure we have no cache configured.  puppet master
      # switches the configurations around a bit, so it's important
      # that we specify the configs for absolutely everything, every
      # time.
      Certificate.indirection.cache_class = nil
      CertificateRequest.indirection.cache_class = nil
    end
  end

  # Puppet::SSL::Host is actually indirected now so the original implementation
  # has been moved into the certificate_status indirector.  This method is in-use
  # in `puppet cert -c <certname>`.
  def self.destroy(name)
    indirection.destroy(name)
  end

  def self.from_data_hash(data)
    instance = new(data["name"])
    if data["desired_state"]
      instance.desired_state = data["desired_state"]
    end
    instance
  end

  def key
    @key ||= Key.indirection.find(name)
  end

  # This is the private key; we can create it from scratch
  # with no inputs.
  def generate_key
    @key = Key.new(name)
    @key.generate
    begin
      Key.indirection.save(@key)
    rescue
      @key = nil
      raise
    end
    true
  end

  # Our certificate request requires the key but that's all.
  def generate_certificate_request(options = {})
    generate_key unless key

    # If this CSR is for the current machine...
    if name == Puppet[:certname].downcase
      # ...add our configured dns_alt_names
      if Puppet[:dns_alt_names] and Puppet[:dns_alt_names] != ''
        options[:dns_alt_names] ||= Puppet[:dns_alt_names]
      end
    end

    csr_attributes = Puppet::SSL::CertificateRequestAttributes.new(Puppet[:csr_attributes])
    if csr_attributes.load
      options[:csr_attributes] = csr_attributes.custom_attributes
      options[:extension_requests] = csr_attributes.extension_requests
    end

    @certificate_request = CertificateRequest.new(name)
    @certificate_request.generate(key.content, options)
    begin
      submit_certificate_request(@certificate_request)
      save_certificate_request_to_disk(@certificate_request)
    rescue
      @certificate_request = nil
      raise
    end

    true
  end

  def http_client(ssl_context)
    Puppet::Rest::Client.new(ssl_context: ssl_context)
  end

  def certificate
    unless @certificate
      generate_key unless key

      # get the CA cert first, since it's required for the normal cert
      # to be of any use. If we can't get it, quit.
      if !ensure_ca_certificate
        return nil
      end

      @certificate = get_host_certificate
      return nil unless @certificate

      validate_certificate_with_key
    end
    @certificate
  end

  def validate_certificate_with_key
    raise Puppet::Error, _("No certificate to validate.") unless certificate
    raise Puppet::Error, _("No private key with which to validate certificate with fingerprint: %{fingerprint}") % { fingerprint: certificate.fingerprint } unless key
    unless certificate.content.check_private_key(key.content)
      raise Puppet::Error, _(<<ERROR_STRING) % { fingerprint: certificate.fingerprint, cert_name: Puppet[:certname], ssl_dir: Puppet[:ssldir], cert_dir: Puppet[:certdir].gsub('/', '\\') }
The certificate retrieved from the master does not match the agent's private key. Did you forget to run as root?
Certificate fingerprint: %{fingerprint}
To fix this, remove the certificate from both the master and the agent and then start a puppet run, which will automatically regenerate a certificate.
On the master:
  puppet cert clean %{cert_name}
On the agent:
  1a. On most platforms: find %{ssl_dir} -name %{cert_name}.pem -delete
  1b. On Windows: del "%{cert_dir}\\%{cert_name}.pem" /f
  2. puppet agent -t
ERROR_STRING
    end
  end

  # Search for an existing CSR for this host either cached on
  # disk or stored by the CA. Returns nil if no request exists.
  # @return [Puppet::SSL::CertificateRequest, nil]
  def certificate_request
    unless @certificate_request
      if csr = load_certificate_request_from_file
        @certificate_request = csr
      elsif csr = download_csr_from_ca
        @certificate_request = csr
      end
    end
    @certificate_request
  end

  # Generate all necessary parts of our ssl host.
  def generate
    generate_key unless key

    existing_request = certificate_request

    # if CSR downloaded from master, but the local keypair was just generated and
    # does not match the public key in the CSR, fail hard
    if !existing_request.nil? &&
      (key.content.public_key.to_s != existing_request.content.public_key.to_s)

      raise Puppet::Error, _(<<ERROR_STRING) % { fingerprint: existing_request.fingerprint, csr_public_key: existing_request.content.public_key.to_text, agent_public_key: key.content.public_key.to_text, cert_name: Puppet[:certname], ssl_dir: Puppet[:ssldir], cert_dir: Puppet[:certdir].gsub('/', '\\') }
The CSR retrieved from the master does not match the agent's public key.
CSR fingerprint: %{fingerprint}
CSR public key: %{csr_public_key}
Agent public key: %{agent_public_key}
To fix this, remove the CSR from both the master and the agent and then start a puppet run, which will automatically regenerate a CSR.
On the master:
  puppet cert clean %{cert_name}
On the agent:
  1a. On most platforms: find %{ssl_dir} -name %{cert_name}.pem -delete
  1b. On Windows: del "%{cert_dir}\\%{cert_name}.pem" /f
  2. puppet agent -t
ERROR_STRING
    end
    generate_certificate_request unless existing_request

    # See if we have a certificate, or try to download one
    certificate
  end

  def initialize(name = nil)
    @name = (name || Puppet[:certname]).downcase
    Puppet::SSL::Base.validate_certname(@name)
    @key = @certificate = @certificate_request = nil
    @crl_usage = Puppet.settings[:certificate_revocation]
    @crl_path = Puppet.settings[:hostcrl]
  end

  # Extract the public key from the private key.
  def public_key
    key.content.public_key
  end

  def use_crl?
    !!@crl_usage
  end

  def use_crl_chain?
    @crl_usage == true || @crl_usage == :chain
  end

  # Create/return a store that uses our SSL info to validate
  # connections.
  def ssl_store(purpose = OpenSSL::X509::PURPOSE_ANY)
    if @ssl_store.nil?
      @ssl_store = build_ssl_store(purpose)
    end
    @ssl_store
  end

  # Attempt to retrieve a cert, if we don't already have one.
  def wait_for_cert(time)
    begin
      return if certificate
      generate
      return if certificate
    rescue StandardError => detail
      Puppet.log_exception(detail, _("Could not request certificate: %{message}") % { message: detail.message })
      if time < 1
        puts _("Exiting; failed to retrieve certificate and waitforcert is disabled")
        exit(1)
      else
        sleep(time)
      end
      retry
    end

    if time < 1
      puts _("Exiting; no certificate found and waitforcert is disabled")
      exit(1)
    end

    while true
      sleep time
      begin
        break if certificate
        Puppet.notice _("Did not receive certificate")
      rescue StandardError => detail
        Puppet.log_exception(detail, _("Could not request certificate: %{message}") % { message: detail.message })
      end
    end
  end

  private

  # Saves the given certificate to disc, at a location determined by this
  # host's configuration.
  # @param [Puppet::SSL::Certificate] cert the cert to save
  def save_host_certificate(cert)
    file_path = certificate_location(name)
    Puppet::Util.replace_file(file_path, 0644) do |f|
      f.write(cert.to_s)
    end
  end

  # Load a previously generated CSR either from memory or from disk
  # @return [Puppet::SSL::CertificateRequest, nil]
  def load_certificate_request_from_file
    request_path = certificate_request_location(name)
    if Puppet::FileSystem.exist?(request_path)
      Puppet::SSL::CertificateRequest.from_s(Puppet::FileSystem.read(request_path))
    end
  end

  # Download the CSR for this host from the CA. Returns nil if the CA
  # has no saved CSR for this host.
  # @raises [Puppet::Error] if the response from the server is not a valid
  #                         CSR or an error occurs while fetching.
  # @return [Puppet::SSL::CertificateRequest, nil]
  def download_csr_from_ca
    begin
      body = Puppet::Rest::Routes.get_certificate_request(
                    http_client(Puppet::Rest::SSLContext.new(OpenSSL::SSL::VERIFY_PEER, ssl_store)),
                    name)
      begin
        Puppet::SSL::CertificateRequest.from_s(body)
      rescue OpenSSL::X509::RequestError => e
        raise Puppet::Error, _("Response from the CA did not contain a valid certificate request: %{message}") % { message: e.message }
      end
    rescue Puppet::Rest::ResponseError => e
      if e.response.status_code == 404
        nil
      else
        raise Puppet::Error, _('Could not download certificate request: %{message}') % { message: e.message }
      end
    end
  end

  # Submit the CSR to the CA, either via an HTTP PUT request
  # @param [Puppet::SSL::CertificateRequest] csr the request to submit
  def submit_certificate_request(csr)
    Puppet::Rest::Routes.put_certificate_request(
                  http_client(Puppet::Rest::SSLContext.new(OpenSSL::SSL::VERIFY_PEER, ssl_store)),
                  csr.render, name)
  end

  def save_certificate_request_to_disk(csr)
    Puppet::Util.replace_file(certificate_request_location(name), 0644) do |file|
      file.write(csr.render)
    end
  end

  # @param crl_string [String] CRLs read from disk or obtained from server
  # @return [Array<OpenSSL::X509::CRL>] CRLs from chain
  # @raise [Puppet::Error<OpenSSL::X509::CRLError>] if the CRL chain is malformed
  def process_crl_string(crl_string)
    delimiters = /-----BEGIN X509 CRL-----.*?-----END X509 CRL-----/m
    crl_string.scan(delimiters).map do |crl|
      begin
        OpenSSL::X509::CRL.new(crl)
      rescue OpenSSL::X509::CRLError => e
        raise Puppet::Error.new(
          _("Failed attempting to load CRL from %{crl_path}! The CRL below caused the error '%{error}':\n%{crl}" % {crl_path: crl_path, error: e.message, crl: crl}),
          e)
      end
    end
  end

  # @param path [String] Path to CRL Chain
  # @return [Array<OpenSSL::X509::CRL>] CRLs from chain
  # @raise [Puppet::Error<OpenSSL::X509::CRLError>] if the CRL chain is malformed
  def load_crls(path)
    crls_pems = Puppet::FileSystem.read(path, encoding: Encoding::UTF_8)
    process_crl_string(crls_pems)
  end

  # Ensures that the CA certificate is available for either generating or
  # validating the host's cert.
  # It will first check if the cert is present in memory (used for testing),
  # then check on disk, and finally try to download it.
  # @raise [Puppet::Error] if text form of found certificate bundle is invalid
  #                        and cannot be loaded into cert objects
  # @return [Boolean] true if the CA certificate was found, false otherwise
  def ensure_ca_certificate
    file_path = certificate_location(CA_NAME)
    if Puppet::FileSystem.exist?(file_path)
      begin
        # This load ensures that the file contents is a valid cert bundle.
        # If the text is malformed, load_certificate_bundle will raise.
        load_certificate_bundle(Puppet::FileSystem.read(file_path))
      rescue Puppet::Error => e
        raise Puppet::Error, _("The CA certificate at %{file_path} is invalid: %{message}") % { file_path: file_path, message: e.message }
      end
    else
      bundle = download_ca_certificate_bundle
      if bundle
        save_bundle(bundle, certificate_location(CA_NAME))
        true
      else
        false
      end
    end
  end

  # Creates an arry of SSL Certificate objects from a PEM-encoding string
  # of one or more certs.
  # @param [String] bundle_string PEM-encoded string of certs
  # @return [[OpenSSL::X509::Certificate], nil] the certs loaded from the
  #         input string, or nil if none could be loaded
  def load_certificate_bundle(bundle_string)
    delimiters = /-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m
    certs = bundle_string.scan(delimiters)

    if certs.empty?
      raise Puppet::Error, _("No valid PEM-encoded certificates.")
    end

    certs.map do |cert|
      begin
        OpenSSL::X509::Certificate.new(cert)
      rescue OpenSSL::X509::CertificateError => e
        raise Puppet::Error, _("Could not parse certificate: %{message}") % { message: e.message }
      end
    end
  end

  # Fetches and saves the crl bundle from the CA server without validating
  # its contents. Takes an optional store to use with the http_client,
  # necessary for initial download of the CRL because `build_ssl_store`
  # calls this `download_and_save_crl_bundle`. If there is an error during
  # this downloading process, the file should not be replaced at all. This
  # streams the file directly to disk to avoid loading the entire CRL in memory.
  # @param [OpenSSL::X509::Store] store optional ssl_store to use with http_client
  # @raise [Puppet::Error<Puppet::Rest::ResponseError>] if bad response from server
  # @return nil
  def download_and_save_crl_bundle(store=nil)
    begin
      # If no SSL store was suppoed, use this host's SSL store
      store ||= ssl_store
      client = http_client(Puppet::Rest::SSLContext.new(OpenSSL::SSL::VERIFY_PEER, store))
      Puppet::Util.replace_file(crl_path, 0644) do |file|
        Puppet::Rest::Routes.get_crls(client, CA_NAME) do |chunk|
          file.write(chunk)
        end
      end
    rescue Puppet::Rest::ResponseError => e
      raise Puppet::Error, _('Could not download CRLs: %{message}') % { message: e.message }
    end
  end

  # Fetches the CA certificate bundle from the CA server
  # @raise [Puppet::Error] if response from the server is not a valid certificate
  #                        bundle
  # @return [[OpenSSL::X509::Certificate]] the certs loaded from the response
  def download_ca_certificate_bundle
    begin
      cert_bundle = Puppet::Rest::Routes.get_certificate(
                    http_client(Puppet::Rest::SSLContext.new(OpenSSL::SSL::VERIFY_NONE)),
                    CA_NAME)
      # This load ensures that the response body is a valid cert bundle.
      # If the text is malformed, load_certificate_bundle will raise.
      begin
        load_certificate_bundle(cert_bundle)
      rescue Puppet::Error => e
        raise Puppet::Error, _("Response from the CA did not contain a valid CA certificate: %{message}") % { message: e.message }
      end
    rescue Puppet::Rest::ResponseError => e
      raise Puppet::Error, _('Could not download CA certificate: %{message}') % { message: e.message }
    end
  end

  # Saves the given bundle to disk to a specified file path.
  # @param bundle [[OpenSSL::X509::Certificate/CRL]] the certs to save
  # @param location [String] place on disk to save bundle
  def save_bundle(cert_bundle, location)
    Puppet::Util.replace_file(location, 0644) do |f|
      bundle_string = cert_bundle.map(&:to_pem).join("\n")
      f.write(bundle_string)
    end
  end

  # Attempts to load or fetch this host's certificate. Returns nil if
  # no certificate could be found.
  # @return [Puppet::SSL::Certificate, nil]
  def get_host_certificate
    if cert = check_for_certificate_on_disk(name)
      return cert
    elsif cert = download_certificate_from_ca(name)
      save_host_certificate(cert)
      return cert
    else
      return nil
    end
  end

  # Checks for the requested certificate on disc, at a location
  # determined by this host's configuration.
  # @name [String] name the name of the cert to look for
  # @raise [Puppet::Error] if contents of certificate file is invalid
  #                        and could not be loaded
  # @return [Puppet::SSL::Certificate, nil]
  def check_for_certificate_on_disk(cert_name)
    file_path = certificate_location(cert_name)
    if Puppet::FileSystem.exist?(file_path)
      begin
        Puppet::SSL::Certificate.from_s(Puppet::FileSystem.read(file_path))
      rescue OpenSSL::X509::CertificateError
        raise Puppet::Error, _("The certificate at %{file_path} is invalid. Could not load.") % { file_path: file_path }
      end
    end
  end

  # Attempts to download this host's certificate from the CA server.
  # Returns nil if the CA does not yet have a signed cert for this host.
  # @param [String] name then name of the cert to fetch
  # @raise [Puppet::Error] if response from the CA does not contain a valid
  #                        certificate
  # @return [Puppet::SSL::Certificate, nil]
  def download_certificate_from_ca(cert_name)
    begin
      cert = Puppet::Rest::Routes.get_certificate(
                    http_client(Puppet::Rest::SSLContext.new(OpenSSL::SSL::VERIFY_PEER, ssl_store)),
                    cert_name)
      begin
        Puppet::SSL::Certificate.from_s(cert)
      rescue OpenSSL::X509::CertificateError
        raise Puppet::Error, _("Response from the CA did not contain a valid certificate for %{cert_name}.") % { cert_name: cert_name }
      end
    rescue Puppet::Rest::ResponseError => e
      if e.response.status_code == 404
        Puppet.debug _("No certificate for %{cert_name} on CA") % { cert_name: cert_name }
        nil
      else
        raise Puppet::Rest::ResponseError, _("Could not download host certificate: %{message}") % { message: e.message }
      end
    end
  end

  # Returns the file path for the named certificate, based on this host's
  # configuration.
  # @param [String] name the name of the cert to find
  # @return [String] file path to the cert's location
  def certificate_location(cert_name)
    File.join(Puppet[:certdir], "#{cert_name}.pem")
  end

  # Returns the file path for the named CSR, based on this host's configuration.
  # @param [String] name the name of the CSR to find
  # @return [String] file path to the CSR's location
  def certificate_request_location(cert_name)
     File.join(Puppet[:requestdir], "#{cert_name}.pem")
  end

  # @param [OpenSSL::X509::PURPOSE_*] constant defining the kinds of certs
  #   this store can verify
  # @return [OpenSSL::X509::Store]
  # @raise [OpenSSL::X509::StoreError] if localcacert is malformed or non-existant
  # @raise [Puppet::Error] if the CRL chain is malformed
  # @raise [Errno::ENOENT] if the CRL does not exist on disk but use_crl? is true
  def build_ssl_store(purpose=OpenSSL::X509::PURPOSE_ANY)
    store = OpenSSL::X509::Store.new
    store.purpose = purpose

    # Use the file path here, because we don't want to cause
    # a lookup in the middle of setting our ssl connection.
    store.add_file(Puppet.settings[:localcacert])

    if use_crl?
      if !Puppet::FileSystem.exist?(crl_path)
        download_and_save_crl_bundle(store)
      end

      crls = load_crls(crl_path)

      flags = OpenSSL::X509::V_FLAG_CRL_CHECK
      if use_crl_chain?
        flags |= OpenSSL::X509::V_FLAG_CRL_CHECK_ALL
      end

      store.flags = flags
      crls.each {|crl| store.add_crl(crl) }
    end
    store
  end
end
