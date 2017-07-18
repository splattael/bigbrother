require "telegram_bot"
require "html"

module Bigbrother
  module Notifier
    class Telegram < TelegramBot::Bot
      include Notifier

      @bot : Bot?

      config "telegram",
        name: String,
        token: String,
        chat_id: Int32,
        whitelist: Array(String)?,
        blacklist: Array(String)?

      def notify(response, only_errors)
        if !only_errors || response.error?
          message = present_response(response)
          @bot.not_nil!.notify(message)
        end
      end

      def start(app)
        super(app)
        @bot = Bot.new(self, app)
      end

      private def present_response(response)
        String.build do |string|
          if response.ok?
            string << "<i>OK</i>"
          else
            string << "<b>FAIL</b>"
          end

          string << " "
          string << response.type
          string << " "
          string << response.label
          string << ", duration=#{response.duration.total_milliseconds}ms"

          if response.error?
            error = HTML.escape(response.exception.inspect)
            string << "\n<pre>#{error}</pre>"
          end
        end
      end

      class Bot < TelegramBot::Bot
        include TelegramBot::CmdHandler

        def initialize(@config : Telegram, @app : App)
          super(
            name: @config.name,
            token: @config.token,
            whitelist: @config.whitelist,
            blacklist: @config.blacklist
          )

          cmd "check" do |msg|
            @app.not_nil!.run_checks(only_errors: false)
          end

          spawn do
            polling
          end
        end

        def notify(message)
          send_message @config.chat_id, message, parse_mode: "HTML"
        end
      end
    end
  end
end
