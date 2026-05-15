# ADR 0005: Cache-Key Versioning Lockstep with Gem Version

**Date:** 2026-05-15
**Status:** Accepted

## Context

The pipeline caches each source image's processed manifest under
`.bridgetown-cache/image_pipeline/<sha1>.manifest.json`. The cache key
is a SHA1 digest computed from:

1. The source file's bytes (so editing an image invalidates).
2. A plugin-version constant (so a plugin upgrade invalidates all
   prior caches).
3. A "config fingerprint" hash of widths, formats, output_dir, quality
   (so config changes invalidate).

In the in-repo plugin at rubycentral/rubyconf-2026, item 2 was a manually
maintained constant: `PLUGIN_VERSION = "0.1.0".freeze`. The site author
was responsible for bumping it when the plugin's *behaviour* changed in a
way that should invalidate prior derivatives — for example, after the
JPEG quality default was changed in PR #105, or after the AVIF encoder
plugin was added in PR #106.

This worked, but coupled the cache-key invariant to author discipline.
A forgotten bump would mean adopters carry stale derivatives through a
behavioural change.

When extracting to a gem we had to pick what gets hashed into the
cache key.

## Decision

The cache key uses `Bridgetown::ImagePipeline::VERSION` directly — the
same constant that the gemspec reads to set `spec.version`. Bumping the
gem version automatically invalidates every adopter's cache on their
next build.

```ruby
def cache_key(absolute_source_path)
  digest = Digest::SHA1.new
  digest.update(File.binread(absolute_source_path))
  digest.update(Bridgetown::ImagePipeline::VERSION)
  digest.update(JSON.generate(config_fingerprint))
  digest.hexdigest
end
```

### Options

**A. Hash `VERSION` directly (chosen).** Single source of truth. The
gem version is in `version.rb`, the gemspec, and the cache key — bumping
one bumps the cache invariant. The `version.rb` file is loaded by the
gem's main file at require time, so it is available when the builder
runs.

**B. Maintain a separate `PLUGIN_VERSION` constant (matches in-repo
plugin).** Lets the author bump cache invalidation independently from
the public gem version. Worth it only if there's a real case for
invalidating without a release; we couldn't think of one.

**C. Manual bump per breaking change, separate from gem version.**
Decouples invariants. Maximum control, maximum forgetfulness risk.
No.

## Consequences

- **Positive:** A maintainer who bumps the gem version to 0.2.0 cannot
  forget to invalidate adopters' caches — both invariants move
  together. Zero discipline required.
- **Positive:** The cache-key contract is documented in one place
  (this ADR) and visible in one constant (`VERSION`). New
  contributors don't need to learn a second invariant.
- **Neutral:** Every gem release invalidates every adopter's cache on
  their next build. For small sites this is a few seconds; for
  rubycentral/rubyconf-2026 (which currently has ~70 source images at
  five widths × three formats each) it's about 90 seconds. Acceptable
  given how rarely the gem releases.
- **Negative:** The maintainer cannot release a documentation-only
  change without also forcing a rebuild for every adopter, *unless*
  the documentation-only release uses a non-numeric pre-release
  suffix (e.g. `0.1.1.docs1`). If this becomes a real problem we can
  switch to hashing only the major+minor of `VERSION`. Not
  pre-optimizing for it.

## References

- [`lib/bridgetown/image_pipeline/version.rb`](../../lib/bridgetown/image_pipeline/version.rb)
  — the single source of truth.
- [`lib/bridgetown/image_pipeline/builder.rb`](../../lib/bridgetown/image_pipeline/builder.rb)
  — the `cache_key` method.
