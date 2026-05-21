# bridgetown-image-pipeline

A Bridgetown 2.0+ plugin that pre-generates responsive image derivatives
(**AVIF**, **WebP**) at multiple widths, plus ERB helpers for `<picture>`
elements and CSS `image-set()` backgrounds.

## Features

- **Build-time derivative generation** via libvips. AVIF + WebP at configurable
  widths (default: 600, 1200, 1600). Source-width-aware (no upscaling).
- **`picture_tag` helper** — emits `<picture>` with `<source>` per format and
  an `<img>` fallback with `srcset` + `sizes`.
- **`bg_image_block` helper** — emits an inline `<style>` block with
  `background-image: image-set(...)` rules for backgrounds. Tailwind-breakpoint
  aware. Drop-in replacement for `bg-[url(...)]` utilities.
- **`Inspector`** (optional, off by default) — rewrites bare `<img>` tags in
  rendered HTML to wrap them in `<picture>` with the appropriate sources.
- **Per-derivative cache** keyed by source SHA1 + gem version + config
  fingerprint. Rebuilds skip unchanged sources.

## Requirements

- Ruby >= 3.2
- Bridgetown >= 2.0, < 3.0
- libvips with **HEIF/AVIF plugin** installed

## Quick start

```ruby
# Gemfile
gem "bridgetown-image-pipeline"
```

```ruby
# config/initializers.rb
Bridgetown.configure do |config|
  init "bridgetown-image-pipeline"
end
```

```erb
<%= picture_tag "/images/hero.jpg", alt: "...", sizes: "100vw" %>
```

See [`docs/INSTALLATION.md`](docs/INSTALLATION.md) for libvips setup, CI
configuration, and activation options.

## Documentation

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) — libvips + HEIF/AVIF
  setup, GitHub Actions, plugin activation
- [`docs/HELPERS.md`](docs/HELPERS.md) — `picture_tag`, `bg_image_block`,
  `bg_image_class`, and the `Inspector`
- [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) — all options and
  defaults, plus the Tailwind v4 `bg-[url(...)]` gotcha
- [`docs/INTERNALS.md`](docs/INTERNALS.md) — design spec
- [`docs/adr/`](docs/adr/) — architecture decision records
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — development setup, tests, releases

## License

MIT — see [`LICENSE.txt`](LICENSE.txt).

## Status

Maintained by [Flagrant](https://beflagrant.com). No SLA. Issues and PRs
welcome at
[github.com/beflagrant/bridgetown-image-pipeline](https://github.com/beflagrant/bridgetown-image-pipeline).
