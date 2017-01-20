tag 'risk:medium'
test_name "Write to Windows eventlog"

confine :to, :platform => 'windows'

require 'puppet/acceptance/common_utils'
extend Puppet::Acceptance::CommandUtils

require 'puppet/acceptance/windows_utils'
extend Puppet::Acceptance::WindowsUtils

agents.each do |agent|
  # get remote time
  # https://msdn.microsoft.com/en-us/library/aa394226(v=vs.85).aspx
  # set Microsecond and time zone offset both to 0
  now = on(agent, "#{ruby_command(agent)} -e \"puts Time.now.utc.strftime('%Y%m%d%H%M%S.000000-000')\"").stdout.chomp

  # generate an error, no master on windows boxes
  # we use `agent` because it creates an eventlog log destination by default,
  # whereas `apply` does not.
  on agent, puppet('agent', '--server', '127.0.0.1', '--test'), :acceptable_exit_codes => [1]

  # make sure there's a Puppet error message in the log
  # cygwin + ssh + wmic hangs trying to read stdin, so echo '' |
  on agent, "cmd /c echo '' | wmic ntevent where \"LogFile='Application' and SourceName='Puppet' and TimeWritten >= '#{now}'\"  get Message,Type /format:csv" do
    fail_test "Event not found in Application event log" unless
      stdout.include?('target machine actively refused it. - connect(2) for "127.0.0.1"')
  end
end
