module Shells
  class ShellBase

    attr_accessor :input_fifo
    private :input_fifo, :input_fifo

    add_hook :on_before_run do |sh|
      sh.instance_eval do
        self.input_fifo = []
      end
    end

    add_hook :on_after_run do |sh|
      sh.instance_eval do
        self.input_fifo = nil
      end
    end

    ##
    # Defines the line ending used to terminate commands sent to the shell.
    #
    # The default is "\n".  If you need "\r\n", "\r", or some other value, simply override this function.
    def line_ending
      "\n"
    end

    protected

    ##
    # Adds input to be sent to the shell.
    def queue_input(data) #:doc:
      sync do
        if options[:unbuffered_input]
          data = data.chars
          input_fifo.push *data
        else
          input_fifo.push data
        end
      end
    end

    private

    def next_input
      sync { input_fifo.shift }
    end


  end
end