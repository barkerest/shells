require 'shells/serial_bash_shell'
require 'shells/pf_sense_common'

module Shells

  ##
  # Executes a serial session with a pfSense host.
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
  #   Shells::SerialPfSenseShell.new(
  #       path: 'COM3'
  #   ) do |shell|
  #     shell.pf_shell do |shell|
  #       cfg = shell.get_config_section("aliases")
  #       cfg["alias"] ||= []
  #       cfg["alias"] << {
  #           :name => "MY_NETWORK",
  #           :type => "network",
  #           :address => "192.168.1.0/24",
  #           :descr => "My home network",
  #           :details => "Created #{Time.now.to_s}"
  #       }
  #       shell.set_config_section("aliases", cfg, "Add home network")
  #       shell.apply_filter_config
  #     end
  #   end
  #
  class SerialPfSenseShell < SerialShell

    include PfSenseCommon

  end

end
