module Shells
  class ShellBase

    protected

    ##
    # Sets up the shell session.
    #
    # This method is called after connecting the shell before the session block is run.
    #
    # By default this method will wait for the prompt to appear in the output.
    #
    # If you need to set the prompt, you would want to do it here.
    def setup #:doc:
      setup_prompt
    end

    ##
    # Sets up the prompt for the shell session.
    #
    # By default this method will wait for the prompt to appear in the output.
    #
    # If you need to set the prompt, you would want to do it here.
    def setup_prompt #:doc:
      wait_for_prompt 30, 30, true
    end


    ##
    # Tears down the shell session.
    #
    # This method is called after the session block is run before disconnecting the shell.
    #
    # The default implementation simply sends the quit command to the shell and waits up to 1 second for a result.
    #
    # This method will be called even if an exception is raised during the session.
    def teardown #:doc:
      unless options[:quit].to_s.strip == ''
        self.ignore_io_error = true
        exec_ignore_code options[:quit], command_timeout: 1, timeout_error: false
      end
    end

    ##
    # Connects to the shell.
    #
    # You must define this method in your subclass.
    def connect #:doc:
      raise ::NotImplementedError
    end

    ##
    # Disconnects from the shell.
    #
    # You must define this method in your subclass.
    # This method will always be called, even if an exception occurs during the session.
    def disconnect #:doc:
      raise ::NotImplementedError
    end

    ##
    # Determines if the shell is currently active.
    #
    # You must define this method in your subclass.
    def active? #:doc:
      raise ::NotImplementedError
    end

    ##
    # Runs the IO loop on the shell while the block returns true.
    #
    # You must define this method in your subclass.
    # It should block for as little time as necessary before yielding to the block.
    def io_loop(&block) #:doc:
      raise ::NotImplementedError
    end

    ##
    # Sends data to the shell.
    #
    # You must define this method in your subclass.
    #
    # It is important that this method not be called directly outside of the +run+ method.
    # Use +queue_input+ to send data to the shell so that it can be handled in a synchronous manner.
    def send_data(data) #:doc:
      raise ::NotImplementedError
    end

    ##
    # Register a callback to run when stdout data is received.
    #
    # The block will be passed the data received.
    #
    # You must define this method in your subclass and it should set a hook to be called when data is received.
    #
    #   def stdout_received
    #     @conn.on_stdout do |data|
    #       yield data
    #     end
    #   end
    #
    def stdout_received(&block) #:doc:
      raise ::NotImplementedError
    end

    ##
    # Register a callback to run when stderr data is received.
    #
    # The block will be passed the data received.
    #
    # You must define this method in your subclass and it should set a hook to be called when data is received.
    #
    #   def stderr_received
    #     @conn.on_stderr do |data|
    #       yield data
    #     end
    #   end
    #
    def stderr_received(&block) #:doc:
      raise ::NotImplementedError
    end

    ##
    # Gets the exit code from the last command.
    #
    # You must define this method in your subclass to utilize exit codes.
    def get_exit_code #:doc:
      self.last_exit_code = :undefined
    end

    public

    ##
    # Reads from a file on the device.
    def read_file(path)
      nil
    end

    ##
    # Writes to a file on the device.
    def write_file(path, data)
      false
    end




  end
end