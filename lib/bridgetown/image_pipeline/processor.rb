# frozen_string_literal: true

require "image_processing/vips"
require "fileutils"

module Bridgetown
  module ImagePipeline
    class Processor
      def initialize(config:, output_root:)
        @config = config
        @output_root = output_root
      end

      def process(source_path, basename:)
        image = Vips::Image.new_from_file(source_path)
        source_width  = image.width
        source_height = image.height
        original_ext  = File.extname(source_path).downcase.delete(".")
        original_ext  = "jpg" if original_ext == "jpeg"
        original_fmt  = original_ext.to_sym

        variants = []

        @config.widths.each do |target_width|
          next if target_width > source_width

          @config.formats.each do |fmt|
            variants << build_variant(source_path, basename, target_width, fmt)
          end

          # Generate a fallback variant in the source's own format so the
          # <img src> always has something to point at, but skip it when
          # the configured formats already cover the source format —
          # otherwise variants ends up with duplicates (e.g. webp source
          # with formats=[:webp] would emit each width twice).
          next if @config.formats.include?(original_fmt)

          variants << build_variant(source_path, basename, target_width, original_fmt)
        end

        {
          width: source_width,
          height: source_height,
          variants: variants
        }
      end

      private

      def build_variant(source_path, basename, target_width, format)
        ext = format == :jpeg ? "jpg" : format.to_s
        relative_path = File.join("/", @config.output_dir, "#{basename}-#{target_width}.#{ext}")
        absolute_path = File.join(@output_root, @config.output_dir, "#{basename}-#{target_width}.#{ext}")
        FileUtils.mkdir_p(File.dirname(absolute_path))

        saver_format = format == :jpg ? :jpeg : format
        quality = @config.quality[saver_format] || @config.quality[format]

        ImageProcessing::Vips
          .source(source_path)
          .resize_to_limit(target_width, nil)
          .convert(saver_format.to_s)
          .saver(quality: quality)
          .call(destination: absolute_path)

        {
          path: relative_path,
          width: target_width,
          format: saver_format
        }
      end
    end
  end
end
