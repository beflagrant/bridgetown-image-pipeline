# ADR 0004: Output Directory Under `_bridgetown/` Prefix

**Date:** 2026-05-15
**Status:** Accepted

## Context

The plugin writes generated AVIF/WebP derivatives into a subdirectory of
the site's `output/` build folder. The URLs of those derivatives become
public — they appear in `<picture>` `srcset` attributes and in
`image-set(url(...))` CSS rules, which means they get baked into the
rendered HTML and CSS that ships to browsers, indexed by search engines,
and cached by CDNs and downstream proxies.

Changing this path is therefore a breaking change for any consumer with
existing pipeline URLs. The in-repo version at rubycentral/rubyconf-2026
used `output_dir: "_pipeline/images"`, putting derivatives at
`https://rubyconf.org/_pipeline/images/all-flora-1200.avif`. When
extracting to a gem we had to pick a default for new adopters.

Bridgetown's framework convention is to use the `_bridgetown/` prefix for
framework-managed output that should survive `keep_files` across builds.
The asset-pipeline outputs (esbuild, etc.) live under
`output/_bridgetown/static/`. Using the same prefix signals "this
directory is managed by a Bridgetown plugin, do not edit by hand."

## Decision

The gem default for `output_dir` is `_bridgetown/image_pipeline`. Sites
that need to preserve existing URLs (such as rubycentral/rubyconf-2026
migrating off its in-repo plugin) override via the initializer:

```ruby
init "bridgetown-image-pipeline" do
  output_dir "_pipeline/images"
end
```

### Options

**A. `_bridgetown/image_pipeline` (chosen).** Follows the Bridgetown
framework convention. Aligns with where other framework-managed output
lives. Self-documents the directory's purpose. Existing adopters
override via one kwarg if they care about URL continuity.

**B. `_pipeline/images` (match in-repo plugin).** Behaviour continuity:
existing sites can adopt the gem without rewriting any URLs. But the
default looks framework-foreign and lives outside Bridgetown's
reserved-prefix convention; new adopters get an arbitrary-looking
top-level `_pipeline/` directory in their `output/`.

**C. Configurable, no default** — force every adopter to pick.
Maximum explicitness, maximum boilerplate. No.

## Consequences

- **Positive:** New adopters' build output sits under
  `output/_bridgetown/image_pipeline/`, which is already on Bridgetown's
  `keep_files` exemption list so clean builds don't trash derivatives.
- **Positive:** Directory naming announces "this is managed by a
  plugin." Less confusion when an author wonders why `_bridgetown/`
  contains a directory they didn't create.
- **Neutral:** rubycentral/rubyconf-2026 needs to override
  `output_dir` to `_pipeline/images` during its gem-adoption PR to keep
  every existing image URL working. Documented in the README's
  "Configuration" section.
- **Negative:** Anyone else migrating off another pipeline (e.g. a
  hand-rolled `_responsive/`, an old asset_pack output) has to override
  the kwarg or accept a one-time URL change. The mitigation is the
  same as for rubyconf-2026: one line in the initializer.

## References

- Bridgetown core's `keep_files` configuration:
  [bridgetown-core-2.0.5/lib/bridgetown-core/configuration.rb:56](https://github.com/bridgetownrb/bridgetown/blob/main/bridgetown-core/lib/bridgetown-core/configuration.rb).
- [README "Configuration" section](../../README.md#configuration) for
  the `output_dir` kwarg.
