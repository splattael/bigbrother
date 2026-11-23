require "./../spec_helper"

private def backoff_app(port, backoff = "{min_attempts: 2, delay: 3600, max_delay: 3600}")
  Bigbrother::App.new(Bigbrother::Config.from_yaml(<<-YAML))
    check_every: 300
    notifiers: []
    checks:
      - type: "host_ip"
        host: "127.0.0.1"
        port: #{port}
        ssl_min_days_valid: null
        backoff: #{backoff}
    YAML
end

# Checks run in their own fibers; waits until the round has been recorded.
private def run_round(app, expected_failed_runs, **options)
  app.run_checks(**options)
  check = app.checks.first
  50.times do
    break if app.failed_runs(check) == expected_failed_runs
    sleep 10.milliseconds
  end
  app.failed_runs(check).should eq expected_failed_runs
end

private def closed_port
  server = TCPServer.new("127.0.0.1", 0)
  server.local_address.port.tap { server.close }
end

module Bigbrother
  describe App do
    it "pauses a failing check once min_attempts runs have failed" do
      app = backoff_app(closed_port)
      check = app.checks.first

      run_round app, 1
      app.paused?(check).should be_false

      run_round app, 2
      app.paused?(check).should be_true
      app.paused?(check, Time.instant + 3601.seconds).should be_false

      # Skipped while paused: the count stays where it is.
      run_round app, 2
    end

    it "still runs a paused check when asked for explicitly" do
      app = backoff_app(closed_port, "{min_attempts: 1, delay: 3600, max_delay: 3600}")

      run_round app, 1
      run_round app, 2, ignore_backoff: true
    end

    it "ends the backoff when the check succeeds" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      server.close
      app = backoff_app(port, "{min_attempts: 1, delay: 3600, max_delay: 3600}")
      check = app.checks.first

      run_round app, 1
      app.paused?(check).should be_true

      server = TCPServer.new("127.0.0.1", port)
      begin
        run_round app, 0, ignore_backoff: true
        app.paused?(check).should be_false
      ensure
        server.close
      end
    end

    it "never pauses a check without backoff" do
      app = backoff_app(closed_port, "null")

      run_round app, 1
      run_round app, 2
      app.paused?(app.checks.first).should be_false
    end
  end
end
