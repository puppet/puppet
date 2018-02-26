#!/usr/bin/env ruby
require 'spec_helper'
require 'puppet/util/windows'

describe Puppet::Util::Windows::ADSI::User,
  :if => Puppet::Util::Platform.windows? do

  describe ".initialize" do
    it "cannot reference BUILTIN accounts like SYSTEM due to WinNT moniker limitations" do
      system = Puppet::Util::Windows::ADSI::User.new('SYSTEM')
      # trying to retrieve COM object should fail to load with a localized version of:
      # ADSI connection error: failed to parse display name of moniker `WinNT://./SYSTEM,user'
      #     HRESULT error code:0x800708ad
      #           The user name could not be found.
      # Matching on error code alone is sufficient
      expect { system.native_user }.to raise_error(/0x800708ad/)
    end
  end

  describe '.each' do
    it 'should return a list of users with UTF-8 names' do
      begin
        original_codepage = Encoding.default_external
        Encoding.default_external = Encoding::CP850 # Western Europe

        Puppet::Util::Windows::ADSI::User.each do |user|
          expect(user.name.encoding).to be(Encoding::UTF_8)
        end
      ensure
        Encoding.default_external = original_codepage
      end
    end
  end

  describe '.[]' do
    it 'should return string attributes as UTF-8' do
      administrator = Puppet::Util::Windows::ADSI::User.new('Administrator')
      expect(administrator['Description'].encoding).to eq(Encoding::UTF_8)
    end
  end

  describe '.groups' do
    it 'should return a list of groups with UTF-8 names' do
      begin
        original_codepage = Encoding.default_external
        Encoding.default_external = Encoding::CP850 # Western Europe


        # lookup by English name Administrator is OK on localized Windows
        administrator = Puppet::Util::Windows::ADSI::User.new('Administrator')
        administrator.groups.each do |name|
          expect(name.encoding).to be(Encoding::UTF_8)
        end
      ensure
        Encoding.default_external = original_codepage
      end
    end
  end
end

describe Puppet::Util::Windows::ADSI::Group,
  :if => Puppet::Util::Platform.windows? do

  let (:administrator_bytes) { [1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 32, 2, 0, 0] }
  let (:administrators_principal) { Puppet::Util::Windows::SID::Principal.lookup_account_sid(administrator_bytes) }

  describe '.each' do
    it 'should return a list of groups with UTF-8 names' do
      begin
        original_codepage = Encoding.default_external
        Encoding.default_external = Encoding::CP850 # Western Europe


        Puppet::Util::Windows::ADSI::Group.each do |group|
          expect(group.name.encoding).to be(Encoding::UTF_8)
        end
      ensure
        Encoding.default_external = original_codepage
      end
    end
  end

  describe '.members' do
    it 'should return a list of members resolvable with Puppet::Util::Windows::ADSI::Group.name_sid_hash' do
      temp_groupname = "g#{SecureRandom.uuid}"
      temp_username  = "u#{SecureRandom.uuid}"[0..12]

      # select a virtual account that requires an authority to be able to resolve to SID
      # the Dhcp service is chosen for no particular reason aside from it's a service available on all Windows versions
      dhcp_virtualaccount = Puppet::Util::Windows::SID.name_to_sid_object('NT SERVICE\Dhcp')

      # adding :SidTypeGroup as a group member will cause error in IAdsUser::Add
      # adding :SidTypeDomain (such as S-1-5-80 / NT SERVICE or computer name) won't error
      #   but also won't be returned as a group member
      # uncertain how to obtain :SidTypeComputer (perhaps AD? the local machine is :SidTypeDomain)
      users = [
        # Use sid_to_name to get localized names of SIDs - BUILTIN, SYSTEM, NT AUTHORITY, Everyone are all localized
        # :SidTypeWellKnownGroup
        # SYSTEM is prefixed with the NT Authority authority, resolveable with or without authority
        { :sid => 'S-1-5-18', :name => Puppet::Util::Windows::SID.sid_to_name('S-1-5-18') },
        # Everyone is not prefixed with an authority, resolveable with or without NT AUTHORITY authority
        { :sid => 'S-1-1-0', :name => Puppet::Util::Windows::SID.sid_to_name('S-1-1-0') },
        # Dhcp service account is prefixed with NT SERVICE authority, requires authority to resolve SID
        # behavior is similar to IIS APPPOOL\DefaultAppPool
        { :sid => dhcp_virtualaccount.sid, :name => dhcp_virtualaccount.domain_account },

        # :SidTypeAlias with authority component
        # Administrators group is prefixed with BUILTIN authority, can be resolved with or without authority
        { :sid => 'S-1-5-32-544', :name => Puppet::Util::Windows::SID.sid_to_name('S-1-5-32-544') },
      ]

      begin
        # :SidTypeUser as user on localhost, can be resolved with or without authority prefix
        user = Puppet::Util::Windows::ADSI::User.create(temp_username)
        user.commit()
        users.push({ :sid => user.sid.sid, :name => Puppet::Util::Windows::ADSI.computer_name + '\\' + temp_username })

        # create a test group and add above 5 members by SID
        group = described_class.create(temp_groupname)
        group.commit()
        group.set_members(users.map { |u| u[:sid]} )

        # most importantly make sure that all name are convertible to SIDs
        expect { described_class.name_sid_hash(group.members) }.to_not raise_error

        # also verify the names returned are as expected
        expected_usernames = users.map { |u| u[:name] }
        expect(group.members).to eq(expected_usernames)
      ensure
        described_class.delete(temp_groupname) if described_class.exists?(temp_groupname)
        Puppet::Util::Windows::ADSI::User.delete(temp_username) if Puppet::Util::Windows::ADSI::User.exists?(temp_username)
      end
    end

    it 'should return a list of members with UTF-8 names' do
      begin
        original_codepage = Encoding.default_external
        Encoding.default_external = Encoding::CP850 # Western Europe

        # lookup by English name Administrators is not OK on localized Windows
        admins = Puppet::Util::Windows::ADSI::Group.new(administrators_principal.account)
        admins.members.each do |name|
          expect(name.encoding).to be(Encoding::UTF_8)
        end
      ensure
        Encoding.default_external = original_codepage
      end
    end
  end
end
