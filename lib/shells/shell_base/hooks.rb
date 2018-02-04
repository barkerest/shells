module Shells
  class ShellBase

    private

    def self.hooks
      @hooks ||= {}
    end

    def self.parent_hooks(name)
      superclass.respond_to?(:all_hooks, true) ? superclass.send(:all_hooks, name) : []
    end

    def self.all_hooks(name)
      parent_hooks(name) + (hooks[name] || [])
    end

    protected

    ##
    # Adds a hook method to the class.
    #
    # A hook method should return :break if it wants to cancel executing any other hook methods in the chain.
    def self.add_hook(hook_name, proc = nil, &block) #:doc:
      hooks[hook_name] ||= []

      if proc.respond_to?(:call)
        hooks[hook_name] << proc
      elsif proc.is_a?(Symbol) || proc.is_a?(String)
        if self.respond_to?(proc, true)
          hooks[hook_name] << method(proc.to_sym)
        end
      elsif proc
        raise ArgumentError, 'proc must respond to :call method or be the name of a static method in this class'
      end

      if block
        hooks[hook_name] << block
      end

    end



    ##
    # Runs a hook statically.
    #
    # The arguments supplied are passed to the hook methods directly.
    #
    # Return false unless the hook was executed.  Returns :break if one of the hook methods returns :break.
    def self.run_static_hook(hook_name, *args)
      list = all_hooks(hook_name)
      list.each do |hook|
        result = hook.call(*args)
        return :break if result == :break
      end
      list.any?
    end

    ##
    # Runs a hook in the current shell instance.
    #
    # The hook method is passed the shell as the first argument then the arguments passed to this method.
    #
    # Return false unless the hook was executed.  Returns :break if one of the hook methods returns :break.
    def run_hook(hook_name, *args)
      list = self.class.all_hooks(hook_name)
      shell = self
      list.each do |hook|
        result = hook.call(shell, *args)
        return :break if result == :break
      end
      list.any?
    end

    ##
    # Returns true if there are any hooks to run.
    def have_hook?(hook_name)
      self.class.all_hooks(hook_name).any?
    end

  end
end