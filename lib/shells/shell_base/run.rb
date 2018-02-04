module Shells
  class ShellBase

    attr_accessor :run_flag
    private :run_flag, :run_flag=

    add_hook :on_init do |sh|
      sh.instance_eval do
        self.run_flag = false
      end
    end

    ##
    # Is the shell currently running?
    def running?
      run_flag
    end

    # the thread used to run the session.
    attr_accessor :session_thread
    private :session_thread, :session_thread=

    # track exceptions raised during session execution.
    attr_accessor :session_exception
    private :session_exception, :session_exception=

    ##
    # Set to true to ignore IO errors.
    attr_accessor :ignore_io_error
    protected :ignore_io_error, :ignore_io_error=

    add_hook :on_before_run do |sh|
      sh.instance_eval do
        self.session_exception = nil
        self.ignore_io_error = false
      end
    end

    ##
    # Runs a shell session.
    #
    # The block provided will be run asynchronously with the shell.
    #
    # Returns the shell instance.
    def run(&block)
      sync do
        raise Shells::AlreadyRunning if running?
        self.run_flag = true
      end

      begin
        run_hook :on_before_run

        debug 'Connecting...'
        connect

        buffer_output

        # run the session asynchronously.
        self.session_thread = Thread.start(self) do |sh|
          begin
            begin
              debug 'Executing setup...'
              sh.instance_eval { setup }
              debug 'Executing block...'
              block.call sh
            ensure
              debug 'Executing teardown...'
              sh.instance_eval { teardown }
            end
          rescue Shells::QuitNow
            # just exit the session.
          rescue =>e
            # if the exception is handled by the hook no further processing is required, otherwise we store the exception
            # to propagate it in the main thread.
            unless sh.run_hook(:on_exception, e) == :break
              sh.sync { sh.instance_eval { self.session_exception = e } }
            end
          end
        end

        # process the input buffer while the thread is alive and the shell is active.
        debug 'Entering IO loop...'
        io_loop do
          if active?
            begin
              if session_thread.status    # not dead
                # process input from the session.
                unless wait_for_output
                  inp = next_input
                  if inp
                    send_data inp
                    self.wait_for_output = (options[:unbuffered_input] == :echo)
                  end
                end

                # continue running the IO loop
                true
              elsif session_exception
                # propagate the exception.
                raise session_exception.class, session_exception.message, session_exception.backtrace
              else
                # the thread has exited, but no exception exists.
                # regardless, the IO loop should now exit.
                false
              end
            rescue IOError
              if ignore_io_error
                # we were (sort of) expecting the IO error, so just tell the IO loop to exit.
                false
              else
                raise
              end
            end
          else
            # the shell session is no longer active, tell the IO loop to exit.
            false
          end
        end
      rescue
        # when an error occurs, try to disconnect, but ignore any further errors.
        begin
          debug 'Disconnecting...'
          disconnect
        rescue
          # ignore
        end
        raise
      else
        # when no error occurs, try to disconnect and propagate any errors (unless we are ignoring IO errors).
        begin
          debug 'Disconnecting...'
          disconnect
        rescue IOError
          raise unless ignore_io_error
        end
      ensure
        # cleanup
        run_hook :on_after_run
        self.run_flag = false
      end

      self
    end

    protected

    ##
    # Adds code to be run when an exception occurs.
    #
    # This code will receive the shell as the first argument and the exception as the second.
    # If it handles the exception it should return :break.
    #
    #   on_exception do |shell, ex|
    #     if ex.is_a?(MyExceptionType)
    #       ...
    #       :break
    #     else
    #       false
    #     end
    #   end
    #
    # You can also pass the name of a static method.
    #
    #   def self.some_exception_handler(shell, ex)
    #     ...
    #   end
    #
    #   on_exception :some_exception_handler
    #
    def self.on_exception(proc = nil, &block)
      add_hook :on_exception, proc, &block
    end


  end
end