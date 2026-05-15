# frozen_string_literal: true

module Bridgetown
  module ImagePipeline
    Config = Struct.new(
      :source_globs, :exclude, :widths, :formats, :output_dir,
      :quality, :auto_rewrite, :fail_on_missing, :breakpoints, :default_width,
      keyword_init: true
    ) do
      DEFAULTS = {
        source_globs:    ["src/images/**/*.{jpg,jpeg,png}"],
        exclude:         [],
        widths:          [400, 600, 800, 1200, 1600],
        formats:         [:avif, :webp],
        output_dir:      "_bridgetown/image_pipeline",
        quality:         { avif: 65, webp: 88, jpeg: 88 },
        auto_rewrite:    false,
        fail_on_missing: false,
        breakpoints:     { 640 => 400, 768 => 600, 1024 => 800, 1280 => 1200 },
        default_width:   1600,
      }.freeze

      # Build a Config from initializer kwargs. Unknown keys raise.
      def self.from(**overrides)
        merged = DEFAULTS.merge(overrides)
        merged[:formats] = Array(merged[:formats]).map(&:to_sym)
        merged[:quality] = DEFAULTS[:quality].merge(merged[:quality] || {})
        new(**merged)
      end
    end
  end
end
