#! /usr/bin/env ruby
require 'spec_helper'

require 'puppet/file_serving/terminus_helper'

describe Puppet::FileServing::TerminusHelper do
  before do
    @helper = Object.new
    @helper.extend(Puppet::FileServing::TerminusHelper)

    @model = mock 'model'
    @helper.stubs(:model).returns(@model)

    @request = stub 'request', :key => "url", :options => {}

    @fileset = stub 'fileset', :files => [], :path => "/my/file"
    Puppet::FileServing::Fileset.stubs(:new).with("/my/file", {}).returns(@fileset)
  end

  it "should find a file with absolute path" do
    file = stub 'file', :collect => nil
    file.expects(:collect).with(nil)
    @model.expects(:new).with("/my/file", {:relative_path => nil}).returns(file)
    @helper.path2instance(@request, "/my/file")
  end

  it "should pass through links, checksum_type, and source_permissions" do
    file = stub 'file', :checksum_type= => nil, :links= => nil, :collect => nil
    [[:checksum_type, :sha256], [:links, true]].each {|k, v|
      file.expects(k.to_s+'=').with(v)
      @request.options[k] = v
    }
    @request.options[:source_permissions] = :yes
    file.expects(:collect).with(:yes)
    @model.expects(:new).with("/my/file", {:relative_path => :file}).returns(file)
    @helper.path2instance(@request, "/my/file", {:relative_path => :file})
  end

  it "should use a fileset to find paths" do
    @fileset = stub 'fileset', :files => [], :path => "/my/files"
    Puppet::FileServing::Fileset.expects(:new).with { |key, options| key == "/my/file" }.returns(@fileset)
    @helper.path2instances(@request, "/my/file")
  end

  it "should support finding across multiple paths by merging the filesets" do
    first = stub 'fileset', :files => [], :path => "/first/file"
    Puppet::FileServing::Fileset.expects(:new).with { |path, options| path == "/first/file" }.returns(first)
    second = stub 'fileset', :files => [], :path => "/second/file"
    Puppet::FileServing::Fileset.expects(:new).with { |path, options| path == "/second/file" }.returns(second)

    Puppet::FileServing::Fileset.expects(:merge).with(first, second).returns({})

    @helper.path2instances(@request, "/first/file", "/second/file")
  end

  it "should pass the indirection request to the Fileset at initialization" do
    Puppet::FileServing::Fileset.expects(:new).with { |path, options| options == @request }.returns @fileset
    @helper.path2instances(@request, "/my/file")
  end

  describe "when creating instances" do
    before do
      @request.stubs(:key).returns "puppet://host/mount/dir"

      @one = stub 'one', :links= => nil, :collect => nil
      @two = stub 'two', :links= => nil, :collect => nil

      @fileset = stub 'fileset', :files => %w{one two}, :path => "/my/file"
      Puppet::FileServing::Fileset.stubs(:new).returns(@fileset)
    end

    it "should set each returned instance's path to the original path" do
      @model.expects(:new).with { |key, options| key == "/my/file" }.returns(@one)
      @model.expects(:new).with { |key, options| key == "/my/file" }.returns(@two)
      @helper.path2instances(@request, "/my/file")
    end

    it "should set each returned instance's relative path to the file-specific path" do
      @model.expects(:new).with { |key, options| options[:relative_path] == "one" }.returns(@one)
      @model.expects(:new).with { |key, options| options[:relative_path] == "two" }.returns(@two)
      @helper.path2instances(@request, "/my/file")
    end

    it "should set the links value on each instance if one is provided" do
      @one.expects(:links=).with :manage
      @two.expects(:links=).with :manage
      @model.expects(:new).returns(@one)
      @model.expects(:new).returns(@two)

      @request.options[:links] = :manage
      @helper.path2instances(@request, "/my/file")
    end

    it "should set the request checksum_type if one is provided" do
      @one.expects(:checksum_type=).with :test
      @two.expects(:checksum_type=).with :test
      @model.expects(:new).returns(@one)
      @model.expects(:new).returns(@two)

      @request.options[:checksum_type] = :test
      @helper.path2instances(@request, "/my/file")
    end

    it "should collect the instance's attributes" do
      @one.expects(:collect)
      @two.expects(:collect)
      @model.expects(:new).returns(@one)
      @model.expects(:new).returns(@two)

      @helper.path2instances(@request, "/my/file")
    end
  end

  describe "::escape_url" do
    it "should prefix http URLs" do
      described_class.escape_url('http://foo.bar').should == 'url=http://foo.bar'
    end
    it "should prefix https URLs" do
      described_class.escape_url('https://foo.bar').should == 'url=https://foo.bar'
    end
    it "should leave non-http keys alone" do
      %w{ftp://foo.bar gopher://foo.bar ymmv://foo.bar some-non-URL}.each do |key|
        described_class.escape_url(key).should == key
      end
    end
  end

  describe "#unescape_url" do
    it "should remove the prefix from file_metadata indirector keys" do
      @helper.unescape_url('/file_metadata/url=result').should == 'result'
    end
    it "should remove the prefix from file_content indirector keys" do
      @helper.unescape_url('/file_content/url=result').should == 'result'
    end
    it "should not try to remove other prefixes" do
      %w{url=foobar /catalog/url=foobar key-without-prefix}.each do |key|
        @helper.unescape_url(key).should == key
      end
    end
  end
end
