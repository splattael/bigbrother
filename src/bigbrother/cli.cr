require "option_parser"
require "yaml"
require "base64"

require "./version"

module Bigbrother
  class Cli
    enum Status
      Run
      Reload
      Stop
    end

    @config_file : String?
    @webhook_port : Int32 = 0
    @parser : OptionParser
    @status : Status = Status::Run

    def initialize(@config_file, @webhook_port, @parser)
    end

    def run
      while @status != Status::Stop
        start_app
      end
    end

    private def start_app
      config = read_config(@config_file, ENV["BB_CONFIG_YAML_BASE64"]?)

      unless config
        message = "Unable to read or parse config\n\n" + @parser.to_s
        abort message
      end

      if @webhook_port > 0
        configure_port(config, @webhook_port)
      end

      @status = Status::Run

      app = App.new(config.not_nil!)
      register_signal_handlers(app)
      app.run
    end

    def self.run(argv)
      config_file = nil
      webhook_port = 0

      parser = OptionParser.parse(argv) do |parser|
        parser.banner = "Usage: bigbrother -c config.yml [arguments]"
        parser.on("-v", "--version", "Show current version") do
          puts version
          exit 0
        end
        parser.on("-c YAML", "--config=YAML", "Provide config file") do |name|
          config_file = name
        end
        parser.on("-p", "--port=PORT", "Provide webhook port used by heroku.") do |port|
          webhook_port = port.to_i
        end
        parser.on("-h", "--help", "Show help") do
          abort parser.to_s
        end
      end

      cli = new(config_file, webhook_port, parser)
      cli.run
    end

    private def read_config(config_file, yaml_string)
      if config_file && File.exists?(config_file)
        Config.from_yaml(File.read(config_file))
      elsif yaml_string
        Config.from_yaml(Base64.decode_string(yaml_string))
      end
    end

    private def configure_port(config : Config, port)
      config.notifiers.each { |notifier| configure_port(notifier, port) }
    end

    private def configure_port(config : Notifier::Telegram, port)
      if webhook = config.webhook
        webhook.port = port
      end
    end

    private def configure_port(config : Notifier, port)
      # fallback
    end

    def self.version
      "%{name} %{version} [%{sha1}] (%{date}) Crystal %{cr_version}" % {
        name:       "bigbrother",
        version:    VERSION,
        sha1:       VERSION_SHA1,
        date:       VERSION_DATE,
        cr_version: Crystal::VERSION,
      }
    end

    private def register_signal_handlers(app)
      handle_signal(Signal::INT, Signal::TERM, message: "Exit") { stop!(app) }
      handle_signal(Signal::HUP, message: "Reloading config") { reload!(app) }
    end

    private def stop!(app)
      @status = Status::Stop
      app.stop
    end

    private def reload!(app)
      @status = Status::Reload
      app.stop
    end

    private def handle_signal(*signals, message, &block)
      signals.each do |signal|
        signal.trap do
          puts "Caught signal #{signal} -> #{message}"
          block.call
        end
      end
    end
  end
end
