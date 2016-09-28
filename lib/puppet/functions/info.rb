# Log a message on the server at level info.
Puppet::Functions.create_function(:info, Puppet::Functions::InternalFunction) do
  dispatch :info do
    scope_param
    repeated_param 'Any', :values
  end

  def info(scope, *values)
    Puppet::Util::Log.log_func(scope, :info, values)
  end
end
