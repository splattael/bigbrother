module Bigbrother
  class App
    @notifiers : Array(Notifier)
    getter checks : Array(Check)
    # Backoff state per check. Lives here, not on the check, and is lost on a
    # config reload, which therefore also retries every paused check at once.
    @failed_runs = Hash(Check, Int32).new(0)
    @paused_until = {} of Check => Time::Instant

    def initialize(@config : Config)
      @notifiers = define_notifiers(@config.notifiers)
      @checks = define_checks(@config.checks)
      @notifiers.each(&.start(self))
      @checks.each(&.start(self))
      @stopped = false
    end

    def run
      loop do
        run_checks
        sleep_interruptable(@config.check_every) { @stopped }
        break if @stopped
      end
    end

    def stop
      @stopped = true
      @notifiers.each(&.stop)
    end

    # *ignore_backoff* is for checks someone asked for explicitly (Telegram's
    # /check); their outcome still counts towards the backoff.
    def run_checks(only_errors = true, match_label = /.*/, ignore_backoff = false)
      now = Time.instant
      @checks
        .select { |check| match_label.match check.label }
        .reject { |check| !ignore_backoff && paused?(check, now) }
        .each { |check| run_check(check, only_errors, now) }
    end

    def paused?(check, now = Time.instant)
      if paused_until = @paused_until[check]?
        now < paused_until
      else
        false
      end
    end

    def failed_runs(check)
      @failed_runs[check]
    end

    private def sleep_interruptable(seconds, resolution = 1.0)
      while seconds > 0
        break if yield
        seconds -= resolution
        sleep resolution.seconds
      end
    end

    private def run_check(check, only_errors, started_at)
      spawn do
        response = execute_check(check)
        record_outcome(check, response, started_at)
        notify(response, only_errors)
      end
    end

    # The pause counts from the start of the round, not from the end of the
    # run, so a pause of exactly n * check_every skips n - 1 rounds rather
    # than n because the run itself took a few seconds.
    private def record_outcome(check, response, started_at)
      if response.ok?
        @failed_runs.delete(check)
        @paused_until.delete(check)
        return
      end

      failed = @failed_runs[check] += 1
      if pause = check.backoff.try(&.delay_after(failed))
        @paused_until[check] = started_at + pause
      end
    end

    private def execute_check(check)
      retries = check.retries || @config.retries
      failed_attempts = 0
      loop do
        response = check.run
        return response if response.ok? || failed_attempts >= retries

        failed_attempts += 1
        sleep 0.5.seconds
      end
    end

    private def notify(response, only_errors)
      @notifiers.each(&.notify(response, only_errors))
    end

    private def define_notifiers(notifiers)
      notifiers.map(&.as(Notifier))
    end

    private def define_checks(checks)
      checks.map(&.as(Check))
    end
  end
end
