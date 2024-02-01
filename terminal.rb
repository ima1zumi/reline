require 'pty'
require 'io/console'
if ARGV.empty?
  puts <<~EOS
    Reline Visualizer (Minimal terminal emulator that only supports Reline's escape sequences)
    Usage: ruby #{__FILE__} <command>'
    ruby #{__FILE__} irb
    ruby #{__FILE__} bash
    ruby #{__FILE__} ruby -I path/to/reline/lib -I path/to/irb/lib path/to/irb/exe/irb
  EOS
  exit
end

command = ARGV

class Visualizer
  def initialize(pty_output)
    @pty_output = pty_output
    @y, @x = STDIN.raw do
      STDOUT.print "\e[6n"
      STDIN.readpartial(1024)[/\e\[\d+;\d+R/].scan(/\d+/).map { _1.to_i - 1 }
    end
    @height, @width = STDIN.winsize
    @flashed = @height.times.map { {} }
    @screen_lines = @height.times.map { [] }
    @color_seq = []
  end

  def move_cursor(x: @x, y: @y)
    STDOUT.write "\e[#{y + 1};#{x + 1}H"
  end

  def scroll_down(n)
    @y += n
    if @y < @height
      move_cursor
    else
      scroll = @y - @height + 1
      @y = @height - 1
      move_cursor
      STDOUT.write "\n" * scroll
      scroll.times do
        @screen_lines.shift
        @screen_lines << []
        @flashed.shift
        @flashed << {}
      end
    end
  end

  FLASH_SEQ = [0,1,7]
  FLASH_COUNT = 4

  def flash(c)
    @screen_lines[@y][@x] = [c, @color_seq]
    @flashed[@y][@x] = FLASH_COUNT
    draw(c, FLASH_SEQ)
  end

  def restore(force: false)
    backup = @y, @x
    @flashed.each_with_index do |cols, y|
      next if cols.empty?
      @y = y
      cols.keys.sort.each do |x|
        next if cols[x] != 1 && !force
        c, color_seq = @screen_lines[y][x]
        if c
          @x = x
          move_cursor
          draw(c, color_seq)
        end
      end
      cols.transform_values! { _1 - 1 }.delete_if { _2 == 0 }
    end
    @y, @x = backup
    move_cursor
  end

  def draw(c, seq)
    STDOUT.print "\e[0;#{seq.join(';')}m#{c}\e[0m"
  end

  def print(output)
    sequences = output.split(/(\e\[[^a-zA-Z~]*[a-zA-Z~])/)
    sequences.each_with_index do |seq, i|
      if i % 2 == 0
        seq.grapheme_clusters.each do |c|
          case c
          when "\b"
            if @x > 0
              @x -= 1
              move_cursor
            end
          when "\a"
            STDOUT.write c
          when "\r\n"
            @x = 0
            scroll_down(1)
            move_cursor
          when "\r"
            @x = 0
            move_cursor
          when "\n"
            scroll_down(1)
          else
            w = 1 # Reline::Unicode.calculate_width(c)
            if @x + w > @width
              @x = 0
              scroll_down(1)
            end
            flash(c)
            @x += w
            if @x >= @width
              @x = 0
              scroll_down(1)
            else
              move_cursor
            end
          end
        end
      else
        type = seq[-1]
        args = seq.scan(/\d+/).map(&:to_i)
        case type
        when 'A'
          @y = [@y - (args[0] || 1), 0].max
          move_cursor
        when 'B'
          @y = [@y + (args[0] || 1), @height - 1].min
          move_cursor
        when 'C'
          @x = [@x + (args[0] || 1), @width - 1].min
        when 'D'
          @x = [@x - (args[0] || 1), 0].max
          move_cursor
        when 'G'
          @x = ((args[0] || 1) - 1).clamp(0, @width - 1)
          move_cursor
        when 'K'
          @screen_lines[@y].slice!(@x..)
          STDOUT.write seq
        when 'J'
          @screen_lines.each(&:clear)
          STDOUT.write seq
        when 'H'
          @y = (args[0] || 1) - 1
          @x = (args[1] || 1) - 1
          move_cursor
        when 'P'
          @screen_lines[@y].slice!(@x, args[0] || 1)
          STDOUT.write seq
        when 'm'
          if args.empty?
            @color_seq = []
          else
            @color_seq = @color_seq.dup
            args.each do |arg|
              arg == 0 ? @color_seq = [] : @color_seq << arg
            end
          end
        when 'n', 'l', 'h'
          STDOUT.write seq
        else
          raise "Unimplemented escape sequence: #{seq.inspect} #{output.inspect}"
        end
      end
    end
  end

  def input(s)
    s[/\e\[\d+;\d+R/]&.tap do |cursor_seq|
      @y, @x = cursor_seq.scan(/\d+/).map { _1.to_i - 1 }
    end
    @pty_output.write s
  end

  def timer(winch)
    puts 'WINCH not supported yet' if winch
    restore
  end

  def exit
    restore(force: true)
    Kernel.exit
  end
end

PTY.spawn command.join(' ') do |input, output, pid|
  visualizer = Visualizer.new(output)
  winch = false
  Signal.trap(:WINCH) { winch = true }
  Signal.trap(:INT) { Process.kill(:INT, pid) }

  queue = Queue.new
  Thread.new do
    loop do
      if input.wait_readable(0.2)
        queue << [:print, input.readpartial(1024).force_encoding('utf-8')]
      end
    end
  rescue
    queue << :exit
  end

  Thread.new do
    loop do
      queue << [:timer, winch]
      winch = false
      sleep 0.05
    end
  end

  Thread.new do
    STDIN.raw do
      loop do
        if STDIN.wait_readable(0.2)
          queue << [:input, STDIN.readpartial(1024)]
        end
      end
    end
  end

  loop do
    event, *args = queue.deq
    visualizer.send(event, *args)
  end
end
