require 'net/ssh'

module Shells
  ##
  # Executes an SSH session with a host.
  #
  # Valid options:
  # *   +host+
  #     The name or IP address of the host to connect to.  Defaults to 'localhost'.
  # *   +port+
  #     The port on the host to connect to.  Defaults to 22.
  # *   +user+
  #     The user to login with.
  # *   +password+
  #     The password to login with.
  # *   +prompt+
  #     The prompt used to determine when processes finish execution.
  #     Defaults to '~~#', but if that doesn't work for some reason because it is valid output from one or more
  #     commands, you can change it to something else.  It must be unique and cannot contain certain characters.
  #     The characters you should avoid are !, $, \, /, ", and ' because no attempt is made to escape them and the
  #     resulting prompt can very easily become something else entirely.  If they are provided, they will be
  #     replaced to protect the shell from getting stuck.
  # *   +shell+
  #     If set to :shell, then the default shell is executed.
  #     If set to anything else, it is assumed to be the executable path to the shell you want to run,
  #     for instance "/bin/sh".
  #
  #   SecureShell.new(
  #       host: '10.10.10.10',
  #       user: 'somebody',
  #       password: 'super-secret'
  #   ) do |shell|
  #     shell.exec('cd /usr/local/bin')
  #     user_bin_files = shell.exec('ls -A1').split('\n')
  #     @app_is_installed = user_bin_files.include?('my_app')
  #   end
  class SecureShell < Shells::ShellBase

    ##
    # The error raised when we failed to request a PTY.
    FailedToRequestPty = Class.new(Shells::ShellError)

    ##
    # The error raised when we fail to start the shell on the PTY.
    FailedToStartShell = Class.new(Shells::ShellError)


    protected

    def validate_options # :nodoc:
      options[:host] ||= 'localhost'
      options[:port] ||= 22
      options[:shell] ||= :shell
      options[:quit] ||= 'exit'
      options[:timeout] ||= 5

      raise InvalidOption, 'Missing host.' if options[:host].to_s.strip == ''
      raise InvalidOption, 'Missing user.' if options[:user].to_s.strip == ''
    end

    def exec_shell(&block)

      ignore_io_error = false
      begin

        Net::SSH.start(
            options[:host],
            options[:user],
            password: options[:password],
            port: options[:port],
            non_interactive: true,
            timeout: options[:timeout]
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

                # yield to the block
                block.call

                # send the exit command.
                ignore_io_error = true
                send_data options[:quit] + line_ending
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

    def exec_prompt(&block)
      # set the prompt, wait up to 2 seconds for a response, then try one more time.
      begin
        exec "PS1=\"#{options[:prompt]}\"", command_timeout: 2, retrieve_exit_code: false
      rescue Shells::CommandTimeout
        begin
          exec "PS1=\"#{options[:prompt]}\"", command_timeout: 2, retrieve_exit_code: false
        rescue Shells::CommandTimeout
          Shells::raise FailedToSetPrompt
        end
      end

      # yield to the block
      block.call
    end

    def send_data(data)
      @channel.send_data data
    end

    def loop(&block)
      @channel.connection.loop(&block)
    end

    def stdout_received(&block)
      @channel.on_data do |_,data|
        block.call data
      end
    end

    def stderr_received(&block)
      @channel.on_extended_data do |_, type, data|
        if type == 1
          block.call data
        end
      end
    end

    def get_exit_code
      cmd = 'echo $?'
      push_buffer
      send_data cmd + line_ending
      wait_for_prompt nil, 1
      ret = command_output(cmd).strip.to_i
      pop_discard_buffer
      ret
    end

  end
end