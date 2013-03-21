#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet/pops/api'
require 'puppet/pops/api/model/model'
require 'puppet/pops/impl/model/factory'
require 'puppet/pops/impl/model/model_tree_dumper'
require 'puppet/pops/impl/evaluator_impl'
require 'puppet/pops/impl/base_scope'
require 'puppet/pops/impl/top_scope'

# relative to this spec file (./) does not work as this file is loaded by rspec
require File.join(File.dirname(__FILE__), '/evaluator_rspec_helper')

RSpec.configure do |c|
  c.include EvaluatorRspecHelper
end

# This file contains testing of Conditionals, if, case, unless, selector
#
describe Puppet::Pops::Impl::EvaluatorImpl do
  
  context "(selftest)" do
    it "factory IF should produce an IfExpression" do
      IF(literal(true), literal(true)).current.class.should == Puppet::Pops::API::Model::IfExpression
      IF(literal(true), literal(true), literal(true)).current.class.should == Puppet::Pops::API::Model::IfExpression
    end
  end
  
  context "When the evaluator evaluates" do
    context "an if expression" do
      it 'should output the expected result when dumped' do
        dump(IF(literal(true), literal(2), literal(5))).should == unindent(<<-TEXT
          (if true
            (then 2)
            (else 5))
          TEXT
          )
      end
      it 'if true {5} == 5' do
        evaluate(IF(literal(true), literal(5))).should == 5
      end
      it 'if false {5} == nil' do
        evaluate(IF(literal(false), literal(5))).should == nil
      end
      it 'if false {2} else {5} == 5' do
        evaluate(IF(literal(false), literal(2), literal(5))).should == 5
      end
      it 'if false {2} elsif true {5} == 5' do
        evaluate(IF(literal(false), literal(2), IF(literal(true), literal(5)))).should == 5
      end
      it 'if false {2} elsif false {5} == nil' do
        evaluate(IF(literal(false), literal(2), IF(literal(false), literal(5)))).should == nil
      end
    end
    context "an unless expression" do
      it 'should output the expected result when dumped' do
        dump(UNLESS(literal(true), literal(2), literal(5))).should == unindent(<<-TEXT
          (unless true
            (then 2)
            (else 5))
          TEXT
          )
      end
      it 'unless false {5} == 5' do
        evaluate(UNLESS(literal(false), literal(5))).should == 5
      end
      it 'unless true {5} == nil' do
        evaluate(UNLESS(literal(true), literal(5))).should == nil
      end
      it 'unless true {2} else {5} == 5' do
        evaluate(UNLESS(literal(true), literal(2), literal(5))).should == 5
      end
      it 'unless true {2} elsif true {5} == 5' do
        evaluate(UNLESS(literal(true), literal(2), IF(literal(true), literal(5)))).should == 5
      end
      it 'unless true {2} elsif false {5} == nil' do
        evaluate(UNLESS(literal(true), literal(2), IF(literal(false), literal(5)))).should == nil
      end
    end
    context "a case expression" do
      it 'should output the expected result when dumped' do
        dump(CASE(literal(2),
                  WHEN(literal(1), literal('wat')),
                  WHEN([literal(2), literal(3)], literal('w00t'))
                  )).should == unindent(<<-TEXT
                  (case 2
                    (when (1) (then 'wat'))
                    (when (2 3) (then 'w00t')))
                  TEXT
                  )
        dump(CASE(literal(2),
                  WHEN(literal(1), literal('wat')),
                  WHEN([literal(2), literal(3)], literal('w00t'))
                  ).default(literal(4))).should == unindent(<<-TEXT
                  (case 2
                    (when (1) (then 'wat'))
                    (when (2 3) (then 'w00t'))
                    (when (:default) (then 4)))
                  TEXT
                  )
      end

      it "case 1 { 1 : { 'w00t'} } == 'w00t'" do
        evaluate(CASE(literal(1), WHEN(literal(1), literal('w00t')))).should == 'w00t'
      end
      it "case 2 { 1,2,3 : { 'w00t'} } == 'w00t'" do
        evaluate(CASE(literal(2), WHEN([literal(1), literal(2), literal(3)], literal('w00t')))).should == 'w00t'
      end
      it "case 2 { 1,3 : {'wat'} 2: { 'w00t'} } == 'w00t'" do
        evaluate(CASE(literal(2), 
          WHEN([literal(1), literal(3)], literal('wat')), 
          WHEN(literal(2), literal('w00t')))).should == 'w00t'
      end
      it "case 2 { 1,3 : {'wat'} 5: { 'wat'} default: {'w00t'}} == 'w00t'" do
        evaluate(CASE(literal(2), 
          WHEN([literal(1), literal(3)], literal('wat')), 
          WHEN(literal(5), literal('wat'))).default(literal('w00t'))
          ).should == 'w00t'
      end
      it "case 2 { 1,3 : {'wat'} 5: { 'wat'} } == nil" do
        evaluate(CASE(literal(2), 
          WHEN([literal(1), literal(3)], literal('wat')), 
          WHEN(literal(5), literal('wat')))
          ).should == nil
      end
      it "case 'banana' { 1,3 : {'wat'} /.*ana.*/: { 'w00t'} } == w00t" do
        evaluate(CASE(literal('banana'), 
          WHEN([literal(1), literal(3)], literal('wat')), 
          WHEN(literal(/.*ana.*/), literal('w00t')))
          ).should == 'w00t'
      end
      context "with regular expressions" do
        it "should set numeric variables from the match" do
          evaluate(CASE(literal('banana'), 
            WHEN([literal(1), literal(3)], literal('wat')), 
            WHEN(literal(/.*(ana).*/), var(1)))
            ).should == 'ana'
        end
      end
    end
    context "select expressions" do
      it 'should output the expected result when dumped' do
        dump(literal(2).select(
                  MAP(literal(1), literal('wat')),
                  MAP(literal(2), literal('w00t'))
                  )).should == "(? 2 (1 => 'wat') (2 => 'w00t'))" 
      end
      it "1 ? {1 => 'w00t'} == 'w00t'" do
        evaluate(literal(1).select(MAP(literal(1), literal('w00t')))).should == 'w00t'
      end
      it "2 ? {1 => 'wat', 2 => 'w00t'} == 'w00t'" do
        evaluate(literal(2).select(
          MAP(literal(1), literal('wat')),
          MAP(literal(2), literal('w00t'))
          )).should == 'w00t'
      end
      it "3 ? {1 => 'wat', 2 => 'wat', default => 'w00t'} == 'w00t'" do
        evaluate(literal(3).select(
          MAP(literal(1), literal('wat')),
          MAP(literal(2), literal('wat')),
          MAP(literal(:default), literal('w00t'))
          )).should == 'w00t'
      end
      it "3 ? {1 => 'wat', default => 'w00t', 3 => 'wat'} == 'w00t'" do
        evaluate(literal(3).select(
          MAP(literal(1), literal('wat')),
          MAP(literal(:default), literal('w00t')),
          MAP(literal(2), literal('wat'))
          )).should == 'w00t'
      end
      it "should set numerical variables from match" do
        evaluate(literal('banana').select(
          MAP(literal(1), literal('wat')),
          MAP(literal(/.*(ana).*/), var(1))
          )).should == 'ana'
      end
    end
  end
end