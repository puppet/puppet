require 'spec_helper'

describe 'Puppet::Type::User::Provider::Aix' do
  let(:provider_class) { Puppet::Type.type(:user).provider(:aix) }
  let(:group_provider_class) { Puppet::Type.type(:group).provider(:aix) }

  let(:resource) do
    Puppet::Type.type(:user).new(
      :name   => 'test_aix_user',
      :ensure => :present
    )
  end
  let(:provider) do
    provider_class.new(resource)
  end

  describe '.pgrp_to_gid' do
    it "finds the primary group's gid" do
      allow(provider).to receive(:ia_module_args).and_return(['-R', 'module'])

      expect(group_provider_class).to receive(:list_all)
        .with(provider.ia_module_args)
        .and_return([{ :name => 'group', :id => 1}])

      expect(provider_class.pgrp_to_gid(provider, 'group')).to eql(1)
    end
  end

  describe '.gid_to_pgrp' do
    it "finds the gid's primary group" do
      allow(provider).to receive(:ia_module_args).and_return(['-R', 'module'])

      expect(group_provider_class).to receive(:list_all)
        .with(provider.ia_module_args)
        .and_return([{ :name => 'group', :id => 1}])

      expect(provider_class.gid_to_pgrp(provider, 1)).to eql('group')
    end
  end

  describe '.expires_to_expiry' do
    it 'returns absent if expires is 0' do
      expect(provider_class.expires_to_expiry(provider, '0')).to eql(:absent)
    end

    it 'returns absent if the expiry attribute is not formatted properly' do
      expect(provider_class.expires_to_expiry(provider, 'bad_format')).to eql(:absent)
    end

    it 'returns the password expiration date' do
      expect(provider_class.expires_to_expiry(provider, '0910122314')).to eql('2014-09-10')
    end
  end

  describe '.expiry_to_expires' do
    it 'returns 0 if the expiry date is 0000-00-00' do
      expect(provider_class.expiry_to_expires('0000-00-00')).to eql('0')
    end

    it 'returns 0 if the expiry date is "absent"' do
      expect(provider_class.expiry_to_expires('absent')).to eql('0')
    end

    it 'returns 0 if the expiry date is :absent' do
      expect(provider_class.expiry_to_expires(:absent)).to eql('0')
    end

    it 'returns the expires attribute value' do
      expect(provider_class.expiry_to_expires('2014-09-10')).to eql('0910000014')
    end
  end

  describe '.groups_attribute_to_property' do
    it "reads the user's groups from the etc/groups file" do
      groups = ['system', 'adm']
      allow(Puppet::Util::POSIX).to receive(:groups_of).with(resource[:name]).and_return(groups)

      actual_groups = provider_class.groups_attribute_to_property(provider, 'unused_value')
      expected_groups = groups.join(',')

      expect(actual_groups).to eql(expected_groups)
    end
  end

  describe '.groups_property_to_attribute' do
    it 'raises an ArgumentError if the groups are space-separated' do
      groups = "foo bar baz"
      expect do
        provider_class.groups_property_to_attribute(groups)
      end.to raise_error do |error|
        expect(error).to be_a(ArgumentError)

        expect(error.message).to match(groups)
        expect(error.message).to match("Groups")
      end
    end
  end

  describe '#gid=' do
    let(:value) { 'new_pgrp' }
    let(:old_pgrp) { 'old_pgrp' }
    let(:cur_groups) { 'system,adm' }

    before(:each) do
      allow(provider).to receive(:gid).and_return(old_pgrp)
      allow(provider).to receive(:groups).and_return(cur_groups)
      allow(provider).to receive(:set)
    end

    it 'raises a Puppet::Error if it fails to set the groups property' do
      allow(provider).to receive(:set)
        .with(:groups, cur_groups)
        .and_raise(Puppet::ExecutionFailure, 'failed to reset the groups!')

      expect { provider.gid = value }.to raise_error do |error|
        expect(error).to be_a(Puppet::Error)

        expect(error.message).to match('groups')
        expect(error.message).to match(cur_groups)
        expect(error.message).to match(old_pgrp)
        expect(error.message).to match(value)
      end
    end
  end

  describe '#parse_password' do
    def call_parse_password
      File.open(my_fixture('aix_passwd_file.out')) do |f|
        provider.parse_password(f)
      end
    end

    it "returns :absent if the user stanza doesn't exist" do
      resource[:name] = 'nonexistent_user'
      expect(call_parse_password).to eql(:absent)
    end

    it "returns absent if the user does not have a password" do
      resource[:name] = 'no_password_user'
      expect(call_parse_password).to eql(:absent)
    end

    it "returns the user's password" do
      expect(call_parse_password).to eql('some_password')
    end
  end

  # TODO: If we move from using Mocha to rspec's mocks,
  # or a better and more robust mocking library, we should
  # remove #parse_password and copy over its tests to here.
  describe '#password' do
  end

  describe '#password=' do
    let(:mock_tempfile) do
      mock_tempfile_obj = double()
      allow(mock_tempfile_obj).to receive(:<<)
      allow(mock_tempfile_obj).to receive(:close)
      allow(mock_tempfile_obj).to receive(:delete)
      allow(mock_tempfile_obj).to receive(:path).and_return('tempfile_path')

      allow(Tempfile).to receive(:new)
        .with("puppet_#{provider.name}_pw", :encoding => Encoding::ASCII)
        .and_return(mock_tempfile_obj)

      mock_tempfile_obj
    end
    let(:cmd) do
      [provider.class.command(:chpasswd), *provider.ia_module_args, '-e', '-c']
    end
    let(:execute_options) do
      {
        :failonfail => false,
        :combine => true,
        :stdinfile => mock_tempfile.path
      }
    end

    it 'raises a Puppet::Error if chpasswd fails' do
      allow(provider).to receive(:execute).with(cmd, execute_options).and_return("failed to change passwd!")
      expect { provider.password = 'foo' }.to raise_error do |error|
        expect(error).to be_a(Puppet::Error)
        expect(error.message).to match("failed to change passwd!")
      end
    end

    it "changes the user's password" do
      expect(provider).to receive(:execute).with(cmd, execute_options).and_return("")
      provider.password = 'foo'
    end

    it "changes the user's password without leaking it into logs" do
      pending "Cannot test :execute on JRuby" if RUBY_PLATFORM == 'java' || Puppet::Util::Platform.windows?
      Puppet::Util::Log.level = :debug
      provider.password = 'foo'
      expect(@logs).to include(an_object_having_attributes(level: :debug, message: /Executing/))
      expect(@logs).not_to include(an_object_having_attributes(level: :debug, message: /foo/))
    end

    it "closes and deletes the tempfile" do
      allow(provider).to receive(:execute).with(cmd, execute_options).and_return("")

      expect(mock_tempfile).to receive(:close).twice
      expect(mock_tempfile).to receive(:delete)

      provider.password = 'foo'
    end
  end

  describe '#create' do
    it 'should create the user' do
      allow(provider.resource).to receive(:should).with(anything).and_return(nil)
      allow(provider.resource).to receive(:should).with(:groups).and_return('g1,g2')
      allow(provider.resource).to receive(:should).with(:password).and_return('password')

      expect(provider).to receive(:execute)
      expect(provider).to receive(:groups=).with('g1,g2')
      expect(provider).to receive(:password=).with('password')

      provider.create
    end

    it 'should create the user without leaking the password into logs' do
      Puppet::Util::Log.level = :debug

      #allow(provider).to receive(:command).with(:list).and_return '/usr/sbin/lsuser'
      allow(provider.class).to receive(:command).with(:list).and_return '/usr/sbin/lsuser2'
      #allow(provider).to receive(:command).with(:add).and_return '/usr/bin/mkuser'
      allow(provider.class).to receive(:command).with(:add).and_return '/usr/bin/mkuser2'
      #allow(provider).to receive(:command).with(:delete).and_return '/usr/sbin/rmuser'
      #allow(provider).to receive(:command).with(:modify).and_return '/usr/bin/chuser'
      allow(provider.class).to receive(:command).with(:modify).and_return '/usr/bin/chuser2'
      #allow(provider).to receive(:command).with(:chpasswd).and_return '/bin/chpasswd'
      allow(provider.class).to receive(:command).with(:chpasswd).and_return '/bin/chpasswd2'

      resource[:password] = 'foo'
      #resource[:groups] = ['g1','g2']

      allow(provider).to receive(:execute) do |command, options|
        #expect(command).not_to match(/foo/) if !command.nil?
        #expect(options[:stdin]).to be_an_instance_of(File)
        expect(options).not_to match(/foo/)
        #Puppet.debug('foo')
        '' # good generic result?
      end

      provider.create

      expect(@logs).not_to include(an_object_having_attributes(level: :debug, message: /foo/))
    end
  end
end
