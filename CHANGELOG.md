# Changelog

All notable changes to this gem are recorded in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-15

Initial release. Extracted from
[rubycentral/rubyconf-2026](https://github.com/rubycentral/rubyconf-2026)
after six PRs of in-repo iteration (#97, #105, #106, #109, #110, #112).

### Added

- Build-time AVIF and WebP derivative generation via libvips at configurable
  widths (defaults: 400, 600, 800, 1200, 1600).
- `picture_tag(src, alt:, sizes:, priority:, **attrs)` ERB helper for
  responsive `<picture>` elements.
- `bg_image_block(src, breakpoint_only:, class_suffix:)` ERB helper that
  emits an inline `<style>` block with `image-set(avif, webp)` declarations
  plus Tailwind-breakpoint `@media` overrides.
- `bg_image_class(src, class_suffix:)` ERB helper that returns the derived
  CSS class name without a `<style>` block, for cases that need the class
  in multiple places after emitting the block once.
- `Inspector` (off by default) that walks rendered HTML and rewrites bare
  `<img src="/images/...">` references into responsive `<picture>` tags.
- Per-derivative cache under `.bridgetown-cache/image_pipeline/`, keyed by
  source SHA1 + gem version + config fingerprint.
- Configurable via initializer block:
  ```ruby
  init "bridgetown-image-pipeline" do
    widths        [400, 800, 1600]
    auto_rewrite  true
  end
  ```

### Notes for adopters

- `output_dir` defaults to `_bridgetown/image_pipeline` (under Bridgetown's
  framework-reserved prefix). Override via `output_dir: "your/path"` if you
  need to preserve URLs from a prior in-repo plugin layout.
- `auto_rewrite` and `fail_on_missing` both default to `false` (conservative
  defaults). Enable explicitly if you want the Inspector or strict
  missing-manifest behaviour.

[Unreleased]: https://github.com/beflagrant/bridgetown-image-pipeline/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/beflagrant/bridgetown-image-pipeline/releases/tag/v0.1.0
