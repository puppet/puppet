#!/usr/bin/env rspec
#
# Unit testing for the Windows service Provider
#

require 'spec_helper'

require 'win32/service' if Puppet.features.microsoft_windows?

describe Puppet::Type.type(:service).provider(:windows), :if => Puppet.features.microsoft_windows? do
  before :each do
    @resource = Puppet::Type.type(:service).new(:name => 'nonexistentservice', :provider => :windows)
    @resource.provider.class.expects(:execute).never

    @config = Struct::ServiceConfigInfo.new

    @status = Struct::ServiceStatus.new

    Win32::Service.stubs(:config_info).with(@resource[:name]).returns(@config)
    Win32::Service.stubs(:status).with(@resource[:name]).returns(@status)
  end

  describe ".instances" do
    it "should enumerate all services" do
      list_of_services = ['snmptrap', 'svchost', 'sshd'].map { |s| stub('service', :service_name => s) }
      Win32::Service.expects(:services).returns(list_of_services)

      described_class.instances.map(&:name).should =~ ['snmptrap', 'svchost', 'sshd']
    end
  end

  describe "#start" do
    before :each do
      @config.start_type = Win32::Service.get_start_type(Win32::Service::SERVICE_AUTO_START)
    end

    it "should start the service" do
      @resource.provider.expects(:sc).with(:start, @resource[:name])
      @resource.provider.start
    end

    it "should not raise an exception if the service is already running" do
      @resource.provider.expects(:sc).with(:start, @resource[:name]).raises(Puppet::ExecutionFailure, 'Failed')
      @resource.provider.stubs(:exitstatus).returns(1056) # ERROR_SERVICE_ALREADY_RUNNING

      @resource.provider.start
    end

    it "should raise an error otherwise" do
      @resource.provider.expects(:sc).with(:start, @resource[:name]).raises(Puppet::ExecutionFailure, 'Failed')
      @resource.provider.stubs(:exitstatus).returns(1053) # ERROR_SERVICE_REQUEST_TIMEOUT

      expect { @resource.provider.start }.to raise_error(
        Puppet::Error,
        /Cannot start .*:  The service did not respond to the start or control request in a timely fashion./
      )
    end

    describe "when the service is disabled" do
      before :each do
        @config.start_type = Win32::Service.get_start_type(Win32::Service::SERVICE_DISABLED)
      end

      it "should refuse to start if not managing enable" do
        expect { @resource.provider.start }.to raise_error(Puppet::Error, /Will not start disabled service/)
      end

      it "should enable if managing enable and enable is true" do
        @resource[:enable] = :true

        @resource.provider.expects(:sc).with(:start, @resource[:name])
        Win32::Service.expects(:configure).with('service_name' => @resource[:name], 'start_type' => Win32::Service::SERVICE_AUTO_START).returns(Win32::Service)

        @resource.provider.start
      end

      it "should manual start if managing enable and enable is false" do
        @resource[:enable] = :false

        @resource.provider.expects(:sc).with(:start, @resource[:name])
        Win32::Service.expects(:configure).with('service_name' => @resource[:name], 'start_type' => Win32::Service::SERVICE_DEMAND_START).returns(Win32::Service)

        @resource.provider.start
      end
    end
  end

  describe "#stop" do
    it "should stop a running service" do
      @resource.provider.expects(:sc).with(:stop, @resource[:name])

      @resource.provider.stop
    end

    it "should not raise an exception if the service is already stopped" do
      @resource.provider.expects(:sc).with(:stop, @resource[:name]).raises(Puppet::ExecutionFailure, 'Failed')
      @resource.provider.stubs(:exitstatus).returns(1062) # ERROR_SERVICE_NOT_ACTIVE

      @resource.provider.stop
    end

    it "raise an exception otherwise" do
      @resource.provider.expects(:sc).with(:stop, @resource[:name]).raises(Puppet::ExecutionFailure, 'Failed')
      @resource.provider.stubs(:exitstatus).returns(1051) # ERROR_DEPENDENT_SERVICES_RUNNING

      expect { @resource.provider.stop }.to raise_error(
        Puppet::Error,
        /Cannot stop .*:  A stop control has been sent to a service that other running services are dependent on./
      )
    end
  end

  describe "#status" do
    ['stopped', 'paused', 'stop pending', 'pause pending'].each do |state|
      it "should report a #{state} service as stopped" do
        @status.current_state = state

        @resource.provider.status.should == :stopped
      end
    end

    ["running", "continue pending", "start pending" ].each do |state|
      it "should report a #{state} service as running" do
        @status.current_state = state

        @resource.provider.status.should == :running
      end
    end
  end

  describe "#enabled?" do
    it "should report a service with a startup type of manual as manual" do
      @config.start_type = Win32::Service.get_start_type(Win32::Service::SERVICE_DEMAND_START)

      @resource.provider.enabled?.should == :manual
    end

    it "should report a service with a startup type of disabled as false" do
      @config.start_type = Win32::Service.get_start_type(Win32::Service::SERVICE_DISABLED)

      @resource.provider.enabled?.should == :false
    end

    # We need to guard this section explicitly since rspec will always
    # construct all examples, even if it isn't going to run them.
    if Puppet.features.microsoft_windows?
      [Win32::Service::SERVICE_AUTO_START, Win32::Service::SERVICE_BOOT_START, Win32::Service::SERVICE_SYSTEM_START].each do |start_type_const|
        start_type = Win32::Service.get_start_type(start_type_const)
        it "should report a service with a startup type of '#{start_type}' as true" do
          @config.start_type = start_type

          @resource.provider.enabled?.should == :true
        end
      end
    end
  end

  describe "#enable" do
    it "should set service start type to Service_Auto_Start when enabled" do
      Win32::Service.expects(:configure).with('service_name' => @resource[:name], 'start_type' => Win32::Service::SERVICE_AUTO_START).returns(Win32::Service)
      @resource.provider.enable
    end
  end

  describe "#disable" do
    it "should set service start type to Service_Disabled when disabled" do
      Win32::Service.expects(:configure).with('service_name' => @resource[:name], 'start_type' => Win32::Service::SERVICE_DISABLED).returns(Win32::Service)
      @resource.provider.disable
     end
  end

  describe "#manual_start" do
    it "should set service start type to Service_Demand_Start (manual) when manual" do
      Win32::Service.expects(:configure).with('service_name' => @resource[:name], 'start_type' => Win32::Service::SERVICE_DEMAND_START).returns(Win32::Service)
      @resource.provider.manual_start
    end
  end
end
