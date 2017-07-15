require "telegram_bot"

module Bigbrother
  module Notifier
    class Telegram < TelegramBot::Bot
      include Notifier

      @bot : Bot?

      config "telegram",
        # type: "telegram",
        name: String,
        token: String,
        chat_id: Int32

      def notify(response, only_errors)
        if !only_errors || response.error?
          message = response.as_string(false)
          @bot.not_nil!.notify(message)
        end
      end

      def start(app)
        super(app)
        @bot = Bot.new(self, app)
      end

      class Bot < TelegramBot::Bot
        include TelegramBot::CmdHandler

        def initialize(@config : Telegram, @app : App)
          super(@config.name, @config.token)

          cmd "check" do |msg|
            @app.not_nil!.run_checks(only_errors: false)
          end

          spawn do
            polling
          end
        end

        def notify(message)
          send_message @config.chat_id, message
        end
      end
    end
  end
end
