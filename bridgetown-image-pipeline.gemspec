# frozen_string_literal: true

require_relative "lib/bridgetown/image_pipeline/version"

Gem::Specification.new do |spec|
  spec.name = "bridgetown-image-pipeline"
  spec.version = Bridgetown::ImagePipeline::VERSION
  spec.authors = ["Jim Remsik"]
  spec.email = ["jim@beflagrant.com"]

  spec.summary = "Build-time AVIF/WebP image derivatives and helpers for Bridgetown."
  spec.description = <<~DESC
    A Bridgetown 2.0+ plugin that pre-generates responsive AVIF and WebP image
    derivatives at multiple widths, exposes a picture_tag helper for <img>
    elements, a bg_image_block helper that emits CSS image-set() declarations
    for backgrounds, and an Inspector that retroactively wraps bare <img> tags
    with responsive <picture> markup.
  DESC
  spec.homepage = "https://github.com/beflagrant/bridgetown-image-pipeline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml sig/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "bridgetown", ">= 2.0", "< 3.0"
  spec.add_dependency "image_processing", "~> 1.13"
  spec.add_dependency "nokogiri", ">= 1.16"
  spec.add_dependency "ruby-vips", "~> 2.2"
end
