# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Load components directly without booting Bridgetown's initializer chain so
# unit tests can run without a site context. Tests that need the Builder
# integration with Bridgetown still require "bridgetown/image_pipeline".
require "bridgetown/image_pipeline/version"
require "bridgetown/image_pipeline/config"
require "bridgetown/image_pipeline/manifest"
require "bridgetown/image_pipeline/processor"
require "bridgetown/image_pipeline/bg_image_set"
require "bridgetown/image_pipeline/helpers"
require "bridgetown/image_pipeline/inspector"

module Bridgetown
  module ImagePipeline
    class Error < StandardError; end
    class MissingSourceError < Error; end
  end
end

require "minitest/autorun"
