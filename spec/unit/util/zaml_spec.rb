#!/usr/bin/env rspec
# encoding: UTF-8
#
# The above encoding line is a magic comment to set the default source encoding
# of this file for the Ruby interpreter.  It must be on the first or second
# line of the file if an interpreter is in use.  In Ruby 1.9 and later, the
# source encoding determines the encoding of String and Regexp objects created
# from this source file.  This explicit encoding is important becuase otherwise
# Ruby will pick an encoding based on LANG or LC_CTYPE environment variables.
# These may be different from site to site so it's important for us to
# establish a consistent behavior.  For more information on M17n please see:
# http://links.puppetlabs.com/understanding_m17n

require 'spec_helper'

require 'puppet/util/monkey_patches'

describe "Pure ruby yaml implementation" do
  {
  7            => "--- 7",
  3.14159      => "--- 3.14159",
  "3.14159"    => '--- "3.14159"',
  "+3.14159"   => '--- "+3.14159"',
  "0x123abc"   => '--- "0x123abc"',
  "-0x123abc"  => '--- "-0x123abc"',
  "-0x123"     => '--- "-0x123"',
  "+0x123"     => '--- "+0x123"',
  "0x123.456"  => '--- "0x123.456"',
  'test'       => "--- test",
  []           => "--- []",
  :symbol      => "--- !ruby/sym symbol",
  {:a => "A"}  => "--- \n  !ruby/sym a: A",
  {:a => "x\ny"} => "--- \n  !ruby/sym a: |-\n    x\n    y"
  }.each { |o,y|
    it "should convert the #{o.class} #{o.inspect} to yaml" do
      o.to_yaml.should == y
    end
    it "should produce yaml for the #{o.class} #{o.inspect} that can be reconstituted" do
      YAML.load(o.to_yaml).should == o
    end
  }
  #
  # Can't test for equality on raw objects
  {
  Object.new                   => "--- !ruby/object {}",
  [Object.new]                 => "--- \n  - !ruby/object {}",
  {Object.new => Object.new}   => "--- \n  ? !ruby/object {}\n  : !ruby/object {}"
  }.each { |o,y|
    it "should convert the #{o.class} #{o.inspect} to yaml" do
      o.to_yaml.should == y
    end
    it "should produce yaml for the #{o.class} #{o.inspect} that can be reconstituted" do
      lambda { YAML.load(o.to_yaml) }.should_not raise_error
    end
  }

  it "should emit proper labels and backreferences for common objects" do
    # Note: this test makes assumptions about the names ZAML chooses
    # for labels.
    x = [1, 2]
    y = [3, 4]
    z = [x, y, x, y]
    z.to_yaml.should == "--- \n  - &id001\n    - 1\n    - 2\n  - &id002\n    - 3\n    - 4\n  - *id001\n  - *id002"
    z2 = YAML.load(z.to_yaml)
    z2.should == z
    z2[0].should equal(z2[2])
    z2[1].should equal(z2[3])
  end

  it "should emit proper labels and backreferences for recursive objects" do
    x = [1, 2]
    x << x
    x.to_yaml.should == "--- &id001\n  \n  - 1\n  - 2\n  - *id001"
    x2 = YAML.load(x.to_yaml)
    x2.should be_a(Array)
    x2.length.should == 3
    x2[0].should == 1
    x2[1].should == 2
    x2[2].should equal(x2)
  end
end

# Note, many of these tests will pass on Ruby 1.8 but fail on 1.9 if the patch
# fix is not applied to Puppet or there's a regression.  These version
# dependant failures are intentional since the string encoding behavior changed
# significantly in 1.9.
describe "UTF-8 encoded String#to_yaml (Bug #11246)" do
  # JJM All of these snowmen are different representations of the same
  # UTF-8 encoded string.
  let(:snowman)         { 'Snowman: [☃]' }
  let(:snowman_escaped) { "Snowman: [\xE2\x98\x83]" }

  describe "UTF-8 String Literal" do
    subject { snowman }

    it "should serialize to YAML" do
      subject.to_yaml
    end
    it "should serialize and deserialize to the same thing" do
      YAML.load(subject.to_yaml).should == subject
    end
    it "should serialize and deserialize to a String compatible with a UTF-8 encoded Regexp" do
      YAML.load(subject.to_yaml).should =~ /☃/u
    end
  end
end

