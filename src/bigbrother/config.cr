require "yaml"

module Bigbrother
  class Config
    YAML.mapping(
      check_every: Int32,
      notifiers: Array(Notifier),
      checks: Array(Check)
    )
  end
end
