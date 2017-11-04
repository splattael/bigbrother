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
