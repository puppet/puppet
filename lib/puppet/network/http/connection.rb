require 'net/https'
require 'puppet/ssl/host'
require 'puppet/ssl/configuration'

module Puppet::Network::HTTP

  # This class provides simple methods for issuing various types of HTTP requests.
  # It's interface is intended to mirror Ruby's Net::HTTP object, but it provides
  # a few important bits of additional functionality.  Notably:
  #
  # * Any HTTPS requests made using this class will use Puppet's SSL certificate
  #   configuration for their authentication, and
  # * Provides some useful error handling for any SSL errors that occur during a
  #   request.
  class Connection

    def initialize(host, port, use_ssl = true)
      @host = host
      @port = port
      @use_ssl = use_ssl
    end
    
    def get(*args)
      request(:get, *args)
    end
    
    def post(*args)
      request(:post, *args)
    end
    
    def head(*args)
      request(:head, *args)
    end
    
    def delete(*args)
      request(:delete, *args)
    end
    
    def put(*args)
      request(:put, *args)
    end
    
    
    def request(method, *args)

      peer_certs = []
      verify_errors = []

      http_conn.verify_callback = proc do |preverify_ok, ssl_context|
        # We use the callback to collect the certificates for use in constructing
        # the error message if the verification failed.  This is necessary since we
        # don't have direct access to the cert that we expected the connection to
        # use otherwise.
        peer_certs << Puppet::SSL::Certificate.from_s(ssl_context.current_cert.to_pem)
        # And also keep the detailed verification error if such an error occurs
        if ssl_context.error_string and not preverify_ok
          verify_errors << "#{ssl_context.error_string} for #{ssl_context.current_cert.subject}"
        end
        preverify_ok
      end
    
      http_conn.send(method, *args)
    rescue OpenSSL::SSL::SSLError => error
      if error.message.include? "certificate verify failed"
        msg = error.message
        msg << ": [" + verify_errors.join('; ') + "]"
        raise Puppet::Error, msg
      elsif error.message =~ /hostname (was )?not match/
        raise unless cert = peer_certs.find { |c| c.name !~ /^puppet ca/i }
    
        valid_certnames = [cert.name, *cert.subject_alt_names].uniq
        msg = valid_certnames.length > 1 ? "one of #{valid_certnames.join(', ')}" : valid_certnames.first
    
        raise Puppet::Error, "Server hostname '#{http_conn.address}' did not match server certificate; expected #{msg}"
      else
        raise
      end
    end

    def address
      http_conn.address
    end

    def port
      http_conn.port
    end

    def use_ssl?
      http_conn.use_ssl?
    end

    # TODO: this shouldn't be here; it leaks our underlying Net::HTTP object out to the
    #  world, and it circumvents our local request methods.  The only reason it's here for
    #  the moment is because the current HTTP report processor relies on it; we should refactor that
    #  code so that it doesn't need this 'start' method (or so that this start method doesn't yield
    #  the Net::HTTP object directly)
    def start(&block)
      http_conn.start(&block)
    end


    private
    
    def http_conn
      @http_conn || initialize_http_conn
    end

    def initialize_http_conn
      args = [@host, @port]
      if Puppet[:http_proxy_host] == "none"
        args << nil << nil
      else
        args << Puppet[:http_proxy_host] << Puppet[:http_proxy_port]
      end
      
      @http_conn = create_http_conn(*args)

      # Pop open the http client a little; older versions of Net::HTTP(s) didn't
      # give us a reader for ca_file... Grr...
      class << @http_conn; attr_accessor :ca_file; end

      @http_conn.use_ssl = @use_ssl
      # Use configured timeout (#1176)
      @http_conn.read_timeout = Puppet[:configtimeout]
      @http_conn.open_timeout = Puppet[:configtimeout]

      cert_setup

      @http_conn
    end

    # Use cert information from a Puppet client to set up the http object.
    def cert_setup
      if FileTest.exist?(Puppet[:hostcert]) and FileTest.exist?(ssl_configuration.ca_auth_file)
        @http_conn.cert_store  = ssl_host.ssl_store
        @http_conn.ca_file     = ssl_configuration.ca_auth_file
        @http_conn.cert        = ssl_host.certificate.content
        @http_conn.verify_mode = OpenSSL::SSL::VERIFY_PEER
        @http_conn.key         = ssl_host.key.content
      else
        # We don't have the local certificates, so we don't do any verification
        # or setup at this early stage.  REVISIT: Shouldn't we supply the local
        # certificate details if we have them?  The original code didn't.
        # --daniel 2012-06-03

        # Ruby 1.8 defaulted to this, but 1.9 defaults to peer verify, and we
        # almost always talk to a dedicated, not-standard CA that isn't trusted
        # out of the box.  This forces the expected state.
        @http_conn.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end

    # This method largely exists for testing purposes, so that we can
    #  mock the actual HTTP connection.
    def create_http_conn(*args)
      Net::HTTP.new(*args)
    end

    # Use the global localhost instance.
    def ssl_host
      Puppet::SSL::Host.localhost
    end

    def ssl_configuration
      @ssl_configuration ||= Puppet::SSL::Configuration.new(
          Puppet[:localcacert],
          :ca_chain_file => Puppet[:ssl_client_ca_chain],
          :ca_auth_file  => Puppet[:ssl_client_ca_auth])
    end

  end
end
