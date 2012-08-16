require 'puppet'
require 'spec_helper'
require 'matchers/catalog'
require 'puppet_spec/compiler'

include PuppetSpec::Compiler

describe Puppet::DSL do
  before :each do
    prepare_compiler
  end

  describe "classes" do

    it "should be able to create a class" do
      p = compile_to_catalog(<<-MANIFEST)
        class foo {
          notice("foo")
        }
      MANIFEST

      r = compile_ruby_to_catalog(<<-MANIFEST)
        hostclass :foo do
          notice "foo"
        end
      MANIFEST

      r.should be_equivalent_to p
    end

    it "should be able to use created class" do
      p = compile_to_catalog(<<-MANIFEST)
        class foo {
        }

        node default {
          include foo
        }
      MANIFEST

      r = compile_ruby_to_catalog(<<-MANIFEST)
        hostclass :foo do
        end

        node "default" do
          use :foo
        end
      MANIFEST

      r.should be_equivalent_to p
    end

    it "should be able to create class with arguments" do
      p = compile_to_catalog(<<-MANIFEST)
        class foo($param = "value") {
          notice($param)
        }
      MANIFEST

      r = compile_ruby_to_catalog(<<-MANIFEST)
        hostclass :foo, :arguments => {:param => "value"} do
          notice params[:param]
        end
      MANIFEST

      r.should be_equivalent_to p
    end

    it "should be able to use class with arguments" do
      p = compile_to_catalog(<<-MANIFEST)
        class foo($param) {
          notice($param)
        }

        node default {
          class {"foo": param => "bar"}
        }
      MANIFEST

      r = compile_ruby_to_catalog(<<-MANIFEST)
        hostclass :foo, :arguments => {:param => nil} do
          notice params[:param]
        end

        node "default" do
          use :foo, :param => "bar"
        end
      MANIFEST

      r.should be_equivalent_to p
    end

    it "should be able to create class with arguments with default values" do
      p = compile_to_catalog(<<-MANIFEST)
        class foo($param = "value") {
          notice($param)
        }

        node default {
          class {"foo": param => "bar"}
        }
      MANIFEST

      r = compile_ruby_to_catalog(<<-MANIFEST)
        hostclass :foo, :arguments => {:param => "value"} do
          notice params[:param]
        end

        node "default" do
          use :foo, :param => "bar"
        end
      MANIFEST

      r.should be_equivalent_to p
    end

    it "should allow inheritance" do
      p = compile_to_catalog(<<-MANIFEST)
        class foo {
          notice("foo")
        }

        class bar inherits foo {
          notice("bar")
        }
      MANIFEST

      r = compile_ruby_to_catalog(<<-MANIFEST)
        hostclass :foo do
          notice "foo"
        end

        hostclass :bar, :inherits => :foo do
          notice "bar"
        end
      MANIFEST

      r.should be_equivalent_to p
    end

    it "should allow inheritance with arguments" do
      p = compile_to_catalog(<<-MANIFEST)
        class foo {
          notice("foo")
        }

        class bar($msg) inherits foo {
          notice("bar", $msg)
        }
      MANIFEST

      r = compile_ruby_to_catalog(<<-MANIFEST)
        hostclass :foo do
          notice "foo"
        end

        hostclass :bar, :inherits => :foo, :arguments => {:msg => nil} do
          notice "bar", params[:msg]
        end
      MANIFEST

      r.should be_equivalent_to p
    end

  end
end

