#
# Small-C Parser
#

require_relative './small-c.tab.rb'

module SmallC
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
end
