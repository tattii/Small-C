#
# Small-C SymbolAnalyze 
#

module SmallC
  class SymbolAnalyze
    def initialize
      @env = Env.new
      @level = 0
      @env.add("print", Object.new("print", 0, :fun, [:fun, :void, :int]))
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

          if type != :int
            raise "[error] invalid var type: #{type} #{node.pos_s}"
          end

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

        if type != :int
          raise "[error] invalid param type: #{type} #{node.pos_s}"
        end

        if name[0] == "*"
          name = name[1]
          type = [:pointer, type]
        else
          name = name[0]
        end

        if defined = @env.lookup(name)
          if defined.kind == :parm
            raise "[error] already defined param: #{name} #{node.pos_s}"
          end
        end

        # declare
        obj = Object.new(name, 1, :parm, type)
        @env.add(name, obj)
        node.attr[:name] = obj

      when :function_proto
        env_stash = Env.new(@env) # for params
        type, name = analyze_function_decl(node)
        @env = env_stash

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
          obj = Object.new(name, 0, :proto, type)
          @env.add(name, obj)
          node.attr[:decl].attr[:name] = obj
        end

      when :function_def
        env_stash = Env.new(@env) # for params
        type, name = analyze_function_decl(node)

        if defined = @env.lookup(name)
          if defined.kind == :proto
            if type != defined.type
              raise "[error] proto: type differs #{name} #{node.pos_s}"
            end
          else
            raise "[error] already defined #{name} #{node.pos_s}"
          end
        end

        # declare
        obj = Object.new(name, 0, :fun, type)
        @env.add(name, obj)
        node.attr[:decl].attr[:name] = obj

        analyze_node(node.attr[:stmts])
        @env = env_stash
        @env.add(name, obj)

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
end
