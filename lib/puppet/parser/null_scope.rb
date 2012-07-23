module Puppet
  module Parser
    if RUBY_VERSION < "1.9"
      class NullScope
        ##
        # Undefine all methods but those defined in BasicObject.
        ##
        instance_methods.each do |m|
          unless ['==', 'equal?', 'instance_eval', 'instance_exec', '__send__', '__id__'].include? m
            undef_method m
          end
        end
      end
    else
      class NullScope < BasicObject; end
    end

    class NullScope
      def initialize(*)
        # do nothing
      end

      def method_missing(*)
        self
      end

      def nil?
        true
      end
    end
  end
end

