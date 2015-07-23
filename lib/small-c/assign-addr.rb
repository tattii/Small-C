#
# Small-C AssignAdddr - 相対番地割り当て
#

module SmallC
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

#pp compd
      compd[:stmts].each do |stmt|
        case stmt[:type]
        when :compdstmt
          assign_compdstmt(stmt)

        when :ifstmt 
          assign_compdstmt(stmt[:stmt1]) if compdstmt?(stmt[:stmt1])
          assign_compdstmt(stmt[:stmt2]) if compdstmt?(stmt[:stmt2])

        when :whilestmt
          assign_compdstmt(stmt[:stmt]) if compdstmt?(stmt[:stmt])

        end
      end

    end
    
    def compdstmt?(stmt)
      stmt.is_a?(Hash) && stmt[:type] == :compdstmt
    end
  end
end
