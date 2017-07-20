module Bigbrother
  module Notifier
    property app : Bigbrother::App?

    def start(app : App)
      @app = app
    end

    abstract def notify(response : Check::Response, only_errors : Bool)

    ## configurable
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
          YAML.mapping(\{{**properties}})
        \{% elsif type.is_a?(Path) %}
          class \{{ type }}
            YAML.mapping(\{{**properties}})
          end
        \{% else %}
           \{% raise "unknown config type. Allowed: StringLiteral, Path." %}
        \{% end %}
      end
    end

    macro finished
      def self.new(pull : YAML::PullParser)
        string = pull.read_raw
        {% for type in TYPES %}
          begin
            config = {{type}}.from_yaml(string)
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
        raise YAML::ParseException.new("Couldn't parse #{self} from #{string}", 0, 0)
      end
    end
  end
end
