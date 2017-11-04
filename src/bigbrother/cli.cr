require "option_parser"
require "yaml"
require "base64"

require "./version"

module Bigbrother
  module Cli
    def self.run(argv)
      config_file = nil

      parser = OptionParser.parse(argv) do |parser|
        parser.banner = "Usage: bigbrother -c config.yml [arguments]"
        parser.on("-v", "--version", "Show current version") do
          puts version
          exit 0
        end
        parser.on("-c YAML", "--config=YAML", "Provide config file") do |name|
          config_file = name
        end
        parser.on("-h", "--help", "Show help") do
          abort parser.to_s
        end
      end

      config = read_config(config_file, ENV["BB_CONFIG_YAML_BASE64"]?)

      unless config
        abort parser.to_s
      end

      app = App.new(config.not_nil!)
      register_signal_handlers(app)
      app.run
    end

    private def self.read_config(config_file, yaml_string)
      if config_file && File.exists?(config_file)
        Config.from_yaml(File.read(config_file))
      elsif yaml_string
        Config.from_yaml(Base64.decode_string(yaml_string))
      end
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

    private def self.register_signal_handlers(app)
      handle_signal(Signal::INT, Signal::TERM, message: "Exit") { app.stop }
    end

    private def self.handle_signal(*signals, message, &block)
      signals.each do |signal|
        signal.trap do
          puts "Caught signal #{signal} -> #{message}"
          block.call
        end
      end
    end
  end
end
