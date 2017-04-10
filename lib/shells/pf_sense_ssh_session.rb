require 'shells/ssh_session'
require 'shells/pf_sense_common'

module Shells

  ##
  # Executes an SSH session with a pfSense host.
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
  #   Shells::PfSenseSshSession.new(
  #       host: '10.10.10.10',
  #       user: 'somebody',
  #       password: 'super-secret'
  #   ) do |shell|
  #     cfg = shell.get_config_section("aliases")
  #     cfg["alias"] ||= []
  #     cfg["alias"] << {
  #         :name => "MY_NETWORK",
  #         :type => "network",
  #         :address => "192.168.1.0/24",
  #         :descr => "My home network",
  #         :details => "Created #{Time.now.to_s}"
  #     }
  #     shell.set_config_section("aliases", cfg, "Add home network")
  #     shell.apply_filter_config
  #   end
  #
  class PfSenseSshSession < SshSession

    include PfSenseCommon

  end

end