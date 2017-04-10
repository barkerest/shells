require 'test_helper'
require 'yaml'

class ShellsTest < Minitest::Test #:nodoc: all

  def setup
    @cfg = YAML.load_file(File.expand_path('../config.yml', __FILE__))
  end

  def test_basic_ssh_session
    session = Shells::SshSession(@cfg['ssh']) do |sh|
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
    Shells::SshSession(@cfg['ssh']) do |sh|
      # non-existent function.
      sh.exec 'this-program-doesnt-exist', retrieve_exit_code: true
      assert sh.last_exit_code != 0

      # explicit exit code.
      sh.exec '(exit 42)', retrieve_exit_code: true
      assert sh.last_exit_code == 42

    end
  end

end
