module Shells
  class ShellBase

    ##
    # Sets the code to be run when debug messages are processed.
    #
    # The code will receive the debug message as an argument.
    #
    #   on_debug do |msg|
    #     puts msg
    #   end
    #
    def self.on_debug(proc = nil, &block)
      add_hook :on_debug, proc, &block
    end

    protected

    ##
    # Processes a debug message.
    def self.debug(msg) #:doc:
      run_static_hook :on_debug, msg
    end

    ##
    # Processes a debug message for an instance.
    #
    # This is processed synchronously.
    def debug(msg) #:doc:
      if have_hook?(:on_debug)
        sync { self.class.debug msg }
      end
    end


  end
end