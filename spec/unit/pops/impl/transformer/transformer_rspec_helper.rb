require 'puppet/pops/api'
require 'puppet/pops/api/model/model'
require 'puppet/pops/impl/model/factory'
require 'puppet/pops/impl/model/model_tree_dumper'
require 'puppet/pops/impl/model/ast_tree_dumper'
require 'puppet/pops/impl/model/ast_transformer'
require 'puppet/pops/impl/parser/eparser'
require 'puppet/pops/impl/top_scope'
require 'puppet/parser/ast'
require File.join(File.dirname(__FILE__), '/../factory_rspec_helper')

module TransformerRspecHelper
  include FactoryRspecHelper
  # Dumps the AST to string form
  #
  def astdump(ast)
    ast = transform(ast) unless ast.kind_of?(Puppet::Parser::AST)
    Puppet::Pops::Impl::Model::AstTreeDumper.new.dump(ast)
  end

  # Transforms the Pops model to an AST model
  #
  def transform(model)
    Puppet::Pops::Impl::Model::AstTransformer.new.transform(model)
  end

  # Parses the string code to a Pops model
  #
  def parse(code)
    parser = Puppet::Pops::Impl::Parser::Parser.new()
    parser.parse_string(code)
  end
end
