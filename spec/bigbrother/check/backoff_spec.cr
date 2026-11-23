require "../../spec_helper"

module Bigbrother
  describe Check::Backoff do
    it "does not pause before min_attempts runs have failed" do
      backoff = Check::Backoff.new(min_attempts: 3, delay: 2.0, max_delay: 60.0)

      backoff.delay_after(1).should be_nil
      backoff.delay_after(2).should be_nil
      backoff.delay_after(3).should eq 2.seconds
    end

    it "doubles the delay after every further failure" do
      backoff = Check::Backoff.new(min_attempts: 1, delay: 1.5, max_delay: 60.0)

      (1..4).map { |n| backoff.delay_after(n) }
        .should eq [1.5.seconds, 3.seconds, 6.seconds, 12.seconds]
    end

    it "caps the delay at max_delay, even after very many failures" do
      backoff = Check::Backoff.new(min_attempts: 1, delay: 1.0, max_delay: 10.0)

      backoff.delay_after(5).should eq 10.seconds
      backoff.delay_after(10_000).should eq 10.seconds
    end

    it "is off unless a check configures it" do
      config = Config.from_yaml <<-YAML
        check_every: 60
        notifiers: []
        checks:
          - type: "host_ip"
            host: "example.com"
            port: 443
          - type: "http"
            url: "https://example.com"
            retries: 5
            backoff:
              min_attempts: 2
              delay: 5
              max_delay: 120
          - type: "ftp"
            host: "example.com"
            backoff: {delay: 600, max_delay: 1800}
        YAML

      config.checks[0].backoff.should be_nil

      backoff = config.checks[1].backoff.not_nil!
      backoff.min_attempts.should eq 2
      backoff.delay.should eq 5.0
      backoff.max_delay.should eq 120.0

      config.checks[2].backoff.not_nil!.min_attempts.should eq 1
    end
    {
      "{min_attempts: 0, delay: 1, max_delay: 1}" => "min_attempts must be at least 1",
      "{delay: 0, max_delay: 1}"                  => "delay must be greater than 0",
      "{delay: -1, max_delay: 1}"                 => "delay must be greater than 0",
      "{delay: .nan, max_delay: 1}"               => "delay must be greater than 0",
      "{delay: 1, max_delay: .inf}"               => "max_delay must be finite",
      "{delay: 10, max_delay: 5}"                 => "max_delay must not be less than delay",
    }.each do |backoff, message|
      it "rejects `#{backoff}` when the config is loaded" do
        yaml = <<-YAML
          check_every: 60
          notifiers: []
          checks:
            - type: "ftp"
              host: "example.com"
              backoff: #{backoff}
          YAML

        ex = expect_raises(YAML::ParseException) { Config.from_yaml(yaml) }
        ex.message.not_nil!.should contain "Invalid backoff: #{message}"
        ex.line_number.should eq 6
      end
    end

    it "rejects invalid values passed to the constructor" do
      expect_raises(ArgumentError, "max_delay must not be less than delay") do
        Check::Backoff.new(delay: 2.0, max_delay: 1.0)
      end
    end

    it "reports a check's own parse error instead of a generic one" do
      ex = expect_raises(YAML::ParseException) do
        Config.from_yaml <<-YAML
          check_every: 60
          notifiers: []
          checks:
            - type: "http"
              retries: 2
          YAML
      end
      ex.message.not_nil!.should_not contain "Cound't parse"
    end
  end
end
