# ADR 0002: Initializer Kwargs As The Only Configuration Surface

**Date:** 2026-05-15
**Status:** Accepted

## Context

Most Bridgetown plugins read configuration from `bridgetown.config.yml` —
either by checking `site.config["plugin_name"]` directly or by going through
Bridgetown's `Bridgetown::Configuration` accessor chain. The in-repo version
of this plugin (at rubycentral/rubyconf-2026) followed that convention with a
top-level `image_pipeline:` block:

```yaml
# bridgetown.config.yml
image_pipeline:
  source_globs: ["src/images/**/*.{jpg,png}"]
  widths: [400, 600, 800, 1200, 1600]
  auto_rewrite: true
```

When extracting the code to a gem we had to pick a configuration surface for
external users. Bridgetown 2.0's `Bridgetown.initializer` API supports a
block form that runs at plugin load time:

```ruby
init "bridgetown-image-pipeline" do
  widths        [400, 800, 1200]
  auto_rewrite  true
end
```

Both YAML and initializer-block configuration are idiomatic for different
parts of the Bridgetown ecosystem. We had to choose one (or both).

## Decision

The plugin reads configuration **only** from the initializer block. The
public API is `Bridgetown::ImagePipeline::Config.from(**overrides)`, where
the keyword arguments correspond 1:1 to the `Config::DEFAULTS` constants.
There is no read path from `bridgetown.config.yml` for this plugin's keys.

### Options

**A. Initializer kwargs only (chosen).** One configuration surface, one
code path, full Ruby semantics (symbols, frozen constants, complex
defaults). Site authors who prefer declarative YAML must accept the Ruby
DSL.

**B. YAML only.** Matches the in-repo plugin's behaviour 1:1, so the
extraction is invisible to existing adopters. But it forecloses the
initializer-block ergonomics (which many other 2.0-era Bridgetown plugins
use) and forces string-keyed config translation inside the gem.

**C. Both.** Read YAML defaults, allow initializer kwargs to override.
Maximum flexibility for adopters, two code paths to test and document.
The added value for a 0.1 release is small — most adopters use one
mechanism or the other, not both.

## Consequences

- **Positive:** A single, idiomatic Ruby configuration entry point. The
  `Config` struct stays a frozen data object; no string-key normalization
  is needed. Setting complex values like `breakpoints: { 640 => 400, ... }`
  is natural in Ruby and awkward in YAML.
- **Positive:** New options can be added with a default constant and a
  Struct member; no YAML parsing code to update.
- **Neutral:** Sites already using the in-repo plugin via YAML need to
  migrate their config block into `config/initializers.rb` during the
  gem-adoption PR. For rubycentral/rubyconf-2026 this is ~10 lines.
- **Negative:** Sites that prefer keeping all configuration in YAML
  (e.g., for non-Ruby contributors to edit) cannot do so for this plugin.
  No workaround other than the adopter loading YAML themselves and
  splatting it into the initializer block.

## References

- [Bridgetown 2.0 initializer documentation](https://www.bridgetownrb.com/docs/configuration/initializers).
- This gem's [`docs/INTERNALS.md`](../INTERNALS.md) for the Config struct
  shape.
