#! /usr/bin/env ruby
require 'spec_helper'

provider = Puppet::Type.type(:package).provider(:portage)

describe provider do
  before do
    packagename="sl"
    @resource = stub('resource', :[] => packagename,:should => true)
    @provider = provider.new(@resource)
    
    portage_mock=stub(:executable => "foo",:execute => true)

    Puppet::Provider::CommandDefiner.stubs(:define).returns(portage_mock)
    @match_result = "app-misc sl [] [] http://www.tkl.iis.u-tokyo.ac.jp/~toyoda/index_e.html http://www.izumix.org.uk/sl/ sophisticated graphical program which corrects your miss typing\n"
    @nomatch_result=""

  end

  it "is versionable" do
    provider.should be_versionable
  end

  it "uses :emerge to install packages" do
    @provider.expects(:emerge)
    @provider.install
  end

  it "uses query to find the latest package" do
    @provider.expects(:query).returns({:versions_available => "myversion"})
    @provider.latest
  end

  it "uses eix to search the lastest version of a package" do
    @provider.expects(:update_eix)
    @provider.expects(:eix).returns(StringIO.new(@match_result))
    @provider.query
  end

  it "eix arguments do not include --stable" do
    @provider.class.eix_search_arguments.should_not include("--stable")
  end

  it "query uses default arguments" do
    @provider.expects(:update_eix)
    @provider.expects(:eix).returns(StringIO.new(@match_result))
    @provider.class.expects(:eix_search_arguments).returns([])
    @provider.query
  end

  it "works with valid search output" do
    @provider.expects(:update_eix)
    @provider.expects(:eix).returns(StringIO.new(@match_result))
    @provider.query[:name].should eq "sl"
  end

end



