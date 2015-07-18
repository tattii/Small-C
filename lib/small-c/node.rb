#
# Small-C Node
#

module SmallC
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

end

