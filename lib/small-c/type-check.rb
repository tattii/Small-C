#
# Small-C Type Check - 型検査
#

# Small-C types
#   :void
#   :int
#   :int_
#   :int__

module SmallC
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
        unless expr.attr[0].type == :pointer ||
          expr.attr[0].attr[:name].kind == :var && expr.attr[0].type[0] != :array ||
          expr.attr[0].attr[:name].kind == :parm
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
            unless arg_type && arg_type == to_type(function.type[i+2])
              raise "[type error] argument type diffes: #{arg_type} #{expr.pos_s}"
            end
          end
        end

        return function.type[1]

      when :variable
        return to_type(expr.attr[:name].type)

      when :number
        return :int

      when :expr
        return check_type_expr_stmt(expr.attr[0])
      end
    end

    def to_type(type)
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
    end
  end
end
