require 'spec_helper'

describe Puppet::Type.type(:package).provider(:yum) do
  include PuppetSpec::Fixtures

  it_behaves_like 'RHEL package provider', described_class, 'yum'

  it "should have lower specificity" do
    allow(Facter).to receive(:value).with(:osfamily).and_return(:redhat)
    allow(Facter).to receive(:value).with(:operatingsystem).and_return(:fedora)
    allow(Facter).to receive(:value).with(:operatingsystemmajrelease).and_return("22")
    expect(described_class.specificity).to be < 200
  end

  describe "should have logical defaults" do
    [2, 2018].each do |ver|
      it "should be the default provider on Amazon Linux #{ver}" do
        allow(Facter).to receive(:value).with(:operatingsystem).and_return('amazon')
        allow(Facter).to receive(:value).with(:osfamily).and_return('redhat')
        allow(Facter).to receive(:value).with(:operatingsystemmajrelease).and_return(ver)
        expect(described_class).to be_default
      end
    end

    Array(4..7).each do |ver|
      it "should be default for redhat #{ver}" do
        allow(Facter).to receive(:value).with(:operatingsystem).and_return('redhat')
        allow(Facter).to receive(:value).with(:osfamily).and_return('redhat')
        allow(Facter).to receive(:value).with(:operatingsystemmajrelease).and_return(ver.to_s)
        expect(described_class).to be_default
      end
    end

    it "should not be default for redhat 8" do
      allow(Facter).to receive(:value).with(:operatingsystem).and_return('redhat')
      allow(Facter).to receive(:value).with(:osfamily).and_return('redhat')
      allow(Facter).to receive(:value).with(:operatingsystemmajrelease).and_return('8')
      expect(described_class).not_to be_default
    end

    it "should not be default for Ubuntu 16.04" do
      allow(Facter).to receive(:value).with(:operatingsystem).and_return('ubuntu')
      allow(Facter).to receive(:value).with(:osfamily).and_return('ubuntu')
      allow(Facter).to receive(:value).with(:operatingsystemmajrelease).and_return('16.04')
      expect(described_class).not_to be_default
    end
  end

  describe "when supplied the source param" do
    let(:name) { 'baz' }

    let(:resource) do
      Puppet::Type.type(:package).new(
        :name => name,
        :provider => 'yum',
      )
    end

    let(:provider) do
      provider = described_class.new
      provider.resource = resource
      provider
    end

    before { allow(described_class).to receive(:command).with(:cmd).and_return("/usr/bin/yum") }

  describe 'provider features' do
    it { is_expected.to be_versionable }
    it { is_expected.to be_install_options }
    it { is_expected.to be_virtual_packages }
    it { is_expected.to be_install_only }
  end

    context "when installing" do
      it "should use the supplied source as the explicit path to a package to install" do
        resource[:ensure] = :present
        resource[:source] = "/foo/bar/baz-1.1.0.rpm"
        expect(provider).to receive(:execute) do |arr|
          expect(arr[-2..-1]).to eq([:install, "/foo/bar/baz-1.1.0.rpm"])
        end
        provider.install
      end
    end

    context "when ensuring a specific version" do
      it "should use the suppplied source as the explicit path to the package to update" do
        # The first query response informs yum provider that package 1.1.0 is
        # already installed, and the second that it's been upgraded
        expect(provider).to receive(:query).twice.and_return({:ensure => "1.1.0"}, {:ensure => "1.2.0"})
        resource[:ensure] = "1.2.0"
        resource[:source] = "http://foo.repo.com/baz-1.2.0.rpm"
        expect(provider).to receive(:execute) do |arr|
          expect(arr[-2..-1]).to eq(['update', "http://foo.repo.com/baz-1.2.0.rpm"])
        end
        provider.install
      end
    end
  end

  context "parsing the output of check-update" do
    context "with no multiline entries" do
      let(:check_update) { File.read(my_fixture("yum-check-update-simple.txt")) }
      let(:output) { described_class.parse_updates(check_update) }

      it 'creates an entry for each package keyed on the package name' do
        expect(output['curl']).to eq([{:name => 'curl', :epoch => '0', :version => '7.32.0', :release => '10.fc20', :arch => 'i686'}, {:name => 'curl', :epoch => '0', :version => '7.32.0', :release => '10.fc20', :arch => 'x86_64'}])
        expect(output['gawk']).to eq([{:name => 'gawk', :epoch => '0', :version => '4.1.0', :release => '3.fc20', :arch => 'i686'}])
        expect(output['dhclient']).to eq([{:name => 'dhclient', :epoch => '12', :version => '4.1.1', :release => '38.P1.fc20', :arch => 'i686'}])
        expect(output['selinux-policy']).to eq([{:name => 'selinux-policy', :epoch => '0', :version => '3.12.1', :release => '163.fc20', :arch => 'noarch'}])
      end

      it 'creates an entry for each package keyed on the package name and package architecture' do
        expect(output['curl.i686']).to eq([{:name => 'curl', :epoch => '0', :version => '7.32.0', :release => '10.fc20', :arch => 'i686'}])
        expect(output['curl.x86_64']).to eq([{:name => 'curl', :epoch => '0', :version => '7.32.0', :release => '10.fc20', :arch => 'x86_64'}])
        expect(output['gawk.i686']).to eq([{:name => 'gawk', :epoch => '0', :version => '4.1.0', :release => '3.fc20', :arch => 'i686'}])
        expect(output['dhclient.i686']).to eq([{:name => 'dhclient', :epoch => '12', :version => '4.1.1', :release => '38.P1.fc20', :arch => 'i686'}])
        expect(output['selinux-policy.noarch']).to eq([{:name => 'selinux-policy', :epoch => '0', :version => '3.12.1', :release => '163.fc20', :arch => 'noarch'}])
        expect(output['java-1.8.0-openjdk.x86_64']).to eq([{:name => 'java-1.8.0-openjdk', :epoch => '1', :version => '1.8.0.131', :release => '2.b11.el7_3', :arch => 'x86_64'}])
      end
    end

    context "with multiline entries" do
      let(:check_update) { File.read(my_fixture("yum-check-update-multiline.txt")) }
      let(:output) { described_class.parse_updates(check_update) }

      it "parses multi-line values as a single package tuple" do
        expect(output['libpcap']).to eq([{:name => 'libpcap', :epoch => '14', :version => '1.4.0', :release => '1.20130826git2dbcaa1.el6', :arch => 'x86_64'}])
      end
    end

    context "with obsoleted packages" do
      let(:check_update) { File.read(my_fixture("yum-check-update-obsoletes.txt")) }
      let(:output) { described_class.parse_updates(check_update) }

      it "ignores all entries including and after 'Obsoleting Packages'" do
        expect(output).not_to include("Obsoleting")
        expect(output).not_to include("NetworkManager-bluetooth.x86_64")
        expect(output).not_to include("1:1.0.0-14.git20150121.b4ea599c.el7")
      end
    end

    context "with security notifications" do
      let(:check_update) { File.read(my_fixture("yum-check-update-security.txt")) }
      let(:output) { described_class.parse_updates(check_update) }

      it "ignores all entries including and after 'Security'" do
        expect(output).not_to include("Security")
      end

      it "includes updates before 'Security'" do
        expect(output).to include("yum-plugin-fastestmirror.noarch")
      end
    end

    context "with broken update notices" do
      let(:check_update) { File.read(my_fixture("yum-check-update-broken-notices.txt")) }
      let(:output) { described_class.parse_updates(check_update) }

      it "ignores all entries including and after 'Update'" do
        expect(output).not_to include("Update")
      end

      it "includes updates before 'Update'" do
        expect(output).to include("yum-plugin-fastestmirror.noarch")
      end
    end

    context "with improper package names in output" do
      it "raises an exception parsing package name" do
        expect {
          described_class.update_to_hash('badpackagename', '1')
        }.to raise_exception(Exception, /Failed to parse/)
      end
    end

    context "with trailing plugin output" do
      let(:check_update) { File.read(my_fixture("yum-check-update-plugin-output.txt")) }
      let(:output) { described_class.parse_updates(check_update) }

      it "parses correctly formatted entries" do
        expect(output['bash']).to eq([{:name => 'bash', :epoch => '0', :version => '4.2.46', :release => '12.el7', :arch => 'x86_64'}])
      end

      it "ignores all mentions of plugin output" do
        expect(output).not_to include("Random plugin")
      end
    end
  end
end
