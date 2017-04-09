require 'base64'
require 'json'

module Shells

  ##
  # An error raised when we fail to navigate the pfSense menu.
  PfSenseMenuNavigationFailure = Class.new(Shells::ShellError)

  ##
  # Common functionality for interacting with a pfSense device.
  module PfSenseCommon

    ##
    # Signals that we want to restart the device.
    RestartNow = Class.new(Exception)

    ##
    # Failed to locate the public key.
    PublicKeyNotFound = Class.new(Shells::ShellError)

    ##
    # Failed to validate the public key.
    PublicKeyInvalid = Class.new(Shells::ShellError)

    ##
    # Failed to locate the user on the device.
    UserNotFound = Class.new(Shells::ShellError)

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
    # Provides class methods to the shell class.
    module ClassMethods

      protected

      ##
      # Navigates the pfSense menu to get to a base shell.
      #
      # When you will be facing the pfSense menu, you should call this before initializing the prompt.
      #   before_init :navigate_menu
      #
      def navigate_menu(shell)

        # Usually the option will be 8 that we want, however we want to parse the menu just to be sure.
        # So we'll start by pushing the buffer and then sending an invalid menu option sequence.
        # This should cause the menu to be redrawn.
        # The prompt we are looking for will be "Enter an option:".

        temp_prompt = /Enter an option:\s*$/

        shell.send(:push_buffer)
        shell.send(:send_data, '-1' + shell.line_ending)

        timeout = Time.now + 5
        shell.send(:loop) do
          raise Shells::CommandTimeout if Time.now > timeout
          !(combined_output =~ temp_prompt)
        end

        menu = if (pos = (combined_output =~ temp_prompt))
                 combined_output[0...pos]
               else
                 combined_output
               end

        if (match = (/\s(\d+)\)\s*shell\s/i).match(menu))
          shell.send(:send_data, match[1] + shell.line_ending)
          temp_prompt = /#\s*$/
          timeout = Time.now + 5

          shell.send(:loop) do
            raise Shells::CommandTimeout if Time.now > timeout
            !(combined_output =~ temp_prompt)
          end
        else
          raise Shells::PfSenseMenuNavigationFailure
        end

        # We have successfully navigated the menu.
        # Clean up the buffer and send a line ending to refresh the prompt.
        shell.send(:pop_discard_buffer)
        shell.send(:send_data, shell.line_ending)

        true
      end

    end

    def self.included(base)  # :nodoc:
      base.extend Shells::PfSenseCommon::ClassMethods

      # Trap the RestartNow exception.
      # When encountered, change the :quit option to '/sbin/reboot'.
      # This requires rewriting the @options instance variable since the hash is frozen
      # after initial validation.
      base.on_exception do |shell, ex|
        if ex.is_a?(RestartNow)
          opt = shell.options.dup
          opt[:quit] = '/sbin/reboot'
          opt.freeze
          shell.instance_variable_set(:@options, opt)
          true
        else
          false
        end
      end

    end

    def validate_options  # :nodoc:
      options[:host] ||= 'localhost'
      options[:port] ||= 22
      options[:shell] = '/usr/local/sbin/pfSsh.php'
      options[:prompt] = 'pfSense shell:'
      options[:quit] = 'exit'
      options[:connect_timeout] ||= 5
      options[:retrieve_exit_code] = false
      options[:on_non_zero_exit_code] = :ignore
      options[:override_set_prompt] = ->(sh) { sleep 1; true } # prompt is set by the shell itself, give the shell a second to load.
      options[:override_get_exit_code] = ->(sh) { 0 }

      raise InvalidOption, 'Missing host.' if options[:host].to_s.strip == ''
      raise InvalidOption, 'Missing user.' if options[:user].to_s.strip == ''
    end

    ##
    # Executes a series of commands on the pfSense shell.
    #
    # This would be the same as calling +exec+ for each command followed by an explicit 'exec' command passed to +exec+.
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

        pf_exec *changes

        (changes.size - 1)
      else
        0
      end
    end

    ##
    # Apply the firewall configuration.
    #
    # You need to apply the firewall configuration after you make changes to aliases, NAT rules, or filter rules.
    def filter_configure
      pf_exec(
          'require_once("shaper.inc");',
          'require_once("filter.inc");',
          'filter_configure_sync();'
      )
    end

    ##
    # Applies the user configuration for the specified user.
    def user_configure(user_id)
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
          raise PublicKeyNotFound
        end
        raise PublicKeyInvalid unless public_key =~ cert_regex
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


      raise UserNotFound unless user_id

      set_config_section 'system', cfg, "Enable certificate authentication for #{options[:user]}."

      user_configure user_id
    end


    ##
    # Exits the shell session immediately and requests a reboot of the pfSense device.
    def reboot
      raise Shells::SessionCompleted if session_completed?
      raise RestartNow
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

  end
end