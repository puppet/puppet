test_name "dpkg ensure held package is latest installed"
confine :to, :platform => /debian-8-amd64/
require 'puppet/acceptance/common_utils'
extend Puppet::Acceptance::PackageUtils
extend Puppet::Acceptance::ManifestUtils


package = "nginx"

agents.each do |agent|
  teardown do
    package_absent(agent, package, '--force-yes')
  end
end

step "Ensure that package is installed first if not present" do
  info = on(agent.name, "apt-cache policy #{package} | grep Candidate:").stdout
  expected_package_version = info.split[1]
  package_manifest = resource_manifest('package', package, ensure: "held")

  apply_manifest_on(agent, package_manifest) do |result|
    info = on(agent.name, "apt-cache policy #{package} | grep Installed").stdout
    installed_package_version = info.split[1]
    assert_match(expected_package_version, installed_package_version)
  end
end
