require "colorize"

module Bigbrother
  module Notifier
    class Console
      include Notifier

      config "console",
        colorize: Bool

      def notify(response, only_errors)
        puts present_response(response, @colorize)
      end

      private def present_response(response, colorize)
        String.build do |string|
          string << "[#{Time.local}] "

          if response.ok?
            string << "OK".colorize.green.toggle(colorize)
          else
            string << "FAIL".colorize.red.toggle(colorize)
          end

          string << " "
          string << response.type
          string << " "
          string << response.label.colorize.mode(:bold).toggle(colorize)
          string << ", duration=#{response.duration.total_milliseconds}ms"

          if response.error?
            string << ", exception=#{response.exception}"
          end
        end
      end
    end
  end
end
