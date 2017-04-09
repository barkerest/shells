require 'shells/version'
require 'shells/errors'
require 'shells/shell_base'
require 'shells/ssh_session'
require 'shells/serial_session'
require 'shells/pf_sense_ssh_session'
require 'shells/pf_sense_serial_session'


##
# A set of basic shell classes.
#
# All shell sessions can be accessed by class name without calling +new+.
#   Shells::SshSession(host: ...)
#   Shells::SerialSession(path: ...)
#   Shells::PfSenseSshSession(host: ...)
#   Shells::PfSenseSerialSession(path: ...)
#
module Shells

  def self.method_missing(m, *args, &block)  # :nodoc:

    is_const = const_defined?(m) rescue nil

    if is_const
      val = const_get(m)
      if val.is_a?(Class) && Shells::ShellBase > val
        return val.new(*args, &block)
      end
    end

    super
  end

end
