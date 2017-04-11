require 'test_helper'
require 'yaml'

class ShellsTest < Minitest::Test #:nodoc: all

  def setup
    @cfg = YAML.load_file(File.expand_path('../config.yml', __FILE__))
    Shells.constants.each do |const|
      const = Shells.const_get(const)
      if const.is_a?(Class) && Shells::ShellBase > const
        const.on_debug { |msg| $stderr.puts msg }
      end
    end
  end

  def test_basic_ssh_session
    log_header
    session = Shells::SshSession(@cfg['ssh'].merge(
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
    Shells::SshSession(@cfg['ssh'].merge(
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

  def test_pf_sense_ssh
    log_header
    Shells::PfSenseSshSession(@cfg['pf_sense_ssh'].merge(
        command_timeout: 5
    )) do |sh|
      assert sh.get_config_section('system').is_a?(Hash)
      assert sh.pf_exec('echo "hello world";').strip == 'hello world'
    end
  end

  def test_pf_sense_serial
    log_header
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
