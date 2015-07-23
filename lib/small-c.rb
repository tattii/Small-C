#
# SmallC Compiler 
#

require_relative './small-c/node.rb'
require_relative './small-c/object.rb'
require_relative './small-c/env.rb'

require_relative './small-c/scan.rb'
require_relative './small-c/parse.rb'
require_relative './small-c/symbol-analyze.rb'
require_relative './small-c/type-check.rb'
require_relative './small-c/intermed-code.rb'
require_relative './small-c/assign-addr.rb'
require_relative './small-c/code-generate.rb'

require 'pp'

module SmallC

  def self.compile(str)
    begin 
      ast = SmallC::Parse.new.parse(str)
      SmallC::SymbolAnalyze.new.analyze(ast)
      SmallC::TypeCheck.new.well_typed?(ast)

      intermed_code = IntermedCode.new.convert(ast)
      AssignAddr.new.assign(intermed_code)

      code = CodeGenerate.new.convert(intermed_code)
      print CodeGenerate.print_code(code)
      exit 0

    rescue Racc::ParseError => e
      STDERR.puts e.message
      exit 1
    rescue RuntimeError => e
      STDERR.puts e.message
      exit 1
    end
  end

  def self.compile_debug(str)
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
     # pp intermed_code

      code = CodeGenerate.new.convert(intermed_code)
     # pp code

     # print CodeGenerate.print_code(code)
    rescue Racc::ParseError => e
      puts e.message
    rescue RuntimeError => e
      puts e.message
    end
  end
end


