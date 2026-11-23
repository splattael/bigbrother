require "yaml_mapping"

module Bigbrother
  module Check
    # Spaces out the retries of a failing check, so a check with enough
    # `retries` can ride out a restart or a short outage before anyone is
    # notified, instead of burning through all of them within a few seconds.
    #
    # The first `min_attempts` failed attempts are retried after the usual
    # short pause. From then on the pause starts at `delay` and doubles after
    # every further failure, capped at `max_delay`. All values in seconds.
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
        delay: {type: Float64, default: 1.0, converter: Seconds},
        max_delay: {type: Float64, default: 60.0, converter: Seconds},
      )

      def initialize(@min_attempts = 1, @delay = 1.0, @max_delay = 60.0)
      end

      # Pause after `failed_attempts` attempts have failed, or nil while the
      # backoff has not started yet.
      def delay_after(failed_attempts : Int32) : Time::Span?
        return if failed_attempts < @min_attempts

        # Float arithmetic: a large exponent becomes Infinity, which the cap
        # absorbs, instead of overflowing an Int32.
        seconds = @delay * 2.0 ** (failed_attempts - @min_attempts)
        Math.min(seconds, @max_delay).seconds
      end
    end
  end
end
