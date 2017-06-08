require 'puppet/resource/status'

class Puppet::Transaction::ResourceHarness
  NO_ACTION = Object.new

  extend Forwardable
  def_delegators :@transaction, :relationship_graph

  attr_reader :transaction

  def initialize(transaction)
    @transaction = transaction
    @persistence = transaction.persistence
  end

  def evaluate(resource)
    status = Puppet::Resource::Status.new(resource)

    begin
      context = ResourceApplicationContext.from_resource(resource, status)
      perform_changes(resource, context)

      if status.changed? && ! resource.noop?
        cache(resource, :synced, Time.now)
        resource.flush if resource.respond_to?(:flush)
      end
    rescue => detail
      status.failed_because(detail)
    ensure
      status.evaluation_time = Time.now - status.time
    end

    status
  end

  def scheduled?(resource)
    return true if Puppet[:ignoreschedules]
    return true unless schedule = schedule(resource)

    # We use 'checked' here instead of 'synced' because otherwise we'll
    # end up checking most resources most times, because they will generally
    # have been synced a long time ago (e.g., a file only gets updated
    # once a month on the server and its schedule is daily; the last sync time
    # will have been a month ago, so we'd end up checking every run).
    schedule.match?(cached(resource, :checked).to_i)
  end

  def schedule(resource)
    unless resource.catalog
      resource.warning _("Cannot schedule without a schedule-containing catalog")
      return nil
    end

    return nil unless name = resource[:schedule]
    resource.catalog.resource(:schedule, name) || resource.fail(_("Could not find schedule %{name}") % { name: name })
  end

  # Used mostly for scheduling at this point.
  def cached(resource, name)
    Puppet::Util::Storage.cache(resource)[name]
  end

  # Used mostly for scheduling at this point.
  def cache(resource, name, value)
    Puppet::Util::Storage.cache(resource)[name] = value
  end

  private

  def perform_changes(resource, context)
    cache(resource, :checked, Time.now)

    ensure_param = resource.parameter(:ensure)
    if ensure_param && ensure_param.should
      ensure_event = sync_if_needed(ensure_param, context)
    else
      ensure_event = NO_ACTION
    end

    if ensure_event == NO_ACTION
      if context.resource_present?
        resource.properties.each do |param|
          sync_if_needed(param, context)
        end
      else
        resource.debug("Nothing to manage: no ensure and the resource doesn't exist")
      end
    end

    persist_system_values(resource, context)
  end

  # We persist the last known values for the properties of a resource after resource
  # application.
  # @param [Puppet::Type] resource resource whose values we are to persist.
  # @param [ResourceApplicationContent] context the application context to operate on.
  def persist_system_values(resource, context)
    param_to_event = {}
    context.status.events.each do |ev|
      param_to_event[ev.property] = ev
    end

    context.system_value_params.each do |pname, param|
      @persistence.set_system_value(resource.ref, pname.to_s,
                                    new_system_value(param,
                                                     param_to_event[pname.to_s],
                                                     @persistence.get_system_value(resource.ref, pname.to_s)))
    end
  end

  def sync_if_needed(param, context)
    current_value = context.current_values[param.name]

    begin
      if param.should && !param.safe_insync?(current_value)
        event = create_change_event(param, current_value)

        if param.noop
          noop(event, param, current_value)
        else
          sync(event, param, current_value)
        end

        event
      else
        NO_ACTION
      end
    rescue => detail
      # Execution will continue on StandardErrors, just store the event
      Puppet.log_exception(detail)

      event = create_change_event(param, current_value)
      event.status = "failure"
      event.message = param.format(_("change from %s to %s failed: "),
                                   param.is_to_s(current_value),
                                   param.should_to_s(param.should)) + detail.to_s
      event
    rescue Exception => detail
      # Execution will halt on Exceptions, they get raised to the application
      event = create_change_event(param, current_value)
      event.status = "failure"
      event.message = param.format(_("change from %s to %s failed: "),
                                   param.is_to_s(current_value),
                                   param.should_to_s(param.should)) + detail.to_s
      raise
    ensure
      if event
        event.calculate_corrective_change(@persistence.get_system_value(context.resource.ref, param.name.to_s))
        context.record(event)
        event.send_log
        context.synced_params << param.name
      end
    end
  end

  def create_change_event(property, current_value)
    options = {}
    should = property.should

    if property.sensitive
      options[:previous_value] = current_value.nil? ? nil : '[redacted]'
      options[:desired_value] = should.nil? ? nil : '[redacted]'
    else
      options[:previous_value] = current_value
      options[:desired_value] = should
    end

    property.event(options)
  end

  def noop(event, param, current_value)
    event.message = param.format(_("current_value %s, should be %s (noop)"),
                                 param.is_to_s(current_value),
                                 param.should_to_s(param.should))
    event.status = "noop"
  end

  def sync(event, param, current_value)
    param.sync
    if param.sensitive
      event.message = param.format(_("changed %s to %s"),
                                   param.is_to_s(current_value),
                                   param.should_to_s(param.should))
    else
      event.message = "#{param.change_to_s(current_value, param.should)}"
    end
    event.status = "success"
  end

  # Given an event and its property, calculate the system_value to persist
  # for future calculations.
  # @param [Puppet::Transaction::Event] event event to use for processing
  # @param [Puppet::Property] property correlating property
  # @param [Object] old_system_value system_value from last transaction
  # @return [Object] system_value to be used for next transaction
  def new_system_value(property, event, old_system_value)
    if event && event.status != "success"
      # For non-success events, we persist the old_system_value if it is defined,
      # or use the event previous_value.
      # If we're using the event previous_value, we ensure that it's
      # an array. This is needed because properties assume that their
      # `should` value is an array, and we will use this value later
      # on in property insync? logic.
      event_value = [event.previous_value] unless event.previous_value.is_a?(Array)
      old_system_value.nil? ? event_value : old_system_value
    else
      # For non events, or for success cases, we just want to store
      # the parameters agent value.
      # We use instance_variable_get here because we want this process to bypass any
      # munging/unmunging or validation that the property might try to do, since those
      # operations may not be correctly implemented for custom types.
      # require 'pry'; binding.pry if property.name == :permissions
      should_value = property.instance_variable_get(:@should)
      # wrapping trick to ensure Enumerable
      [should_value].flatten.each { |i| customize_yaml_generation(i) }
      should_value
    end
  end

  def customize_yaml_generation(instance, to_remove = ['provider'])
    # require 'pry'; binding.pry if instance.class.name == 'Puppet::Type::Acl::Ace'
    if !instance.respond_to?(:encode_with) && to_remove.any? { |n| instance.instance_variable_defined?("@#{n}") }
      singleton_class = class << instance; self; end
      singleton_class.send(:define_method, :encode_with) do |coder|
        names = instance_variables.map { |i| i.to_s[1..-1] } - to_remove
        names.each do |var|
          coder[var] = instance.instance_variable_get("@#{var}")
        end
      end
    end
  end

  # @api private
  ResourceApplicationContext = Struct.new(:resource,
                                          :current_values,
                                          :synced_params,
                                          :status,
                                          :system_value_params) do
    def self.from_resource(resource, status)
      ResourceApplicationContext.new(resource,
                                     resource.retrieve_resource.to_hash,
                                     [],
                                     status,
                                     resource.parameters.select { |n,p| p.is_a?(Puppet::Property) && !p.sensitive })
    end

    def resource_present?
      resource.present?(current_values)
    end

    def record(event)
      status << event
    end
  end
end
