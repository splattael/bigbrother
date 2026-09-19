module Bigbrother
  module Notifier
    property app : Bigbrother::App?

    def start(app : App)
      @app = app
    end

    abstract def notify(response : Check::Response, only_errors : Bool)

    def stop
    end

    # # configurable
    # TODO unite

    TYPES = [] of Class

    macro included
      macro config(type, **properties)
        \{% if type.is_a?(StringLiteral) %}
          \{% TYPES << @type %}

          def {{@type}}.type
            \{{ type }}
          end

          \{% properties[:type] = String %}
          YAML.mapping(\{{properties.double_splat}})
        \{% elsif type.is_a?(Path) %}
          class \{{ type }}
            YAML.mapping(\{{properties.double_splat}})
          end
        \{% else %}
           \{% raise "unknown config type. Allowed: StringLiteral, Path." %}
        \{% end %}
      end
    end

    macro finished
      def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
        {% for type in TYPES %}
          begin
            # A node can parse as more than one type once several of them
            # share their required attributes, so the `type` discriminator --
            # not the first successful parse -- decides. Falling through to
            # the next candidate keeps dispatch independent of the order in
            # which the types happened to register.
            config = {{type}}.new(ctx, node)
            return config if {{type}}.type == config.type
          rescue YAML::ParseException
            # Ignore
          end
        {% end %}
        node.raise "Cound't parse #{self}"
      end
    end
  end
end
