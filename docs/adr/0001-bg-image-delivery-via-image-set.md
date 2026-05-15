# ADR 0001: Background-Image Delivery via `image-set()`

**Date:** 2026-05-14
**Status:** Accepted

> Ported from the rubycentral/rubyconf-2026 site repo, where this was
> originally ADR 0004. Renumbered to 0001 for this gem's ADR series.

## Context

The site already runs every `<img>` reference through a custom
`image_pipeline` Bridgetown builder that emits AVIF and WebP
derivatives at five widths (400, 600, 800, 1200, 1600) and rewrites
markup through a `picture_tag` helper. That pipeline does not touch
CSS, and several pages rely on Tailwind's `bg-[url(/images/...)]`
arbitrary-value utility to attach decorative bitmaps as
`background-image`. The result, as measured by Lighthouse on the
deployed homepage:

- `/` mobile performance scored 0.47 in the post-deploy audit
  immediately before this work began. LCP was 10.3s; total page
  weight was ~2.1 MiB.
- The largest single asset was a 216 KiB raw JPG
  (`all-flora.jpg`), attached as a CSS background and downloaded
  unconditionally at every viewport. Eight other call sites across
  six pages used the same pattern with 88-104 KiB raw PNGs.
- Aggregate raw-bitmap weight across the affected pages was roughly
  1 MiB; Lighthouse flagged two image-related opportunities
  (`offscreen-images`, `uses-responsive-images`) totalling ~183 KiB
  on `/` alone.

The cause was structural: CSS `background-image` declarations can't
participate in `<picture>` element resolution, so none of the
pipeline's existing AVIF/WebP derivatives were reachable from the
bitmap backgrounds. Three delivery paths were available, and we had
to pick one before we could close the gap.

Constraints that shaped the choice:

- **Templates are ERB inside Markdown.** Authors write
  `<section class="bg-cover bg-no-repeat ...">` and expect
  Tailwind-style ergonomics. A delivery mechanism that requires
  every author to think about `<picture>` layering, position
  contexts, or asset preloading would not survive contact with the
  rest of the site.
- **Tailwind v4 is in use.** The build's JIT compilation only sees
  classes that literally appear in template source; any class
  produced at render time is invisible to Tailwind's purge. This
  cuts off CSS strategies that try to register helper-generated
  classes into the global stylesheet.
- **Several bg-images are decorative on small viewports too.** The
  hero on `/faqs` was authored as `lg:bg-[url(...)]` — visible only
  ≥1024px. Whatever we shipped had to support that "only at this
  breakpoint" semantic without forcing authors to drop down to raw
  CSS.
- **AVIF is broadly supported in 2026.** Every evergreen browser
  ships it; the long tail that doesn't is well-covered by WebP.
  Browser stats no longer justify shipping a raw bitmap fallback.

## Decision

Add a single ERB helper, `bg_image_block(src, breakpoint_only:,
class_suffix:)`, in the existing `Builders::ImagePipeline::Helpers`
module. The helper:

1. Looks up `src` in the pipeline manifest.
2. Derives a stable CSS class name from the basename
   (`/images/all-flora.jpg` → `bg-img-all-flora`).
3. Renders an inline `<style>` fragment that sets
   `background-image: image-set(url(.avif) type('image/avif'),
   url(.webp) type('image/webp'))` for the largest available width,
   then emits `@media (max-width:px)` overrides for each Tailwind
   breakpoint that has a smaller derivative.
4. Returns the `<style>` fragment so the template can emit it
   immediately before the element that wears the class.

Templates use it like this:

```erb
<%= bg_image_block("/images/all-flora.jpg") %>
<section class="bg-img-all-flora bg-cover p-6 md:p-10 lg:p-20">
  ...
</section>
```

