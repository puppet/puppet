#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet/pops/api'
require 'puppet/pops/api/model/model'
require 'puppet/pops/impl/model/factory'
require 'puppet/pops/impl/model/model_tree_dumper'
require 'puppet/pops/impl/evaluator_impl'
require 'puppet/pops/impl/base_scope'
require 'puppet/pops/impl/top_scope'


# This file contains basic testing of variable references and assignments
# using a top scope and a local scope.
# It does not test variables and named scopes.
#

# relative to this spec file (./) does not work as this file is loaded by rspec
require File.join(File.dirname(__FILE__), '/evaluator_rspec_helper')

RSpec.configure do |c|
  c.include EvaluatorRspecHelper
end

describe Puppet::Pops::Impl::EvaluatorImpl do
  
  context "(selftest)" do
    it "tests #var should create a VariableExpression" do
      var('a').current.is_a?(Puppet::Pops::API::Model::VariableExpression).should == true
    end
    it "tests #fqn should create a QualifiedName" do
      fqn('a').current.is_a?(Puppet::Pops::API::Model::QualifiedName).should == true
    end
    it "tests #block should create a BlockExpression" do
      block().current.is_a?(Puppet::Pops::API::Model::BlockExpression).should == true
    end
  end
  
  context "When the evaluator deals with variables" do
    context "it should handle" do
      it "simple assignment and dereference" do
        evaluate_l(block( fqn('a').set(literal(2)+literal(2)), var('a'))).should == 4
      end
      it "local scope shadows top scope" do
        top_scope_block   = block( fqn('a').set(literal(2)+literal(2)), var('a'))
        local_scope_block = block( fqn('a').set(var('a') + literal(2)), var('a')) 
        evaluate_l(top_scope_block, local_scope_block).should == 6
      end
      it "shadowed in local does not affect parent scope" do
        top_scope_block   = block( fqn('a').set(literal(2)+literal(2)), var('a'))
        local_scope_block = block( fqn('a').set(var('a') + literal(2)), var('a'))
        top_scope_again = var('a') 
        evaluate_l(top_scope_block, local_scope_block, top_scope_again).should == 4
      end
      it "access to global names works in top scope" do
        top_scope_block   = block( fqn('::a').set(literal(2)+literal(2)), var('::a'))
        evaluate_l(top_scope_block).should == 4
      end
      it "access to global names works in local scope" do
        top_scope_block     = block( fqn('::a').set(literal(2)+literal(2)), var('::a'))
        local_scope_block   = block( fqn('a').set(var('::a')+literal(2)), var('::a'))
        evaluate_l(top_scope_block, local_scope_block).should == 4
      end
      it "can not change a variable value in same scope" do
        expect { evaluate_l(block(fqn('a').set(10), fqn('a').set(20))) }.to raise_error(Puppet::Pops::ImmutableError)
      end
      context "+= operations" do
        it "appending to non existing value, nil += []" do
          top_scope_block = fqn('b').set([1,2,3])
          local_scope_block = fqn('a').plus_set([4])
          expect {evaluate_l(top_scope_block, local_scope_block)}.to raise_error(Puppet::Pops::EvaluationError)
        end
        context "appending to list" do
          it "from list, [] += []" do
            top_scope_block = fqn('a').set([1,2,3])
            local_scope_block = fqn('a').plus_set([4])
            evaluate_l(top_scope_block, local_scope_block).should == [1,2,3,4]
          end
          it "from hash, [] += {a=>b}" do
            top_scope_block = fqn('a').set([1,2,3])
            local_scope_block = fqn('a').plus_set({'a' => 1, 'b'=>2})
            evaluate_l(top_scope_block, local_scope_block).should == [1,2,3,['a',1],['b',2]]
          end
          it "from single value, [] += x" do
            top_scope_block = fqn('a').set([1,2,3])
            local_scope_block = fqn('a').plus_set(4)
            evaluate_l(top_scope_block, local_scope_block).should == [1,2,3,4]
          end
          it "from embedded list, [] += [[x]]" do
            top_scope_block = fqn('a').set([1,2,3])
            local_scope_block = fqn('a').plus_set([[4,5]])
            evaluate_l(top_scope_block, local_scope_block).should == [1,2,3,[4,5]]
          end
       end
       context "appending to hash" do
         it "from hash, {a=>b} += {x=>y}" do
            top_scope_block = fqn('a').set({'a' => 1, 'b' => 2})
            local_scope_block = fqn('a').plus_set({'c' => 3})
            evaluate_l(top_scope_block, local_scope_block) do |scope|
              # Assert no change to top scope hash
              scope.get_variable_entry('a').value.should == {'a' =>1, 'b'=> 2}
            end.should == {'a' => 1, 'b' => 2, 'c' => 3}
          end
          it "from list, {a=>b} += ['x', y]" do
            top_scope_block = fqn('a').set({'a' => 1, 'b' => 2})
            local_scope_block = fqn('a').plus_set(['c', 3])
            evaluate_l(top_scope_block, local_scope_block) do |scope|
              # Assert no change to top scope hash
              scope.get_variable_entry('a').value.should == {'a' =>1, 'b'=> 2}
            end.should == {'a' => 1, 'b' => 2, 'c' => 3}
          end
          it "with overwrite from hash, {a=>b} += {a=>c}" do
            top_scope_block = fqn('a').set({'a' => 1, 'b' => 2})
            local_scope_block = fqn('a').plus_set({'b' => 4, 'c' => 3})
            evaluate_l(top_scope_block, local_scope_block) do |scope|
              # Assert no change to top scope hash
              scope.get_variable_entry('a').value.should == {'a' =>1, 'b'=> 2}
            end.should == {'a' => 1, 'b' => 4, 'c' => 3}
          end
          it "with overwrite from list, {a=>b} += ['a', c]" do
            top_scope_block = fqn('a').set({'a' => 1, 'b' => 2})
            local_scope_block = fqn('a').plus_set(['b', 4, 'c', 3])
            evaluate_l(top_scope_block, local_scope_block) do |scope|
              # Assert no change to topscope hash
              scope.get_variable_entry('a').value.should == {'a' =>1, 'b'=> 2}
            end.should == {'a' => 1, 'b' => 4, 'c' => 3}
          end
          it "from odd length array - error" do
            top_scope_block = fqn('a').set({'a' => 1, 'b' => 2})
            local_scope_block = fqn('a').plus_set(['b', 4, 'c'])
            expect { evaluate_l(top_scope_block, local_scope_block) }.to raise_error(Puppet::Pops::EvaluationError)
          end
        end
      end
      context "access to numeric variables" do
        it "without a match" do
          evaluate_l(block(literal(2) + literal(2), 
            [var(0), var(1), var(2), var(3)])).should == [nil, nil, nil, nil]
        end
        it "after a match" do
          evaluate_l(block(literal('abc') =~ literal(/(a)(b)(c)/), 
            [var(0), var(1), var(2), var(3)])).should == ['abc', 'a', 'b', 'c']
        end
        it "after a failed match" do
          evaluate_l(block(literal('abc') =~ literal(/(x)(y)(z)/), 
            [var(0), var(1), var(2), var(3)])).should == [nil, nil, nil, nil]
        end
        it "after a match with variable referencing a non existing group" do
          evaluate_l(block(literal('abc') =~ literal(/(a)(b)(c)/), 
            [var(0), var(1), var(2), var(3), var(4)])).should == ['abc', 'a', 'b', 'c', nil]
        end
      end
    end
  end
end