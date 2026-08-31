# bigbrother

Server overseer.

`bigbrother` runs predefined checks (e.g. HTTP, TCP) every `n` seconds and notifies (via e.g. Telegram) you if any of these checks fail.

See `config.yml.sample` for some example checks.

## Screenshots

![console](https://github.com/splattael/bigbrother/blob/master/assets/bigbrother.console.png)
![telegram](https://github.com/splattael/bigbrother/blob/master/assets/bigbrother.telegram.png)

## Checks

Currently, the following checks are implemented:

* [http](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/check/http.cr) - Check a URL for specific for its HTTP status code or content.
* [host_ip](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/check/host_ip.cr) - Check a host and ip via TCP.

## Notifiers

A list of available notifiers:

* [telegram](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/notifier/telegram.cr) - Notify via Telegram's bot.
* [console](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/notifier/console.cr) - Print all checks on your terminal.
* [prometheus](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/notifier/prometheus.cr) - Collect and expose Prometheus metrics.

## Installation

    make build-release
    bin/bigbrother

## Usage

    bin/bigbrother -h
    bin/bigbrother -c config.yml

### Example config

See `config.yml.sample`.

### Reload config dynamically

To reload bigbrother's config dynamically send signal `SIGHUP` to the running process.

    kill -HUP $(pidof bigbrother)

Caveats:

- Checks already in flight are not cancelled and run to completion and may still notify under the old config
- No new checks are scheduled until the new App has taken over
- If the new config file is missing or invalid, the reload is discarded and the current config keeps running

## Development

    make build
    bin/bigbrother

## Testing

    make test

Runs the spec suite (`crystal spec`). Some specs generate self-signed certificates on the fly (e.g. to test SSL certificate expiry checks) and require the `openssl` CLI to be installed. The suite also runs as a `test` job in CI (see `.gitlab-ci.yml`).

## Contributing

1. Fork it ( https://github.com/splattael/bigbrother/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [splattael](https://github.com/splattael) Peter Leitzen - creator, maintainer
