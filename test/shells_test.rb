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


  end

end
