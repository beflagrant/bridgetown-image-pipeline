# Internals

This document combines the two design specs that produced this gem's
implementation while it lived in the
[rubycentral/rubyconf-2026](https://github.com/rubycentral/rubyconf-2026)
repository. It is preserved here as design rationale; consult the ADRs in
[`./adr/`](./adr/) for the lockstep decisions that ship in 0.1.0.

The first half describes the original `image_pipeline` builder (PRs #97,
#105, #106). The second half describes the `bg_image_block` helper added in
PR #109. Both designs were validated by the production Lighthouse run on
rubyconf.org (mobile homepage perf 0.47 → 0.93).

---

# Bridgetown Image Pipeline — Design

**Status:** approved
**Author:** Jim Remsik (with Claude)
**Date:** 2026-05-14

## Problem

Lighthouse audits on rubyconf.org flag three image-delivery issues:

- **Properly size images** — ~232 KB savings. Full-resolution JPGs served to mobile viewports (e.g. `red-rocks.jpg` 158 KB rendered at 375×281).
- **Serve images in next-gen formats** — ~159 KB savings. Site uses only JPG/PNG; no AVIF or WebP.
- **Largest Contentful Paint** — 4.1 s on home, 2.9 s on `/location/`. Home LCP element is a CSS background image (`bg-[url(vert-landscape-zoom.jpg)]`) which browsers cannot preload.

Worst pages: `/location/` perf 0.79 (also CLS 0.311 from images without intrinsic dimensions), `/` and `/about/` perf 0.87.

Manual one-off compression has been used in the past but does not scale and does not produce responsive variants or modern formats.

## Goals

1. Eliminate the three Lighthouse image audits across the site.
2. Add intrinsic `width`/`height` to every emitted `<img>` to fix CLS.
3. Ship as a **generally applicable** Bridgetown plugin. Lives inline in this repo first; extractable to a `bridgetown-image-pipeline` gem with no API changes.
4. Zero-touch for most existing `<img>` tags (auto-rewrite via Inspector).
5. Opt-in explicit control where it matters (LCP hero, priority hints).

## Non-goals

- CSS background-image replacement. The home mobile hero (`bg-[url(...)]`) will be manually rewritten to `<img>` in a follow-up commit. Plugin scope is `<img>`/`<picture>` only.
- SVG processing. SVGs pass through unchanged.
- Animated GIF / WebM conversion.
- CDN integration. Output is static files; CDN is the host's concern.

## Architecture

Two-stage plugin, single process, runs during `bridgetown build`.

### Stage 1 — Builder

`Builders::ImagePipeline` runs on the `before :write` hook.

For each source matched by configured globs (`src/images/**/*.{jpg,jpeg,png}` by default):

1. Compute cache key = `SHA1(file_bytes + plugin_version + relevant_config)`.
2. If `.bridgetown-cache/image_pipeline/<key>.manifest.json` exists, reuse it. Skip processing.
3. Otherwise: use `image_processing/vips` to generate derivatives at the cross-product of:
   - Widths: `[400, 800, 1600]` (skip widths ≥ source width)
   - Formats: `[avif, webp]` + original format
4. Write derivatives to `output/_pipeline/images/<basename>-<width>.<ext>`.
5. Persist a per-source manifest fragment; merge into a site-wide manifest in memory for use by Stage 2.

Cache files git-ignored under `.bridgetown-cache/image_pipeline/`. CI rebuilds derivatives on cache miss; warm cache is a no-op.

### Stage 2a — `picture_tag` helper

Ruby helper registered via Bridgetown's helper API.

```erb
<%= picture_tag "/images/hero.jpg",
      alt: "Red Rock Canyon",
      sizes: "(min-width: 1024px) 33vw, 100vw",
      class: "w-full h-auto",
      priority: true %>
```

Output:

```html
<picture>
  <source type="image/avif"
          srcset="/_pipeline/images/hero-400.avif 400w,
                  /_pipeline/images/hero-800.avif 800w,
                  /_pipeline/images/hero-1600.avif 1600w"
          sizes="(min-width: 1024px) 33vw, 100vw">
  <source type="image/webp" srcset="..." sizes="...">
  <img src="/_pipeline/images/hero-800.jpg"
       srcset="/_pipeline/images/hero-400.jpg 400w,
               /_pipeline/images/hero-800.jpg 800w,
               /_pipeline/images/hero-1600.jpg 1600w"
       sizes="(min-width: 1024px) 33vw, 100vw"
       width="2400" height="1600"
       alt="Red Rock Canyon"
       class="w-full h-auto"
       fetchpriority="high"
       loading="eager"
       decoding="async">
</picture>
```

Behaviors:

- `priority: true` → `fetchpriority="high"` + `loading="eager"`. Default `loading="lazy"`.
- `width`/`height` always emitted from intrinsic dimensions → fixes CLS.
- Source not in manifest (SVG, missing file) → plain `<img>` fallback with a stderr warning.
- `sizes:` omitted → warning to stderr (image will work but Lighthouse may flag it).
- All HTML attributes other than the helper's known keys pass through to `<img>`.

### Stage 2b — Auto-rewrite Inspector

Bridgetown 2 Inspectors API hook on `:html` resources, after render.

1. Parse output HTML via Nokogiri.
2. For each `<img>` whose `src` matches a manifest entry **and** parent is not already `<picture>`:
   - Wrap with `<picture>`, inject `<source type="image/avif">` and `<source type="image/webp">` siblings.
   - Add `width`/`height` attrs if missing.
   - Leave existing `srcset`/`sizes`/`loading`/`fetchpriority` alone (don't override author intent).
3. Skip if `<img data-no-pipeline>` opt-out attribute present.

Inspector handles legacy `<img>` tags during migration. Helper preferred for new code (gives priority/sizes control).

## Configuration

Read from `bridgetown.config.yml`:

```yaml
image_pipeline:
  source_globs:
    - "src/images/**/*.{jpg,jpeg,png}"
  exclude:
    - "src/images/sponsors/**"
  widths: [400, 800, 1600]
  formats: [avif, webp]
  output_dir: "_pipeline/images"
  quality:
    avif: 50
    webp: 82
    jpeg: 85
  auto_rewrite: true
  fail_on_missing: false
```

All keys optional. Defaults baked in; sites override what they need.

## Error handling

| Scenario | Behavior |
|---|---|
| libvips not installed on host | Builder logs error, disables itself, site still builds (originals only). |
| Source file unreadable / corrupt | Warn with file path, skip that file. |
| Variant generation fails (encoder error, OOM) | Warn, omit that variant from the manifest, keep the rest. |
| Helper called with unknown source | Plain `<img>` fallback + stderr warning. Raise instead if `fail_on_missing: true`. |
| Cache key collision | Practically impossible (SHA1 over bytes + version + config). Last write wins. |

## File layout

```
plugins/builders/image_pipeline.rb        # builder + entry point
plugins/builders/image_pipeline/
  ├── processor.rb                        # image_processing/vips wrapper
  ├── manifest.rb                         # read/write/lookup
  ├── helpers.rb                          # picture_tag, registered via Bridgetown helpers
  ├── inspector.rb                        # HTML auto-rewrite
  └── config.rb                           # config loader + defaults
config/initializers.rb                    # register helper + inspector
```

When extracted to a gem: flatten to `lib/bridgetown/image_pipeline/*` and add a `Bridgetown::ImagePipeline::Plugin` registration class. Public API (helper name, config keys, manifest schema) does not change.

## Dependencies

- `image_processing` gem (~> 1.13)
- `ruby-vips` gem (transitive)
- libvips system library (host responsibility — `brew install vips` / `apt install libvips`)

The site's existing GitHub Actions workflow installs `imagemagick` for a separate concern; we add a `libvips` install step.

## Testing strategy

**In this repo:** smoke tests only.
- Build succeeds with plugin enabled.
- Sample image (`src/images/red-rocks.jpg`) produces expected derivative files.
- Manifest contains expected entries.

**When extracted to gem:** full RSpec suite.
- Unit tests: cache keying, manifest serialization, helper output snapshots, inspector wrapping logic.
- Integration test: build a fixture Bridgetown site end-to-end.

## Rubyconf integration (follow-up work)

After plugin lands, in a separate PR:

1. Run build once to populate the manifest.
2. Audit `git grep '<img src='` for swap candidates.
3. Replace explicit `<img>` with `picture_tag` where priority/sizes matter:
   - `src/_pages/location.md` — `red-rock_crystal.jpg`, `hotel_room.jpg`
   - `src/_pages/about.md` — `all-flora.jpg`
   - `src/index.md` — `red-rocks.jpg`, `all-flora.jpg`
4. Rewrite home mobile hero `bg-[url(vert-landscape-zoom.jpg)]` div as `<img priority: true>`.
5. Let the Inspector handle the rest (sponsor logos, speaker headshots, etc.).

Expected outcomes:

- LCP `/` 4.1 s → ~2.5 s (preloadable `<img>` + AVIF + correctly sized).
- Perf `/location/` 0.79 → 0.95+ (responsive + AVIF + width/height for CLS).
- "Modern image formats" Lighthouse audit: pass (~159 KB savings realized).
- "Properly size images" Lighthouse audit: pass (~232 KB savings realized).
- CLS on `/location/` 0.311 → near zero (intrinsic dimensions on every `<img>`).

## Open questions

None at design time. Resolve at implementation:

- AVIF quality 50 may need tuning per image; revisit if visible artefacts appear.
- 1600 px max width is conservative for retina laptops viewing full-bleed. Acceptable for v1; widen if needed.
# CSS `bg-[url(...)]` Through the Image Pipeline

**Date:** 2026-05-14
**Status:** Approved, pending implementation plan

## Problem

Several pages reference raw JPG/PNG bitmaps directly from CSS via Tailwind
`bg-[url(/images/foo.png)]`. These images bypass the `image_pipeline` builder
that already emits AVIF/WebP derivatives at multiple widths for everything
referenced through `picture_tag`. Lighthouse reports two consequences on the
homepage:

- LCP `/` mobile 3.7s with a 2993ms render-delay phase
- Two opportunities flagged: `offscreen-images` (~79 KiB) and
  `uses-responsive-images` (~104 KiB)

The deferred-followup memory cites a roughly 432 KiB total payload reduction
across the affected pages. The biggest single offender is `/`'s
`bg-[url(/images/all-flora.jpg)]` (216 KiB raw JPG).

All raw bitmap backgrounds in the site:

| Page | Raw bg image | KiB |
| --- | --- | --- |
| `src/index.md:86` | `all-flora.jpg` | 216 |
| `src/index.md:13` | `about-flowers.png` | 92 |
| `src/index.md:31` | `vert-landscape-zoom.jpg` (already in pipeline; `<picture>` already exists alongside) | 80 |
| `src/_pages/about.md:9` | `about-flowers.png` | 92 |
| `src/_pages/location.md:37` | `about-flowers.png` | 92 |
| `src/_pages/sponsors.md:45` | `flowers_full_bottom.png` | 88 |
| `src/_pages/code_of_conduct.md:8` | `flowers_full_bottom.png` | 88 |
| `src/_pages/policies.md:8` | `flowers_full_bottom.png` | 88 |
| `src/_pages/speakers.md:8` | `yellow-flower-full-b.png` | 96 |
| `src/_pages/ruby_runway.md:66` | `yellow-flower-full-b.png` | 96 |
| `src/_pages/faqs.md:8` | `faq-flowers.png` (only ≥1024px) | 48 |
| `src/_pages/faqs.md:33-36` | `corner-plant-right.png`, `yellow-flower-bottom.png`, `orange-flower-bottom.png`, `faq-flowers.png` (rotated) | 48-104 each |

Out of scope: `src/_layouts/splash.erb` and the `desert-flora*.png` family
referenced from it. The splash layout is unused and will be removed in the
same migration.

## Goal

Ship AVIF and WebP derivatives from the existing pipeline to every CSS
background-image reference, with width selection that follows Tailwind
breakpoints, while preserving the existing `bg-[url(...)]` ergonomics for
template authors.

Non-goals: `<picture>`-based hero replacement for `all-flora.jpg`,
preloading bg images, lazy bg loading, or changes to the existing
`picture_tag` API.

## Architecture

Add a single ERB helper, `bg_image_block(src, breakpoint_only: nil)`, in the
existing `Builders::ImagePipeline::Helpers` module. The helper:

1. Looks up the source in the pipeline manifest.
2. Derives a stable class name from the source basename.
3. Renders one `<style>` block containing one default rule plus
   `@media (max-width: ...)` overrides for each Tailwind breakpoint that has
   a smaller pipeline derivative.
4. Returns the `<style>` fragment so the template can emit it next to the
   element that uses the class.

Templates use it like:

```erb
<%= bg_image_block("/images/all-flora.jpg") %>
<section class="bg-img-all-flora bg-cover p-6 md:p-10 lg:p-20">
  ...
</section>
```

No site-wide CSS bundle is touched. No `<head>` registration. No Bridgetown
render hooks. Each call is self-contained.

### Why inline `<style>`, not a `<head>` collector

The `<head>` partial renders before the body in source order, but ERB
streams sequentially, so a head-time accumulator call would run before any
`bg_image_block` calls in the body. A `post_render` hook could string-patch
the final HTML to inject styles into `<head>`, but that adds plumbing for a
modest payload win. Browsers parse `<style>` blocks anywhere in the
document. A short style fragment placed immediately before the element that
uses it does not regress LCP because the relevant rule is parsed before the
element comes into view.

The cost is one `<style>` block per background. The faqs page is the
upper bound at five blocks; total emitted CSS for that page is well under
2 KiB.

### Tailwind interop

Helper-emitted class names live in inline `<style>` fragments and never
appear in template source. Tailwind's purge does not see them and does not
need to. Templates continue to use Tailwind utilities (`bg-cover`,
`bg-no-repeat`, etc.) alongside the helper-emitted class. The helper sets
only `background-image`; positioning, sizing, and repetition stay with
Tailwind.

## Components

### `Helpers#bg_image_block(src, breakpoint_only: nil)`

Public API. Returns a `<style>` fragment string. Stateless and
deterministic: re-calling with the same source always emits the same class
name and the same CSS. The helper does not deduplicate across calls. A
companion accessor `bg_image_class(src)` returns just the derived class
name (no `<style>`), so templates that legitimately need the same
background twice can emit the block once and reference the class twice.

`breakpoint_only:` accepts an integer pixel value (e.g. `1024`). When set,
the entire `background-image` declaration is wrapped in a single
`@media (min-width: 1024px)` block. This supports the existing
`lg:bg-[url(...)]` usage on `/faqs`.

### `Helpers#bg_image_class(src)`

Returns the derived class name string for `src` with no side effects and
no `<style>` output. Templates that emit the `<style>` block in one place
and reference the same class elsewhere use this accessor.

### `BgImageSet.css(class_name:, derivatives:, breakpoints:, default_width:, breakpoint_only: nil)`

Pure function. Takes manifest data plus the breakpoint map, returns the CSS
string. No Bridgetown or site coupling. Unit-tested in isolation.

```ruby
BREAKPOINTS = { 640 => 400, 768 => 600, 1024 => 800, 1280 => 1200 }.freeze
DEFAULT_WIDTH = 1600
```

Mapping: breakpoint pixel value → pipeline-derivative width. Default rule
uses `1600` if present in the manifest; otherwise the largest available
width.

If a configured breakpoint width is missing from the manifest, the function
logs a warning and substitutes the nearest available width.

### `Manifest#variants_by_width(src)` (new narrow accessor)

Optional helper on the existing `Manifest` to return
`{ width => { format => path } }` for a source. Built on the existing
`find_by_src` plus `entry[:variants]`. Keeps `BgImageSet.css` free of
manifest-shape knowledge.

### Class-name derivation

```ruby
"bg-img-#{File.basename(src, ".*").downcase.gsub(/[^a-z0-9]+/, "-")}"
```

`/images/all-flora.jpg` → `bg-img-all-flora`.
`/images/flowers_full_bottom.png` → `bg-img-flowers-full-bottom`.

Slug collisions between distinct sources (e.g. `corner-plant.png` and
`corner-plant_b.png` both slugify to `bg-img-corner-plant`) raise
`ArgumentError`. Audit: today's set has no slug collisions, so this
constraint costs nothing.

## Data flow

```text
template renders
  → bg_image_block("/images/all-flora.jpg")
  → Manifest#variants_by_width("/images/all-flora.jpg")
    → { 400 => {avif: "/_pipeline/.../-400.avif", webp: ...},
        600 => ..., 800 => ..., 1200 => ..., 1600 => ... }
  → BgImageSet.css(
       class_name: "bg-img-all-flora",
       derivatives: ...,
       breakpoints: BREAKPOINTS,
       default_width: 1600
     )
  → "<style>.bg-img-all-flora{background-image:image-set(
       url(/_pipeline/images/all-flora-1600.avif) type('image/avif'),
       url(/_pipeline/images/all-flora-1600.webp) type('image/webp'))}
     @media (max-width:1280px){.bg-img-all-flora{background-image:image-set(
       url(/_pipeline/images/all-flora-1200.avif) type('image/avif'),
       url(/_pipeline/images/all-flora-1200.webp) type('image/webp'))}}
     ...
     </style>"
  → returned to ERB, inlined before <section>
```

No build-time mutation. Manifest is fully populated before any template
renders.

## CSS shape

Format selection uses `image-set()` with `type()` annotations and only
modern formats:

```css
.bg-img-all-flora {
  background-image: image-set(
    url(/_pipeline/images/all-flora-1600.avif) type('image/avif'),
    url(/_pipeline/images/all-flora-1600.webp) type('image/webp')
  );
}
@media (max-width: 1280px) { .bg-img-all-flora { background-image: image-set(
  url(/_pipeline/images/all-flora-1200.avif) type('image/avif'),
  url(/_pipeline/images/all-flora-1200.webp) type('image/webp')
); } }
@media (max-width: 1024px) { /* 800w */ }
@media (max-width: 768px)  { /* 600w */ }
@media (max-width: 640px)  { /* 400w */ }
```

For `breakpoint_only: 1024`, the entire block is wrapped:

```css
@media (min-width: 1024px) {
  .bg-img-faq-flowers { background-image: image-set(...1600...); }
  @media (max-width: 1280px) { .bg-img-faq-flowers { ...1200... } }
}
```

Browser support: AVIF in CSS `image-set()` is widely supported in 2026 (all
major evergreen browsers). WebP is the fallback. There is no raw-image
fallback in the emitted CSS; browsers that support neither (no longer a
meaningful share) render no background, which on the affected sections is a
decorative-only loss.

## Error handling

- **Source missing from manifest:** log
  `[image_pipeline] no manifest entry for #{src}; bg_image_block falling back to url(#{src})`
  and emit `background-image: url(#{src})`. Matches the existing
  `picture_tag` philosophy when `fail_on_missing: false` (the project's
  current setting).
- **Configured breakpoint width missing from manifest:** log
  `[image_pipeline] bg_image_block: no #{width}w derivative for #{src}; using #{nearest}w`
  and substitute the nearest available width.
- **Slug collision (different src → same class name):** raise
  `ArgumentError` at template render time with both source paths in the
  message. Build fails. Author fixes by renaming one source.

## Migration plan

Each step is its own commit. Lighthouse is re-run after each step to
confirm no regression.

1. Add `bg_image_block` helper, `BgImageSet` module, breakpoint constants,
   unit tests, and `Manifest#variants_by_width`. No template changes yet.
2. `/` (`src/index.md`): replace two `bg-[url(...)]` references
   (`all-flora.jpg`, `about-flowers.png`).
3. `/about`, `/location`: replace `about-flowers.png` reference.
4. `/sponsors`, `/code_of_conduct`, `/policies`: replace
   `flowers_full_bottom.png` reference.
5. `/speakers`, `/ruby_runway`: replace `yellow-flower-full-b.png`
   reference.
6. `/faqs`: replace five backgrounds, including the
   `lg:bg-[url(...)]` case using `breakpoint_only: 1024`. Hold for last
   because the rotated-plant loop has the most variance.
7. Delete `src/_layouts/splash.erb` and the `desert-flora*.png` files
   from `src/images`.

## Testing

Three layers:

1. **`BgImageSet.css` unit tests** (Ruby, no Bridgetown loaded). Cases:
   - Full manifest with every breakpoint width present emits one default
     rule plus four `@media` overrides.
   - Manifest missing one breakpoint width logs warning and uses nearest.
   - Source missing entirely emits `url(src)` fallback rule.
   - `breakpoint_only: 1024` produces single `@media (min-width:1024px)`
     wrapper.
2. **Helper integration test.** Render an ERB fixture page that calls
   `bg_image_block` for a fixture image. Assert the rendered HTML contains
   `<style>` with the expected class and a `.avif` URL.
3. **End-to-end.** The existing Lighthouse CI run on `main` covers this.
   Pre-existing `bin/post_deploy_check` already audits every page in
   `config/deploy_pages.yml`.

## Risks and open questions

- **Browser support for AVIF in `image-set()`.** Verified at design time
  (May 2026) for current evergreen browsers. If the project ever needs to
  support an older WebView, restoring a `url()` fallback inside the same
  `image-set()` is a one-line change.
- **`@media` ordering.** Browser cascade is the same as for any
  `<style>` block. Default rule first, smaller-than overrides after.
- **`<style>` per call vs consolidated.** Accepted trade-off; faqs upper
  bound is ~2 KiB CSS for five backgrounds, negligible against the byte
  reduction.
- **Slug collisions today:** none in the current image set. Constraint is
  free to add now; refactoring out later if it bites is simple.

## Expected impact

| Page | Today (raw bg total) | Projected (largest AVIF, ~70% reduction) |
| --- | --- | --- |
| `/` | 308 KiB (216 + 92) | ~90 KiB |
| `/about` | 92 KiB | ~28 KiB |
| `/location` | 92 KiB | ~28 KiB |
| `/sponsors` | 88 KiB | ~26 KiB |
| `/code_of_conduct` | 88 KiB | ~26 KiB |
| `/policies` | 88 KiB | ~26 KiB |
| `/speakers` | 96 KiB | ~30 KiB |
| `/ruby_runway` | 96 KiB | ~30 KiB |
| `/faqs` | ~240 KiB (5 plants) | ~75 KiB |

Aggregate site weight reduction: roughly 1 MiB across affected pages, with
the homepage carrying the largest single-page improvement.
