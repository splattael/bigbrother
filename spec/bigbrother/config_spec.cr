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
