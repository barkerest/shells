module Shells

  ##
  # Provides a base interface for all shells to build on.
  #
  # Instantiating this class will raise an error.
  class ShellBase

    ##
    # Raise a QuitNow to tell the shell to stop processing and exit.
    QuitNow = Class.new(Exception)

    ##
    # The options provided to this shell.
    attr_reader :options

    ##
    # Gets the exit code from the last command if it was retrieved.
    attr_accessor :last_exit_code

    ##
    # Initializes the shell with the supplied options.
    #
    # These options are common to all shells.
    #   :prompt
    #       Defaults to "~~#".  Most special characters will be stripped.
    #   :retrieve_exit_code
    #       Defaults to false. Can also be true.
    #   :on_non_zero_exit_code
    #       Defaults to :ignore. Can also be :raise.
    #   :silence_timeout
    #       Defaults to 0.
    #       If greater than zero, will raise an error after waiting this many seconds for a prompt.
    #   :command_timeout
    #       Defaults to 0.
    #       If greater than zero, will raise an error after a command runs for this long without finishing.
    #
    # Please check the documentation for specific shell options.
    #
    # Once the shell is initialized, the shell is yielded to the provided code block.
    def initialize(options = {}, &block)

      # cannot instantiate a ShellBase
      raise NotImplementedError if self.class == Shells::ShellBase

      raise ArgumentError, 'A code block is required.' unless block_given?
      raise ArgumentError, '\'options\' must be a hash.' unless options.is_a?(Hash)

      @options = {
          prompt: '~~#',
          retrieve_exit_code: false,
          on_non_zero_exit_code: :ignore,
          silence_timeout: 0,
          command_timeout: 0
      }.merge( options.inject({}){ |m,(k,v)|  m[k.to_sym] = v; m } )

      @options[:prompt] = @options[:prompt]
                              .to_s.strip
                              .gsub('!', '#')
                              .gsub('$', '#')
                              .gsub('\\', '.')
                              .gsub('/', '.')
                              .gsub('"', '-')
                              .gsub('\'', '-')

      @options[:prompt] = '~~#' if @options[:prompt] == ''

      raise Shells::InvalidOption, ':on_non_zero_exit_code must be :ignore, :raise, or nil.' unless [:ignore, :raise].include?(@options[:on_non_zero_exit_code])

      validate_options
      @options.freeze   # no more changes to options now.

      @session_complete = false
      @last_input = Time.now

      exec_shell do
        begin
          run_hook :before_init
          exec_prompt do
            block.call self
          end
          run_hook :before_term
        rescue QuitNow
          nil
        rescue Exception => ex
          unless run_hook(:on_exception, ex)
            raise
          end
        end
      end

      @session_complete = true
    end

    ##
    # Adds code to be run before the shell is fully initialized.
    #
    # This code would normally be used to navigate a menu or setup an environment.
    # This method allows you to define that behavior without rewriting the connection code.
    def self.before_init(proc = nil, &block)
      add_hook :before_init, proc, block
    end

    ##
    # Adds code to be run before the shell is terminated.
    #
    # This code might also be used to navigate a menu or clean up an environment.
    # This method allows you to define that behavior without rewriting the connection code.
    def self.before_term(proc = nil, &block)
      add_hook :before_term, proc, block
    end

    ##
    # Adds code to be run when an exception occurs.
    #
    # This code will receive the shell as the first argument and the exception as the second.
    # If it handles the exception it should return true, otherwise nil or false.
    def self.on_exception(proc = nil, &block)
      add_hook :on_exception, proc, block
    end

    ##
    # Defines the line ending used to terminate commands sent to the shell.
    def line_ending
      "\n"
    end

    ##
    # Has the session been completed?
    def session_complete?
      @session_complete
    end

    ##
    # Gets the standard output from the session.
    #
    # The prompts are stripped from the standard ouput as they are encountered.
    # So this will be a list of commands with their output.
    #
    # All line endings are converted to LF characters, so you will not
    # encounter or need to search for CRLF or CR sequences.
    #
    def stdout
      @stdout || ''
    end

    ##
    # Gets the error output from the session.
    #
    # All line endings are converted to LF characters, so you will not
    # encounter or need to search for CRLF or CR sequences.
    #
    def stderr
      @stderr || ''
    end

    ##
    # Gets both the standard output and error output from the session.
    #
    # The prompts will be included in the combined output.
    # There is no attempt to differentiate error output from standard output.
    #
    # This is essentially the definitive log for the session.
    #
    # All line endings are converted to LF characters, so you will not
    # encounter or need to search for CRLF or CR sequences.
    #
    def combined_output
      @stdcomb || ''
    end

    ##
    # Executes a command during the shell session.
    #
    # If called outside of the +new+ block, this will raise an error.
    #
    # The +command+ is the command to execute in the shell.
    #
    # The +options+ can be used to override the exit code behavior.
    #     :retrieve_exit_code    = :default or true or false
    #     :on_non_zero_exit_code = :default or :ignore or :raise
    #     :silence_timeout       = :default or seconds to wait in silence
    #     :command_timeout       = :default or max seconds to wait for command to finish
    #
    # If provided, the +block+ is a chunk of code that will be processed every time the
    # shell receives output from the program.  If the block returns a string, the string
    # will be sent to the shell.  This can be used to monitor processes or monitor and
    # interact with processes.  The +block+ is optional.
    #
    #   shell.exec('sudo -p "password:" nginx restart') do |data,type|
    #     return 'super-secret' if /password:$/.match(data)
    #     nil
    #   end
    #
    def exec(command, options = {}, &block)
      raise Shells::SessionCompleted if session_complete?

      options ||= {}
      options = self.options.merge(options.inject({}) { |m,(k,v)| m[k.to_sym] = v; m })
      options[:retrieve_exit_code] = self.options[:retrieve_exit_code] if options[:retrieve_exit_code] == :default
      options[:on_non_zero_exit_code] = self.options[:on_non_zero_exit_code] unless options[:on_non_zero_exit_code] == :default
      options[:silence_timeout] = self.options[:silence_timeout] if options[:silence_timeout] == :default
      options[:command_timeout] = self.options[:command_timeout] if options[:command_timeout] == :default

      push_buffer # store the current buffer and start a fresh buffer

      # buffer while also passing data to the supplied block.
      if block_given?
        buffer_input(&block)
      end

      # send the command and wait for the prompt to return.
      send_data command + line_ending
      wait_for_prompt options[:silence_timeout], options[:command_timeout]

      # return buffering to normal.
      if block_given?
        buffer_input
      end

      # get the output of the command, minus the trailing prompt.
      ret = command_output command

      # restore the original buffer and merge the output from the command.
      pop_merge_buffer

      if options[:retrieve_exit_code]
        self.last_exit_code = get_exit_code
        if options[:on_non_zero_exit_code] == :raise
          raise NonZeroExitCode.new(last_exit_code) unless last_exit_code == 0
        end
      else
        self.last_exit_code = nil
      end

      ret
    end


    protected




    ##
    # Validates the options provided to the class.
    #
    # You should define this method in your subclass.
    def validate_options
      warn "The validate_options() method is not defined on the #{self.class} class."
    end

    ##
    # Executes a shell session.
    #
    # This method should connect to the shell and then yield.
    # It should not initialize the prompt.
    # When the yielded block returns this method should then disconnect from the shell.
    #
    # You must define this method in your subclass.
    def exec_shell(&block)
      raise ::NotImplementedError
    end

    ##
    # Runs all prompted commands.
    #
    # This method should initialize the shell prompt and then yield.
    #
    # You must define this method in your subclass.
    def exec_prompt(&block)
      raise ::NotImplementedError
    end

    ##
    # Sends data to the shell.
    #
    # You must define this method in your subclass.
    def send_data(data)
      raise ::NotImplementedError
    end

    ##
    # Loops while the block returns any true value.
    #
    # You must define this method in your subclass.
    def loop(&block)
      raise ::NotImplementedError
    end

    ##
    # Register a callback to run when stdout data is received.
    #
    # The block will be passed the data received.
    #
    # You must define this method in your subclass.
    def stdout_received(&block)
      raise ::NotImplementedError
    end

    ##
    # Register a callback to run when stderr data is received.
    #
    # The block will be passed the data received.
    #
    # You must define this method in your subclass.
    def stderr_received(&block)
      raise ::NotImplementedError
    end

    ##
    # Gets the exit code from the last command.
    #
    # You must define this method in your subclass to utilize exit codes.
    def get_exit_code
      raise ::NotImplementedError
    end





    ##
    # Waits for the prompt to appear at the end of the output.
    #
    # Once the prompt appears, new input can be sent to the shell.
    # This is automatically called in +exec+ so you would only need
    # to call it directly if you were sending data manually to the
    # shell.
    def wait_for_prompt(silence_timeout = nil, command_timeout = nil)
      raise Shells::SessionCompleted if session_complete?

      silence_timeout ||= options[:silence_timeout]
      command_timeout ||= options[:command_timeout]

      sent_nl_at = nil
      sent_nl_times = 0
      silence_timeout = silence_timeout.to_s.to_f unless silence_timeout.is_a?(Numeric)
      nudge_timeout =
          if silence_timeout > 0
            (silence_timeout / 3)  # we want to nudge twice before officially timing out.
          else
            0
          end

      command_timeout = command_timeout.to_s.to_f unless command_timeout.is_a?(Numeric)
      timeout =
          if command_timeout > 0
            Time.now + command_timeout
          else
            nil
          end

      loop do
        last_input = @last_input

        # Do we need to nudge the shell?
        if nudge_timeout > 0 && (Time.now - last_input) > nudge_timeout

          # Have we previously nudged the shell?
          if sent_nl_times > 2
            raise Shells::SilenceTimeout
          else
            sent_nl_times = (sent_nl_at.nil? || sent_nl_at < last_input) ? 1 : (sent_nl_times + 1)
            sent_nl_at = Time.now

            send_data line_ending

            # wait a bit longer...
            @last_input = sent_nl_at
          end
        end

        if timeout && Time.now > timeout
          raise Shells::CommandTimeout
        end

        !(combined_output =~ prompt_match)
      end

      pos = combined_output =~ prompt_match
      if combined_output[pos - 1] != "\n"
        # no newline before prompt, fix that.
        self.combined_output = combined_output[0...pos] + "\n" + combined_output[pos..-1]
      end
      if stdout[-1] != "\n"
        # no newline at end, fix that.
        self.stdout <<= "\n"
      end

    end

    ##
    # Sets the block to call when data is received.
    #
    # If no block is provided, then the shell will simply log all output from the program.
    # If a block is provided, it will be passed the data as it is received.  If the block
    # returns a string, then that string will be sent to the shell.
    def buffer_input(&block)
      raise Shells::SessionCompleted if session_complete?
      block ||= Proc.new { }
      stdout_received do |data|
        @last_input = Time.now
        append_stdout strip_ansi_escape(data), &block
      end
      stderr_received do |data|
        @last_input = Time.now
        append_stderr strip_ansi_escap(data), &block
      end
    end

    ##
    # Pushes the buffers for output capture.
    def push_buffer
      # push the buffer so we can get the output of a command.
      stdout_hist.push stdout
      stderr_hist.push stderr
      stdcomb_hist.push combined_output
      self.stdout = ''
      self.stderr = ''
      self.combined_output = ''
    end

    ##
    # Pops the buffers and merges the captured output.
    def pop_merge_buffer
      # almost a standard pop, however we want to merge history with current.
      if (hist = stdout_hist.pop)
        self.stdout = hist + stdout
      end
      if (hist = stderr_hist.pop)
        self.stderr = hist + stderr
      end
      if (hist = stdcomb_hist.pop)
        self.combined_output = hist + combined_output
      end
    end

    ##
    # Pops the buffers and discards the captured output.
    def pop_discard_buffer
      # a standard pop discarding current data and retrieving the history.
      if (hist = stdout_hist.pop)
        @stdout = hist
      end
      if (hist = stderr_hist.pop)
        @stderr = hist
      end
      if (hist = stdcomb_hist.pop)
        @stdcomb = hist
      end
    end


    private


    def self.add_hook(hook_name, proc, block)
      hooks[hook_name] ||= []
      if proc.respond_to?(:call)
        hooks[hook_name] << proc
      elsif proc.is_a?(Symbol) || proc.is_a?(String)
        if self.respond_to?(proc)
          hooks[hook_name] << method(proc.to_sym)
        end
      end
      if block.respond_to?(:call)
        hooks[hook_name] << block
      end
    end

    def run_hook(hook_name, *args)
      (self.class.hooks[hook_name] || []).each do |hook|
        result = hook.call(self, *args)
        return true if result.is_a?(TrueClass)
      end
      false
    end

    def self.hooks
      @hooks ||= {}
    end


    def stdout=(value)
      @stdout = value
    end

    def stderr=(value)
      @stderr = value
    end

    def combined_output=(value)
      @stdcomb = value
    end

    def append_stdout(data, &block)
      # Combined output gets the prompts,
      # but stdout will be without prompts.
      data = reduce_newlines data
      for_stdout = if (pos = (data =~ prompt_match))
                     data[0...pos]
                   else
                     data
                   end

      self.stdout <<= for_stdout
      self.combined_output <<= data

      if block_given?
        result = block.call(for_stdout, :stdout)
        if result && result.is_a?(String)
          send_data(result + line_ending)
        end
      end
    end

    def append_stderr(data, &block)
      data = reduce_newlines data

      self.stderr <<= data
      self.combined_output <<= data

      if block_given?
        result = block.call(data, :stderr)
        if result && result.is_a?(String)
          send_data(result + line_ending)
        end
      end
    end

    def reduce_newlines(data)
      data.gsub("\r\n", "\n").gsub(" \r", "").gsub("\r", "")
    end

    def command_output(command)
      # get everything except for the ending prompt.
      ret =
          if (prompt_pos = combined_output =~ prompt_match)
            combined_output[0...prompt_pos]
          else
            combined_output
          end

      possible_starts = [
          command,
          options[:prompt] + command,
          options[:prompt] + ' ' + command
      ]

      # Go until we run out of data or we find one of the possible command starts.
      # Note that we EXPECT the command to the first line of the output from the command because we expect the
      # shell to echo it back to us.
      result_cmd,_,result_data = ret.partition("\n")
      until result_data.to_s.strip == '' || possible_starts.include?(result_cmd)
        result_cmd,_,result_data = result_data.partition("\n")
      end

      result_data
    end

    def strip_ansi_escape(data)
      data
          .gsub(/\e\[(\d+;?)*[ABCDEFGHfu]/, "\n")   #   any of the "set cursor position" CSI commands.
          .gsub(/\e\[=?(\d+;?)*[A-Za-z]/,'')        #   \e[#;#;#A or \e[=#;#;#A  basically all the CSI commands except ...
          .gsub(/\e\[(\d+;"[^"]+";?)+p/, '')        #   \e[#;"A"p
          .gsub(/\e[NOc]./,'?')                     #   any of the alternate character set commands.
          .gsub(/\e[P_\]^X][^\e\a]*(\a|(\e\\))/,'') #   any string command
          .gsub(/[\x00\x08\x0B\x0C\x0E-\x1F]/, '')  #   any non-printable characters (notice \x0A (LF) and \x0D (CR) are left as is).
          .gsub("\t", ' ')                          #   turn tabs into spaces.
    end

    def stdout_hist
      @stdout_hist ||= []
    end

    def stderr_hist
      @stderr_hist ||= []
    end

    def stdcomb_hist
      @stdcomb_hist ||= []
    end

    def prompt_match
      # allow for trailing spaces or tabs, but no other whitespace.
      @prompt_match ||= /#{@options[:prompt]}[ \t]*$/
    end

  end

end