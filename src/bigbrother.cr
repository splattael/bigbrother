require "./ext"
require "./bigbrother/**"

module Bigbrother
  def self.run(argv)
    Cli.run(argv)
  end
end

Bigbrother.run(ARGV)
