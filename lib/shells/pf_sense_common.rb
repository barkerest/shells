require 'base64'
require 'json'
require 'byebug'

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
    # Signals that we want to restart the device.
    class RestartNow < Exception

    end


    ##
    # The base shell used when possible.
    BASE_SHELL = '/bin/sh'

    ##
    # The pfSense shell itself.
    PF_SHELL = '/usr/local/sbin/pfSsh.php'

    ##
    # The prompt in the pfSense shell.
    PF_PROMPT = 'pfSense shell:'

    ##
    # Gets the version of the pfSense firmware.
    attr_accessor :pf_sense_version

    ##
    # Gets the user currently logged into the pfSense device.
    attr_accessor :pf_sense_user

    ##
    # Gets the hostname of the pfSense device.
    attr_accessor :pf_sense_host


    def line_ending #:nodoc:
      "\n"
    end

    def self.included(base)  #:nodoc:

      # Trap the RestartNow exception.
      # When encountered, change the :quit option to '/sbin/reboot'.
      # This requires rewriting the @options instance variable since the hash is frozen
      # after initial validation.
      base.on_exception do |shell, ex|
        if ex.is_a?(Shells::PfSenseCommon::RestartNow)
          shell.send(:change_quit, '/sbin/reboot')
          true
        else
          false
        end
      end

    end

    def validate_options  #:nodoc:
      super
      options[:shell] = :shell
      options[:prompt] = 'pfSense shell:'
      options[:quit] = 'exit'
      options[:retrieve_exit_code] = false
      options[:on_non_zero_exit_code] = :ignore
      options[:override_set_prompt] = ->(sh) { true }
      options[:override_get_exit_code] = ->(sh) { 0 }
    end

    def exec_shell(&block) #:nodoc:
      super do
        # We want to drop to the shell before executing the block.
        # So we'll navigate the menu to get the option for the shell.
        # For this first navigation we allow a delay only if we are not connected to a serial device.
        # Serial connections are always on, so they don't need to initialize first.
        menu_option = get_menu_option 'Shell', !(Shells::SerialSession > self.class)
        raise MenuNavigationFailure unless menu_option

        # For 2.3 and 2.4 this is a valid match.
        # If future versions change the default prompt, we need to change our process.
        # [VERSION][USER@HOSTNAME]/root:  where /root is the current dir.
        shell_regex = /\[(?<VER>[^\]]*)\]\[(?<USERHOST>[^\]]*)\](?<CD>\/.*):\s*$/

        # Now we execute the menu option and wait for the shell_regex to match.
        temporary_prompt(shell_regex) do
          exec menu_option.to_s, command_timeout: 5

          # Once we have a match we should be able to repeat it and store the information from the shell.
          data = prompt_match.match(combined_output)
          self.pf_sense_version = data['VER']
          self.pf_sense_user, _, self.pf_sense_host = data['USERHOST'].partition('@')
        end

        block.call

        # Wait for the shell_regex to match again.
        temporary_prompt(shell_regex) { wait_for_prompt nil, 4, false }

        # Exit the shell to return to the menu.
        send_data 'exit' + line_ending

        # After the block we want to know what the Logout option is and we change the quit command to match.
        menu_option = get_menu_option 'Logout'
        raise MenuNavigationFailure unless menu_option
        change_quit menu_option.to_s
      end
    end

    def exec_prompt(&block) #:nodoc:
      debug 'Initializing pfSense shell...'
      exec '/usr/local/sbin/pfSsh.php', command_timeout: 5
      begin
        block.call
      ensure
        debug 'Quitting pfSense shell...'
        send_data 'exit' + line_ending
      end
    end

    ##
    # Executes a series of commands on the pfSense shell.
    def pf_exec(*commands)
      ret = ''
      commands.each { |cmd| ret += exec(cmd) }
      ret + exec('exec')
    end

    ##
    # Reloads the pfSense configuration on the device.
    def parse_config
      pf_exec 'parse_config(true);'
      @config_parsed = true
    end

    ##
    # Determines if the configuration has been parsed during this session.
    def config_parsed?
      instance_variable_defined?(:@config_parsed) && instance_variable_get(:@config_parsed)
    end

    ##
    # Gets a configuration section from the pfSense device.
    def get_config_section(section_name)
      parse_config unless config_parsed?
      JSON.parse pf_exec("echo json_encode($config[#{section_name.to_s.inspect}]);").strip
    end

    ##
    # Sets a configuration section to the pfSense device.
    #
    # Returns the number of changes made to the configuration.
    def set_config_section(section_name, values, message = '')
      current_values = get_config_section(section_name)
      changes = generate_config_changes("$config[#{section_name.to_s.inspect}]", current_values, values)
      if changes&.any?
        if message.to_s.strip == ''
          message = "Updating #{section_name} section."
        end
        changes << "write_config(#{message.inspect});"

        pf_exec(*changes)

        (changes.size - 1)
      else
        0
      end
    end

    ##
    # Apply the firewall configuration.
    #
    # You need to apply the firewall configuration after you make changes to aliases, NAT rules, or filter rules.
    def apply_filter_config
      pf_exec(
          'require_once("shaper.inc");',
          'require_once("filter.inc");',
          'filter_configure_sync();'
      )
    end

    ##
    # Applies the user configuration for the specified user.
    def apply_user_config(user_id)
      user_id = user_id.to_i
      pf_exec(
          'require_once("auth.inc");',
          "$user_entry = $config[\"system\"][\"user\"][#{user_id}];",
          '$user_groups = array();',
          'foreach ($config["system"]["group"] as $gidx => $group) {',
          '  if (is_array($group["member"])) {',
          "    if (in_array(#{user_id}, $group[\"member\"])) { $user_groups[] = $group[\"name\"]; }",
          '  }',
          '}',
          # Intentionally run set_groups before and after to ensure group membership gets fully applied.
          'local_user_set_groups($user_entry, $user_groups);',
          'local_user_set($user_entry);',
          'local_user_set_groups($user_entry, $user_groups);'
      )
    end

    ##
    # Enabled public key authentication for the current pfSense user.
    #
    # Once this has been done you should be able to connect without using a password.
    def enable_cert_auth(public_key = '~/.ssh/id_rsa.pub')
      cert_regex = /^ssh-[rd]sa (?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)? \S*$/m

      # get our cert unless the user provided a full cert for us.
      unless public_key =~ cert_regex
        public_key = File.expand_path(public_key)
        if File.exist?(public_key)
          public_key = File.read(public_key).to_s.strip
        else
          raise Shells::PfSenseCommon::PublicKeyNotFound
        end
        raise Shells::PfSenseCommon::PublicKeyInvalid unless public_key =~ cert_regex
      end

      cfg = get_config_section 'system'
      user_id = nil
      user_name = options[:user].downcase
      cfg['user'].each_with_index do |user,index|
        if user['name'].downcase == user_name
          user_id = index

          authkeys = Base64.decode64(user['authorizedkeys'].to_s).gsub("\r\n", "\n").strip
          unless authkeys == '' || authkeys =~ cert_regex
            warn "Existing authorized keys for user #{options[:user]} are invalid and are being reset."
            authkeys = ''
          end

          if authkeys == ''
            user['authorizedkeys'] = Base64.strict_encode64(public_key)
          else
            authkeys = authkeys.split("\n")
            unless authkeys.include?(public_key)
              authkeys << public_key unless authkeys.include?(public_key)
              user['authorizedkeys'] = Base64.strict_encode64(authkeys.join("\n"))
            end
          end

          break
        end
      end


      raise Shells::PfSenseCommon::UserNotFound unless user_id

      set_config_section 'system', cfg, "Enable certificate authentication for #{options[:user]}."

      apply_user_config user_id
    end


    ##
    # Exits the shell session immediately and requests a reboot of the pfSense device.
    def reboot
      raise Shells::SessionCompleted if session_completed?
      raise Shells::PfSenseCommon::RestartNow
    end

    ##
    # Exits the shell session immediately.
    def quit
      raise Shells::SessionCompleted if session_completed?
      raise Shells::ShellBase::QuitNow
    end



    private

    def generate_config_changes(prefix, old_value, new_value)
      old_value = fix_config_arrays(old_value)
      new_value = fix_config_arrays(new_value)

      if new_value.is_a?(Hash)
        changes = []

        unless old_value.is_a?(Hash)
          # make sure the value is an array now.
          changes << "#{prefix} = array();"
          # and change the old_value to be an empty hash so we can work with it.
          old_value = {}
        end

        # now iterate the hashes and process the child elements.
        new_value.each do |k, new_v|
          old_v = old_value[k]
          changes += generate_config_changes("#{prefix}[#{k.inspect}]", old_v, new_v)
        end

        changes
      else
        if new_value != old_value
          if new_value.nil?
            [ "unset #{prefix};" ]
          else
            [ "#{prefix} = #{new_value.inspect};" ]
          end
        else
          [ ]
        end
      end
    end

    def fix_config_arrays(value)
      if value.is_a?(Array)
        value.each_with_index
            .map{|v,i| [i,v]}.to_h                      # convert to hash
            .inject({}){ |m,(k,v)| m[k.to_s] = v; m }   # stringify keys
      elsif value.is_a?(Hash)
        value.inject({}) { |m,(k,v)| m[k.to_s] = v; m } # stringify keys
      else
        value
      end
    end



    # Processes the pfSense console menu to determine the option to send.
    def get_menu_option(option_text, delay = true)
      option_regex = /\s(\d+)\)\s*#{option_text}\s/i
      prompt_text = 'Enter an option:'

      temporary_prompt prompt_text do
        begin

          # give the prompt a few seconds to draw.
          if delay
            wait_for_prompt(nil, 4, false)
          end

          # See if we have a menu already.
          menu_regex = /(?<MENU>\s0\)(?:.|\r|\n(?!\s0\)))*)#{prompt_text}[ \t]*$/
          match = menu_regex.match(combined_output)
          menu = match ? match['MENU'] : nil

          push_buffer

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
        ensure
          pop_discard_buffer
        end
      end
    end


  end
end