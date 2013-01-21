require 'puppet/parser/ast/block_expression'

class Puppet::Parser::AST
  # A block of statements/expressions with additional parameters
  # Requires scope to contain the values for the defined parameters when evaluated
  # If evaluated without a prepared scope, the lambda will behave like its super class.
  #
  class Lambda < AST::BlockExpression

    # The lambda parameters.
    # These are encoded as an array where each entry is an array of one or two object. The first
    # is the parameter name, and the optional second object is the value expression (that will
    # be evaluated when bound to a scope).
    # The value expression is the default value for the parameter. All default values must be
    # at the end of the parameter list.
    #
    # @return [Array<Array<String,String>] list of parameter names with optional value expression
    attr_accessor :parameters


    # Evaluate each expression/statement and produce the last expression evaluation result
    # @return [Object] what the last expression evaluated to
    def evaluate(scope)
      @expressions.evaluate(scope)
    end

    # Calls the lambda.
    # Assigns argument values in a nested local scope that should be used to evaluate the lambda
    # and then evaluates the lambda.
    # @param scope [Puppet::Scope] the calling scope
    # @return [Object] the result of evaluating the expression(s) in the lambda
    #
    def call(scope, *args)
      raise Puppet::ParseError, "Too many arguments: #{args.size} for #{parameters.size}" unless args.size <= parameters.size
      merged = parameters.zip(args)
      missing = merged.select { |e| !e[1] && e[0].size == 1 }
      unless missing.empty?
        optional = parameters.count { |p| p.size == 2 }
        raise Puppet::ParseError, "Too few arguments; #{args.size} for #{optional > 0 ? ' min ' : ''}#{parameters.size - optional}"
      end
      evaluated = merged.collect do |m|
        n = m[0][0]
        v = m[1] || (m[0][1]).safeevaluate(scope) # given value or default expression value
        [n, v]
      end 
      
      # Store the evaluated name => value associations in a new inner/local/ephemeral scope
      # (This is made complicated due to the fact that the implementation of scope is overloaded with
      # functionality and an inner ephemeral scope must be used (as opposed to just pushing a local scope
      # on a scope "stack").
      begin
        elevel = scope.ephemeral_level
        scope.ephemeral_from(Hash[evaluated], file, line)
        result = safeevaluate(scope)
      ensure
        scope.unset_ephemeral_var(elevel)
        result ||= nil
      end
      result
    end

    # Validate the lambda.
    # Validation checks if parameters with default values are at the end of the list. (It is illegal
    # to have a parameter with default value followed by one without).
    #
    # @raise [Puppet::ParseError] if a parameter with a default comes before a parameter without default value
    #
    def validate
      params = parameters || []
      defaults = params.drop_while {|p| p.size < 2 }
      trailing = defaults.drop_while {|p| p.size == 2 }
      raise Puppet::ParseError, "Lambda parameters with default values must be placed last" unless trailing.empty?
    end

    # Produces the number of parameters (required and optional)
    # @return [Integer] the total number of accepted parameters
    def parameter_count
      @parameters.size
    end

    # Produces the number of optional parameters.
    # @return [Integer] the number of optional accepted parameters
    def optional_parameter_count
      @parameters.count {|p| p.size == 2 }
    end

    def initialize(options)
      super(options)
      # ensure there is an empty parameters structure if not given by creator
      @parameters = [] unless options[:parameters]
      validate
    end
  end
end
