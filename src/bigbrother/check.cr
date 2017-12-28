require "./check/failure"
require "./check/response"

module Bigbrother
  module Check
    property app : Bigbrother::App?

    abstract def check
    abstract def label : String

    def start(app : App)
      @app = app
    end

    def run
      start = Time.now
      begin
        check
        Response.new(self, Time.now - start, nil)
      rescue e
        Response.new(self, Time.now - start, e)
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
        YAML.mapping(\{{**properties}})
      end
    end

    macro finished
      def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
        {% for type in TYPES %}
          begin
            config = {{type}}.new(ctx, node)
            if {{type}}.type != config.type
              raise "Unmatched attribute type for {{type}}:\n" +
                    "  Expected: #{{{type}}.type.inspect}\n" +
                    "    Actual: #{config.type.inspect}"
            end
            return config
          rescue YAML::ParseException
            # Ignore
          end
        {% end %}
        node.raise "Cound't parse #{self}"
      end
    end
  end
end
