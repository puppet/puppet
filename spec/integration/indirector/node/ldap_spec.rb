#!/usr/bin/env rspec
require 'spec_helper'

require 'puppet/indirector/node/ldap'

describe Puppet::Node::Ldap do
  it "should use a restrictive filter when searching for nodes in a class" do
    ldap = Puppet::Node.terminus(:ldap)
    Puppet::Node.indirection.stubs(:terminus).returns ldap
    ldap.expects(:ldapsearch).with("(&(objectclass=puppetClient)(puppetclass=foo))")

    Puppet::Node.search "eh", :class => "foo"
  end
end
