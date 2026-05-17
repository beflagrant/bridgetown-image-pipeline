# bridgetown-image-pipeline

A Bridgetown 2.0+ plugin that pre-generates responsive **AVIF** and **WebP**
image derivatives at multiple widths, plus ERB helpers for `<picture>`
elements and CSS `image-set()` backgrounds.

Used in production at [rubyconf.org](https://rubyconf.org) — homepage mobile
Lighthouse perf score went from **0.47 → 0.93** after the bg-image migration.

## Features

- **Build-time derivative generation** via libvips. AVIF + WebP at configurable
  widths (default: 400, 600, 800, 1200, 1600). Source-width-aware (no upscaling).
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
- libvips with **HEIF/AVIF plugin** installed (see Installation below)

## Installation

Add to your site's `Gemfile`:

```ruby
gem "bridgetown-image-pipeline"
```

Then `bundle install`.

### libvips with HEIF/AVIF support

The plugin needs libvips compiled with HEIF support so it can encode AVIF.

**macOS (Homebrew):**

```sh
brew install vips
```

**Ubuntu / Debian:**

```sh
sudo apt-get install libvips libvips-tools \
  libheif1 libheif-dev libheif-plugin-aomenc libheif-plugin-libde265
```

**Verify the encoder works:**

```sh
vips --vips-config | tr ',' '\n' | grep -i heif
vips black /tmp/_check.avif 16 16 && rm /tmp/_check.avif
```

Both lines should succeed. If the second fails with "cannot encode AVIF", the
libheif AV1 encoder plugin (`libheif-plugin-aomenc` on Ubuntu) is missing.

### CI: GitHub Actions

See [`examples/github-actions-build.yml`](examples/github-actions-build.yml) for
a minimal `ubuntu-latest` workflow. The important step is installing libvips +
libheif **before** `setup-ruby`, otherwise `ruby-vips` fails to `dlopen`
`vips.so.42` at require time and Bridgetown surfaces a misleading

> Dependency Error: Hmm, it looks like you don't have
> `bridgetown-image-pipeline' or one of its dependencies installed.

even though `bundle install` succeeds and `bundle show bridgetown-image-pipeline`
finds the gem.

### Activate the plugin

In `config/initializers.rb`:

```ruby
Bridgetown.configure do |config|
  init "bridgetown-image-pipeline"
end
```

Or with overrides:

```ruby
Bridgetown.configure do |config|
  init "bridgetown-image-pipeline" do
    widths        [400, 800, 1200, 1600]
    auto_rewrite  true                          # enable the Inspector
    output_dir    "_bridgetown/image_pipeline"  # default
  end
end
```

## Usage

### `picture_tag` — responsive `<picture>` elements

```erb
<%= picture_tag "/images/hero.jpg",
      alt: "Sandstone formations at sunset",
      sizes: "(min-width: 1024px) 50vw, 100vw",
      priority: true,
      class: "w-full h-auto" %>
```

Renders:

```html
<picture>
  <source type="image/avif" srcset="/_bridgetown/image_pipeline/hero-400.avif 400w, ..." sizes="...">
  <source type="image/webp" srcset="/_bridgetown/image_pipeline/hero-400.webp 400w, ..." sizes="...">
  <img src="/_bridgetown/image_pipeline/hero-1600.jpg"
       srcset="..." sizes="..."
       width="2400" height="1600"
       alt="Sandstone formations at sunset"
       loading="eager" decoding="async" fetchpriority="high"
       class="w-full h-auto">
</picture>
```

`priority: true` adds `loading="eager"` and `fetchpriority="high"`. Use for
LCP candidates only.

### `bg_image_block` — responsive CSS backgrounds

For decorative `background-image` use cases. Emits an inline `<style>`
block; the caller uses the returned class on the element:

```erb
<%= bg_image_block "/images/all-flora.jpg" %>
<section class="bg-img-all-flora bg-cover p-6 lg:p-20">
  ...
</section>
```

Class names are derived from the source basename:
`/images/all-flora.jpg` → `bg-img-all-flora`.

**Breakpoint-only backgrounds** (replicates Tailwind's `lg:bg-[url(...)]`):

```erb
<%= bg_image_block "/images/hero.jpg", breakpoint_only: 1024 %>
<section class="bg-img-hero bg-cover">  <!-- bg only shows >=1024px -->
```

**Same source in two contexts** (e.g. hero + decorative loop):

```erb
<%= bg_image_block "/images/flowers.png", class_suffix: "hero" %>
<section class="bg-img-flowers-hero ...">

<%= bg_image_block "/images/flowers.png" %>
<div class="bg-img-flowers ...">
```

The `class_suffix:` kwarg keeps the two `<style>` blocks from colliding.

### `bg_image_class` — class name only, no style block

When you need to reference the class in multiple places after emitting the
block once:

```erb
<%= bg_image_block "/images/flowers.png" %>
<% klass = bg_image_class("/images/flowers.png") %>
<section class="<%= klass %> ...">...</section>
<aside class="<%= klass %> ...">...</aside>
```

### `Inspector` — auto-wrap bare `<img>` tags

Off by default. Enable in your initializer:

```ruby
init "bridgetown-image-pipeline" do
  auto_rewrite true
end
```

When on, any rendered `<img src="/images/foo.jpg">` whose source is in the
manifest is rewritten as a `<picture>` with the appropriate sources.
Opt-out on a per-tag basis with `data-no-pipeline`:

```html
<img src="/images/exact-bytes-required.jpg" data-no-pipeline>
```

## Configuration

All options, with defaults:

| Option | Default | Description |
|--------|---------|-------------|
| `source_globs` | `["src/images/**/*.{jpg,jpeg,png}"]` | What to process. **Must live under `src/`** — public URLs are derived by stripping the `src/` prefix, so `src/images/foo.jpg` becomes `/images/foo.jpg` in `picture_tag` lookups. Sources outside `src/` are processed but unreachable from templates. |
| `exclude` | `[]` | Glob patterns to skip |
| `widths` | `[400, 600, 800, 1200, 1600]` | Derivative widths |
| `formats` | `[:avif, :webp]` | Output formats (plus original) |
| `output_dir` | `"_bridgetown/image_pipeline"` | Output path under `output/` |
| `quality` | `{ avif: 65, webp: 88, jpeg: 88 }` | Per-format quality |
| `auto_rewrite` | `false` | Enable the Inspector |
| `fail_on_missing` | `false` | Raise vs. warn on missing manifest |
| `breakpoints` | `{ 640 => 400, 768 => 600, 1024 => 800, 1280 => 1200 }` | Tailwind-style breakpoints for `bg_image_block` |
| `default_width` | `1600` | Default tier for `bg_image_block`'s un-prefixed rule |

## Gotcha: Tailwind v4 and `bg-[url(...)]` in docs

Tailwind v4 auto-scans every file from the CSS entrypoint's parent dir up to
the git root. If your repo has Markdown documentation that quotes raw
Tailwind classes like `bg-[url(...)]` (e.g. in a README that explains a
migration from the old utility to this plugin), Tailwind will pick those
literal strings up and try to emit CSS rules for them. esbuild will then
fail to resolve the `...` placeholder URL, breaking your build.

Fix: add `@source not` directives to your Tailwind CSS:

```css
@import "tailwindcss";
@source not "../../docs/**";
@source not "../../test/**";
```

## Architecture

See [`docs/INTERNALS.md`](docs/INTERNALS.md) for the design spec and
[`docs/adr/`](docs/adr/) for the architecture decision records covering
the helper API, output paths, defaults, and cache-key invariants.

## Development

```sh
bin/setup
bundle exec rake test
bundle exec rake rubocop
```

CI runs against Ruby 3.2/3.3/3.4 × Bridgetown 2.0/edge.

## License

MIT — see [`LICENSE.txt`](LICENSE.txt).

## Status

Maintained by [Flagrant](https://beflagrant.com) for use in production at
[rubyconf.org](https://rubyconf.org). No SLA. Issues and PRs welcome at
[github.com/beflagrant/bridgetown-image-pipeline](https://github.com/beflagrant/bridgetown-image-pipeline).
