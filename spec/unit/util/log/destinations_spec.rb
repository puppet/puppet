#!/usr/bin/env rspec
require 'spec_helper'

require 'puppet/util/log'

describe Puppet::Util::Log.desttypes[:report] do
  before do
    @dest = Puppet::Util::Log.desttypes[:report]
  end

  it "should require a report at initialization" do
    @dest.new("foo").report.should == "foo"
  end

  it "should send new messages to the report" do
    report = mock 'report'
    dest = @dest.new(report)

    report.expects(:<<).with("my log")

    dest.handle "my log"
  end
end


describe Puppet::Util::Log.desttypes[:file] do
  before do
    File.stubs(:open)           # prevent actually creating the file
    @class = Puppet::Util::Log.desttypes[:file]
  end

  it "should default to autoflush false" do
    @class.new('/tmp/log').autoflush.should == false
  end

  describe "when matching" do
    shared_examples_for "file destination" do
      it "should match an absolute path" do
        @class.match?(abspath).should be_true
      end

      it "should not match a relative path" do
        @class.match?(relpath).should be_false
      end
    end

    describe "on POSIX systems" do
      before :each do Puppet.features.stubs(:microsoft_windows?).returns false end

      let (:abspath) { '/tmp/log' }
      let (:relpath) { 'log' }

      it_behaves_like "file destination"
    end

    describe "on Windows systems" do
      before :each do Puppet.features.stubs(:microsoft_windows?).returns true end

      let (:abspath) { 'C:\\temp\\log.txt' }
      let (:relpath) { 'log.txt' }

      it_behaves_like "file destination"
    end
  end
end

describe Puppet::Util::Log.desttypes[:syslog] do
  let (:klass) { Puppet::Util::Log.desttypes[:syslog] }

  # these tests can only be run when syslog is present, because
  # we can't stub the top-level Syslog module
  describe "when syslog is available", :if => Puppet.features.syslog? do
    before :each do
      Syslog.stubs(:opened?).returns(false)
      Syslog.stubs(:const_get).returns("LOG_KERN").returns(0)
      Syslog.stubs(:open)
    end

    it "should open syslog" do
      Syslog.expects(:open)

      klass.new
    end

    it "should close syslog" do
      Syslog.expects(:close)

      dest = klass.new
      dest.close
    end

    it "should send messages to syslog" do
      syslog = mock 'syslog'
      syslog.expects(:info).with("don't panic")
      Syslog.stubs(:open).returns(syslog)

      msg = Puppet::Util::Log.new(:level => :info, :message => "don't panic")
      dest = klass.new
      dest.handle(msg)
    end
  end

  describe "when syslog is unavailable" do
    it "should not be a suitable log destination" do
      Puppet.features.stubs(:syslog?).returns(false)

      klass.suitable?(:syslog).should be_false
    end
  end

  describe Puppet::Util::Log.desttypes[:console] do
    before :each do
      Puppet[:color] = true
    end

    let (:dest) { Puppet::Util::Log.desttypes[:console].new }

    describe "when color is enabled" do
      let (:red_string)   { dest.colorize(:red, 'string') }
      let (:reset_string) { dest.colorize(:reset, 'string') }

      it "should color output" do
        dest.colorize(:red, 'string').should == "[0;31mstring[0m"
      end

      it "should handle multiple overlapping colors in a stack-like way" do
        dest.colorize(:green, "(#{red_string})").should == "[0;32m([0;31mstring[0;32m)[0m"
      end

      it "should handle resets in a stack-like way" do
        dest.colorize(:green, "(#{reset_string})").should == "[0;32m([mstring[0;32m)[0m"
      end

      describe "when the message source is Puppet::Interface" do
        before :each do
          normal_msg.source  = 'Puppet::Interface'
          warning_msg.source = 'Puppet::Interface'
          error_msg.source   = 'Puppet::Interface'
        end

        let(:normal_msg)  { Puppet::Util::Log.new(:level => :info, :message => "Normal") }
        let(:warning_msg) { Puppet::Util::Log.new(:level => :warning, :message => "Warning") }
        let(:error_msg)   { Puppet::Util::Log.new(:level => :err, :message => "Error") }

        it "should output normal messages to stdout" do
          $stdout.expects(:puts)
          dest.handle(normal_msg)
        end

        it "should output warning messages to stderr" do
          $stderr.expects(:puts)
          dest.handle(warning_msg)
        end

        it "should output error messages to stderr" do
          $stderr.expects(:puts)
          dest.handle(error_msg)
        end

        it "should not color normal messages" do
          $stdout.expects(:puts).with("Normal")
          dest.handle(normal_msg)
        end

        it "should color warning messages bright red" do
          $stderr.expects(:puts).with("[1;31mWarning[0m")
          dest.handle(warning_msg)
        end

        it "should color error messages bright red" do
          $stderr.expects(:puts).with("[1;31mError[0m")
          dest.handle(error_msg)
        end
      end
    end

    describe "when color is disabled" do
      before :each do
        Puppet[:color] = false
      end

      it "should not color output" do
        dest.colorize(:red, 'output').should == "output"
      end
    end
  end
end

