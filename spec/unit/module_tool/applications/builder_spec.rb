require 'spec_helper'
require 'puppet/module_tool/applications'
require 'puppet_spec/modules'

describe Puppet::ModuleTool::Applications::Builder do
  include PuppetSpec::Files

  let(:path)         { tmpdir("working_dir") }
  let(:module_name)  { 'mymodule-mytarball' }
  let(:version)      { '0.0.1' }
  let(:release_name) { "#{module_name}-#{version}" }
  let(:tarball)      { File.join(path, 'pkg', release_name) + ".tar.gz" }
  let(:builder)      { Puppet::ModuleTool::Applications::Builder.new(path) }

  shared_examples "a packagable module" do
    def target_exists?(file)
      File.exist?(File.join(path, "pkg", "#{module_name}-#{version}", file))
    end

    it "packages the module in a tarball named after the module" do
      tarrer = mock('tarrer')
      Puppet::ModuleTool::Tar.expects(:instance).returns(tarrer)
      Dir.expects(:chdir).with(File.join(path, 'pkg')).yields
      tarrer.expects(:pack).with(release_name, tarball)

      builder.run
    end

    it "ignores the file patterns found in .pmtignore" do
      open(File.join(path, '.pmtignore'), 'w') do |f|
        f.write <<-IGNOREFILE
junk*
other/junk*
IGNOREFILE
      end
      FileUtils.touch File.join(path, 'junk.txt')
      FileUtils.mkdir File.join(path, 'other')
      FileUtils.touch File.join(path, 'other/junk.log')

      tarrer = mock('tarrer')
      Puppet::ModuleTool::Tar.expects(:instance).returns(tarrer)
      Dir.expects(:chdir).with(File.join(path, 'pkg')).yields
      tarrer.expects(:pack).with(release_name, tarball)

      builder.run

      target_exists?("junk.txt").should be_false
      target_exists?("other/junk.log").should be_false
      target_exists?("other").should be_true
    end
  end

  context 'with metadata.json' do
    before :each do
      File.open(File.join(path, 'metadata.json'), 'w') do |f|
        f.puts({
          "name" => "#{module_name}",
          "version" => "#{version}",
          "source" => "http://github.com/testing/#{module_name}",
          "author" => "testing",
          "license" => "Apache License Version 2.0",
          "summary" => "Puppet testing module",
          "description" => "This module can be used for basic testing",
          "project_page" => "http://github.com/testing/#{module_name}"
        }.to_json)
      end
    end

    it_behaves_like "a packagable module"
  end

  context 'with Modulefile' do
    before :each do
      File.open(File.join(path, 'Modulefile'), 'w') do |f|
        f.write <<-MODULEFILE
name    '#{module_name}'
version '#{version}'
source 'http://github.com/testing/#{module_name}'
author 'testing'
license 'Apache License Version 2.0'
summary 'Puppet testing module'
description 'This module can be used for basic testing'
project_page 'http://github.com/testing/#{module_name}'
MODULEFILE
      end
    end

    it_behaves_like "a packagable module"
  end
end
