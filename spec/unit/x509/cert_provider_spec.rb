require 'spec_helper'
require 'puppet/x509'

describe Puppet::X509::CertProvider do
  include PuppetSpec::Files

  def pem(name)
    File.read(my_fixture(name))
  end

  def cert(name)
    OpenSSL::X509::Certificate.new(pem(name))
  end

  def crl(name)
    OpenSSL::X509::CRL.new(pem(name))
  end

  def key(name)
    OpenSSL::PKey::RSA.new(pem(name))
  end

  def request(name)
    OpenSSL::X509::Request.new(pem(name))
  end

  def create_provider(options)
    described_class.new(options)
  end

  context 'when loading' do
    context 'cacerts' do
      it 'returns nil if it does not exist' do
        provider = create_provider(capath: '/does/not/exist')

        expect(provider.load_cacerts).to be_nil
      end

      it 'returns an array of certificates' do
        certs = create_provider(capath: my_fixture('ca.pem')).load_cacerts
        expect(certs.count).to eq(1)
        expect(certs.first.subject.to_s).to eq('/CN=Test CA')
      end

      it 'raises when invalid input is inside BEGIN-END block' do
        ca_path = tmpfile('invalid_cacerts')
        File.open(ca_path, 'w') do |f|
          f.write '-----BEGIN CERTIFICATE-----'
          f.write 'whoops'
          f.write '-----END CERTIFICATE-----'
        end

        expect {
          create_provider(capath: ca_path).load_cacerts
        }.to raise_error(OpenSSL::X509::CertificateError)
      end
    end

    context 'crls' do
      it 'returns nil if it does not exist' do
        provider = create_provider(crlpath: '/does/not/exist')
        expect(provider.load_crls).to be_nil
      end

      it 'returns an array of CRLs' do
        crls = create_provider(crlpath: my_fixture('crl.pem')).load_crls
        expect(crls.count).to eq(1)
        expect(crls.first.issuer.to_s).to eq('/CN=Test CA')
      end

      it 'raises when invalid input is inside BEGIN-END block' do
        pending('jruby NPE bug') if Puppet::Util::Platform.jruby?

        crl_path = tmpfile('invalid_crls')
        File.open(crl_path, 'w') do |f|
          f.write '-----BEGIN X509 CRL-----'
          f.write 'whoops'
          f.write '-----END X509 CRL-----'
        end

        expect {
          create_provider(crlpath: crl_path).load_crls
        }.to raise_error(OpenSSL::X509::CRLError, 'nested asn1 error')
      end
    end
  end

  context 'when saving' do
    context 'cacerts' do
      let(:ca_path) { tmpfile('pem_cacerts') }
      let(:ca_cert) { cert('ca.pem') }

      it 'writes PEM encoded certs' do
        create_provider(capath: ca_path).save_cacerts([ca_cert])

        expect(File.read(ca_path)).to match(/\A-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\Z/m)
      end

      it 'sets mode to 644'
    end

    context 'crls' do
      let(:crl_path) { tmpfile('pem_crls') }
      let(:ca_crl) { crl('crl.pem') }

      it 'writes PEM encoded CRLs' do
        create_provider(crlpath: crl_path).save_crls([ca_crl])

        expect(File.read(crl_path)).to match(/\A-----BEGIN X509 CRL-----.*?-----END X509 CRL-----\Z/m)
      end

      it 'sets mode to 644'
    end
  end

  context 'when loading' do
    context 'private keys' do
      let(:provider) { create_provider(privatekeydir: my_fixture_dir) }

      it 'returns nil if it does not exist' do
        provider = create_provider(privatekeydir: '/does/not/exist')

        expect(provider.load_private_key('whatever')).to be_nil
      end

      it 'returns an RSA key' do
        expect(provider.load_private_key('signed-key')).to be_a(OpenSSL::PKey::RSA)
      end

      it 'downcases name' do
        expect(provider.load_private_key('SIGNED-KEY')).to be_a(OpenSSL::PKey::RSA)
      end

      it 'raises if name is invalid' do
        expect {
          provider.load_private_key('signed/../key')
        }.to raise_error(RuntimeError, 'Certname "signed/../key" must not contain unprintable or non-ASCII characters')
      end

      it 'returns nil if `hostprivkey` is overridden' do
        Puppet[:certname] = 'foo'
        Puppet[:hostprivkey] = File.join(my_fixture_dir, "signed-key.pem")

        expect(provider.load_private_key('foo')).to be_nil
      end

      context 'that are encrypted' do
        it 'raises without a passphrase' do
          # password is 74695716c8b6
          expect {
            provider.load_private_key('encrypted-key')
          }.to raise_error(OpenSSL::PKey::RSAError, /Neither PUB key nor PRIV key/)
        end
      end
    end

    context 'certs' do
      let(:provider) { create_provider(certdir: my_fixture_dir) }

      it 'returns nil if it does not exist' do
        provider = create_provider(certdir: '/does/not/exist')

        expect(provider.load_client_cert('nonexistent')).to be_nil
      end

      it 'returns a certificate' do
        cert = provider.load_client_cert('signed')
        expect(cert.subject.to_s).to eq('/CN=signed')
      end

      it 'downcases name' do
        cert = provider.load_client_cert('SIGNED')
        expect(cert.subject.to_s).to eq('/CN=signed')
      end

      it 'raises if name is invalid' do
        expect {
          provider.load_client_cert('tom/../key')
        }.to raise_error(RuntimeError, 'Certname "tom/../key" must not contain unprintable or non-ASCII characters')
      end

      it 'returns nil if `hostcert` is overridden' do
        Puppet[:certname] = 'foo'
        Puppet[:hostcert] = File.join(my_fixture_dir, "signed.pem")

        expect(provider.load_client_cert('foo')).to be_nil
      end
    end

    context 'requests' do
      let(:request) { request('request.pem') }
      let(:provider) { create_provider(requestdir: my_fixture_dir) }

      it 'returns nil if it does not exist' do
        expect(provider.load_request('whatever')).to be_nil
      end

      it 'returns a request' do
        expect(provider.load_request('request')).to be_a(OpenSSL::X509::Request)
      end

      it 'downcases name' do
        csr = provider.load_request('REQUEST')
        expect(csr.subject.to_s).to eq('/CN=pending')
      end

      it 'raises if name is invalid' do
        expect {
          provider.load_request('tom/../key')
        }.to raise_error(RuntimeError, 'Certname "tom/../key" must not contain unprintable or non-ASCII characters')
      end

      it 'ignores `hostcsr`' do
        Puppet[:hostcsr] = File.join(my_fixture_dir, "doesnotexist.pem")

        expect(provider.load_request('request')).to be_a(OpenSSL::X509::Request)
      end
    end
  end

  context 'when saving' do
    let(:name) { 'tom' }

    context 'private keys' do
      let(:privatekeydir) { tmpdir('privatekeydir') }
      let(:private_key) { key('signed-key.pem') }
      let(:path) { File.join(privatekeydir, 'tom.pem') }
      let(:provider) { create_provider(privatekeydir: privatekeydir) }

      it 'writes PEM encoded private key' do
        provider.save_private_key(name, private_key)

        expect(File.read(path)).to match(/\A-----BEGIN RSA PRIVATE KEY-----.*?-----END RSA PRIVATE KEY-----\Z/m)
      end

      it 'sets mode to 640'

      it 'downcases name' do
        provider.save_private_key('TOM', private_key)

        expect(File).to be_exist(path)
      end

      it 'raises if name is invalid' do
        expect {
          provider.load_private_key('tom/../key')
        }.to raise_error(RuntimeError, 'Certname "tom/../key" must not contain unprintable or non-ASCII characters')
      end
    end

    context 'certs' do
      let(:certdir) { tmpdir('certdir') }
      let(:client_cert) { cert('signed.pem') }
      let(:path) { File.join(certdir, 'tom.pem') }
      let(:provider) { create_provider(certdir: certdir) }

      it 'writes PEM encoded cert' do
        provider.save_client_cert(name, client_cert)

        expect(File.read(path)).to match(/\A-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\Z/m)
      end

      it 'sets mode to 644'

      it 'downcases name' do
        provider.save_client_cert('TOM', client_cert)

        expect(File).to be_exist(path)
      end

      it 'raises if name is invalid' do
        expect {
          provider.save_client_cert('tom/../key', client_cert)
        }.to raise_error(RuntimeError, 'Certname "tom/../key" must not contain unprintable or non-ASCII characters')
      end
    end

    context 'requests' do
      let(:requestdir) { tmpdir('requestdir') }
      let(:csr) { request('request.pem') }
      let(:path) { File.join(requestdir, 'tom.pem') }
      let(:provider) { create_provider(requestdir: requestdir) }

      it 'writes PEM encoded request' do
        provider.save_request(name, csr)

        expect(File.read(path)).to match(/\A-----BEGIN CERTIFICATE REQUEST-----.*?-----END CERTIFICATE REQUEST-----\Z/m)
      end

      it 'sets mode to 644'

      it 'downcases name' do
        provider.save_request('TOM', csr)

        expect(File).to be_exist(path)
      end

      it 'raises if name is invalid' do
        expect {
          provider.save_request('tom/../key', csr)
        }.to raise_error(RuntimeError, 'Certname "tom/../key" must not contain unprintable or non-ASCII characters')
      end
    end
  end
end
