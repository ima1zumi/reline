require_relative 'helper'

class Reline::Config::Test < Reline::TestCase
  def setup
    @pwd = Dir.pwd
    @tmpdir = File.join(Dir.tmpdir, "test_reline_config_#{$$}")
    begin
      Dir.mkdir(@tmpdir)
    rescue Errno::EEXIST
      FileUtils.rm_rf(@tmpdir)
      Dir.mkdir(@tmpdir)
    end
    Dir.chdir(@tmpdir)
    Reline.test_mode
    @config = Reline::Config.new
  end

  def teardown
    Dir.chdir(@pwd)
    FileUtils.rm_rf(@tmpdir)
    Reline.test_reset
    @config.reset
  end

  def test_if_with_mode
    @config.read_lines(<<~LINES.lines)
      $if mode=vi
        "\C-e": history-search-backward
      $else
        "\C-e": history-search-forward
      $endif
    LINES

    assert_equal({[5] => :history_search_backward}, @config.instance_variable_get(:@additional_key_bindings)[:vi_insert])
    assert_equal({[5] => :history_search_backward}, @config.instance_variable_get(:@additional_key_bindings)[:vi_command])
    assert_equal({[6] => :history_search_forward}, @config.instance_variable_get(:@additional_key_bindings)[:emacs])
    assert_equal {[6] => :history_search_forward}, @config.instance_variable_get(:@additional_key_bindings)[:emacs]
  end
end

