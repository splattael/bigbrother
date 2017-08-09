require "option_parser"
require "yaml"

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

      unless config_file
        abort parser.to_s
      end

      config = Config.from_yaml(File.read(config_file.not_nil!))
      App.new(config).run
    end

    def self.version
      "%{name} %{version} [%{sha1}] (%{date}) Crystal %{cr_version}" % {
        name: "bigbrother",
        version: VERSION,
        sha1: VERSION_SHA1,
        date: VERSION_DATE,
        cr_version: Crystal::VERSION
      }
    end
  end
end
