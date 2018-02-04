module Shells
  class ShellBase

    # used when the buffer is pushed/popped.
    attr_accessor :output_stack
    private :output_stack, :output_stack=

    ##
    # Gets the STDOUT contents from the session.
    attr_accessor :stdout
    private :stdout=

    ##
    # Gets the STDERR contents from the session.
    attr_accessor :stderr
    private :stderr=

    ##
    # Gets all of the output contents from the session.
    attr_accessor :output
    private :output=

    ##
    # Gets the last time output was received from the shell.
    attr_accessor :last_output
    protected :last_output
    private :last_output=

    ##
    # The character string we are expecting to be echoed back from the shell.
    attr_accessor :wait_for_output
    private :wait_for_output, :wait_for_output

    add_hook :on_before_run do |sh|
      sh.instance_eval do
        self.output_stack = []
        self.stdout = ''
        self.stderr = ''
        self.output = ''
        self.last_output = Time.now
        self.wait_for_output = false
      end
    end

    add_hook :on_after_run do |sh|
      sh.instance_eval do
        self.output_stack = nil
        self.last_output = nil
        self.wait_for_output = false
      end
    end

    private

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

    def reduce_newlines(data)
      data.gsub("\r\n", "\n").gsub(" \r", "").gsub("\r", "")
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

      sync do
        self.stdout += for_stdout
        self.output += data
        self.wait_for_output = false
      end

      if block_given?
        result = block.call(for_stdout, :stdout)
        if result && result.is_a?(String)
          queue_input(result + line_ending)
        end
      end
    end

    def append_stderr(data, &block)
      data = reduce_newlines data

      sync do
        self.stderr += data
        self.output += data
      end

      if block_given?
        result = block.call(data, :stderr)
        if result && result.is_a?(String)
          queue_input(result + line_ending)
        end
      end
    end


    protected

    ##
    # Sets the block to call when data is received.
    #
    # If no block is provided, then the shell will simply log all output from the program.
    # If a block is provided, it will be passed the data as it is received.  If the block
    # returns a string, then that string will be sent to the shell.
    #
    # This method is called internally in the +exec+ method, but there may be legitimate use
    # cases outside of that method as well.
    def buffer_output(&block) #:doc:
      raise Shells::NotRunning unless running?
      block ||= Proc.new { }
      stdout_received do |data|
        self.last_output = Time.now
        append_stdout strip_ansi_escape(data), &block
      end
      stderr_received do |data|
        self.last_output = Time.now
        append_stderr strip_ansi_escape(data), &block
      end
    end

    ##
    # Pushes the buffers for output capture.
    #
    # This method is called internally in the +exec+ method, but there may be legitimate use
    # cases outside of that method as well.
    def push_buffer #:doc:
      raise Shells::NotRunning unless running?
      # push the buffer so we can get the output of a command.
      debug 'Pushing buffer >>'
      sync do
        output_stack.push [ stdout, stderr, output ]
        self.stdout = ''
        self.stderr = ''
        self.output = ''
      end
    end

    ##
    # Pops the buffers and merges the captured output.
    #
    # This method is called internally in the +exec+ method, but there may be legitimate use
    # cases outside of that method as well.
    def pop_merge_buffer #:doc:
      raise Shells::NotRunning unless running?
      # almost a standard pop, however we want to merge history with current.
      debug 'Merging buffer <<'
      sync do
        hist_stdout, hist_stderr, hist_output = (output_stack.pop || [])
        if hist_stdout
          self.stdout = hist_stdout + stdout
        end
        if hist_stderr
          self.stderr = hist_stderr + stderr
        end
        if hist_output
          self.output = hist_output + output
        end
      end
    end

    ##
    # Pops the buffers and discards the captured output.
    #
    # This method is used internally in the +get_exit_code+ method, but there may be legitimate use
    # cases outside of that method as well.
    def pop_discard_buffer #:doc:
      raise Shells::SessionCompleted if session_complete?
      # a standard pop discarding current data and retrieving the history.
      debug 'Discarding buffer <<'
      sync do
        hist_stdout, hist_stderr, hist_output = (output_stack.pop || [])
        self.stdout = hist_stdout || ''
        self.stderr = hist_stderr || ''
        self.output = hist_output || ''
      end
    end

  end
end