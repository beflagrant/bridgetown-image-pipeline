# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class ConfigTest < Minitest::Test
  def test_defaults_when_no_overrides
    cfg = Bridgetown::ImagePipeline::Config.from
    assert_equal ["src/images/**/*.{jpg,jpeg,png}"], cfg.source_globs
    assert_equal [], cfg.exclude
    assert_equal [400, 600, 800, 1200, 1600], cfg.widths
    assert_equal %i[avif webp], cfg.formats
    assert_equal "_bridgetown/image_pipeline", cfg.output_dir
    assert_equal({ avif: 65, webp: 88, jpeg: 88 }, cfg.quality)
    assert_equal false, cfg.auto_rewrite
    assert_equal false, cfg.fail_on_missing
    assert_equal({ 640 => 400, 768 => 600, 1024 => 800, 1280 => 1200 }, cfg.breakpoints)
    assert_equal 1600, cfg.default_width
  end

  def test_kwargs_override_defaults
    cfg = Bridgetown::ImagePipeline::Config.from(
      widths: [320, 960],
      quality: { webp: 90 },
      auto_rewrite: true
    )
    assert_equal [320, 960], cfg.widths
    assert_equal 90, cfg.quality[:webp]
    assert_equal 65, cfg.quality[:avif]
    assert_equal true, cfg.auto_rewrite
  end

  def test_breakpoints_override
    cfg = Bridgetown::ImagePipeline::Config.from(
      breakpoints: { 600 => 400, 900 => 800 },
      default_width: 1200
    )
    assert_equal({ 600 => 400, 900 => 800 }, cfg.breakpoints)
    assert_equal 1200, cfg.default_width
  end
end

class ManifestTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("image_pipeline_manifest")
    @manifest = Bridgetown::ImagePipeline::Manifest.new(cache_dir: @tmp)
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def test_round_trip_via_cache
    entry = {
      width: 800, height: 600,
      variants: [{ path: "/_bridgetown/image_pipeline/foo-400.webp", width: 400, format: :webp }]
    }
    @manifest.put("src/images/foo.jpg", entry, cache_key: "abc123")

    fresh = Bridgetown::ImagePipeline::Manifest.new(cache_dir: @tmp)
    loaded = fresh.fetch_cached("abc123")
    assert_equal 800, loaded[:width]
    assert_equal :webp, loaded[:variants].first[:format]
  end

  def test_lookup_by_public_url
    @manifest.put("src/images/foo.jpg", {
                    width: 800, height: 600,
                    variants: [{ path: "/_bridgetown/image_pipeline/foo-400.webp", width: 400, format: :webp }]
                  }, cache_key: "abc123")
    found = @manifest.find_by_src("/images/foo.jpg")
    refute_nil found
    assert_equal 800, found[:width]
  end

  def test_lookup_returns_nil_for_unknown_src
    assert_nil @manifest.find_by_src("/images/missing.jpg")
  end

  def test_variants_by_width_groups_formats
    @manifest.put("src/images/x.jpg", {
                    width: 1600, height: 900,
                    variants: [
                      { path: "/_bridgetown/image_pipeline/x-400.avif", width: 400, format: :avif },
                      { path: "/_bridgetown/image_pipeline/x-400.webp",  width: 400,  format: :webp },
                      { path: "/_bridgetown/image_pipeline/x-1600.avif", width: 1600, format: :avif },
                      { path: "/_bridgetown/image_pipeline/x-1600.webp", width: 1600, format: :webp }
                    ]
                  }, cache_key: "k")

    result = @manifest.variants_by_width("/images/x.jpg")
    assert_equal(
      {
        400 => { avif: "/_bridgetown/image_pipeline/x-400.avif", webp: "/_bridgetown/image_pipeline/x-400.webp" },
        1600 => { avif: "/_bridgetown/image_pipeline/x-1600.avif", webp: "/_bridgetown/image_pipeline/x-1600.webp" }
      },
      result
    )
  end

  def test_variants_by_width_returns_empty_hash_for_unknown_src
    assert_equal({}, @manifest.variants_by_width("/images/nope.jpg"))
  end
