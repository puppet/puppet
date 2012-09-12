test_name "Zone: dataset configuration"

confine :to, :platform => 'solaris'

require 'puppet/acceptance/solaris_util'
extend Puppet::Acceptance::ZoneUtils

def moresetup(agent)
  on agent,"zfs create tstpool/xx"
  on agent,"zfs create tstpool/yy"
  on agent,"zfs create tstpool/zz"
end

teardown do
  step "Zone: dataset - cleanup"
  agents.each do |agent|
    clean agent
  end
end


agents.each do |agent|
  step "Zone: dataset - cleanup"
  clean agent
  step "Zone: dataset - setup"
  setup agent, :size => '64m'
  moresetup agent
  #-----------------------------------
  step "Zone: dataset - clean slate"
  # Make sure that the zone is absent.
  apply_manifest_on(agent, 'zone {tstzone : ensure=>absent}') do
    assert_match( /Finished catalog run in .*/, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - make it configured"
  # Make it configured
  apply_manifest_on(agent, 'zone {tstzone : ensure=>configured, path=>"/tstzones/mnt" }') do
    assert_match( /ensure: created/, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - idempotency, should not create again."
  apply_manifest_on(agent, 'zone {tstzone : ensure=>configured, path=>"/tstzones/mnt" }') do
    assert_no_match( /ensure: created/, result.stdout, "err: #{agent}")
  end

  step "Zone: dataset - basic test, a single data set"
  apply_manifest_on(agent, 'zone {tstzone : ensure=>configured, dataset=>"tstpool/xx", path=>"/tstzones/mnt" }') do
    assert_match(/defined 'dataset' as .'tstpool.xx'./, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - basic test, a single data set should change to another"
  apply_manifest_on(agent,'zone {tstzone : ensure=>configured, dataset=>"tstpool/yy", path=>"/tstzones/mnt" }') do
    assert_match(/dataset changed 'tstpool.xx' to .'tstpool.yy'./, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - basic test, idempotency"
  apply_manifest_on(agent,'zone {tstzone : ensure=>configured, dataset=>"tstpool/yy", path=>"/tstzones/mnt" }') do
    assert_no_match(/dataset changed 'tstpool.xx' to .'tstpool.yy'./, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - array test, should change to an array"
  apply_manifest_on(agent,'zone {tstzone : ensure=>configured, dataset=>["tstpool/yy","tstpool/zz"], path=>"/tstzones/mnt" }') do
    assert_match(/dataset changed 'tstpool.yy' to .'tstpool.yy', 'tstpool.zz'./, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - array test, should change one single element"
  apply_manifest_on(agent,'zone {tstzone : ensure=>configured, dataset=>["tstpool/xx","tstpool/zz"], path=>"/tstzones/mnt" }') do
    assert_match(/dataset changed 'tstpool.yy,tstpool.zz' to .'tstpool.xx', 'tstpool.zz'./, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - array test, should remove elements"
  apply_manifest_on(agent,'zone {tstzone : ensure=>configured, dataset=>[], path=>"/tstzones/mnt" }') do
    assert_match(/dataset changed 'tstpool.zz,tstpool.xx' to ../, result.stdout, "err: #{agent}")
  end
  step "Zone: dataset - ensure can remove"
  apply_manifest_on(agent, 'zone {tstzone : ensure=>absent}') do
    assert_match( /ensure: removed/, result.stdout, "err: #{agent}")
  end
end
