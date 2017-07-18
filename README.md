# bigbrother

Server overseer.

`bigbrother` runs predefined checks (e.g. HTTP, TCP) every `n` seconds and notifies (via e.g. Telegram) you if any of these checks fail.

See `config.yml.sample` for some example checks.

## Checks

Currently, the following checks are implemented:

* [http](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/check/http.cr) - Check a URL for specific for its HTTP status code or content.
* [host_ip](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/check/host_ip.cr) - Check a host and ip via TCP.

## Notifiers

A list of available notifiers:

* [telegram](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/notifier/telegram.cr) - Notify via Telegram's bot.
* [console](https://github.com/splattael/bigbrother/blob/master/src/bigbrother/notifier/console.cr) - Print all checks on your terminal.

## Installation

    make build-release
    bin/bigbrother

## Usage

    bin/bigbrother -h
    bin/bigbrother -c config.yml

### Example config

See `config.yml.sample`.

## Development

    make build
    bin/bigbrother

## Contributing

1. Fork it ( https://github.com/splattael/bigbrother/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [splattael](https://github.com/splattael) Peter Leitzen - creator, maintainer
