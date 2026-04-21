require "./ext"
require "./bigbrother/**"

module Bigbrother
  def self.run(argv)
    app = Cli.run(argv)
    app.run
  end
end

Bigbrother.run(ARGV)
