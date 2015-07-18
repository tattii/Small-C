#
# Small-C Object - オブジェクト情報構造体
#

module SmallC
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
end
