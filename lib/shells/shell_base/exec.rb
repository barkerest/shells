module Shells
  class ShellBase

    ##
    # Gets the exit code from the last command if it was retrieved.
    attr_accessor :last_exit_code
    private :last_exit_code=

    add_hook :on_before_run do |sh|
      sh.instance_eval do
        self.last_exit_code = nil
      end
    end

    add_hook :on_after_run do |sh|
      sh.instance_eval do
        self.last_exit_code = nil
      end
    end

    ##
    # Executes a command during the shell session.
    #
    # If called outside of the +new+ block, this will raise an error.
    #
    # The +command+ is the command to execute in the shell.
    #
    # The +options+ can be used to override the exit code behavior.
    # In all cases, the :default option is the same as not providing the option and will cause +exec+
    # to inherit the option from the shell's options.
    #
    # +retrieve_exit_code+::
    #       This can be one of :default, true, or false.
    # +on_non_zero_exit_code+::
    #       This can be on ot :default, :ignore, or :raise.
    # +silence_timeout+::
    #       This can be :default or the number of seconds to wait in silence before timing out.
    # +command_timeout+::
    #       This can be :default or the maximum number of seconds to wait for a command to finish before timing out.
    #
    # If provided, the +block+ is a chunk of code that will be processed every time the
    # shell receives output from the program.  If the block returns a string, the string
    # will be sent to the shell.  This can be used to monitor processes or monitor and
    # interact with processes.  The +block+ is optional.
    #
    #   shell.exec('sudo -p "password:" nginx restart') do |data,type|
    #     return 'super-secret' if /password:$/.match(data)
    #     nil
    #   end
    #
    def exec(command, options = {}, &block)
      raise Shells::NotRunning unless running?

      options ||= {}
      options = { timeout_error: true, get_output: true }.merge(options)
      options = self.options.merge(options.inject({}) { |m,(k,v)| m[k.to_sym] = v; m })
      options[:retrieve_exit_code] = self.options[:retrieve_exit_code] if options[:retrieve_exit_code] == :default
      options[:on_non_zero_exit_code] = self.options[:on_non_zero_exit_code] unless [:raise, :ignore].include?(options[:on_non_zero_exit_code])
      options[:silence_timeout] = self.options[:silence_timeout] if options[:silence_timeout] == :default
      options[:command_timeout] = self.options[:command_timeout] if options[:command_timeout] == :default
      options[:command_is_echoed] = true if options[:command_is_echoed].nil?
      ret = ''

      begin
        push_buffer # store the current buffer and start a fresh buffer

        # buffer while also passing data to the supplied block.
        if block_given?
          buffer_output(&block)
        end

        # send the command and wait for the prompt to return.
        debug 'Queueing command: ' + command
        queue_input command + line_ending
        if wait_for_prompt(options[:silence_timeout], options[:command_timeout], options[:timeout_error])
          # get the output of the command, minus the trailing prompt.
          ret =
              if options[:get_output]
                debug 'Reading output of command...'
                command_output command, options[:command_is_echoed]
              else
                ''
              end

          if options[:retrieve_exit_code]
            self.last_exit_code = get_exit_code
            if options[:on_non_zero_exit_code] == :raise
              raise NonZeroExitCode.new(last_exit_code) unless last_exit_code == 0 || last_exit_code == :undefined
            end
          else
            self.last_exit_code = nil
          end
        else
          # A timeout occurred and timeout_error was set to false.
          self.last_exit_code = :timeout
          ret = output
        end

      ensure
        # return buffering to normal.
        if block_given?
          buffer_output
        end

        # restore the original buffer and merge the output from the command.
        pop_merge_buffer
      end
      ret
    end

    ##
    # Executes a command specifically for the exit code.
    #
    # Does not return the output of the command, only the exit code.
    def exec_for_code(command, options = {}, &block)
      options = (options || {}).merge(retrieve_exit_code: true, on_non_zero_exit_code: :ignore)
      exec command, options, &block
      last_exit_code
    end

    ##
    # Executes a command ignoring any exit code.
    #
    # Returns the output of the command and does not even retrieve the exit code.
    def exec_ignore_code(command, options = {}, &block)
      options = (options || {}).merge(retrieve_exit_code: false, on_non_zero_exit_code: :ignore)
      exec command, options, &block
    end

    protected

    ##
    # Gets the output from a command.
    def command_output(command, expect_command = true)  #:doc:
      # get everything except for the ending prompt.
      ret =
          if (prompt_pos = (output =~ prompt_match))
            output[0...prompt_pos]
          else
            output
          end

      if expect_command
        command_regex = command_match(command)

        # Go until we run out of data or we find one of the possible command starts.
        # Note that we EXPECT the command to the first line of the output from the command because we expect the
        # shell to echo it back to us.
        result_cmd,_,result_data = ret.partition("\n")
        until result_data.to_s.strip == '' || result_cmd.strip =~ command_regex
          result_cmd,_,result_data = result_data.partition("\n")
        end

        if result_cmd.nil? || !(result_cmd =~ command_regex)
          STDERR.puts "SHELL WARNING: Failed to match #{command_regex.inspect}."
        end

        result_data
      else
        ret
      end
    end

    private

    def command_match(command)
      p = regex_escape options[:prompt]
      c = regex_escape command
      /\A(?:#{p}\s*)?#{c}[ \t]*\z/
    end


  end
end