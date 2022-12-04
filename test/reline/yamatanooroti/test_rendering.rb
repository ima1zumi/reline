require 'reline'

begin
  require 'yamatanooroti'

  class Reline::TestRendering < Yamatanooroti::TestCase
    def setup
      puts 'setup'
      @pwd = Dir.pwd
      suffix = '%010d' % Random.rand(0..65535)
      @tmpdir = File.join(File.expand_path(Dir.tmpdir), "test_reline_config_#{$$}_#{suffix}")
      begin
        Dir.mkdir(@tmpdir)
      rescue Errno::EEXIST
        puts 'rescue'
        FileUtils.rm_rf(@tmpdir)
        Dir.mkdir(@tmpdir)
      end
      @inputrc_backup = ENV['INPUTRC']
      @inputrc_file = ENV['INPUTRC'] = File.join(@tmpdir, 'temporaty_inputrc')
      File.unlink(@inputrc_file) if File.exist?(@inputrc_file)
    end

    def teardown
      puts 'teardown'
      FileUtils.rm_rf(@tmpdir)
      ENV['INPUTRC'] = @inputrc_backup
      ENV.delete('RELINE_TEST_PROMPT') if ENV['RELINE_TEST_PROMPT']
    end

    def test_suppress_auto_indent_just_after_pasted
      puts 'a'
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      puts 'b'
      write("def hoge\n  [[\n      3]]\ned")
      puts 'c'
      write("\C-bn")
      puts 'd'
      close
      puts 'e'
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt>   [[
        prompt>       3]]
        prompt> end
      EOC
      puts 'f'
    end

    def test_suppress_auto_indent_for_adding_newlines_in_pasting
      puts method_name, ' skip'
#       start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
#       write("<<~Q\n")
#       write("{\n  #\n}")
#       write("#")
#       close
#       assert_screen(<<~EOC)
#         Multiline REPL.
#         prompt> <<~Q
#         prompt> {
#         prompt>   #
#         prompt> }#
#       EOC
    end
  end
rescue LoadError, NameError
  puts 'LoadError or NameError'
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
