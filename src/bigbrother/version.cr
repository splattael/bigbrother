module Bigbrother
  VERSION = "0.1.0"

  # .git is not available in the Docker build context (see .dockerignore),
  # so CI passes the commit SHA in via the GIT_SHA1 build-time env var.
  VERSION_SHA1 = {% if env("GIT_SHA1") %}
                   {{ env("GIT_SHA1") }}
                 {% else %}
                   {{ `git rev-parse --short HEAD 2>/dev/null || echo "??????"`.stringify.chomp }}
                 {% end %}
  VERSION_DATE = {{ `date +%F`.stringify.chomp }}
end
