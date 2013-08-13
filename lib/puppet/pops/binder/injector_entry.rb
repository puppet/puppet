# Represents an entry in the injectors internal data.
#
# @api private
#
class Puppet::Pops::Binder::InjectorEntry
  # @api private
  attr_reader :precedence

  # @api private
  attr_reader :binding

  # @api private
  attr_accessor :resolved

  # @api private
  attr_accessor :cached

  # @api private
  attr_accessor :cached_producer

  # @api private
  def initialize(precedence, binding)
    @precedence = precedence
    @binding = binding
    @cached_producer = nil
  end

  # Marks an overriding entry as resolved (if not an overriding entry, the marking has no effect).
  # @api private
  #
  def mark_override_resolved()
    @resolved = true
  end

  # The binding is resolved if it is non-override, or if the override has been resolved
  # @api private
  #
  def is_resolved?()
    !binding.override || resolved
  end

  def is_abstract?
    binding.abstract
  end
end
