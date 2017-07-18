# bigbrother

Server overseer.

`bigbrother` runs predefined checks (e.g. HTTP, TCP) every `n` seconds and notifies (via e.g. Telegram) you if any these checks fail.

See `config.yml.sample` for some example checks.

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
