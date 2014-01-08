# The Adapters module contains adapters for Documentation, Origin, SourcePosition, and Loader.
#
module Puppet::Pops::Adapters
  # A documentation adapter adapts an object with a documentation string.
  # (The intended use is for a source text parser to extract documentation and store this
  # in DocumentationAdapter instances).
  #
  class DocumentationAdapter < Puppet::Pops::Adaptable::Adapter
    # @return [String] The documentation associated with an object
    attr_accessor :documentation
  end

  # A SourcePosAdapter holds a reference to  a *Positioned* object (object that has offset and length).
  # This somewhat complex structure makes it possible to correctly refer to a source position
  # in source that is embedded in some resource; a parser only sees the embedded snippet of source text
  # and does not know where it was embedded. It also enables lazy evaluation of source positions (they are
  # rarely needed - typically just when there is an error to report.
  #
  # @note It is relatively expensive to compute line and position on line - it is not something that
  #   should be done for every token or model object.
  #
  # @see Puppet::Pops::Utils#find_adapter, Puppet::Pops::Utils#find_closest_positioned
  #
  class SourcePosAdapter < Puppet::Pops::Adaptable::Adapter
    attr_accessor :locator

    def self.create_adapter(o)
      new(o)
    end

    def initialize(o)
      @adapted = o
    end

    def locator
      @locator ||= find_locator(@adapted.eContainer)
    end

    def find_locator(o)
      if o.nil?
        raise ArgumentError, "InternalError: SourcePosAdapter for something that has no locator among parents"
      end
      return o.locator if o.is_a?(Puppet::Pops::Model::Program)
      if adapter = self.class.get(o)
        return adapter.locator
      else
        find_locator(o.eContainer)
      end
    end
    private :find_locator

    def offset
      @adapted.offset
    end

    def length
      @adapted.length
    end

    # Produces the line number for the given offset.
    # @note This is an expensive operation
    #
    def line
      locator.line_for_offset(offset)
    end

    # Produces the position on the line of the given offset.
    # @note This is an expensive operation
    #
    def pos
      locator.pos_on_line(offset)
    end

    # Extracts the text represented by this source position (the string is obtained from the locator)
    def extract_text
      locator.string.slice(offset, length)
    end
  end

  # A LoaderAdapter adapts an object with a {Puppet::Pops::Loader}. This is used to make further loading from the
  # perspective of the adapted object take place in the perspective of this Loader.
  #
  # It is typically enough to adapt the root of a model as a search is made towards the root of the model
  # until a loader is found, but there is no harm in duplicating this information provided a contained
  # object is adapted with the correct loader.
  #
  # @see Puppet::Pops::Utils#find_adapter
  #
  class LoaderAdapter < Puppet::Pops::Adaptable::Adapter
    # @return [Puppet::Pops::Loader] the loader
    attr_accessor :loader
  end
end
