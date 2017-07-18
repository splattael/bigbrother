module Bigbrother
  module Check
    class Failure < Exception
      def initialize(@message : String)
      end
    end
  end
end
