module Bigbrother
  module Notifier
    property app : Bigbrother::App?

    def start(app : App)
      @app = app
    end

    abstract def notify(response : Check::Response, only_errors : Bool)

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
        {% raise "Please define at least one notifier" %}
      {% end %}

      alias Types = Array(Union({{ *TYPES }}))
    end
  end
end
