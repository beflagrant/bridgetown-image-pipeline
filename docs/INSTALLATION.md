# Installation

Add to your site's `Gemfile`:

```ruby
gem "bridgetown-image-pipeline"
```

Then `bundle install`.

## libvips with HEIF/AVIF support

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

## CI: GitHub Actions

See [`../examples/github-actions-build.yml`](../examples/github-actions-build.yml)
for a minimal `ubuntu-latest` workflow that covers both gotchas:

1. **Install libvips + libheif before `setup-ruby`.** Otherwise `ruby-vips`
   fails to `dlopen` `vips.so.42` at require time and Bridgetown surfaces a
   misleading

   > Dependency Error: Hmm, it looks like you don't have
   > `bridgetown-image-pipeline' or one of its dependencies installed.

   even though `bundle install` succeeds and `bundle show bridgetown-image-pipeline`
   finds the gem.

2. **Cache the derivatives across runs.** AVIF encoding is CPU-heavy — a
   site with ~30+ source images can take 10+ minutes of cold CI time per
   build. Caching `.bridgetown-cache/image_pipeline` (the content-addressed
   manifest) and `output/_bridgetown/image_pipeline` (the encoded
   derivatives) with `restore-keys` fallback lets unchanged images
   short-circuit. Adding a single new image only re-encodes that image.

## Activate the plugin

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

See [`CONFIGURATION.md`](CONFIGURATION.md) for all options.
