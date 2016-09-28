# Log a message on the server at level err.
Puppet::Functions.create_function(:err, Puppet::Functions::InternalFunction) do
  dispatch :err do
    scope_param
    repeated_param 'Any', :values
  end

  def err(scope, *values)
    Puppet::Util::Log.log_func(scope, :err, values)
  end
end
