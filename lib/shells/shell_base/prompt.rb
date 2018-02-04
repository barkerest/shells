module Shells
  class ShellBase

    private

    def prompt_match
      @prompt_match
    end

    def prompt_match=(value)
      # allow for trailing spaces or tabs, but no other whitespace.
      @prompt_match =
          if value.nil?
            nil
          elsif value.is_a?(::Regexp)
            value
          else
            /#{regex_escape value.to_s}[ \t]*$/
          end
    end

    add_hook :on_before_run do |sh|
      sh.instance_eval do
        self.prompt_match = options[:prompt]
      end
    end

    add_hook :on_after_run do |sh|
      sh.instance_eval do
        self.prompt_match = nil
      end
    end

    protected

    ##
    # Waits for the prompt to appear at the end of the output.
    #
    # Once the prompt appears, new input can be sent to the shell.
    # This is automatically called in +exec+ so you would only need
    # to call it directly if you were sending data manually to the
    # shell.
    #
    # This method is used internally in the +exec+ method, but there may be legitimate use cases
    # outside of that method as well.
    def wait_for_prompt(silence_timeout = nil, command_timeout = nil, timeout_error = true) #:doc:
      raise Shells::NotRunning unless running?

      silence_timeout ||= options[:silence_timeout]
      command_timeout ||= options[:command_timeout]

      # when did we send a NL and how many have we sent while waiting for output?
      nudged_at = nil
      nudge_count = 0

      silence_timeout = silence_timeout.to_s.to_f unless silence_timeout.is_a?(Numeric)
      nudge_seconds =
          if silence_timeout > 0
            (silence_timeout / 3.0)  # we want to nudge twice before officially timing out.
          else
            0
          end

      # if there is a limit for the command timeout, then set the absolute timeout for the loop.
      command_timeout = command_timeout.to_s.to_f unless command_timeout.is_a?(Numeric)
      timeout =
          if command_timeout > 0
            Time.now + command_timeout
          else
            nil
          end

      # loop until the output matches the prompt regex.
      # if something gets output async server side, the silence timeout will be handy in getting the shell to reappear.
      until output =~ prompt_match
        # hint that we need to let another thread run.
        Thread.pass

        last_response = last_output

        # Do we need to nudge the shell?
        if nudge_seconds > 0 && (Time.now - last_response) > nudge_seconds
          nudge_count = (nudged_at.nil? || nudged_at < last_response) ? 1 : (nudge_count + 1)

          # Have we previously nudged the shell?
          if nudge_count > 2  # we timeout on the third nudge.
            raise Shells::SilenceTimeout if timeout_error
            debug ' > silence timeout'
            return false
          else
            nudged_at = Time.now

            queue_input line_ending

            # wait a bit longer...
            self.last_output = nudged_at
          end
        end

        # honor the absolute timeout.
        if timeout && Time.now > timeout
          raise Shells::CommandTimeout if timeout_error
          debug ' > command timeout'
          return false
        end
      end

      # make sure there is a newline before the prompt, just to keep everything clean.
      pos = (output =~ prompt_match)
      if output[pos - 1] != "\n"
        # no newline before prompt, fix that.
        self.output = output[0...pos] + "\n" + output[pos..-1]
      end

      # make sure there is a newline at the end of STDOUT content buffer.
      if stdout[-1] != "\n"
        # no newline at end, fix that.
        self.stdout += "\n"
      end

      true
    end

    ##
    # Sets the prompt to the value temporarily for execution of the code block.
    def temporary_prompt(prompt) #:doc:
      raise Shells::NotRunning unless running?
      old_prompt = prompt_match
      begin
        self.prompt_match = prompt
        yield if block_given?
      ensure
        self.prompt_match = old_prompt
      end
    end


  end
end