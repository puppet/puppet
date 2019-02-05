require 'puppet/x509'

# SSL Provider
#
# @api private
class Puppet::SSL::SSLProvider
  # Create an insecure `SSLContext`. Connections made from the returned context
  # will not authenticate the server, i.e. `VERIFY_NONE`, and are vulnerable to
  # MITM. Do not call this method.
  #
  # @return [Puppet::SSL::SSLContext] A context to use to create connections
  # @api private
  def create_insecure_context
    store = create_x509_store([], [], false)

    Puppet::SSL::SSLContext.new(store, [], [], nil, nil, [], Puppet::SSL::Validator.no_validator)
  end

  # Create an `SSLContext` using the trusted `cacerts` and optional `crls`.
  # Connections made from the returned context will authenticate the server,
  # i.e. `VERIFY_PEER`, but will not use a client certificate.
  #
  # The `crls` parameter must contain CRLs corresponding to each CA in `cacerts`
  # depending on the verification `mode`:
  #
  # :chain - `crls` must contain a CRL for every CA in `cacerts`
  # :leaf - `crls` must contain (at least) the CRL for the leaf CA in `cacerts`
  # false - `crls` can be empty
  #
  # @param cacerts [Array<OpenSSL::X509::Certificate>] Array of trusted CA certs
  # @param crls [Array<OpenSSL::X509::CRL>] Array of CRLs
  # @param mode [:chain, :leaf, false] verification mode
  # @return [Puppet::SSL::SSLContext] A context to use to create connections
  # @raise (see #create_context)
  # @api private
  def create_root_context(cacerts, crls = [], revocation: Puppet[:certificate_revocation])
    verify_cacerts(cacerts, crls, revocation)

    store = create_x509_store(cacerts, crls, revocation)
    Puppet::SSL::SSLContext.new(store, cacerts, crls, nil, nil, [], Puppet::SSL::Validator.default_validator)
  end

  # Create an `SSLContext` using the trusted `cacerts`, `crls`, `private_key`,
  # `client_cert`, and verification `mode`. Connections made from the returned
  # context will be mutually authenticated.
  #
  # The `crls` parameter must contain CRLs corresponding to each CA in `cacerts`
  # depending on the verification `mode`:
  #
  # :chain - `crls` must contain a CRL for every CA in `cacerts`
  # :leaf - `crls` must contain (at least) the CRL for the leaf CA in `cacerts`
  # false - `crls` can be empty
  #
  # The `private_key` and public key from the `client_cert` must match.
  #
  # @param cacerts [Array<OpenSSL::X509::Certificate>] Array of trusted CA certs
  # @param crls [Array<OpenSSL::X509::CRL>] Array of CRLs
  # @param private_key [OpenSSL::PKey::RSA] client's private key
  # @param client_cert [OpenSSL::X509::Certificate] client's cert whose public
  #   key matches the `private_key`
  # @param mode [:chain, :leaf, false] verification mode
  # @return [Puppet::SSL::SSLContext] A context to use to create connections
  # @raise [Puppet::SSL::CertVerifyError] There was an issue with
  #   one of the certs or CRLs.
  # @raise [Puppet::SSL::SSLError] There was an issue with the
  #   `private_key`.
  # @api private
  def create_context(cacerts, crls, private_key, client_cert, revocation: Puppet[:certificate_revocation])
    raise ArgumentError, "Private key is required" unless private_key
    raise ArgumentError, "Client cert is required" unless client_cert

    verify_cacerts(cacerts, crls, revocation)

    # REMIND: if client and server certs are issued by different intermediate
    # CA certs, then the client issuer cert may not be in the CA bundle we
    # download from the server. There should be a way to load additional certs,
    # to complete the chain, and send in the Client's Certificate message.

    store = create_x509_store(cacerts, crls, revocation)
    chain = verify_cert_with_store(store, client_cert)

    unless private_key.is_a?(OpenSSL::PKey::RSA)
      raise Puppet::SSL::SSLError, _("Unsupported key '%{type}'") % { type: private_key.class.name }
    end

    unless client_cert.check_private_key(private_key)
      raise Puppet::SSL::SSLError, _("The certificate for '%{name}' does not match its private key") % { name: subject(client_cert) }
    end

    Puppet::SSL::SSLContext.new(store, cacerts, crls, private_key, client_cert, chain, Puppet::SSL::Validator.default_validator)
    # REMIND: X509_verify_cert can raise
  end

  # Verify the `csr` was signed with a private key corresponding to the
  # `public_key`. This ensures the CSR was signed by someone in possession
  # of the private key, and that it hasn't been tampered with since.
  def verify_request(csr, public_key)
    unless csr.verify(public_key)
      raise Puppet::SSL::SSLError, _("The CSR for host '%{name}' does not match the public key") % { name: subject(csr) }
    end

    csr
  end

  private

  def default_flags
    # checking the signature of the self-signed cert doesn't add any security,
    # but it's a sanity check to make sure the cert isn't corrupt. This option
    # is only available in openssl 1.1+
    if defined?(OpenSSL::X509::V_FLAG_CHECK_SS_SIGNATURE)
      OpenSSL::X509::V_FLAG_CHECK_SS_SIGNATURE
    else
      0
    end
  end

  def verify_cacerts(cacerts, crls, mode)
    # If revocation mode is :leaf, then we can't perform revocation checking
    # until we know which issuer is the leaf, so disable revocation checking
    # while verifying the trusted CA certs.
    store = create_x509_store(cacerts, crls, mode == :leaf ? false : mode)

    cacerts.each do |cert|
      verify_cert_with_store(store, cert)
    end
  end

  def create_x509_store(roots, crls, mode)
    store = OpenSSL::X509::Store.new
    store.purpose = OpenSSL::X509::PURPOSE_ANY
    store.flags = default_flags | revocation_mode(mode)

    roots.each { |cert| store.add_cert(cert) }
    crls.each { |crl| store.add_crl(crl) }

    store
  end

  def subject(x509)
    x509.subject.to_s
  end

  def issuer(x509)
    x509.issuer.to_s
  end

  def revocation_mode(mode)
    case mode
    when false
      0
    when :leaf
      OpenSSL::X509::V_FLAG_CRL_CHECK
    else
      # :chain is the default
      OpenSSL::X509::V_FLAG_CRL_CHECK | OpenSSL::X509::V_FLAG_CRL_CHECK_ALL
    end
  end

  def verify_cert_with_store(store, cert)
    # chain is unused because puppet requires any intermediate CA certs
    # needed to complete the client's chain to be in the CA bundle
    # that we downloaded from the server, and they've already been
    # added to the store
    store_context = OpenSSL::X509::StoreContext.new(store, cert, [])
    unless store_context.verify
      current_cert = store_context.current_cert

      message =
        case store_context.error
        when OpenSSL::X509::V_ERR_CERT_NOT_YET_VALID
          _("The certificate '%{subject}' is not yet valid, verify time is synchronized") % { subject: subject(current_cert) }
        when OpenSSL::X509::V_ERR_CERT_HAS_EXPIRED
          _("The certificate '%{subject}' has expired, verify time is synchronized") %  { subject: subject(current_cert) }
        when OpenSSL::X509::V_ERR_CRL_NOT_YET_VALID
          _("The CRL issued by '%{issuer}' is not yet valid, verify time is synchronized") % { issuer: issuer(current_cert) }
        when OpenSSL::X509::V_ERR_CRL_HAS_EXPIRED
          _("The CRL issued by '%{issuer}' has expired, verify time is synchronized") % { issuer: issuer(current_cert) }
        when OpenSSL::X509::V_ERR_CERT_SIGNATURE_FAILURE
          _("Invalid signature for certificate '%{subject}'") % { subject: subject(current_cert) }
        when OpenSSL::X509::V_ERR_CRL_SIGNATURE_FAILURE
          _("Invalid signature for CRL issued by '%{issuer}'") % { issuer: issuer(current_cert) }
        when OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY
          _("The issuer '%{issuer}' of certificate '%{subject}' cannot be found locally") % {
            issuer: issuer(current_cert), subject: subject(current_cert) }
        when OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT
          _("The issuer '%{issuer}' of certificate '%{subject}' is missing") % {
            issuer: issuer(current_cert), subject: subject(current_cert) }
        when OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL
          _("The CRL issued by '%{issuer}' is missing") % { issuer: issuer(current_cert) }
        when OpenSSL::X509::V_ERR_CERT_REVOKED
          _("Certificate '%{subject}' is revoked") % { subject: subject(current_cert) }
        else
          # error_string is labeled ASCII-8BIT, but is encoded based on Encoding.default_external
          err_utf8 = Puppet::Util::CharacterEncoding.convert_to_utf_8(store_context.error_string)
          _("Certificate '%{subject}' failed verification (%{err}): %{err_utf8}") % {
            subject: subject(current_cert), err: store_context.error, err_utf8: err_utf8 }
        end

      raise Puppet::SSL::CertVerifyError.new(message, store_context.error, current_cert)
    end

    # resolved chain from leaf to root
    store_context.chain
  end
end
