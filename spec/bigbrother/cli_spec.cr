require "../spec_helper"

module Bigbrother
  describe Cli do
    it "reports name, version, sha1, date and Crystal version" do
      version = Cli.new.version

      version.should start_with "bigbrother #{VERSION} ["
      version.should contain VERSION_SHA1
      version.should contain VERSION_DATE
      version.should end_with "Crystal #{Crystal::VERSION}"
    end
  end
end
