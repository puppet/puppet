require 'puppet/util/windows'

Puppet::Type.type(:group).provide :windows_adsi do
  desc "Local group management for Windows. Group members can be both users and groups.
    Additionally, local groups can contain domain users."

  defaultfor :operatingsystem => :windows
  confine    :operatingsystem => :windows

  has_features :manages_members

  def members_insync?(current, should)
    return false unless current

    # By comparing account SIDs we don't have to worry about case
    # sensitivity, or canonicalization of account names.

    # Cannot use munge of the group property to canonicalize @should
    # since the default array_matching comparison is not commutative
    (should_empty = should.nil?) || should.empty?

    return false if current.empty? != should_empty

    # dupes automatically weeded out when hashes built
    Puppet::Util::Windows::ADSI::Group.name_sid_hash(current) == Puppet::Util::Windows::ADSI::Group.name_sid_hash(should)
  end

  def members_to_s(users)
    return '' if users.nil? || !users.kind_of?(Array)
    users = users.map do |user_name|
      sid = Puppet::Util::Windows::SID.name_to_sid_object(user_name)
      if sid.account =~ /\\/
        account, _ = Puppet::Util::Windows::ADSI::User.parse_name(sid.account)
      else
        account = sid.account
      end
      resource.debug("#{sid.domain}\\#{account} (#{sid.to_s})")
      "#{sid.domain}\\#{account}"
    end
    return users.join(',')
  end

  def group
    @group ||= Puppet::Util::Windows::ADSI::Group.new(@resource[:name])
  end

  def members
    group.members
  end

  def members=(members)
    group.set_members(members)
  end

  def create
    @group = Puppet::Util::Windows::ADSI::Group.create(@resource[:name])
    @group.commit

    self.members = @resource[:members]
  end

  def exists?
    Puppet::Util::Windows::ADSI::Group.exists?(@resource[:name])
  end

  def delete
    Puppet::Util::Windows::ADSI::Group.delete(@resource[:name])
  end

  # Only flush if we created or modified a group, not deleted
  def flush
    @group.commit if @group
  end

  def gid
    Puppet::Util::Windows::SID.name_to_sid(@resource[:name])
  end

  def gid=(value)
    fail "gid is read-only"
  end

  def self.instances
    Puppet::Util::Windows::ADSI::Group.map { |g| new(:ensure => :present, :name => g.name) }
  end
end
