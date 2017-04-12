require 'puppet/util/character_encoding'
# Wrapper around Ruby Etc module allowing us to manage encoding in a single
# place.
# This represents a subset of Ruby's Etc module, only the methods required by Puppet.
# Etc returns strings in variable encoding depending on
# environment. For Puppet we specifically want UTF-8 as our input from the Etc
# module - which is our input for many resource instance 'is' values. The
# associated 'should' value will basically always be coming from Puppet in
# UTF-8. Etc is defined for Windows but calls to it return nil.
#
# We only use Etc for retrieving existing property values from the system. For
# setting property values, providers leverage system tools (i.e., `useradd`)
#
# @api private
module Puppet::Etc
  class << self
    # Etc::getgrent returns an Etc::Group struct object
    # On first call opens /etc/group and returns parse of first entry. Each subsquent call
    # returns new struct the next entry or nil if EOF. Call ::endgrent to close file.
    def getgrent
      convert_field_values_to_utf8!(::Etc.getgrent)
    end

    # closes handle to /etc/group file
    def endgrent
      ::Etc.endgrent
    end

    # effectively equivalent to IO#rewind of /etc/group
    def setgrent
      ::Etc.setgrent
    end

    # Etc::getpwent returns an Etc::Passwd struct object
    # On first call opens /etc/passwd and returns parse of first entry. Each subsquent call
    # returns new struct for the next entry or nil if EOF. Call ::endgrent to close file.
    def getpwent
      convert_field_values_to_utf8!(::Etc.getpwent)
    end

    # closes handle to /etc/passwd file
    def endpwent
      ::Etc.endpwent
    end

    #effectively equivalent to IO#rewind of /etc/passwd
    def setpwent
      ::Etc.setpwent
    end

    # Etc::getpwnam searches /etc/passwd file for an entry corresponding to
    # username.
    # returns an Etc::Passwd struct corresponding to the entry or raises
    # ArgumentError if none
    def getpwnam(username)
      convert_field_values_to_utf8!(::Etc.getpwnam(username))
    end

    # Etc::getgrnam searches /etc/group file for an entry corresponding to groupname.
    # returns an Etc::Group struct corresponding to the entry or raises
    # ArgumentError if none
    def getgrnam(groupname)
      convert_field_values_to_utf8!(::Etc.getgrnam(groupname))
    end

    # Etc::getgrid searches /etc/group file for an entry corresponding to id.
    # returns an Etc::Group struct corresponding to the entry or raises
    # ArgumentError if none
    def getgrgid(id)
      convert_field_values_to_utf8!(::Etc.getgrgid(id))
    end

    # Etc::getpwuid searches /etc/passwd file for an entry corresponding to id.
    # returns an Etc::Passwd struct corresponding to the entry or raises
    # ArgumentError if none
    def getpwuid(id)
      convert_field_values_to_utf8!(::Etc.getpwuid(id))
    end

    private
    # Utility method for converting the String values of a struct returned by
    # the Etc module to UTF-8. Structs returned by the ruby Etc module contain
    # members with fields of type String, Integer, or Array of Strings, so we
    # handle these types. Otherwise ignore fields.
    #
    # NOTE: If a string cannot be converted to UTF-8, this leaves the original
    # string string intact in the Struct.
    #
    # Warning! This is a destructive method - the struct passed is modified!
    #
    # @api private
    # @param [Etc::Passwd or Etc::Group struct]
    # @return [Etc::Passwd or Etc::Group struct] the original struct with values
    #   converted to UTF-8 if possible, or the original value intact if not
    def convert_field_values_to_utf8!(struct)
      return nil if struct.nil?
      struct.each_with_index do |value, index|
        if value.is_a?(String)
            converted = Puppet::Util::CharacterEncoding.convert_to_utf_8!(value)
            struct[index] = converted if !converted.nil?
        elsif value.is_a?(Array)
          struct[index] = convert_array_values_to_utf8!(value)
        end
      end
    end

    # Helper method for ::convert_field_values_to_utf8!
    #
    # Warning! This is a destructive method - the array passed is modified!
    #
    # @api private
    # @param [Array] object containing String values to convert to UTF-8
    # @return [Array] original Array with String values converted to UTF-8 if
    #   convertible, or original, unmodified values if not.
    def convert_array_values_to_utf8!(string_array)
      string_array.map! do |elem|
        converted = Puppet::Util::CharacterEncoding.convert_to_utf_8!(elem)
        converted.nil? ? elem : converted
      end
    end
  end
end



