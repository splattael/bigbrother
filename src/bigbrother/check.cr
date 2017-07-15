module Bigbrother
  module Check
    property app : Bigbrother::App?

    abstract def check
    abstract def target

    def start(app : App)
      @app = app
    end

    class Failure < Exception
      def initialize(@message : String)
      end
    end

    TYPES = [] of Class

    macro included
      {% TYPES << @type %}

      # TODO check name with YAML's `type:`
      macro config(_name, **properties)
        YAML.mapping(\{{**properties}})
      end
    end

    macro finished
      {% if TYPES.empty? %}
        {% raise "Please define at least one check" %}
      {% end %}

      alias Types = Array(Union({{ *TYPES }}))
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
  end
end
