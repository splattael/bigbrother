require "../../spec_helper"

module Bigbrother
  describe Check::Backoff do
    it "keeps the short pause until min_attempts attempts have failed" do
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
            backoff: {}
        YAML

      config.checks[0].backoff.should be_nil

      backoff = config.checks[1].backoff.not_nil!
      backoff.min_attempts.should eq 2
      backoff.delay.should eq 5.0
      backoff.max_delay.should eq 120.0

      defaults = config.checks[2].backoff.not_nil!
      defaults.min_attempts.should eq 1
      defaults.delay.should eq 1.0
      defaults.max_delay.should eq 60.0
    end
  end
end
