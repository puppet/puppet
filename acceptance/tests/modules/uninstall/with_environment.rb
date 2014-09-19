test_name 'puppet module uninstall (with environment)'
require 'puppet/acceptance/module_utils'
extend Puppet::Acceptance::ModuleUtils

tmpdir = master.tmpdir('environmentpath')

step 'Setup'

stub_forge_on(master)

puppet_conf = generate_base_legacy_and_directory_environments(tmpdir)

crakorn_metadata = <<-EOS
{
 "name": "jimmy/crakorn",
 "version": "0.4.0",
 "source": "",
 "author": "jimmy",
 "license": "MIT",
 "dependencies": []
}
EOS

# Configure a non-default environment
apply_manifest_on master, %Q{
  file {
    [
      '#{tmpdir}/legacyenv/modules/crakorn',
      '#{tmpdir}/environments/direnv/modules',
      '#{tmpdir}/environments/direnv/modules/crakorn',
    ]:
      ensure => directory,
  }
  file {
    '#{tmpdir}/legacyenv/modules/crakorn/metadata.json':
      content => '#{crakorn_metadata}',
  }
  file {
    '#{tmpdir}/environments/direnv/modules/crakorn/metadata.json':
      content => '#{crakorn_metadata}',
  }
}

check_module_uninstall_in = lambda do |environment, environment_path|
  on master, "puppet module uninstall jimmy-crakorn --config=#{puppet_conf} --environment=#{environment}" do
    assert_equal <<-OUTPUT, stdout
\e[mNotice: Preparing to uninstall 'jimmy-crakorn' ...\e[0m
Removed 'jimmy-crakorn' (\e[0;36mv0.4.0\e[0m) from #{environment_path}
    OUTPUT
  end
  on master, "[ ! -d #{environment_path}/crakorn ]"
end

step 'Uninstall a module from a non default legacy environment' do
  check_module_uninstall_in.call('legacyenv', "#{tmpdir}/legacyenv/modules")
end

step 'Enable directory environments' do
  on master, puppet("config", "set",
                    "environmentpath", "#{tmpdir}/environments",
                    "--section", "main",
                    "--config", puppet_conf)
end

step 'Uninstall a module from a non default directory environment' do
  check_module_uninstall_in.call('direnv', "#{tmpdir}/environments/direnv/modules")
end
