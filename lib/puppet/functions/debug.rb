# Log a message on the server at level debug.
Puppet::Functions.create_function(:debug, Puppet::Functions::InternalFunction) do
  dispatch :debug do
    scope_param
    repeated_param 'Any', :values
  end

  def debug(scope, *values)
    Puppet::Util::Log.log_func(scope, :debug, values)
  end
end
