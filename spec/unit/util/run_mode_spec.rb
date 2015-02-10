#! /usr/bin/env ruby
require 'spec_helper'

describe Puppet::Util::RunMode do
  before do
    @run_mode = Puppet::Util::RunMode.new('fake')
  end

  it "has rundir depend on vardir" do
    expect(@run_mode.run_dir).to eq('$vardir/run')
  end

  describe Puppet::Util::UnixRunMode, :unless => Puppet.features.microsoft_windows? do
    before do
      @run_mode = Puppet::Util::UnixRunMode.new('fake')
    end

    describe "#puppet_dir" do
      describe "when run as root" do
        it "has puppetdir /etc/puppetlabs/agent" do
          as_root { expect(@run_mode.puppet_dir).to eq(File.expand_path('/etc/puppetlabs/agent')) }
        end
      end

      describe "when run as non-root" do
        it "has puppetdir ~/.puppet" do
          as_non_root { expect(@run_mode.puppet_dir).to eq(File.expand_path('~/.puppet')) }
        end

        it "fails when asking for the puppet_dir as non-root and there is no $HOME" do
          as_non_root do
            without_home do
              expect { @run_mode.puppet_dir }.to raise_error ArgumentError, /couldn't find HOME/
            end
          end
        end
      end

      context "master run mode" do
        before do
          @run_mode = Puppet::Util::UnixRunMode.new('master')
        end
        it "has puppetdir ~/.puppet when run as non-root and master run mode (#16337)" do
          as_non_root { expect(@run_mode.puppet_dir).to eq(File.expand_path('~/.puppet')) }
        end
      end

      it "fails when asking for the conf_dir as non-root and there is no $HOME" do
        as_non_root do
          without_home do
            expect { @run_mode.conf_dir }.to raise_error ArgumentError, /couldn't find HOME/
          end
        end
      end
    end

    describe "#var_dir" do
      it "has vardir /var/lib/puppet when run as root" do
        as_root { expect(@run_mode.var_dir).to eq(File.expand_path('/var/lib/puppet')) }
      end

      it "has vardir ~/.puppet/var when run as non-root" do
        as_non_root { expect(@run_mode.var_dir).to eq(File.expand_path('~/.puppet/var')) }
      end

      it "fails when asking for the var_dir as non-root and there is no $HOME" do
        as_non_root do
          without_home do
            expect { @run_mode.var_dir }.to raise_error ArgumentError, /couldn't find HOME/
          end
        end
      end
    end
  end

  describe Puppet::Util::WindowsRunMode, :if => Puppet.features.microsoft_windows? do
    before do
      if not Dir.const_defined? :COMMON_APPDATA
        Dir.const_set :COMMON_APPDATA, "/CommonFakeBase"
        @remove_const = true
      end
      @run_mode = Puppet::Util::WindowsRunMode.new('fake')
    end

    after do
      if @remove_const
        Dir.send :remove_const, :COMMON_APPDATA
      end
    end

    describe "#puppet_dir" do
      describe "when run as root" do
        it "has puppetdir /etc/puppet" do
          as_root { expect(@run_mode.puppet_dir).to eq(File.expand_path(File.join(Dir::COMMON_APPDATA, "PuppetLabs", "puppet", "etc"))) }
        end
      end

      describe "when run as non-root" do
        it "has puppetdir in ~/.puppet" do
          as_non_root { expect(@run_mode.puppet_dir).to eq(File.expand_path("~/.puppet")) }
        end

        it "fails when asking for the puppet_dir and there is no %HOME%, %HOMEDRIVE%, and %USERPROFILE%" do
          as_non_root do
            without_env('HOME') do
              without_env('HOMEDRIVE') do
                without_env('USERPROFILE') do
                  expect { @run_mode.puppet_dir }.to raise_error ArgumentError, /couldn't find HOME/
                end
              end
            end
          end
        end
      end
    end

    describe "#var_dir" do
      it "has vardir /var/lib/puppet when run as root" do
        as_root { expect(@run_mode.var_dir).to eq(File.expand_path(File.join(Dir::COMMON_APPDATA, "PuppetLabs", "puppet", "var"))) }
      end

      it "has vardir in ~/.puppet/var when run as non-root" do
        as_non_root { expect(@run_mode.var_dir).to eq(File.expand_path("~/.puppet/var")) }
      end

      it "fails when asking for the var_dir as non-root and there is no %HOME%, %HOMEDRIVE%, and %USERPROFILE%" do
        as_non_root do
          without_env('HOME') do
            without_env('HOMEDRIVE') do
              without_env('USERPROFILE') do
                expect { @run_mode.var_dir }.to raise_error ArgumentError, /couldn't find HOME/
              end
            end
          end
        end
      end
    end
  end

  def as_root
    Puppet.features.stubs(:root?).returns(true)
    yield
  end

  def as_non_root
    Puppet.features.stubs(:root?).returns(false)
    yield
  end

  def without_env(name, &block)
    saved = ENV[name]
    ENV.delete name
    yield
  ensure
    ENV[name] = saved
  end

  def without_home(&block)
    without_env('HOME', &block)
  end
end
