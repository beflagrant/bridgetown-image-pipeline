# frozen_string_literal: true

require "bridgetown"
require_relative "image_pipeline/version"
require_relative "image_pipeline/config"
require_relative "image_pipeline/manifest"
require_relative "image_pipeline/processor"
require_relative "image_pipeline/bg_image_set"
require_relative "image_pipeline/helpers"
require_relative "image_pipeline/inspector"
require_relative "image_pipeline/builder"
require_relative "image_pipeline/view_helpers"

module Bridgetown
  module ImagePipeline
    class Error < StandardError; end
    class MissingSourceError < Error; end
  end
end

# Bridgetown plugin registration.
#
# Usage in a Bridgetown site's config/initializers.rb:
#
#   Bridgetown.configure do |config|
#     init "bridgetown-image-pipeline" do
#       widths        [400, 800, 1200, 1600]
#       output_dir    "_bridgetown/image_pipeline"   # default
#       auto_rewrite  false                          # default
#       # ...any Bridgetown::ImagePipeline::Config::DEFAULTS key
#     end
#   end
#
# Or without overrides:
#
#   init "bridgetown-image-pipeline"
#
Bridgetown.initializer :"bridgetown-image-pipeline" do |config, **overrides|
  Bridgetown::ImagePipeline::Builder.pending_config =
    Bridgetown::ImagePipeline::Config.from(**overrides)
  config.builder Bridgetown::ImagePipeline::Builder
  Bridgetown::RubyTemplateView::Helpers.include(Bridgetown::ImagePipeline::ViewHelpers)
end
