module Bigbrother
  module Check
    class Response
      getter check
      getter duration
      getter exception

      def initialize(@check : Check, @duration : Time::Span, @exception : Exception?)
      end

      def type
        @check.type
      end

      def label
        @check.label
      end

      def error
        @exception
      end

      def error?
        !error.nil?
      end

      def ok?
        error.nil?
      end
    end
  end
end
