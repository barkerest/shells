module Shells
  class ShellBase

    attr_accessor :thread_lock
    private :thread_lock, :thread_lock=

    add_hook :on_init do |sh|
      puts 'Initializing...'
      sh.instance_eval do
        self.thread_lock = Mutex.new
      end
    end

    protected

    ##
    # Synchronizes actions between shell threads.
    def sync(&block)
      thread_lock.synchronize &block
    end


  end
end