require "http/server"
require "prometheus"

module Bigbrother
  module Notifier
    class Prometheus
      include Notifier

      config "prometheus",
        metrics_path: String,
        listen: String?,
        port: Int32?

      def notify(response, only_errors)
        metrics.observe_response(response)
      end

      def start(app)
        super(app)

        spawn Endpoint.new(self, metrics).listen
      end

      def metrics
        (@metrics ||= Metrics.new).not_nil!("no metrics")
      end

      class Metrics
        def initialize
          @total = ::Prometheus.counter("checks_total", "Total checks")
          @duration = ::Prometheus.histogram(
            "check_duration_seconds",
            "Check duration in seconds",
            [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5]
          )
        end

        def observe_response(response)
          labels = {
            "type" => response.type,
            "endpoint" => response.endpoint,
            "status" => response.ok? ? "ok" : "error"
          }
          labels["error"] = response.error.to_s if response.error?

          @total.inc(labels: labels)
          @duration.observe(response.duration.total_seconds, labels)
        end

        def collect(output)
          ::Prometheus.collect(output)
        end
      end

      class Endpoint
        @listen_port : Int32
        @listen_address : String
        @metrics_path : String

        def initialize(@config : Prometheus, @metrics : Metrics)
          handlers = [
            HTTP::ErrorHandler.new,
            HTTP::LogHandler.new
          ]

          @server = HTTP::Server.new(handlers) do |context|
            context.response.content_type = "text/plain"
            handle_request(context)
          end

          @listen_port = @config.port || 8080
          @listen_address = @config.listen || "127.0.0.1"
          @metrics_path = @config.metrics_path || "/metrics"
        end

        def listen
          puts "Listen on port #{@listen_address}:#{@listen_port}#{@metrics_path}"
          address = @server.bind_tcp(@listen_address, @listen_port)
          @server.listen
        end

        private def handle_request(context)
          if context.request.path == @metrics_path
            @metrics.collect(context.response)
          else
            context.response.print "See #{@metrics_path}"
            context.response.status = HTTP::Status::NOT_FOUND
          end
        end
      end
    end
  end
end
