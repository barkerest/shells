require 'net/ssh'
require 'shells/shell_base'

module Shells
  ##
  # Executes an SSH session with a host.
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
  #     If our public key is an authorized key on the host, the password is ignored for connection.
  #     The #sudo_exec method for bash-like shells will also use this password for elevation.
  # +prompt+::
  #     The prompt used to determine when processes finish execution.
  # +shell+::
  #     If set to :shell, then the default shell is executed.  This is the default value.
  #     If set to :none, then no shell is executed, but a PTY is still created.
  #     If set to :no_pty, then no shell is executed and no PTY is created.
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
  #
  #   Shells::SshShell.new(
  #       host: '10.10.10.10',
  #       user: 'somebody',
  #       password: 'super-secret'
  #   ) do |shell|
  #     shell.exec('cd /usr/local/bin')
  #     user_bin_files = shell.exec('ls -A1').split("\n")
  #     @app_is_installed = user_bin_files.include?('my_app')
  #   end
  #
  class SshShell < Shells::ShellBase

    ##
    # The error raised when we failed to request a PTY.
    class FailedToRequestPty < Shells::ShellError

    end

    ##
    # The error raised when we fail to start the shell on the PTY.
    class FailedToStartShell < Shells::ShellError

    end

    attr_accessor :ssh, :channel
    private :ssh, :ssh=, :channel, :channel=

    add_hook :on_before_run do |sh|
      sh.instance_eval do
        self.ssh = nil
        self.channel = nil
      end
    end

    add_hook :on_after_run do |sh|
      sh.instance_eval do
        self.ssh = nil
        self.channel = nil
      end
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


    def connect #:nodoc:

      debug 'Connecting to SSH host...'
      self.ssh = Net::SSH.start(
          options[:host],
          options[:user],
          password: options[:password],
          port: options[:port],
          non_interactive: true,
          timeout: options[:connect_timeout]
      )
      debug ' > connected'

      opened = false

      debug 'Opening channel...'
      self.channel = ssh.open_channel do |ch|
        opened = true
      end

      io_loop { !opened }
      debug ' > opened'

    end

    def setup #:nodoc:
      done = false
      unless options[:shell] == :no_pty
        debug 'Acquiring PTY...'
        channel.request_pty do |_, success|
          raise FailedToRequestPty unless success
          debug ' > acquired'
          done = true
        end
      end

      until done
        sleep 0.0001
      end

      done = false
      unless [:no_pty,:none].include?(options[:shell])
        debug 'Starting shell...'
        # pick a method to start the shell with.
        meth = (options[:shell] == :shell) ? :send_channel_request : :exec
        channel.send(meth, options[:shell].to_s) do |_, success|
          raise FailedToStartShell unless success
          debug ' > started'
          done = true
        end
      end

      until done
        sleep 0.0001
      end

      debug 'Calling setup_prompt...'
      setup_prompt
      debug ' > setup'
    end

    def disconnect #:nodoc:
      debug 'Marking channel for closure...'
      channel.close
      debug ' > marked'
      debug 'Closing SSH connection...'
      ssh.close
      debug ' > closed'
    end

    def send_data(data) #:nodoc:
      channel.send_data data
      debug "Sent: (#{data.size} bytes) #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
    end

    def stdout_received(&block) #:nodoc:
      channel.on_data do |_,data|
        debug "Received: (#{data.size} bytes) #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
        block.call data
      end
    end

    def stderr_received(&block) #:nodoc:
      channel.on_extended_data do |_, type, data|
        if type == 1
          debug "Received: (#{data.size} bytes) [E] #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
          block.call data
        else
          debug "Received: (#{data.size} bytes) [#{type}] #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
        end
      end
    end

    def active?
      channel&.active?
    end

    def io_loop(&block)
      shell = self
      ssh&.loop(0.000001) do |_|
        shell.instance_eval &block
      end
    end


  end
end