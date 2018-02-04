require 'shells/ssh_shell'
require 'shells/bash_common'

module Shells
  ##
  # Executes a Bash session with an SSH host.
  #
  # The default setup of this class should work well with any bash-like shell.
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
  #     Defaults to '~~#', but if that doesn't work for some reason because it is valid output from one or more
  #     commands, you can change it to something else.  It must be unique and cannot contain certain characters.
  #     The characters you should avoid are !, $, \, /, ", and ' because no attempt is made to escape them and the
  #     resulting prompt can very easily become something else entirely.  If they are provided, they will be
  #     replaced to protect the shell from getting stuck.
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
  #   Shells::SshBashShell.new(
  #       host: '10.10.10.10',
  #       user: 'somebody',
  #       password: 'super-secret'
  #   ) do |shell|
  #     shell.exec('cd /usr/local/bin')
  #     user_bin_files = shell.exec('ls -A1').split("\n")
  #     @app_is_installed = user_bin_files.include?('my_app')
  #   end
  #
  class SshBashShell < SshShell

    include BashCommon

  end
end