require 'base64'
require 'json'

require 'shells/pf_shell_wrapper'

module Shells

  ##
  # Common functionality for interacting with a pfSense device.
  module PfSenseCommon

    ##
    # An error raised when we fail to navigate the pfSense menu.
    class MenuNavigationFailure < Shells::ShellError

    end

    ##
    # Failed to locate the public key.
    class PublicKeyNotFound < Shells::ShellError

    end

    ##
    # Failed to validate the public key.
    class PublicKeyInvalid < Shells::ShellError

    end

    ##
    # Failed to locate the user on the device.
    class UserNotFound < Shells::ShellError

    end

    ##
    # The shell is already in pf_shell mode.
    class AlreadyInPfShell < Shells::ShellError

    end

    ##
    # The shell not in pf_shell mode.
    class NotInPfShell < Shells::ShellError

    end

    ##
    # Signals that we want to restart the device.
    class RestartNow < Exception

    end


    ##
    # The prompt text for the main menu.
    MENU_PROMPT = 'Enter an option:'

    ##
    # The base shell used when possible.
    BASE_SHELL = '/bin/sh'

    ##
    # Gets the version of the pfSense firmware.
    attr_accessor :pf_sense_version
    protected :pf_sense_version=

    ##
    # Gets the user currently logged into the pfSense device.
    attr_accessor :pf_sense_user
    protected :pf_sense_user=

    ##
    # Gets the hostname of the pfSense device.
    attr_accessor :pf_sense_host
    protected :pf_sense_host=


    def self.included(base)  #:nodoc:

      base.class_eval do
        # Trap the RestartNow exception.
        # When encountered, change the :quit option to '/sbin/reboot'.
        # This requires rewriting the @options instance variable since the hash is frozen
        # after initial validation.
        on_exception do |shell, ex|
          if ex.is_a?(Shells::PfSenseCommon::RestartNow)
            shell.send(:change_quit, '/sbin/reboot')
            :break
          end
        end

        add_hook :on_before_run do |sh|
          sh.instance_eval do
            self.pf_sense_version = nil
            self.pf_sense_user = nil
            self.pf_sense_host = nil
          end
        end

      end

    end

    def validate_options  #:nodoc:
      super
      options[:shell] = :shell
      options[:quit] = 'exit'
      options[:retrieve_exit_code] = false
      options[:on_non_zero_exit_code] = :ignore
    end

    def line_ending
      @line_ending ||= "\n"
    end

    def setup_prompt #:nodoc:

      # By default we have the main menu.
      # We want to drop to the main shell to execute the PHP shell.
      # So we'll navigate the menu to get the option for the shell.
      # For this first navigation we allow a delay only if we are not connected to a serial device.
      # Serial connections are always on, so they don't need to initialize first.
      menu_option = get_menu_option 'Shell', !(Shells::SerialShell > self.class)
      raise MenuNavigationFailure unless menu_option

      # For 2.3 and 2.4 this is a valid match.
      # If future versions change the default prompt, we need to change our process.
      # [VERSION][USER@HOSTNAME]/root:  where /root is the current dir.
      shell_regex = /\[(?<VER>[^\]]*)\]\[(?<USERHOST>[^\]]*)\](?<CD>\/.*):\s*$/

      # Now we execute the menu option and wait for the shell_regex to match.
      temporary_prompt(shell_regex) do
        exec menu_option.to_s, command_timeout: 5

        # Once we have a match we should be able to repeat it and store the information from the shell.
        data = prompt_match.match(output)
        self.pf_sense_version = data['VER']
        self.pf_sense_user, _, self.pf_sense_host = data['USERHOST'].partition('@')
      end

      # at this point we can now treat it like a regular tcsh shell.
      command = "set prompt='#{options[:prompt]}'"
      exec_ignore_code command, silence_timeout: 10, command_timeout: 10, timeout_error: true, get_output: false
    end

    def teardown #:nodoc:
      # use the default teardown to exit the shell.
      super

      # then navigate to the logout option (if the shell is still active).
      if active?
        menu_option = get_menu_option 'Logout'
        raise MenuNavigationFailure unless menu_option
        exec_ignore_code menu_option.to_s, command_timeout: 1, timeout_error: false
      end
    end

    ##
    # Executes the code block in the pfSense PHP shell.
    def pf_shell(&block)
      ::Shells::PfShellWrapper.new(self, &block).output
    end

    private

    # Processes the pfSense console menu to determine the option to send.
    def get_menu_option(option_text, delay = true)
      option_regex = /\s(\d+)\)\s*#{option_text}\s/i

      temporary_prompt MENU_PROMPT do
        # give the prompt a few seconds to draw.
        if delay
          wait_for_prompt(nil, 4, false)
        end

        # See if we have a menu already.
        menu_regex = /(?<MENU>\s0\)(?:.|\r|\n(?!\s0\)))*)#{MENU_PROMPT}[ \t]*$/
        match = menu_regex.match(output)
        menu = match ? match['MENU'] : nil

        discard_local_buffer do
          if menu.nil?
            # We want to redraw the menu.
            # In order to do that, we need to send a command that is not valid.
            # A blank line equates to a zero, which is (probably) the logout option.
            # So we'll send a -1 to redraw the menu without actually running any commands.
            debug 'Redrawing menu...'
            menu = exec('-1', command_timeout: 5, timeout_error: false)

            if last_exit_code == :timeout
              # If for some reason the shell is/was running, we need to exit it to return to the menu.
              # This time we will raise an error.
              menu = exec('exit', command_timeout: 5)
            end
          end

          # Ok, so now we have our menu options.
          debug "Locating 'XX) #{option_text}' menu option..."
          match = option_regex.match(menu)
          if match
            return match[1].to_i
          else
            return nil
          end
        end
      end
    end


  end
end