#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'
require 'puppet_spec/files'

describe Puppet::Application::Doc do
  include PuppetSpec::Files

  it "should not generate an error when module dir overlaps parent of site.pp (#4798)" do
    begin
      # Note: the directory structure below is more complex than it
      # needs to be, but it's representative of the directory structure
      # used in bug #4798.
      old_dir = Dir.getwd # Note: can't use chdir with a block because it will generate bogus warnings
      tmpdir = tmpfile('doc_spec')
      Dir.mkdir(tmpdir)
      Dir.chdir(tmpdir)
      site_file = 'site.pp'
      File.open(site_file, 'w') do |f|
        f.puts '# A comment'
      end
      modules_dir = 'modules'
      Dir.mkdir(modules_dir)
      rt_dir = File.join(modules_dir, 'rt')
      Dir.mkdir(rt_dir)
      manifests_dir = File.join(rt_dir, 'manifests')
      Dir.mkdir(manifests_dir)
      rt_file = File.join(manifests_dir, 'rt.pp')
      File.open(rt_file, 'w') do |f|
        f.puts '# A class'
        f.puts 'class foo { }'
        f.puts '# A definition'
        f.puts 'define bar { }'
      end

      puppet = Puppet::Application[:doc]
      Puppet[:modulepath] = modules_dir
      Puppet[:manifest] = site_file
      puppet.options[:mode] = :rdoc
      puppet.expects(:exit).with(0)
      puppet.run_command

      File.should be_exist('doc')
    ensure
      Dir.chdir(old_dir)
    end
  end

  it "should respect the -o option" do
    puppetdoc = Puppet::Application[:doc]
    puppetdoc.command_line.stubs(:args).returns(['foo', '-o', 'bar'])
    puppetdoc.parse_options
    puppetdoc.options[:outputdir].should == 'bar'
  end
end
