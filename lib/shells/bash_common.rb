require 'base64'

module Shells
  ##
  # Provides some common functionality for bash-like shells.
  module BashCommon

    ##
    # Reads from a file on the device.
    def read_file(path, use_method = nil)
      if use_method
        use_method = use_method.to_sym
        raise ArgumentError, "use_method (#{use_method.inspect}) is not a valid method." unless file_methods.include?(use_method)
        raise Shells::ShellErro, "The #{use_method} binary is not available with this shell." unless which(use_method)
        send "read_file_#{use_method}", path
      else
        file_methods.each do |method|
          if which(method)
            return send "read_file_#{method}", path
          end
        end
        raise Shells::ShellError, 'No supported binary to encode/decode files.'
      end
    end

    ##
    # Writes to a file on the device.
    def write_file(path, data, use_method = nil)
      if use_method
        use_method = use_method.to_sym
        raise ArgumentError, "use_method (#{use_method.inspect}) is not a valid method." unless file_methods.include?(use_method)
        raise Shells::ShellErro, "The #{use_method} binary is not available with this shell." unless which(use_method)
        send "write_file_#{use_method}", path, data
      else
        file_methods.each do |method|
          if which(method)
            return send "write_file_#{method}", path, data
          end
        end
        raise Shells::ShellError, 'No supported binary to encode/decode files.'
      end
    end

    protected

    ##
    # Gets an exit code by echoing the $? variable from the environment.
    #
    # This can be overridden by specifying either a string command or a Proc
    # for the :override_get_exit_code option in the shell's options.
    def get_exit_code #:nodoc:
      cmd = options[:override_get_exit_code] || 'echo $?'
      if cmd.respond_to?(:call)
        cmd.call(self)
      else
        debug 'Retrieving exit code from last command...'
        push_buffer
        send_data cmd + line_ending
        wait_for_prompt nil, 1
        ret = command_output(cmd).strip.to_i
        pop_discard_buffer
        debug 'Exit code: ' + ret.to_s
        ret
      end
    end

    ##
    # Gets the path to a program, or nil if not found.
    def which(program)
      ret = exec("which #{program} 2>/dev/null").strip
      ret == '' ? nil : ret
    end

    private

    def file_methods
      @file_methods ||= [
          :base64,
          :openssl
      ]
    end

    def with_b64_file(path, data, &block)
      data = Base64.encode64(data)

      # Send 1 line at a time (this will be SLOW for large files).
      lines = data.gsub("\r\n", "\n").split("\n")

      # Construct a temporary filename.
      b64path = path + '.b64'
      if exec_for_code("[ -f #{b64path.inspect} ]") == 0
        # File exists.
        cnt = 2
        while exec_for_code("[ -f #{(b64path + cnt.to_s).inspect} ]") == 0
          cnt += 1
        end
        b64path += cnt.to_s
      end

      debug "Writing #{lines.count} lines to #{b64path}..."

      # Create/overwrite file with the first line.
      first_line = lines.delete_at 0
      exec "echo -n #{first_line} > #{b64path.inspect}"

      # Write remaining blocks.
      # We'll try to speed up by sending multiple commands at a time.
      cmds = []
      lines.each do |line|
        cmds << "echo -n #{line} >> #{b64path.inspect}"
        if cmds.length >= 20
          exec cmds.join(' && ')
          cmds.clear
        end
      end
      if cmds.any?
        exec cmds.join(' && ')
      end

      ret = block.call(b64path)

      exec "rm #{b64path.inspect}"

      ret
    end

    def write_file_base64(path, data)
      with_b64_file path, data do |b64path|
        exec_for_code "base64 -d #{b64path.inspect} > #{path.inspect}", command_timeout: 30
      end
    end

    def write_file_openssl(path, data)
      with_b64_file path, data do |b64path|
        exec_for_code "openssl base64 -d < #{b64path.inspect} > #{path.inspect}"
      end
    end

    def write_file_perl(path, data)
      with_b64_file path, data do |b64path|
        exec_for_code "perl -MMIME::Base64 -ne 'print decode_base64($_)' < #{b64path.inspect} > #{path.inspect}"
      end
    end

    def read_file_base64(path)
      data = exec "base64 -w 0 #{path.inspect}", retrieve_exit_code: true, on_non_zero_exit_code: :ignore, command_timeout: 30
      return nil if last_exit_code != 0
      Base64.decode64 data
    end

    def read_file_openssl(path)
      data = exec "openssl base64 < #{path.inspect}"
      return nil if last_exit_code != 0
      Base64.decode64 data
    end

    def read_file_perl(path)
      data = exec "perl -MMIME::Base64 -ne 'print encode_base64($_)' < #{path.inspect}"
      return nil if last_exit_code != 0
      Base64.decode64 data
    end


  end
end