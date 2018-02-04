require 'rubyserial'
require 'shells/shell_base'

module Shells
  ##
  # Executes a serial session with a device.
  #
  # The default setup of this class should work well with any bash-like shell.
  # In particular, the +exec_prompt+ method sets the "PS1" environment variable, which should set the prompt the shell
  # uses, and the +get_exit_code+ methods retrieves the value of the "$?" variable which should contain the exit code
  # from the last action.  Because there is a possibility that your shell does not utilize those methods, the
  # +override_set_prompt+ and +override_get_exit_code+ options are available to change the behavior.
  #
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
  #   Shells::SerialShell.new(
  #       path: '/dev/ttyusb3',
  #       speed: 9600
  #   ) do |shell|
  #     shell.exec('cd /usr/local/bin')
  #     user_bin_files = shell.exec('ls -A1').split("\n")
  #     @app_is_installed = user_bin_files.include?('my_app')
  #   end
  #
  class SerialShell < Shells::ShellBase

    attr_accessor :serport
    private :serport, :serport=

    attr_accessor :ser_stdout_recv
    private :ser_stdout_recv, :ser_stdout_recv=

    attr_accessor :output_reader
    private :output_reader, :output_reader=

    add_hook :on_before_run do |sh|
      sh.instance_eval do
        self.serport = nil
        self.output_reader = nil
      end
    end

    add_hook :on_after_run do |sh|
      sh.instance_eval do
        self.serport = nil
        self.output_reader = nil
      end
    end

    ##
    # Sets the line ending for the instance.
    def line_ending=(value)
      @line_ending = value || "\r\n"
    end

    ##
    # Gets the line ending for the instance.
    def line_ending
      @line_ending ||= "\r\n"
    end

    protected

    def validate_options #:nodoc:
      options[:speed] ||= 115200
      options[:data_bits] ||= 8
      options[:parity] ||= :none
      options[:quit] ||= 'exit'
      options[:connect_timeout] ||= 5

      raise InvalidOption, 'Missing path.' if options[:path].to_s.strip == ''
    end

    def connect #:nodoc:
      debug 'Opening serial port...'
      self.serport = Serial.new(options[:path], options[:speed], options[:data_bits], options[:parity])
      debug 'Starting output reading thread...'
      self.output_reader = Thread.start(self) do |shell|
        while true
          shell.instance_eval do
            data = ''
            while (byte = serport&.getbyte)
              data << byte.chr
            end
            if data != ''
              # add to the output buffer.
              debug "Received: (#{data.size} bytes) #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
              ser_stdout_recv&.call data
            end
          end
          Thread.pass
        end
      end

    end

    def disconnect #:nodoc:
      output_reader&.exit
      serport.close
    end

    def setup
      # send a newline to the shell to (hopefully) redraw a menu.
      debug 'Refreshing...'
      queue_input line_ending

      debug 'Calling setup_prompt...'
      setup_prompt
      debug ' > prompt setup'
    end

    def send_data(data) #:nodoc:
      serport.write data
      debug "Sent: (#{data.size} bytes) #{(data.size > 32 ? (data[0..30] + '...') : data).inspect}"
    end

    def active?
      return false if serport.nil?
      return false if serport.closed?
      true
    end

    def io_loop(&block) #:nodoc:
      while true
        break unless block.call
        Thread.pass
      end
    end

    def stdout_received(&block) #:nodoc:
      sync { self.ser_stdout_recv = block }
    end

    def stderr_received(&block) #:nodoc:
      nil # no stderr to report.
    end

  end
end