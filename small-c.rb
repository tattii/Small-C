#
# SmallC Compiler 
#

require 'strscan'
require 'pp'
require './small-c.tab.rb'

module SmallC

  def self.compile(str)
    begin 
      parser = SmallC::Parse.new
      tree = parser.parse(str)
      pp tree
      p parser.to_s(tree)
      symbol = SmallC::SymbolAnalyze.new
      symbol.analyze(tree)
      pp tree
      p parser.to_s(tree)
    rescue Racc::ParseError => e
      puts e.message
    rescue RuntimeError => e
      puts e.message
    end
  end

  class Parse
    def parse(str)
      @q = []
      @line = 1
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
      # pp @q
      @yydebug = true
      do_parse # racc parse
    end

    def next_token
      @q.shift
    end

    def to_s(program)
      if program
        str = ""
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
    def initialize(type, attr, pos)
      @type = type
      @attr = attr
      @pos = pos 
    end

    def to_s
      case @type
      when :decl
        "#{@attr[:type].to_s} #{list_s @attr[:decls]};"

      when :declarator
        "#{list_s @attr.flatten}"
      when :function_proto
        "#{@attr[:type]} #{@attr[:decl].to_s}"
      when :function_decl
        "#{name_s @attr[:name]}(#{list_s @attr[:params]})"
      when :function_def
        "#{@attr[:type]} #{@attr[:decl].to_s} #{@attr[:stmts].to_s}"
      when :param
        "#{@attr[:type]} #{name_s @attr[:name]}"

      when :if
        "if (#{list_s @attr[:cond]}) #{@attr[:stmt].to_s} else #{@attr[:else_stmt].to_s}"
      when :while
        "while ( #{list_s @attr[:cond]} ) #{@attr[:stmt].to_s}"
      when :return 
        "return #{list_s @attr[0]}"

      when :compound_stmt
        "{ #{list_s @attr[:decls]} #{list_s @attr[:stmts]} }"
      when :expr
        "#{list_s @attr[0]}"

      when :assign
        "#{@attr[0].to_s} = #{@attr[1].to_s}"
      when :op, :logical_op, :rel_op, :eq_op
        "#{@attr[1].to_s} #{@attr[0]} #{@attr[2].to_s}"

      when :address
        "&#{@attr[0]}"
      when :pointer
        "*(#{@attr[0]})"

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

    def name_s(name)
      if name.class == Object
        name.to_s
      else
        list_s name
      end
    end

    def pos_s
      "(at #{@pos[0]}:#{@pos[1]})"
    end
  end

  class Object
    attr_accessor :name, :lev, :kind, :type
    def initialize(name, lev, kind, type)
      @name = name
      @lev = lev
      @kind = kind
      @type = type
    end

    def to_s
      "{name:#{name}, lev:#{lev}, kind:#{kind}, type:#{type}}"
    end
  end


  class Env
    attr_reader :ids
    def initialize(*env)
      if env[0]
        @ids = env[0].ids
      else
        @ids = {}
      end
    end

    def lookup(id)
      return @ids[id]
    end

    def add(id, data)
      @ids[id] = data
    end
  end


  class SymbolAnalyze
    def initialize
      @env = Env.new
      @level = 0
    end

    def analyze(list)
      list.each do |node|
        analyze_node(node)
      end
    end

    def analyze_node(node)
      case node.type
      when :decl
        type_decls = node.attr[:type]
        node.attr[:decls].each_with_index do |d, i|
          decl = d.attr
          type = type_decls

          # pointer
          if decl[0] == "*"
            type = [:pointer, type]
            decl = decl[1]
          end

          name = decl[0]

          # array
          if decl[1]
            type = [:array, type]
          end

          if defined = @env.lookup(name)
            if defined.kind == :fun \
              || defined.kind == :proto \
              || defined.lev == 0 \
              || defined.kind == :var && defined.lev == @level
              raise "[error] already defined #{name} #{node.pos_s}"
            elsif defined.kind == :parm
              warn "[warn] param #{name} defined #{node.pos_s}"
            end
          end

          # declare
          obj = Object.new(name, @level, :var, type)
          @env.add(name, obj)
          node.attr[:decls][i] = obj
        end

      when :param
        name = node.attr[:name]
        type = node.attr[:type]
        if name[0] == "*"
          name = name[1]
          type = [:pointer, type]
        else
          name = name[0]
        end

        if defined = @env.lookup(name)
          if defined.kind == :param
            raise "[error] already defined #{name} #{node.pos_s}"
          end
        end

        # declare
        obj = Object.new(name, 1, :parm, type)
        @env.add(name, obj)
        node.attr[:name] = obj

      when :function_proto
        type = node.attr[:type]
        decl = node.attr[:decl]
        name

        if decl.attr[:name][0] == "*"
          name = decl.attr[:name][1]
          type = [:pointer, type]
        else
          name = decl.attr[:name][0]
        end

        if defined = @env.lookup(name)
          if defined.kind == :fun || defined.kind == :proto
            if type != defined.type
              raise "[error] proto: type differs #{name} #{node.pos_s}"
            end
          else
            raise "[error] already defined #{name} #{node.pos_s}"
          end
        else
          # declare
          obj = Object.new(name, @level, :proto, type)
          @env.add(name, obj)
          decl.attr[:name] = obj
        end

      when :function_def
        type = node.attr[:type]
        decl = node.attr[:decl]
        name

        if decl.attr[:name][0] == "*"
          name = decl.attr[:name][1]
          type = [:pointer, type]
        else
          name = decl.attr[:name][0]
        end

        if defined = @env.lookup(name)
          if defined.kind != :proto
            raise "[error] already defined #{name} #{node.pos_s}"
          end
        end

        # declare
        obj = Object.new(name, @level, :fun, type)
        @env.add(name, obj)
        decl.attr[:name] = obj

      when :variable
        name = node.attr[:name]

        if defined = @env.lookup(name)
          if defined.kind == :var || defined.kind == :parm
            node.attr[:name] = defined
          else
            raise "[error] #{name} is function #{node.pos_s}"
          end
        else
          raise "[error] undefined #{name} #{node.pos_s}"
        end

      when :call
        name = node.attr[:name]

        if defined = @env.lookup(name)
          if defined.kind == :fun || defined.kind == :proto
            node.attr[:name] = defined
          else
            raise "[error] #{name} is not function #{node.pos_s}"
          end
        else
          raise "[error] undefined #{name} #{node.pos_s}"
        end
      end
      
      # block level
      if node.type == :compound_stmt
        level_stash = @level
        @level = (@level == 0) ? 2 : @level+1
        env_stash = @env
        @env = Env.new(@env)

        analyze(node.attr[:decls]) if node.attr[:decls]
        analyze(node.attr[:stmts]) if node.attr[:stmts]

        @level = level_stash
        @env = env_stash

      # round tree nodes
      elsif node.attr.is_a?(Array)
        node.attr.each do |e|
          if e.is_a?(Array) && e[0].is_a?(Node)
            analyze(e)
          elsif e.is_a?(Node)
            analyze_node(e)
          end
        end
      elsif node.attr.is_a?(Hash)
        node.attr.each_value do |v|
          if v.is_a?(Array) && v[0].is_a?(Node)
            analyze(v)
          elsif v.is_a?(Node)
            analyze_node(v)
          end
        end
      end
    end

  end

end


#
# test
# 

# file
if ARGV[0]
  str = File.open(ARGV[0]).read
  SmallC::compile(str)

# repl
else
  while true
    puts
    print '? '
    str = gets.chop!
    break if /q/i =~ str
    SmallC::compile(str)
  end
end

