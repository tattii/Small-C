#
# Small-C CodeGenerate - アセンブリ生成
#

module SmallC
  class CodeGenerate
    Instr = Struct.new("Instr", :op, :args)
    Label = Struct.new("Label", :name)
    Dir   = Struct.new("Dir", :label, :args)
    Reg1   = '$t0'
    Reg2   = '$t1'
    Retreg = '$v0'

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
        Dir.new(".text", []),
        Dir.new(".globl", ["main"]),
        fundefs_code,
        convert_fundef(main),
        Instr.new('jal', ['$ra']),
        Dir.new(".data", []),
        Label.new("newline"),
        Dir.new(".ascii", ['"\n"'])
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
          Instr.new('syscall', []),
          Instr.new('li', ['$v0', 4]),
          Instr.new('la', ['$a0', 'newline']),
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
          Instr.new('lw', [Reg1, var_addr]),
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


    def self.print_code(instrs)
      codes = instrs.map do |instr|
        case instr.class.to_s.split("::").last
        when "Instr"
          "\t#{instr.op} #{instr.args.join(",")}"
        when "Label"
          "#{instr.name}:"
        when "Dir"
          "\t#{instr.label} #{instr.args.join(",")}"
        end
      end

      return codes.join("\n")
    end
  end
end
