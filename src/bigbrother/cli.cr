require "option_parser"
require "yaml_mapping"
require "base64"

require "./version"

module Bigbrother
  class Cli
    def self.run(argv)
      new.run(argv)
    end

    def self.version : String
      new.version
    end

    property config_file : String?

    @app : App?
    @pending_config : Config?

    def initialize
      @config_file = nil
      @exit_requested = false
      @pending_config = nil
    end

    def run(argv)
      parser = OptionParser.parse(argv) do |p|
        p.banner = "Usage: bigbrother -c config.yml [arguments]"
        p.on("-v", "--version", "Show current version") do
          puts version
          exit 0
        end
        p.on("-c YAML", "--config=YAML", "Provide config file") do |name|
          @config_file = name
        end
        p.on("-h", "--help", "Show help") do
          abort p.to_s
        end
      end

      config = read_config

      unless config
        abort parser.to_s
      end

      @app = App.new(config)
      register_signal_handlers

      loop do
        app.run
        break if @exit_requested

        if pending_config = @pending_config
          @pending_config = nil
          @app = App.new(pending_config)
        end
      end
    end

    private def app
      @app.not_nil!("app missing")
    end

    private def read_config
      if config_file
        file = config_file.not_nil!
        Config.from_yaml(File.read(file)) if File.exists?(file)
      end
    rescue ex : YAML::ParseException
      puts "Invalid config #{config_file}: #{ex.message}"
      nil
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

    private def register_signal_handlers
      handle_signal(Signal::INT, Signal::TERM, message: "Exit") do
        @exit_requested = true
        app.stop
      end

      handle_signal(Signal::HUP, message: "Reload config") do
        if config = read_config
          @pending_config = config
          app.stop
        else
          puts "Reload failed: invalid config, keeping current config running"
        end
      end
    end

    private def handle_signal(*signals, message, &block)
      signals.each do |signal|
        signal.reset
        signal.trap do
          puts "Caught signal #{signal} -> #{message}"
          block.call
        end
      end
    end
  end
end
