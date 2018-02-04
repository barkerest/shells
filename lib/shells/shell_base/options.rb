module Shells
  class ShellBase

    ##
    # The options provided to this shell.
    #
    # This hash is read-only.
    attr_accessor :options
    private :options=

    attr_accessor :orig_options
    private :orig_options, :orig_options=

    add_hook :on_after_run do |sh|
      sh.instance_eval do
        self.options = orig_options
      end
    end

    ##
    # Validates the options provided to the class.
    #
    # You should define this method in your subclass.
    def validate_options #:doc:
      warn "The validate_options() method is not defined on the #{self.class} class."
    end
    protected :validate_options


    ##
    # Initializes the shell with the supplied options.
    #
    # These options are common to all shells.
    # +prompt+::
    #       Defaults to "~~#".  Most special characters will be stripped.
    # +retrieve_exit_code+::
    #       Defaults to false. Can also be true.
    # +on_non_zero_exit_code+::
    #       Defaults to :ignore. Can also be :raise.
    # +silence_timeout+::
    #       Defaults to 0.
    #       If greater than zero, will raise an error after waiting this many seconds for a prompt.
    # +command_timeout+::
    #       Defaults to 0.
    #       If greater than zero, will raise an error after a command runs for this long without finishing.
    # +unbuffered_input+::
    #       Defaults to false.
    #       If non-false, then input is sent one character at a time, otherwise input is sent in whole strings.
    #       If set to :echo, then input is sent one character at a time and the character must be echoed back
    #       from the shell before the next character will be sent.
    #
    # Please check the documentation for each shell class for specific shell options.
    def initialize(options = {})

      # cannot instantiate a ShellBase
      raise NotImplementedError if self.class == Shells::ShellBase

      raise ArgumentError, '\'options\' must be a hash.' unless options.is_a?(Hash)

      self.options = {
          prompt: '~~#',
          retrieve_exit_code: false,
          on_non_zero_exit_code: :ignore,
          silence_timeout: 0,
          command_timeout: 0,
          unbuffered_input: false
      }.merge( options.inject({}){ |m,(k,v)|  m[k.to_sym] = v; m } )

      self.options[:prompt] = self.options[:prompt]
                              .to_s.strip
                              .gsub('!', '#')
                              .gsub('$', '#')
                              .gsub('\\', '.')
                              .gsub('/', '.')
                              .gsub('"', '-')
                              .gsub('\'', '-')

      self.options[:prompt] = '~~#' if self.options[:prompt] == ''

      raise Shells::InvalidOption, ':on_non_zero_exit_code must be :ignore or :raise.' unless [:ignore, :raise].include?(self.options[:on_non_zero_exit_code])

      validate_options
      self.options.freeze   # no more changes to options now.
      self.orig_options = self.options  # sort of, we might provide helpers (like +change_quit+)

      run_hook :on_init

    end


    ##
    # Allows you to change the :quit option inside of a session.
    #
    # This is useful if you need to change the quit command for some reason.
    # e.g. - Changing the command to "reboot".
    #
    # Returns the shell instance.
    def change_quit(quit_command)
      raise Shells::NotRunning unless running?
      self.options = options.dup.merge( quit: quit_command ).freeze
      self
    end


  end
end