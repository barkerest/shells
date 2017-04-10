module Shells
  ##
  # An error occurring within the SecureShell class aside from argument errors.
  class ShellError < StandardError

  end

  ##
  # An error raised when a provided option is invalid.
  class InvalidOption < ShellError

  end

  ##
  # An error raised when a command requiring a session is attempted after the session has been completed.
  class SessionCompleted < ShellError

  end

  ##
  # An error raised when a command exits with a non-zero status.
  class NonZeroExitCode < ShellError
    ##
    # The exit code triggering the error.
    attr_accessor :exit_code

    ##
    # Creates a new non-zero exit code error.
    def initialize(exit_code)
      self.exit_code = exit_code
    end

    def message # :nodoc:
      "The exit code was #{exit_code}."
    end
  end

  ##
  # An error raised when a session is waiting for output for too long.
  class SilenceTimeout < ShellError

  end

  ##
  # An error raise when a session is waiting for a command to finish for too long.
  class CommandTimeout < ShellError

  end

  ##
  # An error raised when the session fails to set the prompt in the shell.
  class FailedToSetPrompt < ShellError

  end


end