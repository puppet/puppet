# Group Puppet provider for AIX. It uses standard commands to manage groups:
#  mkgroup, rmgroup, lsgroup, chgroup
require 'puppet/provider/aix_object'

Puppet::Type.type(:group).provide :aix, :parent => Puppet::Provider::AixObject do
  desc "Group management for AIX."

  # This will the default provider for this platform
  defaultfor :operatingsystem => :aix
  confine :operatingsystem => :aix

  # Commands that manage the element
  commands :list      => "/usr/sbin/lsgroup"
  commands :add       => "/usr/bin/mkgroup"
  commands :delete    => "/usr/sbin/rmgroup"
  commands :modify    => "/usr/bin/chgroup"

  # Provider features
  has_features :manages_aix_lam
  has_features :manages_members

  class << self
    # Used by the AIX user provider. Returns a hash of:
    #   {
    #     :name => <group_name>,
    #     :gid  => <gid>
    #   }
    #
    # that matches the group, which can either be the group name or
    # the gid. Takes an optional set of ia_module_args
    def find(group, ia_module_args = [])
      groups = list_all(ia_module_args)

      id_property = mappings[:puppet_property][:id]

      if group.is_a?(String)
        # Find by name
        group_hash = groups.find { |cur_group| cur_group[:name] == group }
      else
        # Find by gid
        group_hash = groups.find do |cur_group|
          id_property.convert_attribute_value(cur_group[:id]) == group
        end
      end

      unless group_hash
        raise ArgumentError, _("No AIX group exists with a group name or gid of %{group}!") % { group: group }
      end

      # Convert :id => :gid
      id = group_hash.delete(:id)
      group_hash[:gid] = id_property.convert_attribute_value(id)

      group_hash
    end
  end

  mapping puppet_property: :members,
          aix_attribute: :users

  numeric_mapping puppet_property: :gid,
                  aix_attribute: :id

  # Now that we have all of our mappings, let's go ahead and make
  # the resource methods (property getters + setters for our mapped
  # properties + a getter for the attributes property).
  mk_resource_methods
end
