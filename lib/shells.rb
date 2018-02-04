require 'shells/version'
require 'shells/errors'
require 'shells/shell_base'
require 'shells/ssh_shell'
require 'shells/serial_shell'
require 'shells/ssh_bash_shell'
require 'shells/serial_bash_shell'
require 'shells/ssh_pf_sense_shell'
require 'shells/serial_pf_sense_shell'


##
# A set of basic shell classes.
#
module Shells

  ##
  # Provides the ability for the Shells module to allow sessions to be instantiated without calling +new+.
  def self.method_missing(m, *args, &block)  #:nodoc:

    is_const =
        if m.to_s =~ /^[A-Z][a-zA-Z0-9_]*$/ # must start with uppercase and contain only letters, numbers, and underscores.
          begin
            const_defined?(m)
          rescue NameError  # if for some reason we still get a NameError, it's obviously not a constant.
            false
          end
        else
          false
        end

    if is_const
      val = const_get(m)
      if val.is_a?(Class) && Shells::ShellBase > val
        return val.new(*args, &block)
      end
    end

    super
  end

end
