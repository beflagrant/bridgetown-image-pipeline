# frozen_string_literal: true

require_relative "helpers"

module Bridgetown
  module ImagePipeline
    module ViewHelpers
      def picture_tag(src, **opts)
        output = helpers_for(site).picture_tag(src, **opts)
        output.respond_to?(:html_safe) ? output.html_safe : output
      end

      def bg_image_block(src, **opts)
        output = helpers_for(site).bg_image_block(src, **opts)
        output.respond_to?(:html_safe) ? output.html_safe : output
      end

      def bg_image_class(src, **opts)
        helpers_for(site).bg_image_class(src, **opts)
      end

      private

      def helpers_for(site)
        Bridgetown::ImagePipeline::Helpers.new(
          manifest: site.image_pipeline_manifest,
          config:   site.image_pipeline_config,
        )
      end
    end
  end
end
