# frozen_string_literal: true

require "json"
require "fileutils"

module Bridgetown
  module ImagePipeline
    class Manifest
      def initialize(cache_dir:)
        @cache_dir = cache_dir
        FileUtils.mkdir_p(@cache_dir)
        @entries = {}        # source_path => entry hash (symbolized)
        @by_src  = {}        # "/images/foo.jpg" => entry hash
      end

      def put(source_path, entry, cache_key:)
        symbolized = deep_symbolize(entry)
        @entries[source_path] = symbolized
        @by_src[public_src_for(source_path)] = symbolized
        File.write(cache_file(cache_key), JSON.generate(symbolized))
      end

      def fetch_cached(cache_key)
        path = cache_file(cache_key)
        return nil unless File.exist?(path)

        deep_symbolize(JSON.parse(File.read(path)))
      end

      def register_cached(source_path, entry)
        @entries[source_path] = entry
        @by_src[public_src_for(source_path)] = entry
      end

      def find_by_src(src)
        @by_src[src]
      end

      def variants_by_width(src)
        entry = @by_src[src]
        return {} unless entry

        entry[:variants].each_with_object({}) do |v, out|
          (out[v[:width]] ||= {})[v[:format]] = v[:path]
        end
      end

      def all
        @entries.dup
      end

      private

      def cache_file(cache_key)
        File.join(@cache_dir, "#{cache_key}.manifest.json")
      end

      def public_src_for(source_path)
        "/#{source_path.sub(%r{\Asrc/}, "")}"
      end

      def deep_symbolize(obj)
        case obj
        when Hash  then obj.each_with_object({}) { |(k, v), out| out[k.to_sym] = deep_symbolize(v) }
        when Array then obj.map { |v| deep_symbolize(v) }
        when String
          %w[avif webp jpeg jpg png].include?(obj) ? obj.to_sym : obj
        else obj
        end
      end
    end
  end
end
