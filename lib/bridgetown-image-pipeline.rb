# frozen_string_literal: true

# Shim so `require "bridgetown-image-pipeline"` (dasherized — what Bridgetown's
# plugin loader uses) resolves to the actual library file.
require_relative "bridgetown/image_pipeline"