describe "binary data" do
  subject { "M\xC0\xDF\xE5tt\xF6" }

  if String.method_defined?(:encoding)
    def binary(str)
      str.force_encoding('binary')
    end
  else
    def binary(str)
      str
    end
  end

  it "should not explode encoding binary data" do
    expect { subject.to_yaml }.not_to raise_error
  end

  it "should mark the binary data as binary" do
    subject.to_yaml.should =~ /!binary/
  end

  it "should round-trip the data" do
    yaml = subject.to_yaml
    read = YAML.load(yaml)
    binary(read).should == binary(subject)
  end

  [
    "\xC0\xAE",                 # over-long UTF-8 '.' character
    "\xC0\x80",                 # over-long NULL byte
    "\xC0\xFF",
    "\xC1\xAE",
    "\xC1\x80",
    "\xC1\xFF",
    "\x80",                     # first continuation byte
    "\xbf",                     # last continuation byte
    # all possible continuation bytes in one shot
    "\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F" +
    "\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F" +
    "\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF" +
    "\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF",
    # lonely start characters - first, all possible two byte sequences
    "\xC0 \xC1 \xC2 \xC3 \xC4 \xC5 \xC6 \xC7 \xC8 \xC9 \xCA \xCB \xCC \xCD \xCE \xCF " +
    "\xD0 \xD1 \xD2 \xD3 \xD4 \xD5 \xD6 \xD7 \xD8 \xD9 \xDA \xDB \xDC \xDD \xDE \xDF ",
    # and so for three byte sequences, four, five, and six, as follow.
    "\xE0 \xE1 \xE2 \xE3 \xE4 \xE5 \xE6 \xE7 \xE8 \xE9 \xEA \xEB \xEC \xED \xEE \xEF ",
    "\xF0 \xF1 \xF2 \xF3 \xF4 \xF5 \xF6 \xF7 ",
    "\xF8 \xF9 \xFA \xFB ",
    "\xFC \xFD ",
    # sequences with the last byte missing
    "\xC0", "\xE0", "\xF0\x80\x80", "\xF8\x80\x80\x80", "\xFC\x80\x80\x80\x80",
    "\xDF", "\xEF\xBF", "\xF7\xBF\xBF", "\xFB\xBF\xBF\xBF", "\xFD\xBF\xBF\xBF\xBF",
    # impossible bytes
    "\xFE", "\xFF", "\xFE\xFE\xFF\xFF",
    # over-long '/' character
    "\xC0\xAF",
    "\xE0\x80\xAF",
    "\xF0\x80\x80\xAF",
    "\xF8\x80\x80\x80\xAF",
    "\xFC\x80\x80\x80\x80\xAF",
    # maximum overlong sequences
    "\xc1\xbf",
    "\xe0\x9f\xbf",
    "\xf0\x8f\xbf\xbf",
    "\xf8\x87\xbf\xbf\xbf",
    "\xfc\x83\xbf\xbf\xbf\xbf",
    # overlong NUL
    "\xc0\x80",
    "\xe0\x80\x80",
    "\xf0\x80\x80\x80",
    "\xf8\x80\x80\x80\x80",
    "\xfc\x80\x80\x80\x80\x80",
  ].each do |input|
    # It might seem like we should more correctly reject these sequences in
    # the encoder, and I would personally agree, but the sad reality is that
    # we do not distinguish binary and textual data in our language, and so we
    # wind up with the same thing - a string - containing both.
    #
    # That leads to the position where we must treat these invalid sequences,
    # which are both legitimate binary content, and illegitimate potential
    # attacks on the system, as something that passes through correctly in
    # a string. --daniel 2012-07-14
    it "binary encode highly dubious non-compliant UTF-8 input #{input.inspect}" do
      encoded = ZAML.dump(binary(input))
      encoded.should =~ /!binary/
      YAML.load(encoded).should == input
    end
  end
end

describe "multi-line values" do
  [
    "none",
    "one\n",
    "two\n\n",
    ["one\n", "two"],
    ["two\n\n", "three"],
    { "\nkey"        => "value" },
    { "key\n"        => "value" },
    { "\nkey\n"      => "value" },
    { "key\nkey"     => "value" },
    { "\nkey\nkey"   => "value" },
    { "key\nkey\n"   => "value" },
    { "\nkey\nkey\n" => "value" },
  ].each do |input|
    it "handles #{input.inspect} without corruption" do
      zaml = ZAML.dump(input)
      YAML.load(zaml).should == input
    end
  end
end
