# frozen_string_literal: true

module Bridgetown
  module ImagePipeline
    module BgImageSet
      module_function

      # variants:    { width_int => { avif: path, webp: path } }
      # breakpoints: { px_int => width_int }, e.g. { 640 => 400, 768 => 600, 1024 => 800, 1280 => 1200 }
      # default_width: the width used for the un-prefixed rule (largest tier)
      # breakpoint_only: if set, wrap the entire output in @media (min-width: Npx)
      # returns: a single line of CSS (no <style> tags)
      def css(class_name:, variants:, breakpoints:, default_width:, breakpoint_only: nil)
        return fallback_css(class_name, breakpoint_only: breakpoint_only) if variants.empty?

        default = nearest(variants, default_width)
        default_rule = rule(class_name, variants[default])

        media_rules = breakpoints.sort_by { |px, _| -px }.map do |px, target_width|
          chosen = nearest(variants, target_width)
          "@media (max-width:#{px}px){#{rule(class_name, variants[chosen])}}"
        end

        body = default_rule + media_rules.join
        breakpoint_only ? "@media (min-width:#{breakpoint_only}px){#{body}}" : body
      end

      def fallback_css(class_name, breakpoint_only:)
        body = ".#{class_name}{background-image:none}"
        breakpoint_only ? "@media (min-width:#{breakpoint_only}px){#{body}}" : body
      end

      def rule(class_name, formats)
        sources = []
        sources << "url(#{formats[:avif]}) type('image/avif')" if formats[:avif]
        sources << "url(#{formats[:webp]}) type('image/webp')" if formats[:webp]
        ".#{class_name}{background-image:image-set(#{sources.join(",")})}"
      end

      def nearest(variants, target)
        return target if variants.key?(target)

        widths = variants.keys.sort
        chosen = widths.min_by { |w| (w - target).abs }
        warn "[bridgetown-image-pipeline] bg_image_block: no #{target}w derivative; using #{chosen}w"
        chosen
      end
    end
  end
end
