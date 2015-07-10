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
      type_check = SmallC::TypeCheck.new
      type_check.well_typed?(tree)
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
        @ids = env[0].ids.clone
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
      @env.add("print", Object.new(print, 0, :fun, [:fun, :void, :int]))
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
            type = [:array, type, decl[1]]
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
        type, name = analyze_function_decl(node)

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
          node.attr[:decl].attr[:name] = obj
        end

      when :function_def
        type, name = analyze_function_decl(node)

        if defined = @env.lookup(name)
          if defined.kind != :proto
            raise "[error] already defined #{name} #{node.pos_s}"
          end
        end

        # declare
        obj = Object.new(name, @level, :fun, type)
        @env.add(name, obj)
        node.attr[:decl].attr[:name] = obj

        analyze_node(node.attr[:stmts])

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

        analyze(node.attr[:args]) if node.attr[:args]
      
      # block level
      when :compound_stmt
        level_stash = @level
        @level = (@level == 0) ? 2 : @level+1
        env_stash = @env
        @env = Env.new(@env)

        analyze(node.attr[:decls]) if node.attr[:decls]
        analyze(node.attr[:stmts]) if node.attr[:stmts]

        @level = level_stash
        @env = env_stash

      # round tree nodes
      else
        if node.attr.is_a?(Array)
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

    def analyze_function_decl(node)
      r_type = node.attr[:type]
      decl = node.attr[:decl]
      name = nil

      if decl.attr[:name][0] == "*"
        name = decl.attr[:name][1]
        r_type = [:pointer, r_type]
      else
        name = decl.attr[:name][0]
      end

      # params
      type = [:fun, r_type]
      if decl.attr[:params]
        analyze(decl.attr[:params])
        decl.attr[:params].each do |param|
          type.push param.attr[:name].type
        end
      end

      return type, name
    end
  end


  #
  # 型検査
  #
  class TypeCheck
    def well_typed?(list)
      list.each do |node|
        well_typed_node?(node)
      end
      return true
    end

    def well_typed_node?(node)
      case node.type
      when :function_def
        @function_return_type = node.attr[:decl].attr[:name].type[1]
        well_typed_node?(node.attr[:stmts])
        @function_return_type = nil

      when :skip
        return true

      when :expr
        if check_type_expr_stmt(node.attr[0]) != nil
          return true
        else
          raise "[type error] wrong expression type #{node.pos_s}"
        end

      when :if
        if check_type_expr_stmt(node.attr[:cond]) == :int \
          && well_typed_node?(node.attr[:stmt]) \
          && (node.attr[:else_stmt] ? well_typed_node?(node.attr[:else_stmt]) : true)
          return true
        else
        raise "[type error] if condition type must be int #{node.pos_s}"
        end

      when :while
        if check_type_expr_stmt(node.attr[:cond]) == :int \
          && well_typed_node?(node.attr[:stmt])
          return true
        else
          raise "[type error] while condition type must be int #{node.pos_s}"
        end

      when :return
        if @function_return_type == :void
          if node.attr[0]
            raise "[type error] return type is void #{node.pos_s}"
          else
            return true
          end
        else
          r_type = check_type_expr_stmt(node.attr[0])
          if r_type == nil
            raise "[type error] wrong return type #{node.pos_s}"
          elsif r_type != @function_return_type
            raise "[type error] return type differs: #{r_type} #{node.pos_s}"
          else
            return true
          end
        end

      when :compound_stmt
        w1 = (node.attr[:decls]) ? well_typed?(node.attr[:decls]) : true
        w2 = well_typed?(node.attr[:stmts]) if node.attr[:stmts]
        return w1 || w2

      end
    end

    #
    # 式文 expr_stmt の型
    # :void
    # :int
    # :int_
    # :int__
    #
    def check_type_expr_stmt(expr_stmt)
      last_type = nil
      expr_stmt.each do |expr|
        last_type = check_type(expr)
        if last_type == nil
          raise "[type error] wrong expression type #{expr.pos_s}"
        end
      end
      return last_type
    end

    def check_type(expr)
      case expr.type
      when :assign
        # object check
        unless expr.attr[0].type == :pointer \
          || expr.attr[0].attr[:name].kind == :var && expr.attr[0].type[0] != :array
          raise "[object error] invalid assign object #{expr.pos_s}"
        end

        e1_type = check_type(expr.attr[0])
        e2_type = check_type(expr.attr[1])
        if e1_type == e2_type
          return e2_type
        else
          raise "[type error] assign type differs: #{e1_type},#{e2_type} #{expr.pos_s}"
        end

      when :logical_op
        if check_type(epxr.attr[1]) == :int && check_type(expr.attr[2]) == :int
          return :int
        else
          raise "[type error] #{expr.attr[0]} operand type must be int #{expr.pos_s}"
        end

      when :eq_op, :rel_op
        e1_type = check_type(expr.attr[1])
        e2_type = check_type(expr.attr[2])
        if e1_type == e2_type
          return :int
        else
          raise "[type error] #{expr.attr[0]} type differs #{expr.pos_s}"
        end

      when :op
        op = expr.attr[0]
        e1_type = check_type(expr.attr[1])
        e2_type = check_type(expr.attr[2])
        if e1_type == :int && e2_type == :int
          return :int
        elsif op == '+' || op == '-'
          if   e1_type == :int_ && e2_type == :int \
            || e2_type == :int_ && e1_type == :int
            return :int_
          elsif e1_type == :int__ && e2_type == :int \
            ||  e2_type == :int__ && e1_type == :int
            return :int__
          end
        else
          raise "[type error] #{op} type differs: #{e1_type},#{e2_type} #{expr.pos_s}"
        end

      when :address
        # object check
        if expr.attr[0].kind != :var
          raise "[object error] &address operand must be var #{expr.pos_s}"
        end

        if check_type(expr.attr[0]) == :int
          return :int
        else
          raise "[type error] &address type must be int #{expr.pos_s}"
        end

      when :pointer
        e_type = check_type(expr.attr[0])
        if e_type == :int_
          return :int
        elsif e_type == :int__
          return :int_
        else
          raise "[type error] invalid *pointer type: #{e_type} #{expr.pos_s}"
        end
        
      when :call
        function = expr.attr[:name]
        args = expr.attr[:args]

        if (args ? args.length : 0) != function.type.length-2
          raise "[error] wrong number of arguments #{expr.pos_s}"
        end

        if args
          args.each_with_index do |arg, i|
            arg_type = check_type(arg)
            unless arg_type && arg_type == function.type[i+2]
              raise "[type error] argument type diffes: #{arg_type} #{expr.pos_s}"
            end
          end
        end

        return function.type[1]

      when :variable
        type = expr.attr[:name].type
        if type[0] == :array
          if type[1] == :int
            return :int_
          elsif type[1] == :int_
            return :int__
          else
            raise "[type error] invalid array type: #{type[1]} #{expr.pos_s}"
          end
        end
        return type

      when :number
        return :int

      when :expr
        return check_type_expr_stmt(expr.attr[0])
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

