require "yaml"

module Bigbrother
  class Config
    YAML.mapping(
      check_every: Int32,
      notifiers: Notifier::Types,
      checks: Check::Types
    )
  end
end
