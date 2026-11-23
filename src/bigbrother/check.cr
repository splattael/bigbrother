require "./check/failure"
require "./check/response"
require "./check/backoff"

module Bigbrother
  module Check
    property app : Bigbrother::App?

    abstract def endpoint
    abstract def check
    abstract def label

    def start(app : App)
      @app = app
    end

    def run
      start = Time.instant
      begin
        check
        Response.new(self, Time.instant - start, nil)
      rescue e
        Response.new(self, Time.instant - start, e)
      end
    end

    protected def fail(message)
      raise Failure.new(message)
    end

    # # configurable
    # TODO unite

    TYPES = [] of Class

    macro included
      macro config(type, **properties)
        \{% TYPES << @type %}

        def {{@type}}.type
          \{{ type }}
        end

        \{% properties[:type] = String %}
        YAML.mapping(
          retries: Int32?,
          backoff: {type: Bigbrother::Check::Backoff, nilable: true},
          \{{properties.double_splat}}
        )
      end
    end

    macro finished
      def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
        wanted = type_of(node)
        {% for type in TYPES %}
          begin
            # A node can parse as more than one type once several of them
            # share their required attributes, so the `type` discriminator --
            # not the first successful parse -- decides. Falling through to
            # the next candidate keeps dispatch independent of the order in
            # which the types happened to register.
            config = {{type}}.new(ctx, node)
            return config if {{type}}.type == config.type
          rescue ex : YAML::ParseException
            # The error of the type the node asks for is the one worth
            # reporting (a missing key, an invalid value); the generic one
            # below would only say that nothing matched.
            raise ex if {{type}}.type == wanted
          end
        {% end %}
        node.raise "Cound't parse #{self}"
      end

      private def self.type_of(node) : String?
        return unless node.is_a?(YAML::Nodes::Mapping)
        node.nodes.each_slice(2) do |(key, value)|
          if key.as?(YAML::Nodes::Scalar).try(&.value) == "type"
            return value.as?(YAML::Nodes::Scalar).try(&.value)
          end
        end
      end
    end
  end
end
