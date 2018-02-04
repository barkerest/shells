module Shells

  ##
  # A wrapper class around a base shell to execute pfSense PHP commands within.
  class PfShellWrapper

    ##
    # The pfSense shell itself.
    PF_SHELL = '/usr/local/sbin/pfSsh.php'

    ##
    # The prompt in the pfSense shell.
    PF_PROMPT = 'pfSense shell:'


    attr_accessor :config_parsed
    private :config_parsed, :config_parsed=

    attr_accessor :shell
    private :shell, :shell=

    ##
    # Gets the output from the pfSense PHP shell session.
    attr_accessor :output

    ##
    # Creates the wrapper, executing the pfSense shell.
    #
    # The provided code block is yielded this wrapper for execution.
    def initialize(base_shell, &block)
      raise ArgumentError, 'a code block is required' unless block_given?
      raise ArgumentError, 'the base shell must be a valid shell' unless base_shell.is_a?(::Shells::ShellBase)

      self.shell = base_shell

      wrapper = self
      code_block = block
      self.output = ''
      self.config_parsed = false

      shell.instance_eval do
        merge_local_buffer do
          begin
            temporary_prompt(PF_PROMPT) do
              debug 'Initializing the pfSense PHP shell...'
              queue_input PF_SHELL + line_ending
              wait_for_prompt 999, 10, true

              debug ' > initialized'
              begin
                code_block.call wrapper
              ensure
                debug 'Exiting the pfSense PHP shell...'
                if wait_for_prompt(5, 5, false)
                  # only queue the exit command if we are still in the pfSense shell.
                  queue_input 'exit' + line_ending
                end
              end
            end
          ensure
            # wait for the normal shell to return.
            wait_for_prompt 10, 10, true
            debug ' > exited'
            wrapper.output = output
          end
        end
      end
    end

    ##
    # Executes a series of commands on the pfSense shell.
    def exec(*commands)
      ret = ''
      commands.each { |cmd| ret += shell.exec(cmd) }
      ret + shell.exec('exec')
    end

    ##
    # Reloads the pfSense configuration on the device.
    def parse_config
      exec 'parse_config(true);'
      self.config_parsed = true
    end

    ##
    # Determines if the configuration has been parsed during this session.
    def config_parsed?
      config_parsed
    end

    ##
    # Gets a configuration section from the pfSense device.
    def get_config_section(section_name)
      parse_config unless config_parsed?
      JSON.parse exec("echo json_encode($config[#{section_name.to_s.inspect}]);").strip
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

        exec(*changes)

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
      exec(
          'require_once("shaper.inc");',
          'require_once("filter.inc");',
          'filter_configure_sync();'
      )
    end

    ##
    # Applies the user configuration for the specified user.
    def apply_user_config(user_id)
      user_id = user_id.to_i
      exec(
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
      raise Shells::NotRunning unless running?
      raise Shells::PfSenseCommon::RestartNow
    end

    ##
    # Exits the shell session immediately.
    def quit
      raise Shells::NotRunning unless running?
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