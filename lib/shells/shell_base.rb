require 'shells/errors'
require 'thread'

module Shells

  ##
  # Provides a base interface for all shells to build on.
  #
  # Instantiating this class will raise an error.
  # All shell sessions should inherit this class and override the necessary interface methods.
  class ShellBase

    def inspect
      "#<#{self.class}:0x#{object_id.to_s(16).rjust(12,'0')} #{options.reject{|k,v| k == :password}.inspect}>"
    end

  end
end


require 'shells/shell_base/hooks'

require 'shells/shell_base/sync'
require 'shells/shell_base/debug'
require 'shells/shell_base/options'
require 'shells/shell_base/interface'     # methods to override in derived classes.
require 'shells/shell_base/input'
require 'shells/shell_base/output'
require 'shells/shell_base/regex_escape'
require 'shells/shell_base/prompt'
require 'shells/shell_base/exec'
require 'shells/shell_base/run'

