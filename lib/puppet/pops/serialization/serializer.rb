require_relative 'extension'

module Puppet::Pops
module Serialization
  class Serializer
    def initialize(writer)
      @written = {}
      @writer = writer
    end

    def finish
      @writer.finish
    end

    def flush
      @writer.flush
    end

    def start_array(size)
      @writer.write(Extension::ArrayStart.new(size))
    end

    def start_map(size)
      @writer.write(Extension::MapStart.new(size))
    end

    def start_object(type_ref, attr_count)
      @writer.write(Extension::ObjectStart.new(type_ref, attr_count))
    end

    def write(value)
      case value
      when Integer, Float, String, true, false, nil, Time
        @writer.write(value)
      when :default
        @writer.write(Extension::Default::INSTANCE)
      else
        index = @written[value.object_id]
        if index.nil?
          write_tabulated_first_time(value)
        else
          @writer.write(Extension::Tabulation.new(index)) unless index.nil?
        end
      end
    end

    def write_tabulated_first_time(value)
      @written[value.object_id] = @written.size
      case value
      when Symbol, Regexp, Semantic::Version, Semantic::VersionRange
        @writer.write(value)
      when Array
        start_array(value.size)
        value.each { |elem| write(elem) }
      when Hash
        start_map(value.size)
        value.each_pair { |key, val| write(key); write(val) }
      when Types::PTypeReferenceType
        @writer.write(value)
      when Types::PuppetObject
        value._ptype.write(value, self)
      else
        impl_class = value.class
        type = Loaders.implementation_registry.type_for_module(impl_class)
        raise SerializationError, "No Puppet Type found for #{impl_class.name}" unless type.is_a?(Types::PObjectType)
        type.write(value, self)
      end
    end
  end
end
end
