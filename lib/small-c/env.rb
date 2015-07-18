#
# Small-C Env - 環境
#

module SmallC
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
end
