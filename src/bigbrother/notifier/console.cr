module Bigbrother
  module Notifier
    class Console
      include Notifier

      config "console",
        # type: "console",
        colorize: Bool

      def notify(response, only_errors)
        message = response.as_string(@colorize)
        time = Time.now.to_s
        puts "[#{time}] #{message}"
      end
    end
  end
end
