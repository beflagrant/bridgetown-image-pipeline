# ADR 0003: Conservative Defaults — `auto_rewrite` and `fail_on_missing` Both Off

**Date:** 2026-05-15
**Status:** Accepted

## Context

Two of this plugin's configuration flags change behaviour in
adopter-visible ways:

- **`auto_rewrite`** enables the `Inspector`, which walks rendered HTML
  and silently rewrites bare `<img src="/images/...">` into
  `<picture>` markup. When it works, it is invisible to authors. When
  it goes wrong (a malformed source, a Nokogiri parsing oddity, an
  unexpected HTML structure) it can mutate output in surprising ways
  that are hard to debug.
- **`fail_on_missing`** controls what happens when a template requests
  a source that the pipeline did not process — typo'd path, untracked
  file, source outside the configured `source_globs`. With it `true`,
  the build raises immediately. With it `false`, the helper warns to
  stderr and falls back to the raw URL (for `<img>`) or a `url(src)`
  CSS rule (for `bg_image_block`).

In the original in-repo plugin at rubycentral/rubyconf-2026,
`auto_rewrite` defaulted to `true` (the site relied on it) and
`fail_on_missing` defaulted to `false`. When the plugin moved to a
public gem, the audience changed: instead of one site that knew to expect
post-render mutation, the gem will be installed by sites that have
neither read the Inspector's source nor watched it run on a real page.

## Decision

In the gem, both flags default to `false`. The `Inspector` does not run
unless the adopter explicitly opts in via:

```ruby
init "bridgetown-image-pipeline" do
  auto_rewrite true
end
```

Missing sources warn to stderr and fall back gracefully. Sites that
want strict behaviour pass `fail_on_missing: true` in their initializer.

### Options

**A. Both default off (chosen).** New adopters get explicit, predictable
behaviour. The `Inspector` is documented as opt-in. Missing sources
degrade gracefully so a typo doesn't break the build for a first-time
user.

**B. Both default on (matches in-repo plugin).** Behaviour-continuity
for the rubycentral/rubyconf-2026 migration is one-line: nothing
changes in the initializer. But every new adopter encounters
HTML-mutation as a surprise and has to discover the opt-out.

**C. `auto_rewrite` off, `fail_on_missing` on.** Strict missing-source
behaviour catches typos at build time, which is useful in CI. But it
breaks new installs for adopters who haven't yet wired their entire
`src/images/` tree into the pipeline.

## Consequences

- **Positive:** First-run experience is quiet — no mystery `<picture>`
  wrapping, no build breaks on a typo. Authors discover features by
  reading the README and opting in.
- **Positive:** The `Inspector`'s known fragility (Nokogiri HTML5
  parsing differences across versions) only affects sites that have
  consciously enabled it.
- **Neutral:** rubycentral/rubyconf-2026 needs `auto_rewrite: true`
  set explicitly in its initializer during the gem-adoption PR.
  One-line change.
- **Negative:** Adopters who *want* the Inspector and don't read the
  README ship without it. The README's "Inspector" section is the
  mitigation.

## References

- See [`docs/INTERNALS.md`](../INTERNALS.md) for the Inspector design.
- [ADR 0002](0002-initializer-kwargs-only.md) — the configuration
  surface these defaults are reachable through.
