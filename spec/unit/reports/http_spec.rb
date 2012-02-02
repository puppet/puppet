#!/usr/bin/env rspec
require 'spec_helper'

require 'puppet/reports'

# FakeHTTP fakes the behavior of Net::HTTP#request and acts as a sensor for an
# otherwise difficult to trace method call.
#
class FakeHTTP
  REQUESTS = {}
  def self.request(req)
    REQUESTS[req.path] = req
  end
end

processor = Puppet::Reports.report(:http)

describe processor do
  before  { Net::HTTP.any_instance.stubs(:start).yields(FakeHTTP) }
  subject { Puppet::Transaction::Report.new("apply").extend(processor) }

  it { should respond_to(:process) }

  it "should use the reporturl setting's host, port and ssl option" do
    uri = URI.parse(Puppet[:reporturl])
    ssl = (uri.scheme == 'https')
    Puppet::Network::HttpPool.expects(:http_instance).with(uri.host, uri.port, use_ssl=ssl).returns(stub_everything('http'))
    subject.process
  end

  it "should use ssl if requested" do
    Puppet[:reporturl] = Puppet[:reporturl].sub(/^http:\/\//, 'https://')
    uri = URI.parse(Puppet[:reporturl])
    Puppet::Network::HttpPool.expects(:http_instance).with(uri.host, uri.port, use_ssl=true).returns(stub_everything('http'))
    subject.process
  end

  describe "request" do
    before { subject.process }

    describe "path" do
      it "should use the path specified by the 'reporturl' setting" do
        reports_request.path.should == URI.parse(Puppet[:reporturl]).path
      end
    end

    describe "body" do
      it "should be the report as YAML" do
        reports_request.body.should == subject.to_yaml
      end
    end

    describe "content type" do
      it "should be 'application/x-yaml'" do
        reports_request.content_type.should == "application/x-yaml"
      end
    end
  end

  private

  def reports_request; FakeHTTP::REQUESTS[URI.parse(Puppet[:reporturl]).path] end
end
