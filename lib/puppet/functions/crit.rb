# Log a message on the server at level crit.
Puppet::Functions.create_function(:crit, Puppet::Functions::InternalFunction) do
  dispatch :crit do
    scope_param
    repeated_param 'Any', :values
  end

  def crit(scope, *values)
    Puppet::Util::Log.log_func(scope, :crit, values)
  end
end
