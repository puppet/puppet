require 'spec_helper'
require 'puppet/settings'

describe "Defaults" do
  describe ".default_diffargs" do
    describe "on AIX" do
      before(:each) do
        Facter.stubs(:value).with(:kernel).returns("AIX")
      end
      describe "on 5.3" do
        before(:each) do
          Facter.stubs(:value).with(:kernelmajversion).returns("5300")
        end
        it "should be empty" do
          expect(Puppet.default_diffargs).to eq("")
        end
      end
      [ "",
        nil,
        "6300",
        "7300",
      ].each do |kernel_version|
        describe "on kernel version #{kernel_version.inspect}" do
          before(:each) do
            Facter.stubs(:value).with(:kernelmajversion).returns(kernel_version)
          end

          it "should be '-u'" do
            expect(Puppet.default_diffargs).to eq("-u")
          end
        end
      end
    end
    describe "on everything else" do
      before(:each) do
        Facter.stubs(:value).with(:kernel).returns("NOT_AIX")
      end

      it "should be '-u'" do
        expect(Puppet.default_diffargs).to eq("-u")
      end
    end
  end

  describe ".default_digest_alg" do
    describe "on windows platform" do
      before(:each) do
        Puppet::Util::Platform.stubs(:windows?).returns true
      end
      it "should be md5" do
        expect(Puppet.default_digest_alg).to eq('md5')
      end
    end

    describe "on non-windows not fips platform" do
      before(:each) do
        Puppet::Util::Platform.stubs(:windows?).returns false
        Puppet::Util::Platform.stubs(:fips_enabled?).returns false
      end
      it "should be md5" do
        expect(Puppet.default_digest_alg).to eq('md5')
      end
    end

    describe "on non-windows fips-enabled platform" do
      before(:each) do
        Puppet::Util::Platform.stubs(:windows?).returns false
        Puppet::Util::Platform.stubs(:fips_enabled?).returns true
      end
      it "should be sha256" do
        expect(Puppet.default_digest_alg).to eq('sha256')
      end
      it 'should raise an error on a prohibited digest_algorithm in fips mode' do
        expect { Puppet.settings[:digest_algorithm] = 'md5' }.to raise_exception ArgumentError, 'MD5 digest is prohited in fips mode. Valid values are ["sha256", "sha384", "sha512", "sha224"].'
      end
      it 'should not raise an error on setting a valid list of checksum types when in fips mode' do
        Puppet.settings[:digest_algorithm] = 'sha384'
        expect(Puppet.settings[:digest_algorithm]).to eq('sha384')
      end
      it 'should raise an error on an invalid digest_algorithm' do
        expect { Puppet.settings[:digest_algorithm] = 'foo' }.to raise_exception ArgumentError, 'Unrecognized digest_algorithm foo is not supported. Valid values are ["sha256", "sha384", "sha512", "sha224"].'
      end
    end
  end

  describe 'strict' do
    it 'should accept the valid value :off' do
      expect {Puppet.settings[:strict] = 'off'}.to_not raise_exception
    end

    it 'should accept the valid value :warning' do
      expect {Puppet.settings[:strict] = 'warning'}.to_not raise_exception
    end

    it 'should accept the valid value :error' do
      expect {Puppet.settings[:strict] = 'error'}.to_not raise_exception
    end

    it 'should fail if given an invalid value' do
      expect {Puppet.settings[:strict] = 'ignore'}.to raise_exception(/Invalid value 'ignore' for parameter strict\./)
    end
  end

  describe 'supported_checksum_types in fips mode testing' do
    describe "on windows platform" do
      before(:each) do
        Puppet::Util::Platform.stubs(:windows?).returns true
      end
      it "should return all checksums" do
        expect(Puppet.default_checksum_types).to eq(['md5', 'sha256', 'sha384', 'sha512', 'sha224'])
      end
    end

    describe "on non-windows non fips platform" do
      before(:each) do
        Puppet::Util::Platform.stubs(:windows?).returns false
        Puppet::Util::Platform.stubs(:fips_enabled?).returns false
      end
      it "should return all checksums" do
        expect(Puppet.default_checksum_types).to eq(['md5', 'sha256', 'sha384', 'sha512', 'sha224'])
      end
    end

    describe "on non-windows fips-enabled platform" do
      before(:each) do
        Puppet::Util::Platform.stubs(:windows?).returns false
        Puppet::Util::Platform.stubs(:fips_enabled?).returns true
      end
      it "should exclude md5" do
        expect(Puppet.default_checksum_types).to eq(['sha256', 'sha384', 'sha512', 'sha224'])
      end
      it 'should raise an error on a prohibited checksum type in fips mode' do
        expect { Puppet.settings[:supported_checksum_types] = ['md5', 'foo'] }.to raise_exception ArgumentError, '["md5", "md5lite"] checksum types are prohibited in FIPS mode. Valid values are ["sha256", "sha256lite", "sha384", "sha512", "sha224", "sha1", "sha1lite", "mtime", "ctime"].'
      end
      it 'should not raise an error on setting a valid list of checksum types when in fips mode' do
        Puppet.settings[:supported_checksum_types] = ['sha256', 'sha384', 'mtime']
        expect(Puppet.settings[:supported_checksum_types]).to eq(['sha256', 'sha384', 'mtime'])
      end
    end
  end

  describe 'supported_checksum_types' do
    it 'should default to md5,sha256,sha512,sha384,sha224' do
      expect(Puppet.settings[:supported_checksum_types]).to eq(['md5', 'sha256', 'sha384', 'sha512', 'sha224'])
    end

    it 'should raise an error on an unsupported checksum type' do
      expect { Puppet.settings[:supported_checksum_types] = ['md5', 'foo'] }.to raise_exception ArgumentError, 'Unrecognized checksum types ["foo"] are not supported. Valid values are ["md5", "md5lite", "sha256", "sha256lite", "sha384", "sha512", "sha224", "sha1", "sha1lite", "mtime", "ctime"].'
    end

    it 'should not raise an error on setting a valid list of checksum types' do
      Puppet.settings[:supported_checksum_types] = ['sha256', 'md5lite', 'mtime']
      expect(Puppet.settings[:supported_checksum_types]).to eq(['sha256', 'md5lite', 'mtime'])
    end

  end

  describe 'server vs server_list' do
    it 'should warn when both settings are set in code' do
      Puppet.expects(:deprecation_warning).with('Attempted to set both server and server_list. Server setting will not be used.', :SERVER_DUPLICATION)
      Puppet.settings[:server] = 'test_server'
      Puppet.settings[:server_list] = ['one', 'two']
    end

    it 'should warn when both settings are set by command line' do
      Puppet.expects(:deprecation_warning).with('Attempted to set both server and server_list. Server setting will not be used.', :SERVER_DUPLICATION)
      Puppet.settings.handlearg("--server_list", "one,two")
      Puppet.settings.handlearg("--server", "test_server")
    end
  end
end
