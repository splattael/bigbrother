# AGENTS.md

Notes for agents (and humans) working on `bigbrother`. Read this before
changing anything under `src/`.

## What this is

A small Crystal daemon. It loads a YAML config, runs every check in it every
`check_every` seconds, and hands each result to every notifier. That is the
whole program; `src/bigbrother/app.cr` is 70 lines and worth reading in full.

    config.yml ──► Config ──► App ──┬─► Check#run ──► Check::Response ─┐
                                    │                                  │
                                    └─► Notifier#notify ◄──────────────┘

- `src/bigbrother/check/` -- one file per check type (`http`, `host_ip`, `ftp`).
- `src/bigbrother/notifier/` -- one file per notifier (`console`, `prometheus`, `telegram`).
- `src/bigbrother/helper/` -- shared bits, currently only certificate expiry.
- `src/ext/` -- YAML constructors for types the stdlib does not parse (`Regex`,
  `HTTP::Headers`, OpenSSL's ASN.1 time).

Everything is wired up by `require "./bigbrother/**"`, so a new file in
`src/bigbrother/check/` needs no registration anywhere else.

## Adding a check

Include `Check` and call the `config` macro. The first argument is the value
of the `type:` key in YAML; the rest becomes a `YAML.mapping`.

```crystal
module Bigbrother
  module Check
    class Example
      include Check

      config "example",
        host: String,
        port: {type: Int32, default: 21}

      def check                 # raise (or `fail "..."`) to report a failure
        fail "boom" unless ok?
      end

      def endpoint              # stable identity, used by the prometheus notifier
        "#{@host}:#{@port}"
      end

      def label                 # what a human sees; may carry extra detail
        endpoint
      end
    end
  end
end
```

`Check#run` wraps `check` in a `begin/rescue` and turns the outcome into a
`Check::Response`, so `check` should raise rather than return a status. Use
`fail(message)` for expected failures -- it raises `Check::Failure`, which
reads better in a notification than a stack-trace-worthy exception.

`retries` is added to every check's mapping by the macro; `App` handles it.

### Gotchas

- **`type:` decides, not the parse.** `Check.new` tries each registered type in
  turn and keeps the one whose `type` matches. Types are registered in the
  order the files are required, i.e. alphabetically, so do not rely on
  ordering -- and do not "optimise" the dispatch by returning the first type
  that parses. Several check types accept a bare `host`/`port` node.
- **`YAML.mapping`, not `YAML::Serializable`.** This is the old `yaml_mapping`
  shard, kept because the `config` macro builds on it. Optional attributes
  need an explicit `nilable: true` *and* a `default:`; a `default:` alone
  means "not nilable, but may be omitted".
- **Anything unusual in a mapping needs an `src/ext/` constructor.** `Regex`
  and `HTTP::Headers` already have one. Enums work out of the box.
- **Never put a password in a failure message.** Notifications go to Telegram
  and to stdout.
- Checks run concurrently in fibers. Keep them free of shared mutable state
  beyond the instance itself.

## Testing

    make test          # crystal spec
    make build         # shards build
    make build-release # stripped, --release, for a deploy

`spec/spec_helper.cr` holds helpers that stand up real servers on an unused
local port rather than stubbing clients -- `with_http_server`,
`with_ftp_server` (a scripted control connection), `with_ftp_store_server` (a
real one, with passive data connections and an in-memory file map),
`with_trusted_tls_server` and `with_self_signed_cert`. Prefer extending those
over mocking: the bugs worth catching here are protocol bugs, and several of
them only appear once two sockets are involved.

One trap when writing such a server: an `OpenSSL::SSL::Socket` buffers where a
`TCPSocket` does not. A fake server that announces a transfer and then blocks
accepting the data connection will deadlock under TLS unless it sets
`sync = true` or flushes first.

The TLS helpers shell out to `openssl`, so the CLI has to be installed. They
use `openssl ca -selfsign -startdate/-enddate` rather than `req -x509
-not_after` or a negative `-days`, both of which some OpenSSL builds reject.

CI (`.gitlab-ci.yml`) runs `crystal spec` on `crystallang/crystal:1.21.0` for
every merge request, then builds and uploads a binary on `master`.

## Conventions

- Run `crystal tool format` on the files you touched before committing. Do not
  reformat the rest: a few files predate the current formatter and reformatting
  them buries the actual change in noise. CI does not check formatting.
- Comments explain *why*, not *what*. Most of the existing ones record a
  failure that was painful to diagnose -- keep that habit and leave the
  reasons behind, especially for protocol quirks and toolchain workarounds.
- Every new check type goes into `README.md` (a bullet plus a section) and
  into `config.yml.sample` with every option listed and commented out at its
  default. Both files are the documentation.
- `shard.yml` pins dependencies by tag or commit. Keep it that way.
