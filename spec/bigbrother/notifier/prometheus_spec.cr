require "../../spec_helper"

module Bigbrother::Notifier
  # `Metrics` registers its metrics in the global prometheus registry, which
  # refuses a second registration under the same name -- so share one instance.
  METRICS = Prometheus::Metrics.new

  private def self.response(endpoint, exception)
    check = Check::HostIp.from_yaml <<-YAML
      type: "host_ip"
      host: "#{endpoint}"
      port: 25
      ssl_min_days_valid: null
      YAML

    Check::Response.new(check, 1.second, exception)
  end

  private def self.lines_for(endpoint)
    METRICS.collect(io = IO::Memory.new)
    io.to_s.lines.select(&.includes?(endpoint))
  end

  describe Prometheus::Metrics do
    it "keeps the exposition parseable when an error has quotes, backslashes and newlines" do
      body = %(# HELP go_gc_duration_seconds A summary.\ngo_gc_duration_seconds{quantile="0"} 2.4e-05\n)
      exception = Check::Failure.new(%(regex=(?-imsx:postfix_showq), match_body="a\\b" #{body}))

      METRICS.observe_response(response("escape.example", exception))

      lines = lines_for("escape.example")
      total = lines.find!(&.starts_with?("checks_total{"))
      total.should contain(%(error="regex=(?-imsx:postfix_showq), match_body=\\"a\\\\b\\" # HELP go_gc_duration_seconds A summary."}))
      # Every sample line is `name{labels} value`, i.e. nothing leaked onto its own line.
      lines.each { |line| line.should match(/\A[a-z_]+\{.*\} [0-9.e+-]+\z/) }
    end

    it "replaces invalid UTF-8 in an error message" do
      message = String.new(Bytes[0x62, 0x6f, 0x64, 0x79, 0x3d, 0xff, 0xfe, 0x21])
      METRICS.observe_response(response("utf8.example", Check::Failure.new(message)))

      total = lines_for("utf8.example").find!(&.starts_with?("checks_total{"))
      total.valid_encoding?.should be_true
      total.should contain(%(error="body=\u{FFFD}\u{FFFD}!"}))
    end

    it "truncates long error messages" do
      METRICS.observe_response(response("long.example", Check::Failure.new("x" * 500)))

      total = lines_for("long.example").find!(&.starts_with?("checks_total{"))
      total.should contain(%(error="#{"x" * 120}..."}))
    end

    it "has no error label for successful checks" do
      METRICS.observe_response(response("ok.example", nil))

      total = lines_for("ok.example").find!(&.starts_with?("checks_total{"))
      total.should_not contain("error=")
    end
  end
end
