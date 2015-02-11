require 'puppet/acceptance/install_utils'

extend Puppet::Acceptance::InstallUtils

test_name "Install Packages"

step "Install repositories on target machines..." do

  sha = ENV['SHA']
  repo_configs_dir = 'repo-configs'

  hosts.each do |host|
    install_repos_on(host, 'puppet', sha, repo_configs_dir)
  end
end


MASTER_PACKAGES = {
  :redhat => [
    'puppet-server',
  ],
  :debian => [
    'puppetmaster-passenger',
  ],
#  :solaris => [
#    'puppet-server',
#  ],
#  :windows => [
#    'puppet-server',
#  ],
}

AGENT_PACKAGES = {
  :redhat => [
    'puppet',
  ],
  :debian => [
    'puppet',
  ],
#  :solaris => [
#    'puppet',
#  ],
#  :windows => [
#    'puppet',
#  ],
}

install_packages_on(master, MASTER_PACKAGES)
install_packages_on(agents, AGENT_PACKAGES)

agents.each do |agent|
  if agent['platform'] =~ /windows/
    arch = agent[:ruby_arch] || 'x86'
    base_url = "http://builds.puppetlabs.lan/puppet/#{ENV['SHA']}/artifacts/windows"
    filename = "puppet-agent-#{ENV['VERSION']}-#{arch}.msi"

    install_puppet_from_msi(agent, :url => "#{base_url}/#{filename}")
  end
end

configure_gem_mirror(hosts)

