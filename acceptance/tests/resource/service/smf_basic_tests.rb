test_name "SMF: basic tests" do
  confine :to, :platform => 'solaris'
  
  tag 'audit:medium',
      'audit:refactor',  # Use block style `test_run`
      'audit:acceptance' # Could be done at the integration (or unit) layer though
                         # actual changing of resources could irreparably damage a
                         # host running this, or require special permissions.
  
  require 'puppet/acceptance/solaris_util'
  require 'puppet/acceptance/service_utils'
  extend Puppet::Acceptance::SMFUtils
  extend Puppet::Acceptance::ServiceUtils
  
  def assert_svcs_info_matches_on(agent, service, info_hash)
    info_hash.merge({ 'next_state' => 'none' })
    on(agent, "svcs -l #{service}") do |result|
      info_hash.each do |key, value|
        escaped_key, escaped_value = Regexp.escape(key), Regexp.escape(value)
  
        assert_match(
          /^#{escaped_key}.*#{escaped_value}$/,
          result.stdout,
          "`svcs -l #{service}` does not indicate that #{key} = #{value} on #{agent}"
        )
      end
    end
  end
  
  teardown do
    agents.each do |agent|
      clean(agent, :service => 'tstapp')
    end
  end
  
  agents.each do |agent|
    clean(agent, :service => 'tstapp')
  
    # Run the tests for a non-existent service first
    run_nonexistent_service_tests(
      'tstapp',
      /Pattern 'tstapp' doesn't match any instances/,
      { 'starting' => 'ensure => running', 'enabling' => 'enable => true' }
    )
  
    # Now set-up the service
    manifest, _ = setup(agent, :service => 'tstapp')
    
    step "Ensure that the service is created with a manifest" do
      apply_manifest_on(agent, 'service {tstapp : enable=>true, manifest=>"%s", ensure=>"running"}' % manifest) do |result|
        assert_match( /ensure changed 'stopped' to 'running'/, result.stdout, "Failed to create, enable and start the service on #{agent}")
      end
    end
  
    step "Ensure that the SMF provider is idempotent -- it does not create services again" do
      apply_manifest_on(agent, 'service {tstapp : enable=>true, manifest=>"%s"}' % manifest, :catch_changes => true)
    end
  
    step "Ensure you can query the service with the ral" do
      on(agent, puppet("resource service tstapp")) do |result|
        assert_match( /ensure => 'running'/, result.stdout, "Failed to query the service with the RAL on #{agent}")
      end
    end
  
    step "Verify that ensure can be syncd. without changing the service's enabled? status" do
      on(agent, puppet("resource service tstapp ensure=stopped"))
      assert_svcs_info_matches_on(agent, 'application/tstapp', { 'enabled' => 'false (temporary)', 'state' => 'disabled' })
    end
  
    step "Ensure that when syncing only enable, the service's current status is preserved" do
      # Mark the service as maint using svcadm
      on(agent, 'svcadm mark -I maintenance tstapp')
      on(agent, puppet("resource service tstapp enable=false"))
      assert_svcs_info_matches_on(agent, 'application/tstapp', { 'enabled' => 'false', 'state' => 'maintenance' })
    end
  
    step "enable == true and ensure == stopped stop the service, but enable it to start again upon reboot" do
      on(agent, puppet("resource service tstapp enable=true ensure=stopped"))
      assert_svcs_info_matches_on(agent, 'application/tstapp', { 'enabled' => 'false (temporary)', 'state' => 'disabled' })
    end
  
    step "enable == false and ensure == running start the service, but disable it upon reboot" do
      on(agent, puppet("resource service tstapp enable=false ensure=running"))
      assert_svcs_info_matches_on(agent, 'application/tstapp', { 'enabled' => 'true (temporary)', 'state' => 'online' })
    end
  
    step "Verify that puppet will noop on the service if enable + ensure are already synced" do
      apply_manifest_on(agent, 'service {tstapp : enable=>false, ensure=>"running"}' % manifest, :catch_changes => true)
      assert_svcs_info_matches_on(agent, 'application/tstapp', { 'enabled' => 'true (temporary)', 'state' => 'online' })
    end

    step "Ensure that pupppet fails when multiple instances of the service resource exist" do
      # Add a second service instance.
      on(agent, 'svccfg -s application/tstapp add second')
      apply_manifest_on(agent, 'service {tstapp : enable=>true}') do |result|
        assert_match(/Error:.*'tstapp' matches multiple FMRIs/, result.stderr, "Puppet fails to output an error message when multiple FMRIs of a given service exist")
      end
    end
  end
end
