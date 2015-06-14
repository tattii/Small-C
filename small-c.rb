require 'strscan'
require 'pp'
require './small-c.tab.rb'

class SmallC

def parse(str)
  @q = []
  @line = 0
  @last_newline_pos = 0
  @last_pos = 0
  s = StringScanner.new(str)

  until s.eos?
    case
	when s.scan(/[ \t]+/)
	when s.scan(/#.*?\n/)
	when s.scan(/\n/)
      @line++
      @last_newline_pos = s.pos

    when s.scan(/\d+/)
	  push_token(:NUMBER, s.matched.to_i)
	when s.scan(/int|void|if|else|while|for|return/)
      push_token(s.matched.upcase.to_sym, s.matched)
	when s.scan(/;|,|\[|\]|\(|\)|\{|\}|\+|-|\*|\/|&|=|>|</)
      push_token(s.matched, s.matched)
	when s.scan(/==|!=|<=|>=|&&|\|\|/)
      push_token(s.matched, s.matched)
    when s.scan(/\w+/)
	  push_token(:IDENT, s.matched)
    end
	@last_pos = s.pos
  end
  @q.push [false, '$end']
  pp @q
  @yydebug = true;
  do_parse
end

def next_token
  @q.shift
end

private
def push_token(token_symbol, value)
  @q.push [token_symbol, {
    value: value,
    line: @line,
    line_pos: @last_pos - @last_newline_pos
  }]
end
end

parser = SmallC.new
while true
  puts
  print '? '
  str = gets.chop!
  break if /q/i =~ str
  pp parser.parse(str)
end
