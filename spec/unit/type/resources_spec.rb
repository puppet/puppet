#! /usr/bin/env ruby
require 'spec_helper'

resources = Puppet::Type.type(:resources)

# There are still plenty of tests to port over from test/.
describe resources do
  describe "when initializing" do
    it "should fail if the specified resource type does not exist" do
      Puppet::Type.stubs(:type).with { |x| x.to_s.downcase == "resources"}.returns resources
      Puppet::Type.expects(:type).with("nosuchtype").returns nil
      lambda { resources.new :name => "nosuchtype" }.should raise_error(Puppet::Error)
    end

    it "should not fail when the specified resource type exists" do
      lambda { resources.new :name => "file" }.should_not raise_error
    end

    it "should set its :resource_type attribute" do
      resources.new(:name => "file").resource_type.should == Puppet::Type.type(:file)
    end
  end

  describe :purge do
    let (:instance) { described_class.new(:name => 'file') }

    it "defaults to false" do
      instance[:purge].should be_false
    end

    it "can be set to false" do
      instance[:purge] = 'false'
    end

    it "cannot be set to true for a resource type that does not accept ensure" do
      instance.resource_type.stubs(:respond_to?).returns true
      instance.resource_type.stubs(:validproperty?).returns false
      expect { instance[:purge] = 'yes' }.to raise_error Puppet::Error
    end

    it "cannot be set to true for a resource type that does not have instances" do
      instance.resource_type.stubs(:respond_to?).returns false
      instance.resource_type.stubs(:validproperty?).returns true
      expect { instance[:purge] = 'yes' }.to raise_error Puppet::Error
    end

    it "can be set to true for a resource type that has instances and can accept ensure" do
      instance.resource_type.stubs(:respond_to?).returns true
      instance.resource_type.stubs(:validproperty?).returns true
      expect { instance[:purge] = 'yes' }.not_to raise_error Puppet::Error
    end
  end

  describe "#check_user purge behaviour" do
    describe "with unless_system_user => true" do
      before do
        @res = Puppet::Type.type(:resources).new :name => :user, :purge => true, :unless_system_user => true
        @res.catalog = Puppet::Resource::Catalog.new
      end

      it "should never purge hardcoded system users" do
        %w{root nobody bin noaccess daemon sys}.each do |sys_user|
          @res.user_check(Puppet::Type.type(:user).new(:name => sys_user)).should be_false
        end
      end

      it "should not purge system users if unless_system_user => true" do
        user_hash = {:name => 'system_user', :uid => 125, :system => true}
        user = Puppet::Type.type(:user).new(user_hash)
        user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
        @res.user_check(user).should be_false
      end

      it "should purge manual users if unless_system_user => true" do
        user_hash = {:name => 'system_user', :uid => 525, :system => true}
        user = Puppet::Type.type(:user).new(user_hash)
        user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
        @res.user_check(user).should be_true
      end

      it "should purge system users over 500 if unless_system_user => 600" do
        res = Puppet::Type.type(:resources).new :name => :user, :purge => true, :unless_system_user => 600
        res.catalog = Puppet::Resource::Catalog.new
        user_hash = {:name => 'system_user', :uid => 525, :system => true}
        user = Puppet::Type.type(:user).new(user_hash)
        user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
        res.user_check(user).should be_false
      end
    end

    describe "with unless_uid" do
      describe "with a uid range" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :user, :purge => true, :unless_uid => 10_000..20_000
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge uids that are not in a specified range" do
          user_hash = {:name => 'special_user', :uid => 25_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_true
        end

        it "should not purge uids that are in a specified range" do
          user_hash = {:name => 'special_user', :uid => 15_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_false
        end
      end

      describe "with a uid range array" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :user, :purge => true, :unless_uid => [10_000..15_000, 15_000..20_000]
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge uids that are not in a specified range array" do
          user_hash = {:name => 'special_user', :uid => 25_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_true
        end

        it "should not purge uids that are in a specified range array" do
          user_hash = {:name => 'special_user', :uid => 15_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_false
        end

      end

      describe "with a uid array" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :user, :purge => true, :unless_uid => [15_000, 15_001, 15_002]
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge uids that are not in a specified array" do
          user_hash = {:name => 'special_user', :uid => 25_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_true
        end

        it "should not purge uids that are in a specified array" do
          user_hash = {:name => 'special_user', :uid => 15000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_false
        end

      end

      describe "with a single uid" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :user, :purge => true, :unless_uid => 15_000
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge uids that are not specified" do
          user_hash = {:name => 'special_user', :uid => 25_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_true
        end

        it "should not purge uids that are specified" do
          user_hash = {:name => 'special_user', :uid => 15_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_false
        end
      end

      describe "with a mixed uid array" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :user, :purge => true, :unless_uid => [10_000..15_000, 16_666]
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should not purge ids in the range" do
          user_hash = {:name => 'special_user', :uid => 15_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_false
        end

        it "should not purge specified ids" do
          user_hash = {:name => 'special_user', :uid => 16_666}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_false
        end

        it "should purge unspecified ids" do
          user_hash = {:name => 'special_user', :uid => 17_000}
          user = Puppet::Type.type(:user).new(user_hash)
          user.stubs(:retrieve_resource).returns Puppet::Resource.new("user", user_hash[:name], :parameters => user_hash)
          @res.user_check(user).should be_true
        end
      end
      
    end
  end

  describe "group_check purge behaviour" do
    describe "with unless_system_group => true" do
      before do
        @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :unless_system_group => true
        @res.catalog = Puppet::Resource::Catalog.new
      end

      it "should never purge hardcoded system groups" do
        %w{root nobody bin noaccess daemon sys adm lp mail wheel}.each do |sys_group|
          @res.group_check(Puppet::Type.type(:group).new(:name => sys_group)).should be_false
        end
      end

      it "should not purge system groups if unless_system_group => true" do
        group_hash = {:name => 'system_group', :gid => 125, :system => true}
        group = Puppet::Type.type(:group).new(group_hash)
        group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
        @res.group_check(group).should be_false
      end

      it "should purge manual groups if unless_system_group => true" do
        group_hash = {:name => 'system_group', :gid => 525, :system => true}
        group = Puppet::Type.type(:group).new(group_hash)
        group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
        @res.group_check(group).should be_true
      end

      it "should purge system groups over 500 if unless_system_group => 600" do
        res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :unless_system_group => 600
        res.catalog = Puppet::Resource::Catalog.new
        group_hash = {:name => 'system_group', :gid => 525, :system => true}
        group = Puppet::Type.type(:group).new(group_hash)
        group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
        res.group_check(group).should be_false
      end
    end

    describe "with unless_gid" do
      describe "with a comma separated string of gids" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :unless_gid => '15000, 15001, 15002'
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge gids that are not in a specified array" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end

        it "should not purge gids that are in a specified array" do
          group_hash = {:name => 'special_group', :gid => 15000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end
      end

      describe "with a gid array" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :unless_gid => [15_000, 15_001, 15_002]
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge gids that are not in a specified array" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end

        it "should not purge gids that are in a specified array" do
          group_hash = {:name => 'special_group', :gid => 15000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end
      end

      describe "with a single gid integer" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :unless_gid => 15_000
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge gids that are not specified" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end

        it "should not purge gids that are specified" do
          group_hash = {:name => 'special_group', :gid => 15_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end
      end

      describe "with a single gid string" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :unless_gid => '15000'
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should purge gids that are not specified" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end

        it "should not purge gids that are specified" do
          group_hash = {:name => 'special_group', :gid => 15_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end
      end
    end

    describe "with only_gid" do
      describe "with a comma separated string of gids" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :only_gid => '15000, 15001, 15002'
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should not purge gids that are not in a specified array" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end

        it "should purge gids that are in a specified array" do
          group_hash = {:name => 'special_group', :gid => 15000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end
      end

      describe "with a gid array" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :only_gid => [15_000, 15_001, 15_002]
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should not purge gids that are not in a specified array" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end

        it "should purge gids that are in a specified array" do
          group_hash = {:name => 'special_group', :gid => 15000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end
      end

      describe "with a single gid integer" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :only_gid => 15_000
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should not purge gids that are not specified" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end

        it "should purge gids that are specified" do
          group_hash = {:name => 'special_group', :gid => 15_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end
      end

      describe "with a single gid string" do
        before do
          @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :only_gid => '15000'
          @res.catalog = Puppet::Resource::Catalog.new
        end

        it "should not purge gids that are not specified" do
          group_hash = {:name => 'special_group', :gid => 25_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_false
        end

        it "should purge gids that are specified" do
          group_hash = {:name => 'special_group', :gid => 15_000}
          group = Puppet::Type.type(:group).new(group_hash)
          group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
          @res.group_check(group).should be_true
        end
      end
    end

    describe "with unless_gid and only_gid" do
      before do
        @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :unless_gid => [15_000, 15_001, 15_002], :only_gid => [15_003]
        @res.catalog = Puppet::Resource::Catalog.new
      end

      it "should raise an error" do
        group_hash = {:name => 'special_group', :gid => 15_000}
        group = Puppet::Type.type(:group).new(group_hash)
        group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
        expect { @res.group_check(group) }.to raise_error ArgumentError
      end
    end

    describe "with overlapping only_gid and unless_system_group" do
      before do
        @res = Puppet::Type.type(:resources).new :name => :group, :purge => true, :only_gid => [125], :unless_system_group => true
        @res.catalog = Puppet::Resource::Catalog.new
      end

      it "should raise an error" do
        group_hash = {:name => 'special_group', :gid => 125}
        group = Puppet::Type.type(:group).new(group_hash)
        group.stubs(:retrieve_resource).returns Puppet::Resource.new("group", group_hash[:name], :parameters => group_hash)
        expect { @res.group_check(group) }.to raise_error ArgumentError
      end
    end    
  end

  describe "#generate" do
    before do
      @host1 = Puppet::Type.type(:host).new(:name => 'localhost', :ip => '127.0.0.1')
      @catalog = Puppet::Resource::Catalog.new
    end

    describe "when dealing with non-purging resources" do
      before do
        @resources = Puppet::Type.type(:resources).new(:name => 'host')
      end

      it "should not generate any resource" do
        @resources.generate.should be_empty
      end
    end

    describe "when the catalog contains a purging resource" do
      before do
        @resources = Puppet::Type.type(:resources).new(:name => 'host', :purge => true)
        @purgeable_resource = Puppet::Type.type(:host).new(:name => 'localhost', :ip => '127.0.0.1')
        @catalog.add_resource @resources
      end

      it "should not generate a duplicate of that resource" do
        Puppet::Type.type(:host).stubs(:instances).returns [@host1]
        @catalog.add_resource @host1
        @resources.generate.collect { |r| r.ref }.should_not include(@host1.ref)
      end

      it "should not include the skipped system users" do
        res = Puppet::Type.type(:resources).new :name => :user, :purge => true
        res.catalog = Puppet::Resource::Catalog.new

        root = Puppet::Type.type(:user).new(:name => "root")
        Puppet::Type.type(:user).expects(:instances).returns [ root ]

        list = res.generate

        names = list.collect { |r| r[:name] }
        names.should_not be_include("root")
      end

      describe "when generating a purgeable resource" do
        it "should be included in the generated resources" do
          Puppet::Type.type(:host).stubs(:instances).returns [@purgeable_resource]
          @resources.generate.collect { |r| r.ref }.should include(@purgeable_resource.ref)
        end
      end

      describe "when the instance's do not have an ensure property" do
        it "should not be included in the generated resources" do
          @no_ensure_resource = Puppet::Type.type(:exec).new(:name => "#{File.expand_path('/usr/bin/env')} echo")
          Puppet::Type.type(:host).stubs(:instances).returns [@no_ensure_resource]
          @resources.generate.collect { |r| r.ref }.should_not include(@no_ensure_resource.ref)
        end
      end

      describe "when the instance's ensure property does not accept absent" do
        it "should not be included in the generated resources" do
          @no_absent_resource = Puppet::Type.type(:service).new(:name => 'foobar')
          Puppet::Type.type(:host).stubs(:instances).returns [@no_absent_resource]
          @resources.generate.collect { |r| r.ref }.should_not include(@no_absent_resource.ref)
        end
      end

      describe "when checking the instance fails" do
        it "should not be included in the generated resources" do
          @purgeable_resource = Puppet::Type.type(:host).new(:name => 'foobar')
          Puppet::Type.type(:host).stubs(:instances).returns [@purgeable_resource]
          @resources.expects(:check).with(@purgeable_resource).returns(false)
          @resources.generate.collect { |r| r.ref }.should_not include(@purgeable_resource.ref)
        end
      end
    end
  end
end
