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
      @line = @line + 1
    when s.scan(/\n/)
      @line = @line + 1
      @last_newline_pos = s.pos

    when s.scan(/\d+/)
      push_token(:NUMBER, s.matched.to_i)
    when s.scan(/int|void|if|else|while|for|return/)
      push_token(s.matched.upcase.to_sym, s.matched)
    when s.scan(/==|!=|<=|>=|&&|\|\|/)
      push_token(s.matched, s.matched)
    when s.scan(/;|,|\[|\]|\(|\)|\{|\}|\+|-|\*|\/|&|=|>|</)
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

def to_s(program)
  if program
    str = ""
    program.shift
    program.each do |decl|
      str += decl.to_s
    end
  end
  return str
end

private
def push_token(token_symbol, value)
  @q.push [token_symbol, {
    value: value,
    pos: [@line, @last_pos - @last_newline_pos]
  }]
end
end


class Node
  attr_accessor :type, :attr, :pos
  def initialize(type, attr, pos_node)
    @type = type
    @attr = attr
    @pos = pos 
  end

  def to_s
    case @type
    when :decl
      "#{@attr[:type].to_s} #{list_s @attr[:decls]};"

    when :declarator
      "#{list_s @attr[0]}"
    when :function_proto
      "#{@attr[:type]} #{@attr[:name].to_s} { #{@attr[:decl].to_s} }"
    when :function_decl
      "#{list_s @attr[:name]} #{@attr[:decl].to_s}"
    when :function_def
      "#{@attr[:type]} #{@attr[:name].to_s} #{@attr[:stmts].to_s}"
    when :param
      "#{@attr[:type]} #{list_s @attr[:name]}"

    when :if
      if @attr[:else_stmt]
        "if (#{list_s @attr[:cond]}) #{@attr[:stmt]} else #{@attr[:else_stmt]}"
      else
        "if (#{list_s @attr[:cond]}) #{@attr[:stmt]}"
      end
    when :while
      "while ( #{list_s @attr[:cond]} ) { #{@attr[:stmt].to_s} }"
    when :for
      "for (#{list_s @attr[:init]}; #{list_s @attr[:cond]}; #{list_s @attr[:iter]}) #{@attr[:stmt].to_s}"
    when :return 
      "return #{list_s @attr[0]}"

    when :compound_stmt
      "{ #{list_s @attr[:decls]} #{list_s @attr[:stmts]} }"
    when :expr
      "#{list_s @attr[0]};"

    when :assign
      "#{@attr[0].to_s} = #{@attr[1].to_s}"
    when :op, :logical_op, :rel_op, :eq_op
      "#{@attr[1].to_s} #{@attr[0]} #{@attr[2].to_s}"

    when :minus
      "-#{@attr[0]}"
    when :address
      "&#{@attr[0]}"
    when :pointer
      "*#{@attr[0]}"

    when :array
      "#{@attr[:name].to_s}[#{list_s @attr[:index]}]"
    when :call
      "#{@attr[:name]}(#{list_s @attr[:args]})"

    when :variable
      @attr[:name]
    when :number
      @attr[:value].to_s
    end
  end

  def list_s(list)
    str = ""
    if list
      str = list.map{|node| node.to_s }.join(" ")
    end
    return str
  end
end


parser = SmallC.new
if ARGV[0]
  file = File.open(ARGV[0]).read
  tree = parser.parse(file)
  pp tree
  print parser.to_s(tree)

else
  # repl
  while true
    puts
    print '? '
    str = gets.chop!
    break if /q/i =~ str
    tree = parser.parse(str)
    pp tree
    print parser.to_s(tree)
  end
end

