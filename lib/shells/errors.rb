module Shells

  ##
  # Raise a QuitNow to tell the shell to stop processing and exit.
  #
  # This is intentionally NOT a RuntimeError since it should only be caught inside the session.
  class QuitNow < Exception

  end

  ##
  # An error occurring within the SecureShell class aside from argument errors.
  class ShellError < StandardError

  end

  ##
  # An error raised when a provided option is invalid.
  class InvalidOption < ShellError

  end

  ##
  # An error raised when +run+ is executed on a shell that is currently running.
  class AlreadyRunning < ShellError

  end

  ##
  # An error raised when a method requiring a running shell is called when the shell is not currently running.
  class NotRunning < ShellError

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
  # A timeout error raised by the shell.
  class ShellTimeout < ShellError

  end

  ##
  # An error raised when a session is waiting for output for too long.
  class SilenceTimeout < ShellTimeout

  end

  ##
  # An error raise when a session is waiting for a command to finish for too long.
  class CommandTimeout < ShellTimeout

  end

  ##
  # An error raised when the session fails to set the prompt in the shell.
  class FailedToSetPrompt < ShellError

  end


end