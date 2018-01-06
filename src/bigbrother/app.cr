module Bigbrother
  class App
    @notifiers : Array(Notifier)
    @checks : Array(Check)

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
    end

    def run_checks(only_errors = true, match_label = /.*/)
      @checks
        .select { |check| match_label.match check.label }
        .each { |check| run_check(check, only_errors) }
    end

    private def sleep_interruptable(seconds, resolution = 1.0)
      while seconds > 0
        break if yield
        seconds -= resolution
        sleep resolution
      end
    end

    private def run_check(check, only_errors)
      spawn do
        response = execute_check(check)
        notify(response, only_errors)
      end
    end

    private def execute_check(check)
      retries = check.retries || @config.retries
      loop do
        response = check.run
        if response.error? && retries > 0
          retries -= 1
        else
          return response
        end
        sleep 0.5
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
