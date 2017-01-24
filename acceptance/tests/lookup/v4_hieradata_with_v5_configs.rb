test_name 'C99572: v4 hieradata with v5 configs' do
  require 'puppet/acceptance/puppet_type_test_tools.rb'
  extend Puppet::Acceptance::PuppetTypeTestTools

  app_type        = File.basename(__FILE__, '.*')
  tmp_environment = mk_tmp_environment_with_teardown(master, app_type)
  fq_tmp_environmentpath  = "#{environmentpath}/#{tmp_environment}"

  confdir = master.puppet('master')['confdir']

  teardown do
    step "remove global hiera.yaml" do
      on(master, "rm #{confdir}/hiera.yaml")
    end
  end

  step "create global hiera.yaml and data" do
    create_remote_file(master, "#{confdir}/hiera.yaml", <<-HIERA)
---
version: 5
hierarchy:
  - name: "%{environment}"
    data_hash: yaml_data
    path: "%{environment}.yaml"
  - name: common
    data_hash: yaml_data
    path: "common.yaml"
    HIERA
    create_remote_file(master, "#{confdir}/#{tmp_environment}.yaml", <<-YAML)
---
environment_key: environment_key-global_env_file
global_key: global_key-global_env_file
    YAML
    create_remote_file(master, "#{confdir}/common.yaml", <<-YAML)
---
environment_key: environment_key-global_common_file
global_key: global_key-global_common_file
    YAML
  end

  step "create environment hiera.yaml and data" do
    on(master, "mkdir -p #{fq_tmp_environmentpath}/data")
    create_remote_file(master, "#{fq_tmp_environmentpath}/hiera.yaml", <<-HIERA)
---
version: 5
hierarchy:
  - name: "%{environment}"
    data_hash: yaml_data
    path: "%{environment}.yaml"
  - name: common
    data_hash: yaml_data
    path: "common.yaml"
  HIERA
    create_remote_file(master, "#{fq_tmp_environmentpath}/data/#{tmp_environment}.yaml", <<-YAML)
---
environment_key: "environment_key-env_file"
    YAML
    create_remote_file(master, "#{fq_tmp_environmentpath}/data/common.yaml", <<-YAML)
---
environment_key: "environment_key-common_file"
global_key: "global_key-common_file"
    YAML
    create_sitepp(master, tmp_environment, <<-SITE)
      notify { "${lookup('environment_key')}": }
      notify { "${lookup('global_key')}": }
    SITE
    on(master, "chmod -R 755 #{fq_tmp_environmentpath}")
  end

  step 'assert lookups using lookup subcommand' do
    on(master, puppet('lookup', "--environment #{tmp_environment}", 'environment_key'), :accept_all_exit_codes => true) do |result|
      assert(result.exit_code == 0, "lookup subcommand didn't exit properly: (#{result.exit_code})")
      assert_match(/environment_key-env_file/, result.stdout,
                   'lookup environment_key subcommand didn\'t find correct key')
    end
    on(master, puppet('lookup', "--environment #{tmp_environment}", 'global_key'), :accept_all_exit_codes => true) do |result|
      assert(result.exit_code == 0, "lookup subcommand didn't exit properly: (#{result.exit_code})")
      assert_match(/global_key-common_file/, result.stdout,
                   'lookup global_key subcommand didn\'t find correct key')
    end
  end

  with_puppet_running_on(master,{}) do
    agents.each do |agent|
      step 'agent lookup' do
        on(agent, puppet('agent', "-t --server #{master.hostname} --environment #{tmp_environment}"),
           :accept_all_exit_codes => true) do |result|
          assert(result.exit_code == 2, "agent lookup didn't exit properly: (#{result.exit_code})")
          assert_match(/global_key-common_file/m, result.stdout,
                       'agent lookup didn\'t find global key')
          assert_match(/environment_key-env_file/m, result.stdout,
                       'agent lookup didn\'t find environment key')
        end
      end
    end
  end

end