end

class ProcessorTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("image_pipeline_test")
    @src = File.expand_path("fixtures/test-image.jpg", __dir__)
    @cfg = Bridgetown::ImagePipeline::Config.from(
      widths: [400, 1600],
      formats: [:webp],
      output_dir: "out",
      quality: { avif: 50, webp: 82, jpeg: 85 }
    )
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def test_generates_webp_at_each_width_smaller_than_source
    processor = Bridgetown::ImagePipeline::Processor.new(config: @cfg, output_root: @tmp)
    result = processor.process(@src, basename: "test-image")
    paths = result[:variants].map { |v| v[:path] }
    assert(paths.any? { |p| p.end_with?("test-image-400.webp") })
    assert(paths.any? { |p| p.end_with?("test-image-1600.webp") })
    assert(paths.any? { |p| p.end_with?("test-image-400.jpg") })
    paths.each { |p| assert File.exist?(File.join(@tmp, p.sub(%r{\A/}, ""))), "missing #{p}" }
  end

  def test_skips_widths_larger_than_source
    @cfg.widths.replace([1600, 2400])
    processor = Bridgetown::ImagePipeline::Processor.new(config: @cfg, output_root: @tmp)
    result = processor.process(@src, basename: "test-image")
    widths = result[:variants].map { |v| v[:width] }.uniq.sort
    assert_equal [1600], widths
  end

  def test_records_intrinsic_dimensions
    processor = Bridgetown::ImagePipeline::Processor.new(config: @cfg, output_root: @tmp)
    result = processor.process(@src, basename: "test-image")
    assert_equal 2000, result[:width]
    assert_equal 1000, result[:height]
  end

  def test_does_not_duplicate_when_source_format_matches_configured_format
    webp_src = File.expand_path("fixtures/test-image.webp", __dir__)
    processor = Bridgetown::ImagePipeline::Processor.new(config: @cfg, output_root: @tmp)
    result = processor.process(webp_src, basename: "test-image")

    # @cfg defaults to formats: [:webp]; the source is also webp.
    # Each width should yield exactly one variant, not two.
    width_counts = result[:variants].group_by { |v| v[:width] }.transform_values(&:size)
    width_counts.each do |width, count|
      assert_equal 1, count, "expected one variant at width #{width}, got #{count}"
    end
  end
end

