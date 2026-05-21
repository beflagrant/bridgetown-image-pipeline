# Contributing

Issues and PRs welcome at
[github.com/beflagrant/bridgetown-image-pipeline](https://github.com/beflagrant/bridgetown-image-pipeline).

## Development

```sh
bin/setup
bundle exec rake test
bundle exec rake rubocop
```

CI runs against Ruby 3.2/3.3/3.4 × Bridgetown 2.0/edge.

## Architecture

- [`docs/INTERNALS.md`](docs/INTERNALS.md) — design spec
- [`docs/adr/`](docs/adr/) — architecture decision records covering the
  helper API, output paths, defaults, and cache-key invariants

## Releases

See [`RELEASING.md`](RELEASING.md).
