require "yaml_mapping"

module Bigbrother
  module Check
    # Spaces out the runs of a check that keeps failing, for hosts we do not
    # control: instead of a check -- and a notification -- every round while
    # the host is down, the check sits out rounds for longer and longer.
    #
    # After `min_attempts` failed runs in a row the check pauses for `delay`,
    # doubling after every further failed run, capped at `max_delay`. A
    # successful run ends the backoff. All values in seconds. A failed run
    # means all of its `retries` failed; retries themselves are unaffected.
    class Backoff
      # YAML's core schema reads `delay: 5` as an integer, which Float64's
      # constructor rejects. Nobody writes `5.0` for seconds, so take both.
      module Seconds
        def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Float64
          Union(Float64, Int64).new(ctx, node).to_f
        end

        def self.to_yaml(value : Float64, yaml : YAML::Nodes::Builder)
          value.to_yaml(yaml)
        end
      end

      YAML.mapping(
        min_attempts: {type: Int32, default: 1},
        # No defaults: only a pause of at least `check_every` skips a round,
        # so a default would either do nothing or pause for very long.
        delay: {type: Float64, converter: Seconds},
        max_delay: {type: Float64, converter: Seconds},
      )

      def initialize(@delay : Float64, @max_delay : Float64, @min_attempts = 1)
        if error = validation_error
          raise ArgumentError.new(error)
        end
      end

      # Hooks into the constructor `YAML.mapping` generates, so a bad value
      # fails when the config is loaded, pointing at its line, instead of
      # pausing a check forever or not at all once it fails.
      def initialize(ctx : YAML::ParseContext, node : YAML::Nodes::Node, _dummy : Nil)
        previous_def
        if error = validation_error
          node.raise "Invalid backoff: #{error}"
        end
      end

      private def validation_error
        # Written so that NaN fails every comparison and is rejected too.
        return "min_attempts must be at least 1" unless @min_attempts >= 1
        return "delay must be greater than 0" unless @delay > 0
        return "max_delay must be finite" unless @max_delay.finite?
        "max_delay must not be less than delay" unless @max_delay >= @delay
      end

      # Pause after `failed_runs` runs in a row have failed, or nil while the
      # backoff has not started yet.
      def delay_after(failed_runs : Int32) : Time::Span?
        return if failed_runs < @min_attempts

        # Float arithmetic: a large exponent becomes Infinity, which the cap
        # absorbs, instead of overflowing an Int32.
        seconds = @delay * 2.0 ** (failed_runs - @min_attempts)
        Math.min(seconds, @max_delay).seconds
      end
    end
  end
end
