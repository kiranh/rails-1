module ActionService # :nodoc:
  module Invocation # :nodoc:
    ConcreteInvocation = :concrete
    VirtualInvocation = :virtual
    UnpublishedConcreteInvocation = :unpublished_concrete

    class InvocationError < ActionService::ActionServiceError # :nodoc:
    end

    def self.append_features(base) # :nodoc:
      super
      base.extend(ClassMethods)
      base.send(:include, ActionService::Invocation::InstanceMethods)
    end

    # Invocation interceptors provide a means to execute custom code before
    # and after method invocations on ActionService::Base objects.
    #
    # When running in _Direct_ dispatching mode, ActionController filters
    # should be used for this functionality instead.
    #
    # The semantics of invocation interceptors are the same as ActionController
    # filters, and accept the same parameters and options.
    #
    # A _before_ interceptor can also cancel execution by returning +false+,
    # or returning a <tt>[false, "cancel reason"]</tt> array if it wishes to supply
    # a reason for canceling the request.
    #
    # === Example
    #
    #   class CustomService < ActionService::Base
    #     before_invocation :intercept_add, :only => [:add]
    #
    #     def add(a, b)
    #       a + b
    #     end
    #
    #     private
    #       def intercept_add
    #         return [false, "permission denied"] # cancel it
    #       end
    #   end
    #
    # Options:
    # [<tt>:except</tt>]  A list of methods for which the interceptor will NOT be called
    # [<tt>:only</tt>]    A list of methods for which the interceptor WILL be called
    module ClassMethods
      # Appends the given +interceptors+ to be called
      # _before_ method invocation.
      def append_before_invocation(*interceptors, &block)
        conditions = extract_conditions!(interceptors)
        interceptors << block if block_given?
        add_interception_conditions(interceptors, conditions)
        append_interceptors_to_chain("before", interceptors)
      end

      # Prepends the given +interceptors+ to be called
      # _before_ method invocation.
      def prepend_before_invocation(*interceptors, &block)
        conditions = extract_conditions!(interceptors)
        interceptors << block if block_given?
        add_interception_conditions(interceptors, conditions)
        prepend_interceptors_to_chain("before", interceptors)
      end

      alias :before_invocation :append_before_invocation

      # Appends the given +interceptors+ to be called
      # _after_ method invocation.
      def append_after_invocation(*interceptors, &block)
        conditions = extract_conditions!(interceptors)
        interceptors << block if block_given?
        add_interception_conditions(interceptors, conditions)
        append_interceptors_to_chain("after", interceptors)
      end

      # Prepends the given +interceptors+ to be called
      # _after_ method invocation.
      def prepend_after_invocation(*interceptors, &block)
        conditions = extract_conditions!(interceptors)
        interceptors << block if block_given?
        add_interception_conditions(interceptors, conditions)
        prepend_interceptors_to_chain("after", interceptors)
      end

      alias :after_invocation :append_after_invocation

      def before_invocation_interceptors # :nodoc:
        read_inheritable_attribute("before_invocation_interceptors")
      end

      def after_invocation_interceptors # :nodoc:
        read_inheritable_attribute("after_invocation_interceptors")
      end

      def included_intercepted_methods # :nodoc:
        read_inheritable_attribute("included_intercepted_methods") || {}
      end
      
      def excluded_intercepted_methods # :nodoc:
        read_inheritable_attribute("excluded_intercepted_methods") || {}
      end

      private
        def append_interceptors_to_chain(condition, interceptors)
          write_inheritable_array("#{condition}_invocation_interceptors", interceptors)
        end

        def prepend_interceptors_to_chain(condition, interceptors)
          interceptors = interceptors + read_inheritable_attribute("#{condition}_invocation_interceptors")
          write_inheritable_attribute("#{condition}_invocation_interceptors", interceptors)
        end

        def extract_conditions!(interceptors)
          return nil unless interceptors.last.is_a? Hash
          interceptors.pop
        end

        def add_interception_conditions(interceptors, conditions)
          return unless conditions
          included, excluded = conditions[:only], conditions[:except]
          write_inheritable_hash("included_intercepted_methods", condition_hash(interceptors, included)) && return if included
          write_inheritable_hash("excluded_intercepted_methods", condition_hash(interceptors, excluded)) if excluded
        end

        def condition_hash(interceptors, *methods)
          interceptors.inject({}) {|hash, interceptor| hash.merge(interceptor => methods.flatten.map {|method| method.to_s})}
        end
    end

    module InstanceMethods # :nodoc:
      def self.append_features(base)
        super
        base.class_eval do
          alias_method :perform_invocation_without_interception, :perform_invocation
          alias_method :perform_invocation, :perform_invocation_with_interception
        end
      end

      def perform_invocation_with_interception(invocation, &block)
        return if before_invocation(invocation.method_name, invocation.params, &block) == false
        result = perform_invocation_without_interception(invocation)
        after_invocation(invocation.method_name, invocation.params, result)
        result
      end

      def perform_invocation(invocation)
        if invocation.concrete?
          unless self.respond_to?(invocation.method_name) && \
                 self.class.web_service_api.has_api_method?(invocation.method_name)
            raise InvocationError, "no such web service method '#{invocation.method_name}' on service object"
          end
        end
        params = invocation.params
        if invocation.concrete? || invocation.unpublished_concrete?
          self.send(invocation.method_name, *params)
        else
          if invocation.block
            params = invocation.block_params + params
            invocation.block.call(invocation.public_method_name, *params)
          else
            self.send(invocation.method_name, *params)
          end
        end
      end

      def before_invocation(name, args, &block)
        call_interceptors(self.class.before_invocation_interceptors, [name, args], &block)
      end

      def after_invocation(name, args, result)
        call_interceptors(self.class.after_invocation_interceptors, [name, args, result])
      end

      private

        def call_interceptors(interceptors, interceptor_args, &block)
          if interceptors and not interceptors.empty?
            interceptors.each do |interceptor|
              next if method_exempted?(interceptor, interceptor_args[0].to_s)
              result = case
                when interceptor.is_a?(Symbol)
                  self.send(interceptor, *interceptor_args)
                when interceptor_block?(interceptor)
                  interceptor.call(self, *interceptor_args)
                when interceptor_class?(interceptor)
                  interceptor.intercept(self, *interceptor_args)
                else
                  raise(
                    InvocationError,
                    "Interceptors need to be either a symbol, proc/method, or a class implementing a static intercept method"
                  )
              end
              reason = nil
              if result.is_a?(Array)
                reason = result[1] if result[1]
                result = result[0]
              end
              if result == false
                block.call(reason) if block && reason
                return false
              end
            end
          end
        end

        def interceptor_block?(interceptor)
          interceptor.respond_to?("call") && (interceptor.arity == 3 || interceptor.arity == -1)
        end
        
        def interceptor_class?(interceptor)
          interceptor.respond_to?("intercept")
        end

        def method_exempted?(interceptor, method_name)
          case
            when self.class.included_intercepted_methods[interceptor]
              !self.class.included_intercepted_methods[interceptor].include?(method_name)
            when self.class.excluded_intercepted_methods[interceptor] 
              self.class.excluded_intercepted_methods[interceptor].include?(method_name)
          end
        end
    end

    class InvocationRequest # :nodoc:
      attr_accessor :type
      attr :public_method_name
      attr_accessor :method_name
      attr_accessor :params
      attr_accessor :block
      attr :block_params

      def initialize(type, public_method_name, method_name, params=nil)
        @type = type
        @public_method_name = public_method_name
        @method_name = method_name
        @params = params || []
        @block = nil
        @block_params = []
      end

      def concrete?
        @type == ConcreteInvocation ? true : false
      end

      def unpublished_concrete?
        @type == UnpublishedConcreteInvocation ? true : false
      end
    end

  end
end
