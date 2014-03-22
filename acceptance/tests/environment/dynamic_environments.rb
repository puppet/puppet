test_name "Dynamic Environments"

testdir = master.tmpdir('dynamic-environment')
environmentsdir = "#{testdir}/environments"

step "Prepare manifests and modules"
def an_environment(envdir, env)
  content = <<-ENVIRONMENT

####################
# #{env} environment
file {
  "#{envdir}/#{env}":;
  "#{envdir}/#{env}/hiera":;
  "#{envdir}/#{env}/manifests":;
  "#{envdir}/#{env}/modules":;
  "#{envdir}/#{env}/modules/amod":;
  "#{envdir}/#{env}/modules/amod/manifests":;
}

file { "#{envdir}/#{env}/hiera.yaml":
  ensure => file,
  content => '
---
:backends: yaml
:yaml:
  :datadir: "#{envdir}/%{environment}/hiera"
:hierarchy:
  - "%{environment}"
  - common
  ',
}
file { "#{envdir}/#{env}/hiera/#{env}.yaml":
  ensure => file,
  content => 'foo: foo-#{env}',
}
file { "#{envdir}/#{env}/hiera/common.yaml":
  ensure => file,
  content => 'foo: foo-common',
}
file { "#{envdir}/#{env}/manifests/site.pp":
  ensure => file,
  content => '
    notify { "#{env}-site.pp": }
    notify { "hiera":
      message => hiera(foo),
    }
    include amod
  '
}
file { "#{envdir}/#{env}/modules/amod/manifests/init.pp":
  ensure => file,
  content => '
    class amod {
      notify { "#{env}-amod": }
    }
  '
}
  ENVIRONMENT
end

manifest = <<-MANIFEST
File {
  ensure => directory,
  owner => #{master['user']},
  group => #{master['group']},
  mode => 0750,
}

file {
  "#{testdir}":;
  "#{environmentsdir}":;
}

#{an_environment(environmentsdir, 'production')}
#{an_environment(environmentsdir, 'testing')}
MANIFEST

apply_manifest_on(master, manifest, :catch_failures => true)

def test_on_agents(environment, default_env = false)
  agents.each do |agent|
    environment_switch = "--environment #{environment}" if !default_env
    on(agent, puppet("agent -t --server #{master}", environment_switch), :acceptable_exit_codes => [2] ) do
      assert_match(/#{environment}-site.pp/, stdout)
      assert_match(/foo-#{environment}/, stdout)
      assert_match(/#{environment}-amod/, stdout)
    end
  end
end

ssldir = on(master, puppet("master --configprint ssldir")).stdout.chomp

common_opts = {
    'modulepath' => "#{testdir}/environments/$environment/modules",
    'hiera_config' => "#{testdir}/environments/$environment/hiera.yaml",
}

master_opts = {
  'master' => {
    'manifest' => "#{testdir}/environments/$environment/manifests/site.pp",
  }.merge(common_opts)
}
with_puppet_running_on master, master_opts, testdir do
  step "Agent run with default environment"
  test_on_agents('production', true)
end

master_opts = {
  'master' => {
    'manifest' => "#{testdir}/environments/$environment/manifests/site.pp",
  }.merge(common_opts)
}
with_puppet_running_on master, master_opts, testdir do
  step "Agent run with testing environment"
  test_on_agents('testing')
end

master_opts = {
  'master' => {
    'manifestdir' => "#{testdir}/environments/$environment/manifests",
  }.merge(common_opts)
}
with_puppet_running_on master, master_opts, testdir do
  step "Agent run with testing environment and manifestdir set instead of manifest"
  test_on_agents('testing')
end
