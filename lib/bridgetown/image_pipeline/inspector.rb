# frozen_string_literal: true

require "nokogiri"

module Bridgetown
  module ImagePipeline
    class Inspector
      def initialize(manifest:, config:)
        @manifest = manifest
        @config   = config
      end

      def rewrite(html)
        return html unless @config.auto_rewrite
        doc = Nokogiri::HTML5.parse(html)
        Inspector.find_imgs(doc).each { |img| process_img(img, doc) }
        doc.to_html
      end

      # Nokogiri 1.19 + HTML5 docs translate `css("img")` to the xpath
      # `//*:img`, which libxml on Linux CI rejects with
      # "Invalid expression". Use local-name() to bypass the HTML5
      # namespace handling entirely.
      def self.find_imgs(doc)
        doc.xpath(".//*[local-name()='img']")
      end

      def process_img(img, doc)
        return if img.parent && img.parent.name == "picture"
        return if img.has_attribute?("data-no-pipeline")
        entry = @manifest.find_by_src(img["src"])
        return unless entry

        ensure_dimensions(img, entry)
        ensure_img_srcset(img, entry)

        picture = Nokogiri::XML::Node.new("picture", doc)
        @config.formats.each do |fmt|
          variants = entry[:variants].select { |v| v[:format] == fmt }
          next if variants.empty?
          source = Nokogiri::XML::Node.new("source", doc)
          source["type"]   = "image/#{fmt}"
          source["srcset"] = variants.map { |v| "#{v[:path]} #{v[:width]}w" }.join(", ")
          source["sizes"]  = img["sizes"] if img["sizes"]
          picture.add_child(source)
        end

        img.replace(picture).tap { picture.add_child(img) }
      end

      private

      def ensure_dimensions(img, entry)
        img["width"]  ||= entry[:width].to_s
        img["height"] ||= entry[:height].to_s
      end

      def ensure_img_srcset(img, entry)
        return if img["srcset"]
        fallback = entry[:variants].reject { |v| v[:format] == :avif || v[:format] == :webp }
        return if fallback.empty?

        img["srcset"] = fallback.map { |v| "#{v[:path]} #{v[:width]}w" }.join(", ")
        img["sizes"]  ||= "100vw"
        smallest = fallback.min_by { |v| v[:width] }
        img["src"] = smallest[:path] if smallest
      end
    end
  end
end