The helper-emitted class lives only in the inline `<style>` block;
Tailwind never sees it. Templates continue to use Tailwind
utilities (`bg-cover`, `bg-no-repeat`, etc.) for everything except
the `background-image` property itself. `breakpoint_only:` accepts
a pixel value (e.g. `1024`) and wraps the entire CSS body in
`@media (min-width:Npx)` so authors can replicate Tailwind's
breakpoint-prefixed bg utilities. Only min-width gating is
supported; max-width (Tailwind's `max-lg:` variant) has no current
caller and is deliberately omitted. `class_suffix:` disambiguates
when the same source is used in two contexts on the same page (the
`/faqs` hero shares its image with the plant-rotation loop, so the
hero passes `class_suffix: "hero"` and gets a scoped
`bg-img-faq-flowers-hero` class).

The rendered shape for the `lg`-only hero case is:

```css
@media (min-width:1024px){
  .bg-img-faq-flowers-hero{background-image:image-set(...1600...)}
  @media (max-width:1280px){.bg-img-faq-flowers-hero{...1200...}}
  /* ... */
}
```

Adding a new bg-image is a two-step author workflow: drop the
source file into `src/images/`, then call `bg_image_block(path)`
in the template. The pipeline builder picks the file up on the
next build and populates the manifest; the helper finds it on the
same build. If the helper is called for a source that the pipeline
hasn't processed (typo in the path, file in the wrong directory),
it logs `[image_pipeline] no manifest entry for ...` and emits a
fallback `background-image: url(src)` rule — degrading to raw
delivery rather than failing the build.

### Options

**A. CSS `image-set()` via inline `<style>` per call site
(chosen).** One helper call emits one self-contained `<style>`
fragment. Browser picks the best supported format. No global CSS
bundle to maintain, no `<head>` registry to coordinate, no
post-render HTML rewriting. Tailwind purge isn't involved because
the helper-emitted class never appears in template source. Cost: a
small duplicate-CSS surface on pages that use many backgrounds
(the upper bound is `/faqs` at five blocks, well under 2 KiB
total).

**B. Convert every bg-image to a `<picture>` element positioned
absolutely behind the section's content.** Strictly the best for
LCP (the `<img>` can be preloaded via `<link rel="preload">` and
gets standard responsive behaviour), but every section needs a
`position: relative` wrapper and a new layer for the actual
content. Every author who adds a background now has to think
about layering, z-index, and pointer events. The migration
touches structural HTML in every affected section instead of
attribute-level edits. Rejected as disproportionate for
decorative bitmaps — and the preloading capability is deliberately
deferred: none of the current bg-images is the LCP element on its
page, so the preload upside has no caller. If a future bg-image
*becomes* an LCP candidate, that page should switch to Option B
for that one section rather than this ADR being revised.

**C. Per-page `<style>` collector with a `<head>` injection
point.** A helper registers each call's CSS into a per-resource
hash; a Bridgetown render hook string-rewrites `</head>` to inject
one consolidated `<style>` block. Cleaner output, but in Bridgetown
2.0.5 ERB renders sequentially and the head partial runs before
the body, so the collector must be backed by either thread-local
state plus a render hook or a post-render HTML rewrite. Both add
plumbing for a small payload win (the inline `<style>` approach
ships at most a couple of KiB of duplicate CSS site-wide).
Rejected as overhead-heavy for the size of the problem.

The CSS `image-set()` format-selection syntax itself uses only
`type('image/avif')` and `type('image/webp')` sources, with no
raw-bitmap fallback. Browsers without AVIF support held under
0.5% of global usage at the time this ADR was written
(caniuse.com, May 2026); the WebP-only sub-share is smaller still.
Browsers that support neither render no background, which on the
affected sections is a decorative-only loss. Adding a third raw
fallback was considered and rejected: it would defeat the whole
point by allowing any browser that prefers the raw URL ordering to
download the bitmap anyway, and the missing-browser surface is
effectively empty. Per-image decode failure inside a supported
format also degrades gracefully — `image-set()` falls through to
the next source in the same declaration, so a corrupt or partial
AVIF download lets the WebP take over without further work.

## Consequences

- **Positive:** Every bg-image on the site now ships AVIF first,
  WebP second, sized to the viewport. The homepage's raw
  `all-flora.jpg` drops from 216 KiB to roughly 90 KiB at the
  largest tier and far less on mobile. The helper API is small
  enough that template authors learn it in one example. The same
  pipeline that powers `picture_tag` is reused — no new build
  step, no new asset directory, no new cache key. The
  per-call-site CSS surface is small: a typical single-bg page
  ships 200-400 bytes of generated CSS, and the per-page upper
  bound is `/faqs` at five blocks (well under 2 KiB total).
- **Positive:** `breakpoint_only:` replaces Tailwind's
  `lg:bg-[url(...)]` pattern with equivalent semantics, so the
  migration is mechanical rather than design-rewriting.
- **Neutral:** Each call site emits its own `<style>` block, so a
  page using the same background in two visually distinct contexts
  needs `class_suffix:` to avoid CSS-cascade collisions. The
  `/faqs` page already hit this in the first migration pass; the
  helper grew the kwarg in response.
- **Neutral:** Some source images are smaller than the largest
  configured pipeline widths (a 480px-wide vertical hero, for
  example). The pipeline processor skips widths larger than the
  source, and the helper warns to stderr and substitutes the
  nearest available width. Warnings appear in build logs; they are
  informational, not failures.
- **Negative:** Browsers without AVIF *and* without WebP support
  see no background image. In 2026 the combined miss is under
  0.5% globally, but if the project's audience ever shifts toward
  legacy-WebView territory the helper needs a third fallback
  source.
- **Negative:** The helper-emitted classes are invisible to
  Tailwind tooling. Authors who try `lg:bg-img-foo` will find the
  prefix has no effect, because Tailwind's variant system doesn't
  see the class. The escape hatch is `breakpoint_only:` on the
  helper itself.
- **Negative:** Tests at unit level cover the CSS emitter
  (`BgImageSet`) and the helper, but visual regression on every
  migrated page is out of scope for the existing test suite. There
  is no screenshot-diff tooling planned; the durable answer is
  human review during PR + the post-deploy Lighthouse run. A
  silently broken bg-image (wrong file picked, wrong viewport
  width) would not be caught by either check directly — only by
  the size-budget warnings Lighthouse already emits.

## References

- Spec (local, not committed):
  `docs/superpowers/specs/2026-05-14-bg-image-pipeline-design.md`
- Plan (local, not committed):
  `docs/superpowers/plans/2026-05-14-bg-image-pipeline.md`
- PR: rubycentral/rubyconf-2026#109
- Prior pipeline work that this builds on:
  `Bridgetown image_pipeline` plugin introduced in PR #97 and
  expanded in PRs #105, #106.
- Lighthouse CI workflow that surfaces regressions (warn-level
  assertions, non-blocking; see `.lighthouserc.json`):
  `.github/workflows/lighthouse.yml`
