module Bigbrother
  VERSION      = "0.1.0"
  VERSION_SHA1 = {{ `git rev-parse --short HEAD`.stringify.chomp }}
  VERSION_DATE = {{ `date +%F`.stringify.chomp }}
end
