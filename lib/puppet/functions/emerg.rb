# Log a message on the server at level emerg.
Puppet::Functions.create_function(:emerg, Puppet::Functions::InternalFunction) do
  dispatch :emerg do
    scope_param
    repeated_param 'Any', :values
  end

  def emerg(scope, *values)
    Puppet::Util::Log.log_func(scope, :emerg, values)
  end
end
