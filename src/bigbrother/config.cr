require "yaml"

module Bigbrother
  class Config
    YAML.mapping(
      check_every: Int32,
      retries: {
        type:    Int32,
        default: 0i32,
      },
      notifiers: Array(Notifier),
      checks: Array(Check)
    )
  end
end
