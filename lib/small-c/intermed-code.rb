#
# Small-C IntermedCode - 中間表現
#
# 中間表現
#　{type: ..., var: ..., ... }
#

module SmallC
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
        @temp_num = 0
        var = node.attr[:decl].attr[:name]
        params = node.attr[:decl].attr[:params].map do |param| 
          {type: :vardecl, var: param.attr[:name]}
        end
        body = convert_stmt(node.attr[:stmts])
        return {type: :fundef,  var: var, parms: params, body: body}

      when :function_proto
        return []
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
        ].flatten

      when :if
        var = gen_decl()
        stmt1 = convert_stmt(node.attr[:stmt])
        stmt2 = convert_stmt(node.attr[:else_stmt]) if node.attr[:else_stmt]
        return [
          node.attr[:cond].map {|expr| convert_expr(expr, var)},
          {type: :ifstmt, var: var, stmt1: stmt1, stmt2: stmt2}
        ].flatten

      when :while
        var = gen_decl()
        stmt = convert_stmt(node.attr[:stmt])
        cond = node.attr[:cond].map {|expr| convert_expr(expr, var)}
        return [
          {type: :whilestmt, var: var, cond: cond.flatten, stmt: stmt}
        ]

      when :return
        var = gen_decl()
        return [
          node.attr[0].map {|expr| convert_expr(expr, var)},
          {type: :returnstmt, var: var}
        ].flatten

      end
    end

    def convert_expr(node, dest)
      case node.type
      when :expr
        t = nil
        code = node.attr[0].map do |expr|
          t = gen_decl()
          convert_expr(expr, t)
        end
        code.push({type: :letstmt, var: dest, exp: {type: :varexp, var: t}}) if t
        return code.flatten

      when :assign
        if node.attr[0].type == :variable
          x = node.attr[0].attr[:name]
          e = node.attr[1]
          t1 = gen_decl()
          t2 = gen_decl()

          return [
            convert_expr(e, t1),
            {type: :letstmt, var: t2, exp: {type: :addrexp, var: x}},
            {type: :writestmt, dest: t2, src: t1},
            {type: :letstmt, var: dest, exp: {type: :varexp, var: t1}}
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
            {type: :letstmt, var: dest, exp: {type: :varexp, var:t2}}
          ]

        end

      when :op
        op = node.attr[0]
        e1 = node.attr[1]
        e2 = node.attr[2]
        d1 = gen_decl()
        d2 = gen_decl()
        d3 = gen_decl()

        if e1.type == :variable && e1.attr[:name].type[0] == :pointer
          d4 = gen_decl()
          if (op == '+' || op == '-')
            addr = {type: :addrexp, var: e1.attr[:name]}
            if e2.type == :number
              return [
                {type: :letstmt, var: d1, exp: addr},
                convert_expr(e2, d2),
                {type: :letstmt, var: d3, exp: {type: :intexp, num: 4}},
                {type: :letstmt, var: d4, exp: 
                  {type: :aopexp, op: '*', var1: d2, var2: d3}},
                {type: :letstmt, var: dest, exp: 
                  {type: :aopexp, op: op, var1: d1, var2: d4}}
              ]
            else
              return [
                {type: :letstmt, var: d1, exp: addr},
                convert_expr(e2.attr[0][0], d2),
                {type: :letstmt, var: d3, exp: {type: :intexp, num: 4}},
                {type: :letstmt, var: d4, exp: 
                  {type: :aopexp, op: '*', var1: d2, var2: d3}},
                {type: :letstmt, var: dest, exp: 
                  {type: :aopexp, op: op, var1: d1, var2: d4}}
              ]
            end
          end
        else
          return [
            convert_expr(e1, d1),
            convert_expr(e2, d2),
            {type: :letstmt, var: dest, exp: {type: :aopexp, op: op, var1: d1, var2: d2}}
          ]
        end

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
        var = node.attr[0].attr[:name]
        return [
          {type: :letstmt, var: dest, exp: {type: :addrexp, var: var}}
        ]

      when :pointer
        t = gen_decl()
        return [
          convert_address(node, t),
          {type: :readstmt, dest: dest, src: t}
        ]

      when :call
        if node.attr[:name].name == "print"
          t = gen_decl()
          return [
            convert_expr(node.attr[:args][0], t),
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
      if pointer.attr[0].type == :variable
        var = {type: :addrexp, var: pointer.attr[0].attr[:name]}
        return [
          {type: :letstmt, var: dest, exp: var}
        ]

      elsif pointer.attr[0].type == :op
        node = pointer.attr[0]
        op = node.attr[0]
        e1 = node.attr[1]
        e2 = node.attr[2]
        d1 = gen_decl()
        d2 = gen_decl()
        d3 = gen_decl()
        d4 = gen_decl()

        if (op == '+' || op == '-') && 
          e1.type == :variable &&
          (e1.attr[:name].type[0] == :array || e1.attr[:name].type[0] == :pointer)
          addr = {type: :addrexp, var: e1.attr[:name]}
          return [
            {type: :letstmt, var: d1, exp: addr},
            convert_expr(e2.attr[0][0], d2),
            {type: :letstmt, var: d3, exp: {type: :intexp, num: 4}},
            {type: :letstmt, var: d4, exp: 
              {type: :aopexp, op: '*', var1: d2, var2: d3}},
            {type: :letstmt, var: dest, exp: 
              {type: :aopexp, op: op, var1: d1, var2: d4}}
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

end
