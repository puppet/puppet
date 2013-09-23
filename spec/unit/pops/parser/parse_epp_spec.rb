#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet_spec/factory_rspec_helper'
require 'puppet/pops'

module EppParserRspecHelper
  include FactoryRspecHelper
  def parse(code)
    parser = Puppet::Pops::Parser::EppParser.new()
    parser.parse_string(code)
  end
end

describe "epp parser" do
  include EppParserRspecHelper

  context "when facing bad input it reports" do
    it "unbalanced tags" do
      expect { dump(parse("<% missing end tag")) }.to raise_error(/Unbalanced/)
    end

    it "abrupt end" do
      expect { dump(parse("dum di dum di dum <%")) }.to raise_error(/Unbalanced/)
    end

    it "nested epp tags" do
      expect { dump(parse("<% $a = 10 <% $b = 20 %>%>")) }.to raise_error(/Syntax error/)
    end

    it "nested epp expression tags" do
      expect { dump(parse("<%= 1+1 <%= 2+2 %>%>")) }.to raise_error(/Syntax error/)
    end
  end

  context "handles parsing of" do
    it "text (and nothing else)" do
      dump(parse("Hello World")).should == "(epp (block (render-s 'Hello World')))"
    end

    it "template parameters" do
      dump(parse("<%($x)%>Hello World")).should == "(epp (parameters x) (block (render-s 'Hello World')))"
    end

    it "template parameters with default" do
      dump(parse("<%($x='cigar')%>Hello World")).should == "(epp (parameters (= x 'cigar')) (block (render-s 'Hello World')))"
    end

    it "template parameters with and without default" do
      dump(parse("<%($x='cigar', $y)%>Hello World")).should == "(epp (parameters (= x 'cigar') y) (block (render-s 'Hello World')))"
    end

    it "comments" do
      dump(parse("<%#($x='cigar', $y)%>Hello World")).should == "(epp (block (render-s 'Hello World')))"
    end

    it "verbatim epp tags" do
      dump(parse("<%% contemplating %%>Hello World")).should == "(epp (block (render-s '<% contemplating %>Hello World')))"
    end

    it "expressions" do
      dump(parse("We all live in <%= 3.14 - 2.14 %> world")).should ==
        "(epp (block (render-s 'We all live in ') (render (- 3.14 2.14)) (render-s ' world')))"
    end
  end
end
