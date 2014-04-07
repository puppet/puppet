#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet/file_bucket/file'


describe Puppet::FileBucket::File, :uses_checksums => true do
  include PuppetSpec::Files

  # this is the default from spec_helper, but it keeps getting reset at odd times
  let(:bucketdir) { Puppet[:bucketdir] = tmpdir('bucket') }

  it "defaults to serializing to `:s`" do
    expect(Puppet::FileBucket::File.default_format).to eq(:s)
  end

  it "accepts s and pson" do
   expect(Puppet::FileBucket::File.supported_formats).to include(:s, :pson)
  end

  using_checksums_it "can make a round trip through `s`" do
    file = Puppet::FileBucket::File.new(plaintext)

    tripped = Puppet::FileBucket::File.convert_from(:s, file.render)

    expect(tripped.contents).to eq(plaintext)
  end

  using_checksums_it "can make a round trip through `pson`" do
    file = Puppet::FileBucket::File.new(plaintext)

    tripped = Puppet::FileBucket::File.convert_from(:pson, file.render(:pson))

    expect(tripped.contents).to eq(plaintext)
  end

  it "should raise an error if changing content" do
    x = Puppet::FileBucket::File.new("first")
    expect { x.contents = "new" }.to raise_error(NoMethodError, /undefined method .contents=/)
  end

  it "should require contents to be a string" do
    expect { Puppet::FileBucket::File.new(5) }.to raise_error(ArgumentError, /contents must be a String, got a Fixnum$/)
  end

  it "should complain about options other than :bucket_path" do
    expect {
      Puppet::FileBucket::File.new('5', :crazy_option => 'should not be passed')
    }.to raise_error(ArgumentError, /Unknown option\(s\): crazy_option/)
  end

  using_checksums_it "should set the contents appropriately" do
    Puppet::FileBucket::File.new(plaintext).contents.should == plaintext
  end

  using_checksums_describe "with various checksum algorithms" do
    it "should default to #{metadata[:digest_algorithm]} as the checksum algorithm if the algorithm is not in the name" do
      Puppet::FileBucket::File.new(plaintext).checksum_type.should == algo
    end
  end

  using_checksums_it "should support multiple checksum algorithms" do
    p = Puppet::FileBucket::File.new(plaintext)
  end

  using_checksums_it "should reject unknown checksum algorithms" do
    expect {
      oda = Puppet[:digest_algorithm]
      begin
        Puppet[:digest_algorithm] = 'wefoijwefoij23f02j'
        Puppet::FileBucket::File.new(plaintext)
      ensure
        Puppet[:digest_algorithm] = oda
      end
    }.to raise_error(Puppet::Error)
  end

  using_checksums_it "should calculate checksums with various algorithms" do
    plaintext.should == "my\r\ncontents"
    Puppet::FileBucket::File.new(plaintext).checksum.should == "{#{algo}}#{checksum}"
  end

  describe "when using back-ends" do
    it "should redirect using Puppet::Indirector" do
      Puppet::Indirector::Indirection.instance(:file_bucket_file).model.should equal(Puppet::FileBucket::File)
    end

    it "should have a :save instance method" do
      Puppet::FileBucket::File.indirection.should respond_to(:save)
    end
  end

  using_checksums_it "should return a url-ish name" do
    Puppet::FileBucket::File.new(plaintext).name.should == "#{algo}/#{checksum}"
  end

  using_checksums_it "should reject a url-ish name with an invalid checksum" do
    bucket = Puppet::FileBucket::File.new(plaintext)
    expect { bucket.name = "sha1/ae548c0cd614fb7885aaa0b6cb191c34/new/path" }.to raise_error(NoMethodError, /undefined method .name=/)
  end

  it "should convert the contents to PSON" do
    Puppet.expects(:deprecation_warning).with('Serializing Puppet::FileBucket::File objects to pson is deprecated.')
    Puppet::FileBucket::File.new("file contents").to_pson.should == '{"contents":"file contents"}'
  end

  it "should load from PSON" do
    Puppet.expects(:deprecation_warning).with('Deserializing Puppet::FileBucket::File objects from pson is deprecated. Upgrade to a newer version.')
    Puppet::FileBucket::File.from_pson({"contents"=>"file contents"}).contents.should == "file contents"
  end

  using_checksums_describe "using the indirector's find method" do
    def make_bucketed_file
      FileUtils.mkdir_p("#{bucketdir}/#{bucket_dir}")
      File.open("#{bucketdir}/#{bucket_dir}/contents", 'w') { |f| f.write plaintext }
    end

    it "should return nil if a file doesn't exist" do
      bucketfile = Puppet::FileBucket::File.indirection.find("#{algo}/#{checksum}")
      bucketfile.should == nil
    end

    it "should find a filebucket if the file exists" do
      make_bucketed_file
      bucketfile = Puppet::FileBucket::File.indirection.find("#{algo}/#{checksum}")
      bucketfile.should_not == nil
    end

    describe "using RESTish digest notation" do
      it "should return nil if a file doesn't exist" do
        bucketfile = Puppet::FileBucket::File.indirection.find("#{algo}/#{checksum}")
        bucketfile.should == nil
      end

      it "should find a filebucket if the file exists" do
        make_bucketed_file
        bucketfile = Puppet::FileBucket::File.indirection.find("#{algo}/#{checksum}")
        bucketfile.should_not == nil
      end
    end
  end
end
