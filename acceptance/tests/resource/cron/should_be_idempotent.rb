test_name "Cron: check idempotency"
confine :except, :platform => 'windows'
confine :except, :platform => /eos/ # See QA-2096

require 'puppet/acceptance/common_utils'
extend Puppet::Acceptance::CronUtils

teardown do
  step "Cron: cleanup"
  agents.each do |agent|
    clean agent
  end
end


agents.each do |agent|
  step "ensure the user exist via puppet"
  setup agent

  step "Cron: basic - verify that it can be created"
  apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => "*", minute  => [1], ensure  => present,}') do
    assert_match( /ensure: created/, result.stdout, "err: #{agent}")
  end
  run_cron_on(agent,:list,'tstuser') do
    assert_match(/. . . . . .bin.true/, result.stdout, "err: #{agent}")
  end

  step "Cron: basic - should not create again"
  apply_manifest_on(agent, 'cron { "myjob": command => "/bin/true", user    => "tstuser", hour    => "*", minute  => [1], ensure  => present,}') do
    assert_no_match( /ensure: created/, result.stdout, "err: #{agent}")
  end
end