class HelperTest < Minitest::Test
  def setup
    @manifest = Bridgetown::ImagePipeline::Manifest.new(cache_dir: Dir.mktmpdir)
    @manifest.put("src/images/hero.jpg", {
                    width: 2400, height: 1600,
                    variants: [
                      { path: "/_bridgetown/image_pipeline/hero-400.avif",  width: 400,  format: :avif },
                      { path: "/_bridgetown/image_pipeline/hero-400.webp",  width: 400,  format: :webp },
                      { path: "/_bridgetown/image_pipeline/hero-400.jpg",   width: 400,  format: :jpeg },
                      { path: "/_bridgetown/image_pipeline/hero-1600.avif", width: 1600, format: :avif },
                      { path: "/_bridgetown/image_pipeline/hero-1600.webp", width: 1600, format: :webp },
                      { path: "/_bridgetown/image_pipeline/hero-1600.jpg",  width: 1600, format: :jpeg }
                    ]
                  }, cache_key: "fake")
    @cfg = Bridgetown::ImagePipeline::Config.from(
      widths: [400, 1600],
      formats: %i[avif webp]
    )
    @helpers = Bridgetown::ImagePipeline::Helpers.new(manifest: @manifest, config: @cfg)
  end

  def test_renders_picture_with_avif_webp_sources_and_img_fallback
    html = @helpers.picture_tag("/images/hero.jpg",
                                alt: "Red Rock",
                                sizes: "(min-width: 1024px) 33vw, 100vw",
                                class: "w-full")
    assert_includes html, "<picture>"
    assert_includes html, 'type="image/avif"'
    assert_includes html, 'type="image/webp"'
    assert_includes html, "/_bridgetown/image_pipeline/hero-400.avif 400w"
    assert_includes html, "/_bridgetown/image_pipeline/hero-1600.webp 1600w"
    assert_includes html, 'alt="Red Rock"'
    assert_includes html, 'class="w-full"'
    assert_includes html, 'width="2400"'
    assert_includes html, 'height="1600"'
    assert_includes html, 'loading="lazy"'
    assert_includes html, 'decoding="async"'
    refute_includes html, "fetchpriority"
  end

  def test_priority_emits_fetchpriority_and_eager_loading
    html = @helpers.picture_tag("/images/hero.jpg", alt: "x", sizes: "100vw", priority: true)
    assert_includes html, 'fetchpriority="high"'
    assert_includes html, 'loading="eager"'
  end

  def test_unknown_src_falls_back_to_plain_img
    html = @helpers.picture_tag("/images/missing.svg", alt: "x")
    assert_includes html, '<img src="/images/missing.svg"'
    refute_includes html, "<picture>"
  end

  def test_unknown_src_raises_when_fail_on_missing
    @cfg.fail_on_missing = true
    err = assert_raises(Bridgetown::ImagePipeline::MissingSourceError) do
      @helpers.picture_tag("/images/missing.svg", alt: "x")
    end
    assert_match(/missing\.svg/, err.message)
  end

  def test_escapes_attribute_values
    html = @helpers.picture_tag("/images/hero.jpg", alt: %q(it's "fine"))
    assert_includes html, 'alt="it&#39;s &quot;fine&quot;"'
  end

  def test_bg_image_class_slugifies_basename
    assert_equal "bg-img-all-flora",            @helpers.bg_image_class("/images/all-flora.jpg")
    assert_equal "bg-img-flowers-full-bottom",  @helpers.bg_image_class("/images/flowers_full_bottom.png")
    assert_equal "bg-img-corner-plant-right",   @helpers.bg_image_class("/images/corner-plant-right.png")
  end

  def test_bg_image_class_idempotent
    a = @helpers.bg_image_class("/images/hero.jpg")
    b = @helpers.bg_image_class("/images/hero.jpg")
    assert_equal a, b
  end

  def test_bg_image_block_emits_style_with_avif_webp_and_class
    @manifest.put("src/images/hero.jpg", {
                    width: 1600, height: 900,
                    variants: [
                      { path: "/_bridgetown/image_pipeline/hero-400.avif",  width: 400,  format: :avif },
                      { path: "/_bridgetown/image_pipeline/hero-400.webp",  width: 400,  format: :webp },
                      { path: "/_bridgetown/image_pipeline/hero-1600.avif", width: 1600, format: :avif },
                      { path: "/_bridgetown/image_pipeline/hero-1600.webp", width: 1600, format: :webp }
                    ]
                  }, cache_key: "k2")

    out = @helpers.bg_image_block("/images/hero.jpg")
    assert out.start_with?("<style>"), out
    assert out.end_with?("</style>"), out
    assert_includes out,
                    ".bg-img-hero{background-image:image-set(url(/_bridgetown/image_pipeline/hero-1600.avif) type('image/avif'),url(/_bridgetown/image_pipeline/hero-1600.webp) type('image/webp'))}"
    assert_includes out,
                    "@media (max-width:640px){.bg-img-hero{background-image:image-set(url(/_bridgetown/image_pipeline/hero-400.avif)"
  end

  def test_bg_image_block_falls_back_when_src_not_in_manifest
    _out, err = capture_io { @result = @helpers.bg_image_block("/images/missing.jpg") }
    assert_includes @result, "<style>.bg-img-missing{background-image:url(/images/missing.jpg)}</style>"
    assert_match(%r{no manifest entry for /images/missing\.jpg}, err)
  end

  def test_bg_image_block_with_breakpoint_only_wraps_min_width
    @manifest.put("src/images/wide.jpg", {
                    width: 1600, height: 800,
                    variants: [
                      { path: "/_bridgetown/image_pipeline/wide-1600.avif", width: 1600, format: :avif },
                      { path: "/_bridgetown/image_pipeline/wide-1600.webp", width: 1600, format: :webp }
                    ]
                  }, cache_key: "k3")

    out = @helpers.bg_image_block("/images/wide.jpg", breakpoint_only: 1024)
    assert_includes out, "@media (min-width:1024px){.bg-img-wide{"
  end

  def test_bg_image_class_with_suffix_appends_segment
    assert_equal "bg-img-faq-flowers-hero",
                 @helpers.bg_image_class("/images/faq-flowers.png", class_suffix: "hero")
  end

  def test_bg_image_block_with_suffix_uses_suffixed_class
    @manifest.put("src/images/zed.jpg", {
                    width: 1600, height: 900,
                    variants: [
                      { path: "/_bridgetown/image_pipeline/zed-1600.avif", width: 1600, format: :avif },
                      { path: "/_bridgetown/image_pipeline/zed-1600.webp", width: 1600, format: :webp }
                    ]
                  }, cache_key: "kz")
    out = @helpers.bg_image_block("/images/zed.jpg", class_suffix: "hero")
    assert_includes out, ".bg-img-zed-hero{background-image:"
    refute_includes out, ".bg-img-zed{background-image:"
  end

  def test_bg_image_block_uses_config_breakpoints
    custom_cfg = Bridgetown::ImagePipeline::Config.from(
      breakpoints: { 900 => 400 },
      default_width: 1600
    )
    helpers = Bridgetown::ImagePipeline::Helpers.new(manifest: @manifest, config: custom_cfg)
    out = helpers.bg_image_block("/images/hero.jpg")
    assert_includes out, "@media (max-width:900px){.bg-img-hero{"
    refute_includes out, "@media (max-width:640px)"
  end
end

class InspectorTest < Minitest::Test
  def setup
    @manifest = Bridgetown::ImagePipeline::Manifest.new(cache_dir: Dir.mktmpdir)
    @manifest.put("src/images/known.jpg", {
                    width: 1200, height: 600,
                    variants: [
                      { path: "/_bridgetown/image_pipeline/known-400.avif", width: 400, format: :avif },
                      { path: "/_bridgetown/image_pipeline/known-400.webp",  width: 400,  format: :webp },
                      { path: "/_bridgetown/image_pipeline/known-400.jpg",   width: 400,  format: :jpeg },
                      { path: "/_bridgetown/image_pipeline/known-1200.avif", width: 1200, format: :avif },
                      { path: "/_bridgetown/image_pipeline/known-1200.webp", width: 1200, format: :webp },
                      { path: "/_bridgetown/image_pipeline/known-1200.jpg",  width: 1200, format: :jpeg }
                    ]
                  }, cache_key: "k")
    @cfg = Bridgetown::ImagePipeline::Config.from(
      widths: [400, 1200],
      formats: %i[avif webp],
      auto_rewrite: true
    )
    @inspector = Bridgetown::ImagePipeline::Inspector.new(manifest: @manifest, config: @cfg)
  end

  def test_wraps_known_img_in_picture
    html = '<html><body><img src="/images/known.jpg" alt="x"></body></html>'
    out  = @inspector.rewrite(html)
    assert_includes out, "<picture>"
    assert_includes out, 'type="image/avif"'
    assert_includes out, 'type="image/webp"'
    assert_includes out, 'width="1200"'
    assert_includes out, 'height="600"'
  end

  def test_leaves_unknown_img_unchanged
    html = '<html><body><img src="/images/unknown.jpg" alt="x"></body></html>'
    out  = @inspector.rewrite(html)
    refute_includes out, "<picture>"
    assert_includes out, '<img src="/images/unknown.jpg"'
  end

  def test_skips_img_already_inside_picture
    html = '<html><body><picture><img src="/images/known.jpg" alt="x"></picture></body></html>'
    out  = @inspector.rewrite(html)
    assert_equal 1, out.scan("<picture>").length
  end

  def test_skips_data_no_pipeline_optout
    html = '<html><body><img src="/images/known.jpg" alt="x" data-no-pipeline></body></html>'
    out  = @inspector.rewrite(html)
    refute_includes out, "<picture>"
  end

  def test_preserves_existing_author_attrs
    html = '<html><body><img src="/images/known.jpg" alt="x" loading="eager" fetchpriority="high" class="hero"></body></html>'
    out  = @inspector.rewrite(html)
    assert_includes out, 'loading="eager"'
    assert_includes out, 'fetchpriority="high"'
    assert_includes out, 'class="hero"'
  end

  def test_rewrite_skipped_when_auto_rewrite_false
    cfg = Bridgetown::ImagePipeline::Config.from(auto_rewrite: false)
    inspector = Bridgetown::ImagePipeline::Inspector.new(manifest: @manifest, config: cfg)
    html = '<html><body><img src="/images/known.jpg" alt="x"></body></html>'
    out  = inspector.rewrite(html)
    refute_includes out, "<picture>"
  end
end

require "bridgetown"
require "bridgetown/image_pipeline/builder"

class BuilderAutoRewriteHookTest < Minitest::Test
  FakeResource = Struct.new(:site, :output, :output_ext)

  class FakeSite
    attr_reader :root_dir

    def initialize(root_dir)
      @root_dir = root_dir
    end

    def in_dest_dir
      File.join(@root_dir, "output")
    end
  end

  def setup
    @tmp     = Dir.mktmpdir("image_pipeline_builder_hook")
    @site    = FakeSite.new(@tmp)
    @cfg     = Bridgetown::ImagePipeline::Config.from(auto_rewrite: true)
    @builder = Bridgetown::ImagePipeline::Builder.allocate
    @builder.instance_variable_set(:@site, @site)
    @builder.instance_variable_set(:@config, @cfg)
    @builder.instance_variable_set(:@manifest,
                                   Bridgetown::ImagePipeline::Manifest.new(cache_dir: File.join(@tmp, "cache")))
    @builder.manifest.put("src/images/known.jpg", {
                            width: 1200, height: 600,
                            variants: [
                              { path: "/_bridgetown/image_pipeline/known-400.avif", width: 400, format: :avif },
                              { path: "/_bridgetown/image_pipeline/known-400.webp",  width: 400,  format: :webp },
                              { path: "/_bridgetown/image_pipeline/known-1200.avif", width: 1200, format: :avif },
                              { path: "/_bridgetown/image_pipeline/known-1200.webp", width: 1200, format: :webp }
                            ]
                          }, cache_key: "k")
  end

  def teardown
    FileUtils.remove_entry(@tmp)
    Bridgetown::Hooks.instance_variable_get(:@registry)&.each_value do |hooks|
      hooks.reject! { |h| h.reloadable == false }
    end
  end

  def test_post_render_hook_rewrites_html_resource_output
    @builder.register_auto_rewrite_hooks!
    resource = FakeResource.new(@site, '<html><body><img src="/images/known.jpg" alt="x"></body></html>', ".html")
    Bridgetown::Hooks.trigger(:resources, :post_render, resource)
    assert_includes resource.output, "<picture>"
    assert_includes resource.output, 'type="image/avif"'
  end

  def test_post_render_hook_skips_non_html_output
    @builder.register_auto_rewrite_hooks!
    resource = FakeResource.new(@site, "raw bytes", ".xml")
    Bridgetown::Hooks.trigger(:resources, :post_render, resource)
    assert_equal "raw bytes", resource.output
  end

  def test_post_render_hook_ignores_other_sites
    @builder.register_auto_rewrite_hooks!
    other_site = FakeSite.new(Dir.mktmpdir("other_site"))
    html = '<html><body><img src="/images/known.jpg" alt="x"></body></html>'
    resource = FakeResource.new(other_site, html, ".html")
    Bridgetown::Hooks.trigger(:resources, :post_render, resource)
    assert_equal html, resource.output
  ensure
    FileUtils.remove_entry(other_site.root_dir) if other_site
  end
end

class BgImageSetTest < Minitest::Test
  def variants_full
    {
      400 => { avif: "/_bridgetown/image_pipeline/foo-400.avif",  webp: "/_bridgetown/image_pipeline/foo-400.webp" },
      600 => { avif: "/_bridgetown/image_pipeline/foo-600.avif",  webp: "/_bridgetown/image_pipeline/foo-600.webp" },
      800 => { avif: "/_bridgetown/image_pipeline/foo-800.avif",  webp: "/_bridgetown/image_pipeline/foo-800.webp" },
      1200 => { avif: "/_bridgetown/image_pipeline/foo-1200.avif", webp: "/_bridgetown/image_pipeline/foo-1200.webp" },
      1600 => { avif: "/_bridgetown/image_pipeline/foo-1600.avif", webp: "/_bridgetown/image_pipeline/foo-1600.webp" }
    }
  end

  def breakpoints
    { 640 => 400, 768 => 600, 1024 => 800, 1280 => 1200 }
  end

  def test_emits_default_rule_and_four_media_overrides
    css = Bridgetown::ImagePipeline::BgImageSet.css(
      class_name: "bg-img-foo",
      variants: variants_full,
      breakpoints: breakpoints,
      default_width: 1600
    )
    assert_includes css,
                    ".bg-img-foo{background-image:image-set(url(/_bridgetown/image_pipeline/foo-1600.avif) type('image/avif'),url(/_bridgetown/image_pipeline/foo-1600.webp) type('image/webp'))}"
    assert_includes css,
                    "@media (max-width:1280px){.bg-img-foo{background-image:image-set(url(/_bridgetown/image_pipeline/foo-1200.avif) type('image/avif'),url(/_bridgetown/image_pipeline/foo-1200.webp) type('image/webp'))}}"
    assert_includes css,
                    "@media (max-width:1024px){.bg-img-foo{background-image:image-set(url(/_bridgetown/image_pipeline/foo-800.avif) type('image/avif'),url(/_bridgetown/image_pipeline/foo-800.webp) type('image/webp'))}}"
    assert_includes css,
                    "@media (max-width:768px){.bg-img-foo{background-image:image-set(url(/_bridgetown/image_pipeline/foo-600.avif) type('image/avif'),url(/_bridgetown/image_pipeline/foo-600.webp) type('image/webp'))}}"
    assert_includes css,
                    "@media (max-width:640px){.bg-img-foo{background-image:image-set(url(/_bridgetown/image_pipeline/foo-400.avif) type('image/avif'),url(/_bridgetown/image_pipeline/foo-400.webp) type('image/webp'))}}"
  end

  def test_falls_back_to_nearest_width_when_breakpoint_missing
    variants = {
      400 => { avif: "/a-400.avif", webp: "/a-400.webp" },
      1200 => { avif: "/a-1200.avif", webp: "/a-1200.webp" },
      1600 => { avif: "/a-1600.avif", webp: "/a-1600.webp" }
    }
    _out, err = capture_io do
      css = Bridgetown::ImagePipeline::BgImageSet.css(
        class_name: "bg-img-a", variants: variants,
        breakpoints: { 768 => 600 }, default_width: 1600
      )
      assert_includes css,
                      "@media (max-width:768px){.bg-img-a{background-image:image-set(url(/a-400.avif) type('image/avif'),url(/a-400.webp) type('image/webp'))}}"
    end
    assert_match(/no 600w derivative; using 400w/, err)
  end

  def test_breakpoint_only_wraps_output_in_min_width_media
    css = Bridgetown::ImagePipeline::BgImageSet.css(
      class_name: "bg-img-foo",
      variants: variants_full,
      breakpoints: breakpoints,
      default_width: 1600,
      breakpoint_only: 1024
    )
    assert css.start_with?("@media (min-width:1024px){"), "expected wrap, got: #{css[0, 60]}"
    assert css.end_with?("}"), "expected closing }, got: ...#{css[-10..]}"
    assert_includes css, ".bg-img-foo{background-image:image-set(url(/_bridgetown/image_pipeline/foo-1600.avif)"
  end

  def test_empty_variants_emits_background_none
    css = Bridgetown::ImagePipeline::BgImageSet.css(
      class_name: "bg-img-missing",
      variants: {},
      breakpoints: breakpoints,
      default_width: 1600
    )
    assert_equal ".bg-img-missing{background-image:none}", css
  end
end
