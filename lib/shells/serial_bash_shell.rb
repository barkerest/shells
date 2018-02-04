require 'shells/serial_shell'
require 'shells/bash_common'

module Shells
  ##
  # Executes a serial session with a device.
  #
  # The default setup of this class should work well with any bash-like shell.
  #
  # Valid options:
  # +path+::
  #     The path to the serial device (e.g. - COM3 or /dev/tty2)
  #     This is a required option.
  # +speed+::
  #     The bitrate for the connection.
  #     The default is 115200.
  # +data_bits+::
  #     The number of data bits for the connection.
  #     The default is 8.
  # +parity+::
  #     The parity for the connection.
  #     The default is :none.
  # +prompt+::
  #     The prompt used to determine when processes finish execution.
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
  #
  #   Shells::SerialBashShell.new(
  #       path: '/dev/ttyusb3',
  #       speed: 9600
  #   ) do |shell|
  #     shell.exec('cd /usr/local/bin')
  #     user_bin_files = shell.exec('ls -A1').split("\n")
  #     @app_is_installed = user_bin_files.include?('my_app')
  #   end
  #
  class SerialBashShell < SerialShell

    include Shells::BashCommon

  end
end