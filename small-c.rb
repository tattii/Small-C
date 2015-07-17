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
      ast = parser.parse(str)
      pp ast
      p to_s(ast)
      symbol = SmallC::SymbolAnalyze.new
      symbol.analyze(ast)
      pp ast
      type_check = SmallC::TypeCheck.new
      type_check.well_typed?(ast)
      p to_s(ast)

      intermed_code = IntermedCode.new.convert(ast)
      AssignAddr.new.assign(intermed_code)
      pp intermed_code

      code = CodeGenerate.new.convert(intermed_code)
      pp code
    rescue Racc::ParseError => e
      puts e.message
    rescue RuntimeError => e
      puts e.message
    end
  end

  class Scan
    def scan(str)
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

      return @q
    end

    private
    def push_token(token_symbol, value)
      @q.push [token_symbol, {
        value: value,
        pos: [@line, @last_pos - @last_newline_pos]
      }]
    end
  end

  class Parse
    def parse(str)
      scanner = Scan.new
      @q = scanner.scan(str)
      @yydebug = true
      do_parse # racc parse
    end

    def next_token
      @q.shift
    end
  end

  # プログラム文字列化
  def self.to_s(program)
    if program
      str = ""
      program.each do |decl|
        str += decl.to_s
      end
    end
    return str
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
    attr_accessor :name, :lev, :kind, :type, :offset
    def initialize(name, lev, kind, type)
      @name = name
      @lev = lev
      @kind = kind
      @type = type
    end

    def to_s
      "{name:#{name}, lev:#{lev}, kind:#{kind}, type:#{type}}"
    end

    def to_addr
      "#{offset}($fp)"
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
        w2 = (node.attr[:stmts]) ? well_typed?(node.attr[:stmts]) : true

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
        if check_type(expr.attr[1]) == :int && check_type(expr.attr[2]) == :int
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
        elsif type[0] == :pointer
          if type[1] == :int
            return :int_
          else
            raise "[type error] invalid *pointer type: #{type[1]} #{expr.pos_s}"
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


  class IntermedCode
    def convert(prog)
      @temp_num = 0
      @temp_decls = []
      codes = []
      prog.each do |node|
        codes << convert_prog(node)
      end
      return codes.flatten
    end

    def convert_prog(node)
      case node.type
      when :decl
        return node.attr[:decls].map do |decl|
          {type: :vardecl, var: decl}
        end

      when :function_def
        var = node.attr[:decl].attr[:name]
        params = node.attr[:decl].attr[:params].map do |param| 
          {type: :vardecl, var: param.attr[:name]}
        end
        body = convert_stmt(node.attr[:stmts])
        return {type: :fundef,  var: var, parms: params, body: body}
      end
    end

    def convert_stmt(node)
      case node.type
      when :compound_stmt
        decls = node.attr[:decls].map do |decl|
          decl.attr[:decls].map do |d|
            {type: :vardecl, var: d}
          end
        end
        @temp_decls.push []
        stmts = node.attr[:stmts].map do |stmt|
          convert_stmt(stmt)
        end
        temp = @temp_decls.pop
        return {type: :compdstmt, decls: decls.flatten + temp, stmts: stmts.flatten}


      when :skip
        return {type: :emptystmt}

      when :expr
        var = gen_decl()
        return [
          node.attr[0].map {|expr| convert_expr(expr, var)},
        ]

      when :if
        var = gen_decl()
        stmt1 = convert_stmt(node.attr[:stmt])
        stmt2 = convert_stmt(node.attr[:else_stmt]) if node.attr[:else_stmt]
        return [
          node.attr[:cond].map {|expr| convert_expr(expr, var)},
          {type: :ifstmt, var: var, stmt1: stmt1, stmt2: stmt2}
        ]

      when :while
        var = gen_decl()
        stmt = convert_stmt(node.attr[:stmt])
        return [
          node.attr[:cond].map {|expr| convert_expr(expr, var)},
          {type: :whilestmt, var: var, stmt: stmt}
        ]

      when :return
        var = gen_decl()
        return [
          node.attr[:cond].map {|expr| convert_expr(expr, var)},
          {type: :returnstmt, var: var}
        ]

      end
    end

    def convert_expr(node, dest)
      case node.type
      when :assign
        if node.attr[0].type == :variable
          x = node.attr[0].attr[:name]
          e = node.attr[1]
          return [
            convert_expr(e, x),
            {type: :letstmt, var: dest, exp: x}
          ]

        elsif node.attr[0].type == :pointer
          address = node.attr[0]
          exp = node.attr[1]
          t1 = gen_decl()
          t2 = gen_decl()
          return [
            convert_address(address, t1),
            convert_expr(exp, t2),
            {type: :writestmt, dest: t1, src: t2},
            {type: :letstmt, var: dest, exp: t2}
          ]
        end

      when :op
        op = node.attr[0]
        e1 = node.attr[1]
        e2 = node.attr[2]
        d1 = gen_decl()
        d2 = gen_decl()
        d3 = gen_decl()

        return [
          convert_expr(e1, d1),
          convert_expr(e2, d2),
          {type: :letstmt, var: dest, exp: {type: :aopexp, op: op, var1: d1, var2: d2}}
        ]

      when :eq_op, :rel_op
        op = node.attr[0]
        e1 = node.attr[1]
        e2 = node.attr[2]
        d1 = gen_decl()
        d2 = gen_decl()

        return [
          convert_expr(e1, d1),
          convert_expr(e2, d2),
          {type: :letstmt, var: dest, exp: {type: :relopexp, op: op, var1: d1, var2: d2}}
        ]

      when :logical_op
        op = node.attr[0]
        e1 = node.attr[1]
        e2 = node.attr[2]
        d1 = gen_decl()
        d2 = gen_decl()
        res = gen_decl()

        if op == "&&"
          return [
            convert_expr(e1, d1),
            {type: :ifstmt, var: d1, 
              stmt1: {type: :compdstmt, decls: [], 
                  stmts: [
                  convert_expr(e2, d2),
                  {type: :ifstmt, var: d2,
                    stmt1: {type: :letstmt, var: dest, exp: {type: :intexp, num: 1}},
                    stmt2: {type: :letstmt, var: dest, exp: {type: :intexp, num: 0}},
                  }
                ].flatten
              },
              stmt2: {type: :letstmt, var: dest, exp: {type: :intexp, num: 0}}
            }
          ]
        elsif op == "||"
          return [
            convert_expr(e1, d1),
            {type: :ifstmt, var: d1, 
              stmt1: {type: :letstmt, var: dest, exp: {type: :intexp, num: 1}},
              stmt2: {type: :compdstmt, decls: [], 
                  stmts: [
                  convert_expr(e2, d2),
                  {type: :ifstmt, var: d2,
                    stmt1: {type: :letstmt, var: dest, exp: {type: :intexp, num: 1}},
                    stmt2: {type: :letstmt, var: dest, exp: {type: :intexp, num: 0}},
                  }
                ].flatten
            }}
          ]
        end

      when :address
        t = gen_decl()
        return [
          convert_expr(node.attr[0], t),
          {type: :letstmt, var: dest, exp: {type: :addrexp, var: t}}
        ]

      when :pointer
        t = gen_decl()
        return [
          convert_expr(node.attr[0], t),
          {type: :readstmt, dest: dest, src: t}
        ]

      when :call
        if node.attr[:name].name == "print"
          t = gen_decl()
          return [
            convert_expr(node.attr[0], t),
            {type: :printstmt, var: t}
          ]
        else
          args = []
          codes = []
          node.attr[:args].each do |arg|
            t = gen_decl()
            args.push t
            codes.push convert_expr(arg, t)
          end
          return [
            codes,
            {type: :callstmt, dest: dest, f: node.attr[:name], vars: args}
          ]
        end

      when :variable
        exp = {type: :varexp, var: node.attr[:name]}
        return {type: :letstmt, var: dest, exp: exp}

      when :number
        exp = {type: :intexp, num: node.attr[:value]}
        return {type: :letstmt, var: dest, exp: exp}

      end
    end

    def convert_address(pointer, dest)
      if pointer.attr[0].type == :op
        node = pointer.attr[0]
        op = node.attr[0]
        e1 = node.attr[1]
        e2 = node.attr[2]
        d1 = gen_decl()
        d2 = gen_decl()
        d3 = gen_decl()

        if (op == '+' || op == '-') && 
          e1.type == :variable &&
          (e1.attr[:name].type[0] == :array || e1.attr[:name].type[0] == :pointer)
          addr = {type: :addrexp, exp: {type: :varexp, var: e1.attr[:name].name}}
          return [
            {type: :letstmt, var: d1, exp: addr},
            convert_expr(e2.attr[0][0], d2),
            {type: :letstmt, var: d3, exp:
              {type: :aopexp, op: '*', var1: d2, var2: {type: :intexp, num: 4}}},
            {type: :letstmt, var: dest, exp: 
              {type: :aopexp, op: op, var1: d1, var2: d3}}
          ]
        end
      end
    end

    def gen_decl
      temp_name = "_t" + @temp_num.to_s
      t = Object.new(temp_name, -1, :var, :temp)
      @temp_decls.last.push({type: :vardecl, var: t})
      @temp_num += 1
      return t
    end
  end



  class AssignAddr
    def assign(intermed_code)
      intermed_code.each do |code|
        if code[:type] == :fundef
          assign_fundef(code)
        end
      end
    end

    def assign_fundef(fundef)
      parm_offset = 0
      @offset = 4
      fundef[:parms].each do |parm|
        parm_offset += 4
        parm[:var].offset = parm_offset
      end
      assign_compdstmt(fundef[:body])
      fundef[:localvarsize] = 4 - @offset
    end

    def assign_compdstmt(compd)
      compd[:decls].each do |decl|
        if decl[:var].type[0] == :array
          @offset += -4 * decl[:var].type[2]
          decl[:var].offset = @offset

        else
          @offset += -4
          decl[:var].offset = @offset
        end
      end

      compd[:stmts].each do |stmt|
        case stmt[:type]
        when :compdstmt
          assign_compdstmt(stmt)

        when :ifstmt
          assign_compdstmt(stmt[:stmt1]) if stmt[:stmt1] && stmt[:stmt1][:type] == :compdstmt
          assign_compdstmt(stmt[:stmt2]) if stmt[:stmt2] && stmt[:stmt2][:type] == :compdstmt

        when :whilestmt
          assign_compdstmt(stmt[:stmt]) if stmt[:stmt] && stmt[:stmt][:type] == :compdstmt

        end
      end

    end
  end

  
  class CodeGenerate
    Instr = Struct.new("Instr", :op, :args)
    Label = Struct.new("Label", :name)
    Dir   = Struct.new("Dir", :label, :args)
    Reg1   = '$t0'
    Reg2   = '$t1'
    Retreg = '$v0'
    Fpreg  = '$fp'

    def initialize
      @labels = 0
    end

    def convert(intermed_code)
      # 整理
      global_vars = []
      fundefs = []
      main = nil

      intermed_code.each do |intmd|
        if intmd[:type] == :vardecl
          global_vars.push intmd
        elsif intmd[:type] == :fundef
          if intmd[:var].name == "main"
            main = intmd
          else
            fundefs.push intmd
          end
        end
      end

      fundefs_code = fundefs.map {|fundef| convert_fundef(fundef)}.flatten

      if main == nil
        raise "[error] main function undefined"
      end
      
      return [
        Dir.new(".text", nil),
        Dir.new(".global", ["main"]),
        fundefs_code,
        convert_fundef(main),
      ].flatten
    end

    def convert_fundef(intmd)
      f = intmd[:var].name
      stmts = intmd[:body]
      args = intmd[:parms]
      localvarsize = intmd[:localvarsize]
      argsize = 4 * args.length
      code = convert_stmt(stmts, localvarsize, argsize)

      return [
        Label.new(f),
        savecode(localvarsize, argsize),
        code
      ].flatten
    end

    # localvarsize, argsize => return
    def convert_stmt(intmd, localvarsize, argsize)
      case intmd[:type]
      when :compdstmt
        code = intmd[:stmts].map {|stmt| convert_stmt(stmt, localvarsize, argsize) }
        return code.flatten

      when :emptystmt
        return [ Instr.new('nop', []) ]

      when :ifstmt
        cond_addr = intmd[:var].to_addr
        code1 = intmd[:stmt1] ? convert_stmt(intmd[:stmt1], localvarsize, argsize) : []
        code2 = intmd[:stmt2] ? convert_stmt(intmd[:stmt2], localvarsize, argsize) : []
        label1 = next_label()
        label2 = next_label()
        return [
          Instr.new('lw', [Reg1, cond_addr]),
          Instr.new('beqz', [Reg1, label1]),
          code1,
          Instr.new('j', [label2]),
          Label.new(label1),
          code2,
          Label.new(label2)
        ].flatten

      when :whilestmt
        cond_addr = intmd[:var].to_addr
        code = intmd[:stmt] ? convert_stmt(intmd[:stmt], localvarsize, argsize) : []
        label1 = next_label()
        label2 = next_label()
        return [
          Instr.new('lw', [Reg1, cond_addr]),
          Instr.new('beqz', [Reg1, label2]),
          Label.new(label1),
          code,
          Instr.new('lw', [Reg1, cond_addr]),
          Instr.new('beqz', [Reg1, label2]),
          Instr.new('j', [label1]),
          Label.new(label2)
        ].flatten

      when :returnstmt
        addr = intmd[:var].to_addr
        return [
          Instr.new('lw', [Reg1, addr]),
          Instr.new('move', [Retreg, Reg1]),
          restorecode(localvarsize, argsize)
        ]

      when :callstmt
        dest_addr = intmd[:dest].to_addr
        f = intmd[:f].name
        args = intmd[:vars]
        offset_sp = -4 * (args.length + 1)

        # $spから逆順にストア
        args_code = args.map do |arg|
          offset_sp += 4
          return [
            Instr.new('lw', [Reg1, arg.to_addr]),
            Instr.new('sw', [Reg1, "#{offset_sp}($sp)"])
          ]
        end

        return [
          args_code,
          Instr.new('jal', [f]),
          Instr.new('sw', [Retreg, dest_addr])
        ].flatten


      when :printstmt
        src_addr = intmd[:var].to_addr
        return [
          Instr.new('li', ['$v0', 1]),
          Instr.new('lw', [Reg1, src_addr]),
          Instr.new('move', ['$a0', Reg1]),
          Instr.new('syscall', [])
        ]

      when :letstmt
        return convert_expr(intmd[:exp], intmd[:var])

      when :writestmt
        dest_addr = intmd[:dest].to_addr
        src_addr = intmd[:src].to_addr
        return [
          Instr.new('lw', [Reg1, src_addr]),
          Instr.new('lw', [Reg2, dest_addr]),
          Instr.new('sw', [Reg1, "0(#{Reg2})"])
        ]

      when :readstmt
        dest_addr = intmd[:dest].to_addr
        src_addr = intmd[:src].to_addr
        return [
          Instr.new('lw', [Reg1, src_addr]),
          Instr.new('lw', [Reg1, "0(#{Reg1})"]),
          Instr.new('sw', [Reg1, dest_addr])
        ]

      end
    end

    def convert_expr(intmd, dest)
      case intmd[:type]
      when :varexp
        src_addr = intmd[:var].to_addr
        dest_addr = dest.to_addr
        return [
          Instr.new('lw', [Reg1, src_addr]),
          Instr.new('sw', [Reg1, dest_addr])
        ]

      when :intexp
        num = intmd[:num] 
        addr = dest.to_addr
        return [
          Instr.new('li', [Reg1, num]),
          Instr.new('sw', [Reg1, addr])
        ]

      when :aopexp
        aop_mips = {
          '+' => 'add',
          '-' => 'sub',
          '*' => 'mul',
          '/' => 'div'
        };
        op = aop_mips[intmd[:op]]
        addr1 = intmd[:var1].to_addr
        addr2 = intmd[:var2].to_addr
        dest_addr = dest.to_addr
        return [
          Instr.new('lw', [Reg1, addr1]),
          Instr.new('lw', [Reg2, addr2]),
          Instr.new(op, [Reg1, Reg1, Reg2]),
          Instr.new('sw', [Reg1, dest_addr])
        ]

      when :relopexp
        relop_mips = {
          '==' => 'seq',
          '!=' => 'sne',
          '>'  => 'sgt',
          '<'  => 'slt',
          '>=' => 'sge',
          '<=' => 'sle'
        };
        op = relop_mips[intmd[:op]]
        addr1 = intmd[:var1].to_addr
        addr2 = intmd[:var2].to_addr
        dest_addr = dest.to_addr
        return [
          Instr.new('lw', [Reg1, addr1]),
          Instr.new('lw', [Reg2, addr2]),
          Instr.new(op, [Reg1, Reg1, Reg2]),
          Instr.new('sw', [Reg1, dest_addr])
        ]

      when :addrexp
        var_addr = intmd[:var].to_addr
        dest_addr = dest.to_addr

        return [
          Instr.new('li', [Reg1, var_addr]),
          Instr.new('sw', [Reg1, dest_addr])
        ]
      end
    end


    def next_label
      label = "L" + @labels.to_s
      @labels += 1
      return label.to_sym
    end

    def savecode(localvarsize, argsize)
      localsize = localvarsize + 4*2
      framesize = localsize + argsize

      return [
        Instr.new('subu', ['$sp', '$sp', framesize]),
        Instr.new('sw', ['$ra', '4($sp)']),
        Instr.new('sw', ['$fp', '0($sp)']),
        Instr.new('addiu', ['$fp', '$sp', localsize - 4])
      ]
    end

    def restorecode(localvarsize, argsize)
      localsize = localvarsize + 4*2
      framesize = localsize + argsize

      return [
        Instr.new('lw', ['$ra', '4($sp)']),
        Instr.new('lw', ['$fp', '0($sp)']),
        Instr.new('addiu', ['$sp', '$sp', framesize]),
        Instr.new('jr', ['$ra'])
      ]
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
    break if /^q$/i =~ str
    SmallC::compile(str)
  end
end

