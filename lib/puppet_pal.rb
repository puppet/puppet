# Puppet as a Library "PAL"

# Yes, this requires all of puppet for now because 'settings' and many other things...
require 'puppet'
require 'puppet/parser/script_compiler'

# This is the main entry point for "Puppet As a Library" PAL.
# This file should be required instead of "puppet"
# Initially, this will require ALL of puppet - over time this will change as the monolithical "puppet" is broken up
# into smaller components.
#
# @example Running a snippet of Puppet Language code
#   require 'puppet_pal'
#   result = Puppet::Pal.in_tmp_environment('pal_env', modulepath: ['/tmp/testmodules']) do |pal|
#     pal.evaluate_script_string('1+2+3')
#   end
#   # The result is the value 6
#
# @example Making a run_plan call
#   require 'puppet_pal'
#   result = Puppet::Pal.in_tmp_environment('pal_env', modulepath: ['/tmp/testmodules']) do |pal|
#     pal.run_plan('mymodule::myplan', plan_args: { 'arg1' => 10, 'arg2' => '20 })
#   end
#   # The result is what 'mymodule::myplan' returns
#
module Puppet
module Pal

  # @param compiler [Puppet::Pal::Compiler] a configured compiler as obtained in the callback from `with_script_compiler`

  class Compiler
    attr_reader :internal_compiler
    protected :internal_compiler

    attr_reader :internal_evaluator
    protected :internal_evaluator

    def initialize(internal_compiler)
      @internal_compiler = internal_compiler
      @internal_evaluator = Puppet::Pops::Parser::EvaluatingParser.new
    end

    # Calls a function given by name with arguments specified in an `Array`, and optionally accepts a code block.
    # @param function_name [String] the name of the function to call
    # @param args [Object] the arguments to the function
    # @param block [Proc] an optional callable block that is given to the called function
    # @return [Object] what the called function returns
    #
    def call_function(function_name, *args, &block)
      # TRANSLATORS: do not translate variable name strings in these assertions
      Pal::assert_non_empty_string(function_name, 'function_name', false)
      Pal::assert_type(Pal::T_ANY_ARRAY, args, 'args', false)
      internal_evaluator.evaluator.external_call_function(function_name, args, topscope, &block)
    end

    # Returns an Array[Puppet::Pops::Types::PCallableType] describing the given function's signatures, or empty array if function not found.
    # @param function_name [String] the name of the function to get a signature for
    # @return [Array<Puppet::Pops::Types::PCallableType>] an array of callable signatures, or an empty array if function not found
    def function_signatures(function_name)
      loader = internal_compiler.loaders.private_environment_loader
      if func = loader.load(:function, function_name)
        t = func.class.dispatcher.to_type
        return t.is_a?(Puppet::Pops::Types::PVariantType) ? t.types : [t]
      end
      # Could not find function
      Puppet::Pops::EMPTY_ARRAY
    end

    # Lexes a string of puppet language code in top scope and returns an array of 'tokens'.
    # A "source_file" reference to a source can be given - if not an actual file name, by convention the name should
    # be bracketed with < > to indicate it is something symbolic; for example `<commandline>` if the string was given on the
    # command line.
    #
    # If the given `puppet_code` is `nil`, nil is returned, otherwise the result of lexing the
    # puppet language string. The given string must form a complete and valid token as an error is raised
    # otherwise. That is, it is not possible to divide a token on multiple lines and lex each line individually.
    #
    # A token is is encoded as an Array with two entries - the first is always a symbol indicating the kind of token.
    # The second is a a `TokenValue` object holding the value of the token and meta data about that token. To get
    # information from the `TokenValue´ use operator `[key]` to get the following keys:
    #
    # * `value` -- the value of the lexed token
    # * `file` -- the name of the file
    # * `line` -- the line number where the token starts (computed on demand, do not request unless needed)
    # * `pos` -- the start position on the line where the token starts (computed on demand, do not request unless needed)
    # * `length` -- the length of the token text
    # * `offset` -- the byte offset of the token's start
    # * `locator` -- an object with information about byte/chars/line-endings that can compute further information
    #
    # @param puppet_code [String, nil] the puppet language code to lex, must be a complete token
    # @param source_file [String, nil] an optional reference to a source (a file or symbolic name/location)
    # @return [Array<Symbol, Puppet::Pops::Parser::LexerSupport::TokenValue] an array of token tuples, or nil if there was no input to lex
    #
    def lex_string(puppet_code, source_file=nil)
      return nil if puppet_code.nil?
      unless puppet_code.is_a?(String)
        raise ArgumentError, _("The argument 'puppet_code' must be a String, got %{type}") % { type: puppet_code.class }
      end
      return [] if puppet_code == ''

      lexer = internal_evaluator.parser.lexer
      lexer.lex_string(puppet_code, source_file)
      result = lexer.fullscan()
      result.pop # throw away EOF token
      result
    end

    # Lexes a file of puppet language code in top scope and returns an array of 'tokens'.
    #
    # If the given `file` is `nil`, `nil` is returned, otherwise the result of lexing the
    # puppet language file (which must exist).
    #
    # For the format of the returned tokens see the `lex_string` method.
    #
    # @param file [String, nil] the puppet language file to lex
    # @return [Array<Symbol, Puppet::Pops::Parser::LexerSupport::TokenValue] an array of token tuples, or nil if there was no input to lex
    #
    def lex_file(file)
      return nil if file.nil?
      unless file.is_a?(String)
        raise ArgumentError, _("The argument 'file' must be a String, got %{type}") % { type: puppet_code.class }
      end

      unless Puppet::FileSystem.exist?(file)
        raise ArgumentError, _("The argument 'file' must be an existing file - '%{file}' was not found") % { file: file }
      end

      lexer = internal_evaluator.parser.lexer
      lexer.lex_file(file)
      result = lexer.fullscan()
      result.pop # throw away EOF token
      result
    end

    # Evaluates a string of puppet language code in top scope.
    # A "source_file" reference to a source can be given - if not an actual file name, by convention the name should
    # be bracketed with < > to indicate it is something symbolic; for example `<commandline>` if the string was given on the
    # command line.
    #
    # If the given `puppet_code` is `nil` or an empty string, `nil` is returned, otherwise the result of evaluating the
    # puppet language string. The given string must form a complete and valid expression/statement as an error is raised
    # otherwise. That is, it is not possible to divide a compound expression by line and evaluate each line individually.
    #
    # @param puppet_code [String, nil] the puppet language code to evaluate, must be a complete expression/statement
    # @param source_file [String, nil] an optional reference to a source (a file or symbolic name/location)
    # @return [Object] what the `puppet_code` evaluates to
    #
    def evaluate_string(puppet_code, source_file = nil)
      return nil if puppet_code.nil? || puppet_code == ''
      unless puppet_code.is_a?(String)
        raise ArgumentError, _("The argument 'puppet_code' must be a String, got %{type}") % { type: puppet_code.class }
      end
      internal_evaluator.evaluate_string(topscope, puppet_code, source_file)
    end

    # Evaluates a puppet language file in top scope.
    # The file must exist and contain valid puppet language code or an error is raised.
    #
    # @param file [Path, String] an absolute path to a file with puppet language code, must exist
    # @return [Object] what the last evaluated expression in the file evaluated to
    #
    def evaluate_file(file)
      internal_evaluator.evaluate_file(topscope, file)
    end

    # Parses a puppet data type given in String format and returns that type, or raises an error.
    # A type is needed in calls to `new` to create an instance of the data type, or to perform type checking
    # of values - typically using `type.instance?(obj)` to check if `obj` is an instance of the type.
    #
    # @example Verify if obj is an instance of a data type
    #   # evaluates to true
    #   pal.type('Enum[red, blue]').instance?("blue")
    #
    # @example Create an instance of a data type
    #   # using an already create type
    #   t = pal.type('Car')
    #   pal.create(t, 'color' => 'black', 'make' => 't-ford')
    #
    #   # letting 'new_object' parse the type from a string
    #   pal.create('Car', 'color' => 'black', 'make' => 't-ford')
    #
    # @param type_string [String] a puppet language data type
    # @return [Puppet::Pops::Types::PAnyType] the data type
    #
    def type(type_string)
      Puppet::Pops::Types::TypeParser.singleton.parse(type_string)
    end

    # Creates a new instance of a given data type.
    # @param data_type [String, Puppet::Pops::Types::PAnyType] the data type as a data type or in String form.
    # @param arguments [Object] one or more arguments to the called `new` function
    # @return [Object] an instance of the given data type,
    #   or raises an error if it was not possible to parse data type or create an instance.
    #
    def create(data_type, *arguments)
      t = data_type.is_a?(String) ? type(data_type) : data_type
      unless t.is_a?(Puppet::Pops::Types::PAnyType)
        raise ArgumentError, _("Given data_type value is not a data type, got '%{type}'") % {type: t.class}
      end
      call_function('new', t, *arguments)
    end

    private

    def topscope
      internal_compiler.topscope
    end
  end

  class ScriptCompiler < Compiler
    # Returns the signature callable of the given plan (the arguments it accepts, and the data type it returns)
    # @param plan_name [String] the name of the plan to get the signature of
    # @return [Puppet::Pops::Types::PCallableType, nil] returns a callable data type, or nil if plan is not found
    #
    def plan_signature(plan_name)
      loader = internal_compiler.loaders.private_environment_loader
      if func = loader.load(:plan, plan_name)
        return func.class.dispatcher.to_type
      end
      # Could not find plan
      nil
    end
  end

  # Defines a context in which multiple operations in an env with a script compiler can be performed in a given block.
  # The calls that takes place to PAL inside of the given block are all with the same instance of the compiler.
  # The parameter `configured_by_env` makes it possible to either use the configuration in the environment, or specify
  # `manifest_file` or `code_string` manually. If neither is given, an empty `code_string` is used.
  #
  # @example define a script compiler without any initial logic
  #   pal.with_script_compiler do | compiler |
  #     # do things with compiler
  #   end
  #
  # @example define a script compiler with a code_string containing initial logic
  #   pal.with_script_compiler(code_string: '$myglobal_var = 42')  do | compiler |
  #     # do things with compiler
  #   end
  #
  # @param configured_by_env [Boolean] when true the environment's settings are used, otherwise the given `manifest_file` or `code_string`
  # @param manifest_file [String] a Puppet Language file to load and evaluate before calling the given block, mutually exclusive with `code_string`
  # @param code_string [String] a Puppet Language source string to load and evaluate before calling the given block, mutually exclusive with `manifest_file`
  # @param facts [Hash] optional map of fact name to fact value - if not given will initialize the facts (which is a slow operation)
  #   If given at the environment level, the facts given here are merged with higher priority.
  # @param variables [Hash] optional map of fully qualified variable name to value. If given at the environment level, the variables
  #   given here are merged with higher priority.
  # @param block [Proc] the block performing operations on compiler
  # @return [Object] what the block returns
  # @yieldparam [Puppet::Pal::ScriptCompiler] compiler, a ScriptCompiler to perform operations on.
  #
  def self.with_script_compiler(
      configured_by_env: false,
      manifest_file:     nil,
      code_string:       nil,
      facts:             nil,
      variables:         nil,
      &block
    )
    # TRANSLATORS: do not translate variable name strings in these assertions
    assert_mutually_exclusive(manifest_file, code_string, 'manifest_file', 'code_string')
    assert_non_empty_string(manifest_file, 'manifest_file', true)
    assert_non_empty_string(code_string, 'code_string', true)
    assert_type(T_BOOLEAN, configured_by_env, "configured_by_env", false)

    if configured_by_env
      unless manifest_file.nil? && code_string.nil?
        # TRANSLATORS: do not translate the variable names in this error message
        raise ArgumentError, _("manifest_file or code_string cannot be given when configured_by_env is true")
      end
      # Use the manifest setting
      manifest_file = Puppet[:manifest]
    else
      # An "undef" code_string is the only way to override Puppet[:manifest] & Puppet[:code] settings since an
      # empty string is taken as Puppet[:code] not being set.
      #
      if manifest_file.nil? && code_string.nil?
        code_string = 'undef'
      end
    end

    Puppet[:tasks] = true
    # After the assertions, if code_string is non nil - it has the highest precedence
    Puppet[:code] = code_string unless code_string.nil?
    overrides = {}
    unless facts.nil?
      overrides[:pal_facts] = Puppet.lookup(:pal_facts).merge(facts)
    end
    unless variables.nil?
      overrides[:pal_variables] = Puppet.lookup(:pal_variables).merge(variables)
    end
    Puppet.override(overrides, "PAL::with_script_compiler") do # TRANSLATORS: Do not translate, symbolic name
      # If manifest_file is nil, the #main method will use the env configured manifest
      # do things in block while a Script Compiler is in effect
      main(manifest_file, &block)
    end
  end

  # Evaluates a Puppet Language script string.
  # @param code_string [String] a snippet of Puppet Language source code
  # @return [Object] what the Puppet Language code_string evaluates to
  # @deprecated Use {#with_script_compiler} and then evaluate_string on the given compiler - to be removed in 1.0 version
  #
  def self.evaluate_script_string(code_string)
    # prevent the default loading of Puppet[:manifest] which is the environment's manifest-dir by default settings
    # by setting code_string to 'undef'
    with_script_compiler do |compiler|
      compiler.evaluate_string(code_string)
    end
  end

  # Evaluates a Puppet Language script (.pp) file.
  # @param manifest_file [String] a file with Puppet Language source code
  # @return [Object] what the Puppet Language manifest_file contents evaluates to
  # @deprecated Use {#with_script_compiler} and then evaluate_file on the given compiler - to be removed in 1.0 version
  #
  def self.evaluate_script_manifest(manifest_file)
    with_script_compiler do |compiler|
      compiler.evaluate_file(manifest_file)
    end
  end

  # Runs the given named plan passing arguments by name in a hash.
  # @param plan_name [String] the name of the plan to run
  # @param plan_args [Hash] arguments to the plan - a map of plan parameter name to value, defaults to empty hash
  # @param manifest_file [String] a Puppet Language file to load and evaluate before running the plan, mutually exclusive with code_string
  # @param code_string [String] a Puppet Language source string to load and evaluate before running the plan, mutually exclusive with manifest_file
  # @return [Object] returns what the evaluated plan returns
  # @deprecated Use {#with_script_compiler} and then `call_function('run_plan', plan_name, plan_args)` on the given compiler - to be removed in 1.0 version
  #
  def self.run_plan(plan_name,
      plan_args:     {},
      manifest_file: nil,
      code_string:   nil
    )
    with_script_compiler(manifest_file: manifest_file, code_string: code_string) do |compiler|
      compiler.call_function('run_plan', plan_name, plan_args)
    end
  end


  # Defines the context in which to perform puppet operations (evaluation, etc)
  # The code to evaluate in this context is given in a block.
  #
  # @param env_name [String] a name to use for the temporary environment - this only shows up in errors
  # @param modulepath [Array<String>] an array of directory paths containing Puppet modules, may be empty, defaults to empty array
  # @param settings_hash [Hash] a hash of settings - currently not used for anything, defaults to empty hash
  # @param facts [Hash] optional map of fact name to fact value - if not given will initialize the facts (which is a slow operation)
  # @param variables [Hash] optional map of fully qualified variable name to value
  # @return [Object] returns what the given block returns
  # @yieldparam [Puppet::Pal] context, a context that responds to Puppet::Pal methods
  #
  def self.in_tmp_environment(env_name,
      modulepath:    [],
      settings_hash: {},
      facts:         nil,
      variables:     {},
      &block
    )
    assert_non_empty_string(env_name, _("temporary environment name"))
    # TRANSLATORS: do not translate variable name string in these assertions
    assert_optionally_empty_array(modulepath, 'modulepath')

    unless block_given?
      raise ArgumentError, _("A block must be given to 'in_tmp_environment'") # TRANSLATORS 'in_tmp_environment' is a name, do not translate
    end

    env = Puppet::Node::Environment.create(env_name, modulepath)

    in_environment_context(
      Puppet::Environments::Static.new(env), # The tmp env is the only known env
      env, facts, variables, &block
      )
  end

  # Defines the context in which to perform puppet operations (evaluation, etc)
  # The code to evaluate in this context is given in a block.
  #
  # The name of an environment (env_name) is always given. The location of that environment on disk
  # is then either constructed by:
  # * searching a given envpath where name is a child of a directory on that path, or
  # * it is the directory given in env_dir (which must exist).
  #
  # The env_dir and envpath options are mutually exclusive.
  #
  # @param env_name [String] the name of an existing environment
  # @param modulepath [Array<String>] an array of directory paths containing Puppet modules, overrides the modulepath of an existing env.
  #   Defaults to `{env_dir}/modules` if `env_dir` is given,
  # @param pre_modulepath [Array<String>] like modulepath, but is prepended to the modulepath
  # @param post_modulepath [Array<String>] like modulepath, but is appended to the modulepath
  # @param settings_hash [Hash] a hash of settings - currently not used for anything, defaults to empty hash
  # @param env_dir [String] a reference to a directory being the named environment (mutually exclusive with `envpath`)
  # @param envpath [String] a path of directories in which there are environments to search for `env_name` (mutually exclusive with `env_dir`).
  #   Should be a single directory, or several directories separated with platform specific `File::PATH_SEPARATOR` character.
  # @param facts [Hash] optional map of fact name to fact value - if not given will initialize the facts (which is a slow operation)
  # @param variables [Hash] optional map of fully qualified variable name to value
  # @return [Object] returns what the given block returns
  # @yieldparam [Puppet::Pal] context, a context that responds to Puppet::Pal methods
  #
  def self.in_environment(env_name,
      modulepath:    nil,
      pre_modulepath: [],
      post_modulepath: [],
      settings_hash: {},
      env_dir:       nil,
      envpath:       nil,
      facts:         nil,
      variables:     {},
      &block
    )
    # TRANSLATORS terms in the assertions below are names of terms in code
    assert_non_empty_string(env_name, 'env_name')
    assert_optionally_empty_array(modulepath, 'modulepath', true)
    assert_optionally_empty_array(pre_modulepath, 'pre_modulepath', false)
    assert_optionally_empty_array(post_modulepath, 'post_modulepath', false)
    assert_mutually_exclusive(env_dir, envpath, 'env_dir', 'envpath')

    unless block_given?
      raise ArgumentError, _("A block must be given to 'in_environment'") # TRANSLATORS 'in_environment' is a name, do not translate
    end

    if env_dir
      unless Puppet::FileSystem.exist?(env_dir)
        raise ArgumentError, _("The environment directory '%{env_dir}' does not exist") % { env_dir: env_dir }
      end

      # a nil modulepath for env_dir means it should use its ./modules directory
      mid_modulepath = modulepath.nil? ? [Puppet::FileSystem.expand_path(File.join(env_dir, 'modules'))] : modulepath

      env = Puppet::Node::Environment.create(env_name, pre_modulepath + mid_modulepath + post_modulepath)
      environments = Puppet::Environments::StaticDirectory.new(env_name, env_dir, env) # The env being used is the only one...
    else
      assert_non_empty_string(envpath, 'envpath')

      # The environment is resolved against the envpath. This is setup without a basemodulepath
      # The modulepath defaults to the 'modulepath' in the found env when "Directories" is used
      #
      if envpath.is_a?(String) && envpath.include?(File::PATH_SEPARATOR)
        # potentially more than one directory to search
        env_loaders = Puppet::Environments::Directories.from_path(envpath, [])
        environments = Puppet::Environments::Combined.new(*env_loaders)
      else
        environments = Puppet::Environments::Directories.new(envpath, [])
      end
      env = environments.get(env_name)
      if env.nil?
        raise ArgumentError, _("No directory found for the environment '%{env_name}' on the path '%{envpath}'") % { env_name: env_name, envpath: envpath }
      end
      # A given modulepath should override the default
      mid_modulepath = modulepath.nil? ? env.modulepath : modulepath
      env_path = env.configuration.path_to_env
      env = env.override_with(:modulepath => pre_modulepath + mid_modulepath + post_modulepath)
      # must configure this in case logic looks up the env by name again (otherwise the looked up env does
      # not have the same effective modulepath).
      environments = Puppet::Environments::StaticDirectory.new(env_name, env_path, env) # The env being used is the only one...
    end
    in_environment_context(environments, env, facts, variables, &block)
  end

  private

  # Prepares the puppet context with pal information - and delegates to the block
  # No set up is performed at this step - it is delayed until it is known what the
  # operation is going to be (for example - using a ScriptCompiler).
  #
  def self.in_environment_context(environments, env, facts, variables, &block)
    # Create a default node to use (may be overridden later)
    node = Puppet::Node.new(Puppet[:node_name_value], :environment => env)

    Puppet.override(
      environments: environments,     # The env being used is the only one...
      pal_env: env,                   # provide as convenience
      pal_current_node: node,         # to allow it to be picked up instead of created
      pal_variables: variables,       # common set of variables across several inner contexts
      pal_facts: facts                # common set of facts across several inner contexts (or nil)
    ) do
      # DELAY: prepare_node_facts(node, facts)
      return block.call(self)
    end
  end

  # Prepares the node for use by giving it node_facts (if given)
  # If a hash of facts values is given, then the operation of creating a node with facts is much
  # speeded up (as getting a fresh set of facts is avoided in a later step).
  #
  def self.prepare_node_facts(node, facts)
    # Prepare the node with facts if it does not already have them
    if node.facts.nil?
      node_facts = facts.nil? ? nil : Puppet::Node::Facts.new(Puppet[:node_name_value], facts)
      node.fact_merge(node_facts)
      # Add server facts so $server_facts[environment] exists when doing a puppet script
      # SCRIPT TODO: May be needed when running scripts under orchestrator. Leave it for now.
      #
      node.add_server_facts({})
    end
  end

  def self.add_variables(scope, variables)
    return if variables.nil?
    unless variables.is_a?(Hash)
      raise ArgumentError, _("Given variables must be a hash, got %{type}") % { type: variables.class }
    end

    rich_data_t = Puppet::Pops::Types::TypeFactory.rich_data
    variables.each_pair do |k,v|
      unless k =~ Puppet::Pops::Patterns::VAR_NAME
        raise ArgumentError, _("Given variable '%{varname}' has illegal name") % { varname: k }
      end

      unless rich_data_t.instance?(v)
        raise ArgumentError, _("Given value for '%{varname}' has illegal type - got: %{type}") % { varname: k, type: v.class }
      end

      scope.setvar(k, v)
    end
  end

  # The main routine for script compiler
  # Picks up information from the puppet context and configures a script compiler which is given to
  # the provided block
  #
  def self.main(manifest = nil, &block)
    # Configure the load path
    env = Puppet.lookup(:pal_env)
    env.each_plugin_directory do |dir|
      $LOAD_PATH << dir unless $LOAD_PATH.include?(dir)
    end

    # Puppet requires Facter, which initializes its lookup paths. Reset Facter to
    # pickup the new $LOAD_PATH.
    Facter.reset

    node = Puppet.lookup(:pal_current_node)
    prepare_node_facts(node, Puppet.lookup(:pal_facts))

    configured_environment = node.environment || Puppet.lookup(:current_environment)

    apply_environment = manifest ?
      configured_environment.override_with(:manifest => manifest) :
      configured_environment

    # Modify the node descriptor to use the special apply_environment.
    # It is based on the actual environment from the node, or the locally
    # configured environment if the node does not specify one.
    # If a manifest file is passed on the command line, it overrides
    # the :manifest setting of the apply_environment.
    node.environment = apply_environment

    # TRANSLATORS, the string "For puppet PAL" is not user facing
    Puppet.override({:current_environment => apply_environment}, "For puppet PAL") do
        begin
          # support the following features when evaluating puppet code
          # * $facts with facts from host running the script
          # * $settings with 'settings::*' namespace populated, and '$settings::all_local' hash
          # * $trusted as setup when using puppet apply
          # * an environment
          #

          # fixup trusted information
          node.sanitize()

          compiler = Puppet::Parser::ScriptCompiler.new(node.environment, node.name)
          topscope = compiler.topscope

          # When scripting the trusted data are always local, but set them anyway
          topscope.set_trusted(node.trusted_data)

          # Server facts are always about the local node's version etc.
          topscope.set_server_facts(node.server_facts)

          # Set $facts for the node running the script
          facts_hash = node.facts.nil? ? {} : node.facts.values
          topscope.set_facts(facts_hash)

          # create the $settings:: variables
          topscope.merge_settings(node.environment.name, false)

          add_variables(topscope, Puppet.lookup(:pal_variables))

          # compiler.compile(&block)
          compiler.compile do | internal_compiler |
            # wrap the internal compiler to prevent it from leaking in the PAL API
            block.call(ScriptCompiler.new(internal_compiler)) unless !block_given?
          end

        rescue Puppet::ParseErrorWithIssue, Puppet::Error => detail
          # already logged and handled by the compiler for these two cases
          raise

        rescue => detail
          Puppet.log_exception(detail)
          raise
      end
    end
  end

  T_STRING = Puppet::Pops::Types::PStringType::NON_EMPTY
  T_STRING_ARRAY = Puppet::Pops::Types::TypeFactory.array_of(T_STRING)
  T_ANY_ARRAY = Puppet::Pops::Types::TypeFactory.array_of_any
  T_BOOLEAN = Puppet::Pops::Types::PBooleanType::DEFAULT

  def self.assert_type(type, value, what, allow_nil=false)
    Puppet::Pops::Types::TypeAsserter.assert_instance_of(nil, type, value, allow_nil) { _('Puppet Pal: %{what}') % {what: what} }
  end

  def self.assert_non_empty_string(s, what, allow_nil=false)
    assert_type(T_STRING, s, what, allow_nil)
  end

  def self.assert_optionally_empty_array(a, what, allow_nil=false)
    assert_type(T_STRING_ARRAY, a, what, allow_nil)
  end

  def self.assert_mutually_exclusive(a, b, a_term, b_term)
    if a && b
      raise ArgumentError, _("Cannot use '%{a_term}' and '%{b_term}' at the same time") % { a_term: a_term, b_term: b_term }
    end
  end

  def self.assert_block_given(block)
    if block.nil?
      raise ArgumentError, _("A block must be given")
    end
  end
end
end

