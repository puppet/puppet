module PuppetSpec::Compiler
  def compile_to_catalog(string, node = Puppet::Node.new('foonode'))
    Puppet[:code] = string
    Puppet::Parser::Compiler.compile(node)
  end

  def compile_ruby_to_catalog(string = nil, node = Puppet::Node.new('foonode'))
    Puppet[:manifest] = "test.rb"
    Puppet[:code] = string
    Puppet::Parser::Compiler.compile(node)
  end

  def prepare_compiler
    @compiler = Puppet::Parser::Compiler.new(Puppet::Node.new("floppy", :environment => 'production'))
    @scope = Puppet::Parser::Scope.new @compiler
    @topscope = @compiler.topscope
    @scope.parent = @topscope
  end

end
