require 'net/ssh'
require 'shells/shell_base'

module Shells
  ##
  # Executes an SSH session with a host.
  #
  # The default setup of this class should work well with any bash-like shell.
  # In particular, the +exec_prompt+ method sets the "PS1" environment variable, which should set the prompt the shell
  # uses, and the +get_exit_code+ methods retrieves the value of the "$?" variable which should contain the exit code
  # from the last action.  Because there is a possibility that your shell does not utilize those methods, the
  # +override_set_prompt+ and +override_get_exit_code+ options are available to change the behavior.
  #
  #
  # Valid options:
  # +host+::
  #     The name or IP address of the host to connect to.  Defaults to 'localhost'.
  # +port+::
  #     The port on the host to connect to.  Defaults to 22.
  # +user+::
  #     The user to login with.  This option is required.
  # +password+::
  #     The password to login with.
  #     If our public key is an authorized key on the host, the password is ignored.
  # +prompt+::
  #     The prompt used to determine when processes finish execution.
  #     Defaults to '~~#', but if that doesn't work for some reason because it is valid output from one or more
  #     commands, you can change it to something else.  It must be unique and cannot contain certain characters.
  #     The characters you should avoid are !, $, \, /, ", and ' because no attempt is made to escape them and the
  #     resulting prompt can very easily become something else entirely.  If they are provided, they will be
  #     replaced to protect the shell from getting stuck.
  # +shell+::
  #     If set to :shell, then the default shell is executed.
  #     If set to anything else, it is assumed to be the executable path to the shell you want to run.
  # +quit+::
  #     If set, this defines the command to execute when quitting the session.
  #     The default is "exit" which will probably work most of the time.
  # +retrieve_exit_code+::
  #     If set to a non-false value, then the default behavior will be to retrieve the exit code from the shell after
  #     executing a command.  If set to a false or nil value, the default behavior will be to ignore the exit code
  #     from the shell.  When retrieved, the exit code is stored in the +last_exit_code+ property.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # +on_non_zero_exit_code+::
  #     If set to :ignore (the default) then non-zero exit codes will not cause errors.  You will still be able to check
  #     the +last_exit_code+ property to determine if the command was successful.
  #     If set to :raise then non-zero exit codes will cause a Shells::NonZeroExitCode to be raised when a command exits
  #     with a non-zero return value.
  #     This option only comes into play when +retrieve_exit_code+ is set to a non-false value.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # +silence_timeout+::
  #     When a command is executing, this is the maximum amount of time to wait for any feedback from the shell.
  #     If set to 0 (or less) there is no timeout.
  #     Unlike +command_timeout+ this value resets every time we receive feedback.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # +command_timeout+::
  #     When a command is executing, this is the maximum amount of time to wait for the command to finish.
  #     If set to 0 (or less) there is no timeout.
  #     Unlike +silence_timeout+ this value does not reset when we receive feedback.
  #     This option can be overridden by providing an alternate value to the +exec+ method on a case-by-case basis.
  # +connect_timeout+::
  #     This is the maximum amount of time to wait for the initial connection to the SSH shell.
  # +override_set_prompt+::
  #     If provided, this must be set to either a command string that will set the prompt, or a Proc that accepts
  #     the shell as an argument.
  #     If set to a string, the string is sent to the shell and we wait up to two seconds for the prompt to appear.
  #     If that fails, we resend the string and wait one more time before failing.
  #     If set to a Proc, the Proc is called.  If the Proc returns a false value, we fail.  If the Proc returns
  #     a non-false value, we consider it successful.
  # +override_get_exit_code+::
  #     If provided, this must be set to either a command string that will retrieve the exit code, or a Proc that
  #     accepts the shell as an argument.
  #     If set to a string, the string is sent to the shell and the output is parsed as an integer and used as the exit
  #     code.
  #     If set to a Proc, the Proc is called and the return value of the proc is used as the exit code.
  #
  #   Shells::SshSession.new(
  #       host: '10.10.10.10',
  #       user: 'somebody',
  #       password: 'super-secret'
  #   ) do |shell|
  #     shell.exec('cd /usr/local/bin')
  #     user_bin_files = shell.exec('ls -A1').split("\n")
  #     @app_is_installed = user_bin_files.include?('my_app')
  #   end
  #
  class SshSession < Shells::ShellBase

    ##
    # The error raised when we failed to request a PTY.
    class FailedToRequestPty < Shells::ShellError

    end

    ##
    # The error raised when we fail to start the shell on the PTY.
    class FailedToStartShell < Shells::ShellError

    end


    protected

    def validate_options  #:nodoc:
      options[:host] ||= 'localhost'
      options[:port] ||= 22
      options[:shell] ||= :shell
      options[:quit] ||= 'exit'
      options[:connect_timeout] ||= 5

      raise InvalidOption, 'Missing host.' if options[:host].to_s.strip == ''
      raise InvalidOption, 'Missing user.' if options[:user].to_s.strip == ''
    end

    def exec_shell(&block)  #:nodoc:

      ignore_io_error = false
      begin

        Net::SSH.start(
            options[:host],
            options[:user],
            password: options[:password],
            port: options[:port],
            non_interactive: true,
            timeout: options[:connect_timeout]
        ) do |ssh|

          # open the channel
          ssh.open_channel do |ch|
            # request a PTY
            ch.request_pty do |ch_pty, success_pty|
              raise FailedToRequestPty unless success_pty

              # pick a method to start the shell with.
              meth = (options[:shell] == :shell) ? :send_channel_request : :exec

              # start the shell
              ch_pty.send(meth, options[:shell].to_s) do |ch_sh, success_sh|
                raise FailedToStartShell unless success_sh

                @channel = ch_sh

                buffer_input

                # give the shell a chance to get ready.
                sleep 0.25

                begin
                  # yield to the block
                  block.call

                ensure
                  # send the exit command.
                  ignore_io_error = true
                  send_data options[:quit] + line_ending
                end

                @channel.wait
              end

            end
          end

        end
      rescue IOError
        unless ignore_io_error
          raise
        end
      ensure
        @channel = nil
      end

    end

    def exec_prompt(&block) #:nodoc:
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

    def send_data(data) #:nodoc:
      @channel.send_data data
      debug "Sent: (#{data.size} bytes) #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
    end

    def loop(&block)  #:nodoc:
      @channel.connection.loop(&block)
    end

    def stdout_received(&block) #:nodoc:
      @channel.on_data do |_,data|
        debug "Received: (#{data.size} bytes) #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
        block.call data
      end
    end

    def stderr_received(&block) #:nodoc:
      @channel.on_extended_data do |_, type, data|
        if type == 1
          debug "Received: (#{data.size} bytes) [E] #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
          block.call data
        end
      end
    end

    def get_exit_code #:nodoc:
      cmd = options[:override_get_exit_code] || 'echo $?'
      if cmd.respond_to?(:call)
        cmd.call(self)
      else
        debug 'Retrieving exit code from last command...'
        push_buffer
        send_data cmd + line_ending
        wait_for_prompt nil, 1
        ret = command_output(cmd).strip.to_i
        pop_discard_buffer
        debug 'Exit code: ' + ret.to_s
        ret
      end
    end

  end
end