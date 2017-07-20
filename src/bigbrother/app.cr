module Bigbrother
  class App
    @notifiers : Array(Notifier)
    @checks : Array(Check)

    def initialize(@config : Config)
      @notifiers = define_notifiers(@config.notifiers)
      @checks = define_checks(@config.checks)
      @notifiers.each(&.start(self))
      @checks.each(&.start(self))

      register_signal_handlers
    end

    def run
      loop do
        run_checks
        sleep @config.check_every
      end
    end

    def run_checks(only_errors = true)
      @checks.each do |check|
        run_check(check, only_errors)
      end
    end

    private def run_check(check, only_errors)
      spawn do
        response = check.run
        notify(response, only_errors)
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

    private def register_signal_handlers
      handle_signal(Signal::INT, Signal::TERM, message: "Exit") { exit 1 }
    end

    private def handle_signal(*signals, message, &block)
      signals.each do |signal|
        signal.trap do
          puts "Caught signal #{signal} -> #{message}"
          block.call
        end
      end
    end
  end
end
