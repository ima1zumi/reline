require_relative 'helper'

class Reline::WithinPipeTest < Reline::TestCase
  def setup
    Reline.send(:test_mode)
    @reader, @writer = IO.pipe((RELINE_TEST_ENCODING rescue Encoding.default_external))
    Reline.input = @reader
    @output = Reline.output = File.open(IO::NULL, 'w')
    @config = Reline.class_variable_get(:@@config)
    @line_editor = Reline.class_variable_get(:@@line_editor)
  end

  def teardown
    Reline.input = STDIN
    Reline.output = STDOUT
    @reader.close
    @writer.close
    @output.close
    @config.reset
  end

  def test_simple_input
    @writer.write("abc\n")
    assert_equal 'abc', Reline.readmultiline(&proc{ true })
  end

  def test_unknown_macro
    @config.add_default_key_binding('abc'.bytes, :unknown_macro)
    @writer.write("abcd\n")
    assert_equal 'd', Reline.readmultiline(&proc{ true })
  end
end