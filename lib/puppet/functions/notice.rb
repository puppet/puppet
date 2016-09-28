# Log a message on the server at level notice.
Puppet::Functions.create_function(:notice, Puppet::Functions::InternalFunction) do
  dispatch :notice do
    scope_param
    repeated_param 'Any', :values
  end

  def notice(scope, *values)
    Puppet::Util::Log.log_func(scope, :notice, values)
  end
end
