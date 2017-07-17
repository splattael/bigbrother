require "colorize"

module Bigbrother
  module Check
    class Response
      getter check
      getter duration
      getter exception

      def initialize(@check : Check, @duration : Time::Span, @exception : Exception?)
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

      def as_string(colorize = true)
        type = check.class.to_s.gsub(/Bigbrother::Check::/, "")

        String.build do |string|
          if ok?
            string << "OK".colorize.green.toggle(colorize)
          else
            string << "FAIL".colorize.red.toggle(colorize)
          end

          string << "[#{type}]=#{check.label.colorize.mode(:bold).toggle(colorize)}"
          string << ", duration=#{duration}"

          if error?
            string << ", exception=#{@exception}"
          end
        end
      end
    end
  end
end
