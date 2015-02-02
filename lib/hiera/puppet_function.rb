require 'hiera_puppet'

# Provides the base class for the puppet functions hiera, hiera_array, hiera_hash, and hiera_include.
# The actual function definitions will call init_dispatch and override the merge_type and post_lookup methods.
#
# @see hiera_array.rb, hiera_include.rb under lib/puppet/functions for sample usage
#
class Hiera::PuppetFunction < Puppet::Functions::InternalFunction
  def self.init_dispatch
    dispatch :hiera_splat do
      scope_param
      param 'Tuple[String, Any, Any, 1, 3]', :args
    end

    dispatch :hiera do
      scope_param
      param 'String',:key
      param 'Any',   :default
      param 'Any',   :override
      arg_count(1,3)
    end

    dispatch :hiera_block1 do
      scope_param
      param 'String',        :key
      required_block_param 'Callable[1,1]', :default_block
    end

    dispatch :hiera_block2 do
      scope_param
      param 'String',                       :key
      param 'Any',                          :override
      required_block_param 'Callable[1,1]', :default_block
    end
  end

  def hiera_splat(scope, args)
    hiera(scope, *args)
  end

  def hiera(scope, key, default = nil, override = nil)
    post_lookup(key, lookup(scope, key, default, override))
  end

  def hiera_block1(scope, key, default_block)
    hiera_block2(scope, key, nil, default_block)
  end

  def hiera_block2(scope, key, override, default_block)
    undefined = (@@undefined_value ||= Object.new)
    result = lookup(scope, key, undefined, override)
    post_lookup(key, result.equal?(undefined) ? default_block.call(scope, key) : result)
  end

  def lookup(scope, key, default, override)
    HieraPuppet.lookup(key, default,scope, override, merge_type)
  end

  def merge_type
    :priority
  end

  def post_lookup(key, result)
    result
  end
end
