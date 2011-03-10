# encoding: utf-8

module CarrierWave
  module Uploader
    module Url

      ##
      # === Returns
      #
      # [String] the location where this file is accessible via a url
      #
      def url
        if file.respond_to?(:url) and not file.url.blank?
          file.url
        elsif current_path
          File.expand_path(current_path).gsub(File.expand_path(root), '')
        end
      end

      alias_method :to_s, :url

      ##
      # === Returns
      #
      # [String] A JSON serialization containing this uploader's URL(s)
      #
      def as_json(options = nil)
        h = { :url => url }
        versions.each do |name, version|
          h[version.version_name] = {}
          h[version.version_name]['url'] = version.url
        end
        h
      end

    end # Url
  end # Uploader
end # CarrierWave