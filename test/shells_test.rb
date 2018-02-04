require 'test_helper'
require 'yaml'

class ShellsTest < Minitest::Test #:nodoc: all

  class TestError < Exception

  end

  def hook_test_class
    Class.new(Shells::SshShell) do
      on_debug { |msg| $stderr.puts msg }

      attr_accessor :flags

      def initialize(flags, options = {})
        self.flags = flags
        super options
      end

      before_init { |sh| sh.flags[:before_init_processed] = true; nil }
      after_init { |sh| sh.flags[:after_init_processed] = true; nil }
      before_term { |sh| sh.flags[:before_term_processed] = true; nil }
      after_term { |sh| sh.flags[:after_term_processed] = true; nil }

      def self.run(cfg)
        flags = {
            error_processed: false,
            block_processed: false,
            before_init_processed: false,
            after_init_processed: false,
            before_term_processed: false,
            after_term_processed: false,
        }
        begin
          new(flags, cfg) do
            flags[:block_processed] = true
            yield if block_given?
          end
        rescue TestError
          flags[:error_processed] = true
        end
        flags
      end

    end
  end

  def setup
    @cfg = YAML.load_file(File.expand_path('../config.yml', __FILE__))
    @hook_test = hook_test_class
    Shells.constants.each do |const|
      const = Shells.const_get(const)
      if const.is_a?(Class) && Shells::ShellBase > const
        const.on_debug { |msg| $stderr.puts msg }
      end
    end
  end


  def test_basic_ssh_session
    log_header
    skip if @cfg['ssh'].empty?
    session = Shells::SshShell(@cfg['ssh'].merge(
        retrieve_exit_code: false,
        on_non_zero_exit_code: :ignore,
        command_timeout: 5
    )) do |sh|
      sh.exec 'ls -al'
    end

    assert session.session_complete?
    assert session.combined_output =~ /ls -al/
    assert session.stdout =~ /ls -al/

    assert_raises Shells::SessionCompleted do
      session.exec 'some action'
    end

  end

  def test_exit_codes
    log_header
    skip if @cfg['ssh'].empty?
    Shells::SshShell(@cfg['ssh'].merge(
        retrieve_exit_code: true,
        on_non_zero_exit_code: :ignore,
        command_timeout: 5
    )) do |sh|
      # non-existent function.
      sh.exec 'this-program-doesnt-exist', retrieve_exit_code: true
      assert sh.last_exit_code != 0

      # explicit exit code.
      sh.exec '(exit 42)', retrieve_exit_code: true
      assert sh.last_exit_code == 42

    end
  end

  def test_read_write_file
    log_header
    skip if @cfg['ssh'].empty?
    Shells::SshShell(@cfg['ssh'].merge(
        retrieve_exit_code: false,
        on_non_zero_exit_code: :ignore,
        command_timeout: 5
    )) do |sh|

      [
          # First something simple that easily should fit into a single transfer block.
          "Hello World!\nThis is a test file.",
          # Then a fairly long file with 300 lines in it that should require several transfer blocks.
          "Hello World!!!\nThis is a test file.\n" + ((3..300).to_a.map{|i| "This is line #{i}."}).join("\n"),
          # And one that has binary data.
          (0..8000).to_a.pack('S*')
      ].each_with_index do |data,idx|
        # Write the file
        code = sh.write_file 'my_test_file', data
        assert code == 0, "Bad exit code for writing on data #{idx}"

        # my_test_file should exist.
        assert sh.exec_for_code('[ -f my_test_file ]') == 0, "my_test_file does not exist for data #{idx}"
        # my_test_file.b64 should not exist.
        assert sh.exec_for_code('[ -f my_test_file.b64 ]') != 0, "my_test_file.b64 does exist for data #{idx}"

        # read the file and verify the contents.
        test_data = sh.read_file 'my_test_file'
        assert_equal data, test_data, "my_test_file content mismatch for data #{idx}"

        # clean up.
        sh.exec 'rm my_test_file'
        assert sh.exec_for_code('[ -f my_test_file ]') != 0, "Failed to remove my_test_file for data #{idx}"
      end
    end
  end

  def test_error_in_code_block
    log_header
    skip if @cfg['ssh'].empty?
    flags = @hook_test.run(@cfg['ssh']) { raise TestError }

    # The error was processed?
    assert flags[:error_processed]

    # all hooks should have run.
    assert flags[:block_processed]
    assert flags[:before_init_processed]
    assert flags[:after_init_processed]
    assert flags[:before_term_processed]
    assert flags[:after_term_processed]

  end

  def test_error_in_before_term
    log_header
    skip if @cfg['ssh'].empty?
    @hook_test.before_term { raise TestError }
    flags = @hook_test.run @cfg['ssh']

    # The error was processed?
    assert flags[:error_processed]

    # all blocks should have run.
    assert flags[:before_init_processed]
    assert flags[:after_init_processed]
    assert flags[:before_term_processed]
    assert flags[:after_term_processed]
    assert flags[:block_processed]

  end

  def test_error_in_after_init
    log_header
    skip if @cfg['ssh'].empty?
    @hook_test.after_init { raise TestError }
    flags = @hook_test.run @cfg['ssh']

    # The error was processed?
    assert flags[:error_processed]

    # block_processed should not be set.
    assert !flags[:block_processed]

    # everything else should have run.
    assert flags[:before_init_processed]
    assert flags[:after_init_processed]
    assert flags[:before_term_processed]
    assert flags[:after_term_processed]

  end

  def test_error_in_before_init
    log_header
    skip if @cfg['ssh'].empty?
    @hook_test.before_init { raise TestError }
    flags = @hook_test.run @cfg['ssh']

    # The error was processed?
    assert flags[:error_processed]

    # block_processed, after_init, and before_term should not be set.
    assert !flags[:block_processed]
    assert !flags[:after_init_processed]
    assert !flags[:before_term_processed]

    # everything else should have run.
    assert flags[:before_init_processed]
    assert flags[:after_term_processed]
  end

  def test_pf_sense_ssh
    log_header
    skip if @cfg['pf_sense_ssh'].empty?
    Shells::PfSenseSshSession(@cfg['pf_sense_ssh'].merge(
        command_timeout: 5
    )) do |sh|
      assert sh.get_config_section('system').is_a?(Hash)
      assert sh.pf_exec('echo "hello world";').strip == 'hello world'
    end
  end

  def test_pf_sense_serial
    log_header
    skip if @cfg['pf_sense_serial'].empty?
    Shells::PfSenseSerialSession(@cfg['pf_sense_serial'].merge(
        command_timeout: 5
    )) do |sh|
      assert sh.get_config_section('system').is_a?(Hash)
      assert sh.pf_exec('echo "hello world";').strip == 'hello world'
    end
  end

  private

  def log_header
    $stderr.puts '=' * 79
    $stderr.puts caller_locations(1,1).first.label
    $stderr.puts '=' * 79
  end

end
