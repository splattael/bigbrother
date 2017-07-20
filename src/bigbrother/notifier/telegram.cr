require "telegram_bot"
require "html"

module Bigbrother
  module Notifier
    class Telegram
      include Notifier

      @bot : Bot?

      config "telegram",
        name: String,
        token: String,
        chat_id: Int32,
        whitelist: Array(String)?,
        blacklist: Array(String)?,
        webhook: Webhook?

      config Webhook,
        url: String,
        listen: String?,
        port: Int32?,
        ssl_certificate_path: String?,
        ssl_key_path: String?

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

          if webhook = @config.webhook
            spawn serve_webhook(webhook)
          else
            spawn start_polling
          end
        end

        def notify(message)
          send_message @config.chat_id, message, parse_mode: "HTML"
        end

        private def serve_webhook(config)
          set_webhook(config.url, config.ssl_certificate_path)
          serve(
            bind_address: config.listen || "127.0.0.1",
            bind_port: config.port || 80,
            ssl_certificate_path: config.ssl_certificate_path,
            ssl_key_path: config.ssl_key_path
          )
        end

        private def start_polling
          set_webhook("") # Disable webhook
          polling
        end
      end
    end
  end
end
