require 'spec_helper'
require 'puppet_spec/https'
require 'puppet_spec/files'
require 'puppet/network/http_pool'

describe Puppet::Network::HttpPool, unless: Puppet::Util::Platform.jruby? do
  include PuppetSpec::Files

  before :all do
    WebMock.disable!
  end

  after :all do
    WebMock.enable!
  end

  before :each do
    # make sure we don't take too long
    Puppet[:http_connect_timeout] = '5s'
  end

  let(:hostname) { '127.0.0.1' }
  let(:wrong_hostname) { 'localhost' }
  let(:server) { PuppetSpec::HTTPSServer.new }

  context "when calling deprecated HttpPool methods" do
    let(:ssl_host) {
      # use server's cert/key as the client cert/key
      host = Puppet::SSL::Host.new
      host.key = Puppet::SSL::Key.from_instance(server.server_key, host.name)
      host.certificate = Puppet::SSL::Certificate.from_instance(server.server_cert, host.name)
      host
    }

    before(:each) do
      ssldir = tmpdir('http_pool')
      Puppet[:ssldir] = ssldir
      Puppet.settings.use(:main, :ssl)

      File.write(Puppet[:localcacert], server.ca_cert.to_pem)
      File.write(Puppet[:hostcrl], server.ca_crl.to_pem)
      File.write(Puppet[:hostcert], server.server_cert.to_pem)
      File.write(Puppet[:hostprivkey], server.server_key.to_pem)
    end

    # Can't use `around(:each)` because it will cause ssl_host to be
    # created outside of any rspec example, and $confdir won't be set
    before(:each) do
      Puppet.push_context(ssl_host: ssl_host)
    end

    after (:each) do
      Puppet.pop_context
    end

    def connection(host, port)
      Puppet::Network::HttpPool.http_instance(host, port, use_ssl: true)
    end

    shared_examples_for 'HTTPS client' do
      it "connects over SSL" do
        server.start_server do |port|
          http = connection(hostname, port)
          res = http.get('/')
          expect(res.code).to eq('200')
        end
      end

      it "raises if the server's cert doesn't match the hostname we connected to" do
        server.start_server do |port|
          http = connection(wrong_hostname, port)
          expect {
            http.get('/')
          }.to raise_error { |err|
            expect(err).to be_instance_of(Puppet::SSL::CertMismatchError)
            expect(err.message).to match(/\AServer hostname '#{wrong_hostname}' did not match server certificate; expected one of (.+)/)

            md = err.message.match(/expected one of (.+)/)
            expect(md[1].split(', ')).to contain_exactly('127.0.0.1', 'DNS:127.0.0.1', 'DNS:127.0.0.2')
          }
        end
      end

      it "raises if the server's CA is unknown" do
        # File must exist and by not empty so DefaultValidator doesn't
        # downgrade to VERIFY_NONE, so use a different CA that didn't
        # issue the server's cert
        capath = tmpfile('empty')
        File.write(capath, cert_fixture('netlock-arany-utf8.pem'))
        Puppet[:localcacert] = capath
        Puppet[:certificate_revocation] = false

        server.start_server do |port|
          http = connection(hostname, port)
          expect {
            http.get('/')
          }.to raise_error(Puppet::Error,
                           %r{certificate verify failed.* .self signed certificate in certificate chain for CN=Test CA.})
        end
      end
    end


    context "when using single use HTTPS connections" do
      include_examples 'HTTPS client'
    end

    context "when using persistent HTTPS connections" do
      around :each do |example|
        pool = Puppet::Network::HTTP::Pool.new
        Puppet.override(:http_pool => pool) do
          example.run
        end
        pool.close
      end

      include_examples 'HTTPS client'
    end
  end

  context "when calling HttpPool.connection method" do
    let(:ssl) { Puppet::SSL::SSLProvider.new }
    let(:ssl_context) { ssl.create_root_context(cacerts: [server.ca_cert], crls: [server.ca_crl]) }

    def connection(host, port, ssl_context:)
      Puppet::Network::HttpPool.connection(host, port, ssl_context: ssl_context)
    end

    # Configure the server's SSLContext to require a client certificate. The `client_ca`
    # setting allows the server to advertise which client CAs it will accept.
    def require_client_certs(ctx)
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
      ctx.client_ca = [cert_fixture('ca.pem')]
    end

    it "connects over SSL" do
      server.start_server do |port|
        http = connection(hostname, port, ssl_context: ssl_context)
        res = http.get('/')
        expect(res.code).to eq('200')
      end
    end

    it "raises if the server's cert doesn't match the hostname we connected to" do
      server.start_server do |port|
        http = connection(wrong_hostname, port, ssl_context: ssl_context)
        expect {
          http.get('/')
        }.to raise_error { |err|
          expect(err).to be_instance_of(Puppet::SSL::CertMismatchError)
          expect(err.message).to match(/\AServer hostname '#{wrong_hostname}' did not match server certificate; expected one of (.+)/)

          md = err.message.match(/expected one of (.+)/)
          expect(md[1].split(', ')).to contain_exactly('127.0.0.1', 'DNS:127.0.0.1', 'DNS:127.0.0.2')
        }
      end
    end

    it "raises if the server's CA is unknown" do
      server.start_server do |port|
        ssl_context = ssl.create_root_context(cacerts: [cert_fixture('netlock-arany-utf8.pem')],
                                              crls: [server.ca_crl])
        http = Puppet::Network::HttpPool.connection(hostname, port, ssl_context: ssl_context)
        expect {
          http.get('/')
        }.to raise_error(Puppet::Error,
                         %r{certificate verify failed.* .self signed certificate in certificate chain for CN=Test CA.})
      end
    end

    it "warns when client has an incomplete client cert chain" do
      expect(Puppet).to receive(:warning).with("The issuer 'CN=Test CA Agent Subauthority' of certificate 'CN=pluto' cannot be found locally")

      pluto = cert_fixture('pluto.pem')

      ssl_context = ssl.create_context(
        cacerts: [server.ca_cert], crls: [server.ca_crl],
        client_cert: pluto, private_key: key_fixture('pluto-key.pem')
      )

      # verify client has incomplete chain
      expect(ssl_context.client_chain.map(&:to_der)).to eq([pluto.to_der])

      # force server to require (not request) client certs
      ctx_proc = -> (ctx) {
        require_client_certs(ctx)

        # server needs to trust the client's intermediate CA to complete the client's chain
        ctx.cert_store.add_cert(cert_fixture('intermediate-agent.pem'))
      }

      server.start_server(ctx_proc: ctx_proc) do |port|
        http = Puppet::Network::HttpPool.connection(hostname, port, ssl_context: ssl_context)
        res = http.get('/')
        expect(res.code).to eq('200')
      end
    end

    it "sends a complete client cert chain" do
      pluto = cert_fixture('pluto.pem')
      client_ca = cert_fixture('intermediate-agent.pem')

      ssl_context = ssl.create_context(
        cacerts: [server.ca_cert, client_ca],
        crls: [server.ca_crl, crl_fixture('intermediate-agent-crl.pem')],
        client_cert: pluto,
        private_key: key_fixture('pluto-key.pem')
      )

      # verify client has complete chain from leaf to root
      expect(ssl_context.client_chain.map(&:to_der)).to eq([pluto, client_ca, server.ca_cert].map(&:to_der))

      server.start_server(ctx_proc: method(:require_client_certs)) do |port|
        http = Puppet::Network::HttpPool.connection(hostname, port, ssl_context: ssl_context)
        res = http.get('/')
        expect(res.code).to eq('200')
      end
    end
  end
end
