# frozen_string_literal: true

module Bunnycdn
  # Builds full CDN URLs for both user uploads and static assets.
  #
  # For user uploads (ActiveStorage → S3 → Bunny Pull Zone):
  #   Bunnycdn::UrlBuilder.upload_url("abc123key", width: 800, quality: 80)
  #   # => "https://uploads.b-cdn.net/uploads-production/abc123key?width=800&quality=80"
  #
  # For static assets:
  #   Bunnycdn::UrlBuilder.static_url("header-data-and-ai.jpg", width: 2560)
  #   # => "https://static.b-cdn.net/assets/header-data-and-ai-3b5432cc.jpg?width=2560"
  #
  class UrlBuilder
    # Keys that are transformation parameters (everything else is an HTML attribute).
    TRANSFORM_KEYS = %i[
      width height crop gravity quality fetch_format format effect
      dpr secure transformation aspect_ratio optimizer sharpen blur sepia
      brightness contrast saturation hue gamma tint flip flop rotate
      angle upscaling focus_crop page flags
    ].to_set.freeze

    class << self
      # Build a CDN URL for a user-uploaded file (ActiveStorage blob).
      #
      # The blob key is served from the pull zone root: a Bunny pull zone whose
      # origin is the upload bucket maps "<zone>/<key>" → "<bucket>/<key>". The
      # Cloudinary-style mapping folder (e.g. "uploads-production/") is NOT part
      # of the delivered path — it only selects which bucket/zone to use and is
      # stripped before we get here. If your zone instead serves the files under
      # a sub-path, bake that path into uploads_zone_url.
      #
      # @param blob_key [String] The ActiveStorage blob key
      # @param options [Hash] Transformation options (width:, height:, crop:, etc.)
      # @return [String] The full Bunny CDN URL
      def upload_url(blob_key, **options)
        base = Bunnycdn.configuration.uploads_zone_url
        raise Error, "uploads_zone_url is not configured" unless base

        build_url(base, blob_key.to_s, options)
      end

      # Build a CDN URL for a static asset (from the Rails asset pipeline).
      #
      # @param asset_path [String] The asset path (e.g., "header-image.jpg" or "/assets/header-image-abc123.jpg")
      # @param options [Hash] Transformation options
      # @return [String] The full Bunny CDN URL
      def static_url(asset_path, **options)
        config = Bunnycdn.configuration
        base = config.static_zone_url

        raise Error, "static_zone_url is not configured" unless base

        build_url(base, asset_path, options)
      end

      # Build a URL for any path on any Bunny pull zone.
      #
      # @param base_url [String] The pull zone base URL
      # @param path [String] The file path
      # @param options [Hash] Transformation options
      # @return [String] The full URL with query parameters
      def build_url(base_url, path, options = {})
        # Separate HTML attributes from transformation options
        transform_opts = extract_transform_options(options)
        transformer = Transformer.new(transform_opts)
        query = transformer.to_query_string

        base_url = base_url.chomp("/")
        path = path.sub(%r{\A/}, "")

        url = "#{base_url}/#{path}"
        url += "?#{query}" unless query.empty?
        url
      end

      private

      def extract_transform_options(options)
        options.select { |key, _| TRANSFORM_KEYS.include?(key.to_sym) }
      end
    end
  end
end
