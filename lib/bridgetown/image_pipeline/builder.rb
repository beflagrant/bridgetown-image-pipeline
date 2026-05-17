# frozen_string_literal: true

require "digest"
require "json"
require_relative "config"
require_relative "manifest"
require_relative "processor"
require_relative "inspector"

module Bridgetown
  module ImagePipeline
    class Builder < Bridgetown::Builder
      attr_reader :manifest, :config

      # Bridgetown 2.x calls .new(name, site) on registered builders; earlier
      # docs assumed .new(site). Accept either calling convention.
      class << self
        attr_accessor :pending_config
      end

      def initialize(*args, cache_root: nil)
        site = args.last
        super(*args)
        @site        = site
        @config      = self.class.pending_config || Config.from
        cache_root ||= File.join(site.root_dir, ".bridgetown-cache", "image_pipeline")
        @manifest    = Manifest.new(cache_dir: cache_root)
        @output_root = site.in_dest_dir
        @processor   = Processor.new(config: @config, output_root: @output_root)
      end

      def build
        hook(:site, :pre_render) { run }
        attach_to_site!
        register_auto_rewrite_hooks! if @config.auto_rewrite
      end

      def register_auto_rewrite_hooks!
        inspector = Inspector.new(manifest: @manifest, config: @config)
        site_to_match = @site
        rewriter = lambda do |obj|
          return unless obj.site.equal?(site_to_match)
          return unless html_output?(obj)

          obj.output = inspector.rewrite(obj.output.to_s)
        end
        Bridgetown::Hooks.register_one(:resources,       :post_render, reloadable: false, &rewriter)
        Bridgetown::Hooks.register_one(:generated_pages, :post_render, reloadable: false, &rewriter)
      end

      def html_output?(obj)
        return false unless obj.respond_to?(:output_ext)

        obj.output_ext.to_s.downcase == ".html"
      end

      def run
        sources.each { |src| process_one(src) }
      end

      def attach_to_site!
        site = @site
        manifest = @manifest
        config   = @config
        site.define_singleton_method(:image_pipeline_manifest) { manifest }
        site.define_singleton_method(:image_pipeline_config)   { config }
      end

      private

      def sources
        patterns = @config.source_globs.map { |g| File.join(@site.root_dir, g) }
        excludes = @config.exclude.map { |g| File.join(@site.root_dir, g) }
        patterns.flat_map { |p| Dir.glob(p) }
                .reject { |abs| excludes.any? { |ex| File.fnmatch?(ex, abs, File::FNM_PATHNAME | File::FNM_EXTGLOB) } }
                .uniq
                .sort
      end

      def process_one(absolute_source_path)
        relative = relative_to_site(absolute_source_path)
        key      = cache_key(absolute_source_path)
        cached   = @manifest.fetch_cached(key)

        if cached && derivatives_exist?(cached)
          @manifest.register_cached(relative, cached)
          return
        end

        basename = File.basename(absolute_source_path, ".*")
        result   = @processor.process(absolute_source_path, basename: basename)
        @manifest.put(relative, result, cache_key: key)
      end

      def relative_to_site(absolute_path)
        absolute_path.sub("#{@site.root_dir}/", "")
      end

      # Cache key invariant per ADR 0005:
      # - gem VERSION is hashed in, so bumping the gem invalidates all derivatives
      # - source bytes are hashed in, so editing an image regenerates
      # - config fingerprint is hashed in, so widths/formats/quality changes regenerate
      def cache_key(absolute_source_path)
        digest = Digest::SHA1.new
        digest.update(File.binread(absolute_source_path))
        digest.update(Bridgetown::ImagePipeline::VERSION)
        digest.update(JSON.generate(config_fingerprint))
        digest.hexdigest
      end

      def config_fingerprint
        {
          widths: @config.widths,
          formats: @config.formats,
          output_dir: @config.output_dir,
          quality: @config.quality
        }
      end

      def derivatives_exist?(entry)
        entry[:variants].all? do |v|
          File.exist?(File.join(@output_root, v[:path].sub(%r{\A/}, "")))
        end
      end
    end
  end
end
