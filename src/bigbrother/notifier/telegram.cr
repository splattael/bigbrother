require "tourmaline"
require "html"

module Bigbrother
  module Notifier
    class Telegram
      include Notifier

      @bot : Bot?

      config "telegram",
        token: String,
        chat_id: Int32 | String

      def notify(response, only_errors)
        if !only_errors || response.error?
          message = present_response(response)
          @bot.not_nil!("bot missing").notify(message)
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

      class Bot
        getter client : Tourmaline::Client

        def initialize(@config : Telegram, @app : App)
          @client = Tourmaline::Client.new(@config.token)

          register "help" do |ctx|
            notify <<-MESSAGE, ctx: ctx
              /check
              /check LABEL (example <code>/check .com</code>)"
              /chat_id
              /version
            MESSAGE
          end

          register "check" do |ctx|
            match_label = ctx.text ? Regex.new(ctx.text!) : /.*/
            @app
              .not_nil!("app missing")
              .run_checks(only_errors: false, match_label: match_label)
          end

          register "chat_id" do |ctx|
            notify "Chat ID: #{ctx.message!.chat.id}", ctx: ctx
          end

          register "version" do |ctx|
            notify Bigbrother::Cli.version, ctx: ctx
          end

          spawn client.poll
        end

        def register(command, &block : Tourmaline::Context ->)
          cmd = Tourmaline::CommandHandler.new(command) do |ctx|
            block.call(ctx)
          end

          client.register(cmd)
        end

        def notify(message, ctx = nil)
          if ctx
            ctx.reply message, parse_mode: Tourmaline::ParseMode::HTML
          else
            client.send_message(@config.chat_id, message, parse_mode: Tourmaline::ParseMode::HTML)
          end
        end
      end
    end
  end
end
