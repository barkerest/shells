require 'rubyserial'
require 'shells/shell_base'

module Shells
  ##
  # Executes a serial session with a device.
  #
  # The default setup of this class should work well with any bash-like shell.
  # In particular, the +exec_prompt+ method sets the "PS1" environment variable, which should set the prompt the shell
  # uses, and the +get_exit_code+ methods retrieves the value of the "$?" variable which should contain the exit code
  # from the last action.  Because there is a possibility that your shell does not utilize those methods, the
  # +override_set_prompt+ and +override_get_exit_code+ options are available to change the behavior.
  #
  #
  # Valid options:
  # *   +path+
  #     The path to the serial device (e.g. - COM3 or /dev/tty2)
  #     This is a required option.
  # *   +speed+
  #     The bitrate for the connection.
  #     The default is 115200.
  # *   +data_bits+
  #     The number of data bits for the connection.
  #     The default is 8.
  # *   +parity+
  #     The parity for the connection.
  #     The default is :none.
  # *   +prompt+
  #     The prompt used to determine when processes finish execution.
  #     Defaults to '~~#', but if that doesn't work for some reason because it is valid output from one or more
  #     commands, you can change it to something else.  It must be unique and cannot contain certain characters.
  #     The characters you should avoid are !, $, \, /, ", and ' because no attempt is made to escape them and the
  #     resulting prompt can very easily become something else entirely.  If they are provided, they will be
  #     replaced to protect the shell from getting stuck.
  # *   +quit+
  #     If set, this defines the command to execute when quitting the session.
  #     The default is "exit" which will probably work most of the time.
  # *   +retrieve_exit_code+
  #     If set to a non-false value, then the default behavior will be to retrieve the exit code from the shell after
  #     executing a command.  If set to a false or nil value, the default behavior will be to ignore the exit code
  #     from the shell.  When retrieved, the exit code is stored in the +last_exit_code+ property.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # *   +on_non_zero_exit_code+
  #     If set to :ignore (the default) then non-zero exit codes will not cause errors.  You will still be able to check
  #     the +last_exit_code+ property to determine if the command was successful.
  #     If set to :raise then non-zero exit codes will cause a Shells::NonZeroExitCode to be raised when a command exits
  #     with a non-zero return value.
  #     This option only comes into play when +retrieve_exit_code+ is set to a non-false value.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # *   +silence_timeout+
  #     When a command is executing, this is the maximum amount of time to wait for any feedback from the shell.
  #     If set to 0 (or less) there is no timeout.
  #     Unlike +command_timeout+ this value resets every time we receive feedback.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # *   +command_timeout+
  #     When a command is executing, this is the maximum amount of time to wait for the command to finish.
  #     If set to 0 (or less) there is no timeout.
  #     Unlike +silence_timeout+ this value does not reset when we receive feedback.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # *   +override_set_prompt+
  #     If provided, this must be set to either a command string that will set the prompt, or a Proc that accepts
  #     the shell as an argument.
  #     If set to a string, the string is sent to the shell and we wait up to two seconds for the prompt to appear.
  #     If that fails, we resend the string and wait one more time before failing.
  #     If set to a Proc, the Proc is called.  If the Proc returns a false value, we fail.  If the Proc returns
  #     a non-false value, we consider it successful.
  # *   +override_get_exit_code+
  #     If provided, this must be set to either a command string that will retrieve the exit code, or a Proc that
  #     accepts the shell as an argument.
  #     If set to a string, the string is sent to the shell and the output is parsed as an integer and used as the exit
  #     code.
  #     If set to a Proc, the Proc is called and the return value of the proc is used as the exit code.
  #
  #   Shells::SerialSession.new(
  #       path: '/dev/ttyusb3',
  #       speed: 9600
  #   ) do |shell|
  #     shell.exec('cd /usr/local/bin')
  #     user_bin_files = shell.exec('ls -A1').split("\n")
  #     @app_is_installed = user_bin_files.include?('my_app')
  #   end
  #
  class SerialSession < Shells::ShellBase

    def line_ending # :nodoc:
      "\r\n"
    end

    protected

    def validate_options
      options[:speed] ||= 115200
      options[:data_bits] ||= 8
      options[:parity] ||= :none
      options[:quit] ||= 'exit'
      options[:connect_timeout] ||= 5

      raise InvalidOption, 'Missing path.' if options[:path].to_s.strip == ''
    end

    def exec_shell(&block)

      @serport = Serial.new options[:path], options[:speed], options[:data_bits], options[:parity]

      begin
        # start buffering
        buffer_input

        # yield to the block
        block.call

      ensure
        # send the quit message.
        send_data options[:quit] + line_ending

        @serport.close
        @serport = nil
      end
    end

    def exec_prompt(&block)
      cmd = options[:override_set_prompt] || "PS1=\"#{options[:prompt]}\""
      if cmd.respond_to?(:call)
        raise Shells::FailedToSetPrompt unless cmd.call(self)
      else
        # set the prompt, wait up to 2 seconds for a response, then try one more time.
        begin
          exec cmd, command_timeout: 2, retrieve_exit_code: false
        rescue Shells::CommandTimeout
          begin
            exec cmd, command_timeout: 2, retrieve_exit_code: false
          rescue Shells::CommandTimeout
            raise Shells::FailedToSetPrompt
          end
        end
      end

      # yield to the block
      block.call
    end

    def send_data(data)
      @serport.write data
      puts "I send #{data.inspect} to the serial device."
    end

    def loop(&block)
      while true
        while true
          data = @serport.read(256).to_s
          break if data == ""
          puts "I read #{data.inspect} from the serial device."
          @_stdout_recv.call data
        end
        break unless block&.call
      end
    end

    def stdout_received(&block)
      @_stdout_recv = block
    end

    def stderr_received(&block)
      @_stderr_recv = block
    end

    def get_exit_code
      cmd = options[:override_get_exit_code] || 'echo $?'
      if cmd.respond_to?(:call)
        cmd.call(self)
      else
        push_buffer
        send_data cmd + line_ending
        wait_for_prompt nil, 1
        ret = command_output(cmd).strip.to_i
        pop_discard_buffer
        ret
      end
    end

  end
end