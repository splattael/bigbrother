require "../spec_helper"

module Bigbrother
  describe Config do
    it "resolves polymorphic checks and notifiers to their concrete types" do
      config = Config.from_yaml <<-YAML
        check_every: 60
        retries: 2
        notifiers:
          - type: "console"
            colorize: true
        checks:
          - type: "http"
            url: "https://example.com"
          - type: "host_ip"
            host: "example.com"
            port: 443
        YAML

      config.check_every.should eq 60
      config.retries.should eq 2
      config.notifiers.map(&.class).should eq [Notifier::Console]
      config.checks.map(&.class).should eq [Check::Http, Check::HostIp]
    end

    it "dispatches on the type discriminator, not on the first type that parses" do
      # `host_ip` and `ftp` both accept a bare host/port node, so whichever
      # registers first would win if the discriminator were not consulted.
      config = Config.from_yaml <<-YAML
        check_every: 60
        notifiers: []
        checks:
          - type: "host_ip"
            host: "example.com"
            port: 21
          - type: "ftp"
            host: "example.com"
            port: 21
        YAML

      config.checks.map(&.class).should eq [Check::HostIp, Check::Ftp]
    end

    it "defaults retries to 0 when omitted" do
      config = Config.from_yaml <<-YAML
        check_every: 30
        notifiers: []
        checks: []
        YAML

      config.retries.should eq 0
    end

    it "raises on an unknown check type" do
      expect_raises(YAML::ParseException) do
        Config.from_yaml <<-YAML
          check_every: 30
          notifiers: []
          checks:
            - type: "no_such_check"
          YAML
      end
    end
  end
end
