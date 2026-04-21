require "option_parser"
require "yaml_mapping"
require "base64"

require "./version"

module Bigbrother
  class Cli
    def self.run(argv) : App
      new.run(argv)
    end

    def self.version : String
      new.version
    end

    def run(argv)
      config_file = nil

      parser = OptionParser.parse(argv) do |p|
        p.banner = "Usage: bigbrother -c config.yml [arguments]"
        p.on("-v", "--version", "Show current version") do
          puts version
          exit 0
        end
        p.on("-c YAML", "--config=YAML", "Provide config file") do |name|
          config_file = name
        end
        p.on("-h", "--help", "Show help") do
          abort p.to_s
        end
      end

      config = read_config(config_file)

      unless config
        abort parser.to_s
      end

      app = App.new(config.not_nil!("config missing"))
      register_signal_handlers(app)

      app
    end

    private def read_config(config_file)
      if config_file && File.exists?(config_file)
        Config.from_yaml(File.read(config_file))
      end
    end

    def version
      "%{name} %{version} [%{sha1}] (%{date}) Crystal %{cr_version}" % {
        name:       "bigbrother",
        version:    VERSION,
        sha1:       VERSION_SHA1,
        date:       VERSION_DATE,
        cr_version: Crystal::VERSION,
      }
    end

    private def register_signal_handlers(app)
      handle_signal(Signal::INT, Signal::TERM, message: "Exit") { app.stop }
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
