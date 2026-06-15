# frozen_string_literal: true

module Bunnycdn
  # Transparently routes Rails' image helpers through Bunny CDN, inspired by
  # Cloudinary's `enhance_image_tag`. Flip it on in the initializer and common
  # image_tag / image_path / image_url delivery calls can keep working during
  # migration:
  #
  #   Bunnycdn.configure { |c| c.enhance_image_tag = true }
  #
  # When enabled, the helper rewrites any resolvable upload/static image source
  # to Bunny. Per call, pass `bunny: false` to opt out and keep Rails' normal
  # behaviour. For blanket static-asset delivery via the CDN, set Rails' own
  # `config.asset_host` to the static pull zone — that routes every asset
  # (images, JS, CSS) through Bunny without any overrides.
  module ViewOverrides
    def image_path(source, options = {})
      bunny_enabled, clean_options = extract_bunny_option(options)
      return super(source, clean_options) unless enhance? && bunny_enabled

      transform, passthrough = Bunnycdn::Support.split_options(clean_options)
      upload_url = upload_source_url(source, transform)
      return upload_url if upload_url

      src = source.to_s
      config = Bunnycdn.configuration

      if Bunnycdn::Support.absolute_url?(src)
        append_query(src, transform)
      elsif (match = Bunnycdn::Support.upload_path_match(src))
        return Bunnycdn::UrlBuilder.upload_url(match[2], **transform) if config.uploads_zone_url

        append_query(src, transform)
      elsif config.static_zone_url
        # Resolve through the asset pipeline first (fingerprinting), then point
        # the fingerprinted path at the static pull zone.
        resolved = super(source, passthrough)
        Bunnycdn::UrlBuilder.build_url(config.static_zone_url, strip_host(resolved), transform)
      else
        resolved = super(source, passthrough)
        transform.empty? ? resolved : append_query(resolved, transform)
      end
    end

    # Bunny transformation URLs are already absolute, so for the enhanced path
    # image_url and image_path produce the same result.
    def image_url(source, options = {})
      bunny_enabled, clean_options = extract_bunny_option(options)
      return super(source, clean_options) unless enhance? && bunny_enabled

      url = image_path(source, clean_options)
      return url if Bunnycdn::Support.upload_source?(source)

      Bunnycdn::Support.absolute_url?(url) ? url : super(source, clean_options)
    end

    def image_tag(source, options = {})
      bunny_enabled, clean_options = extract_bunny_option(options)
      return super(source, clean_options) unless enhance? && bunny_enabled

      transform, html = Bunnycdn::Support.split_options(clean_options)
      super(image_path(source, transform), html)
    end

    private

    def enhance?
      Bunnycdn.configuration.enhance_image_tag
    end

    def extract_bunny_option(options)
      clean_options = options.to_h.dup
      bunny_value = if clean_options.key?(:bunny)
                      clean_options.delete(:bunny)
                    else
                      clean_options.delete("bunny")
                    end

      [bunny_value != false, clean_options]
    end

    def strip_host(url)
      url.sub(%r{\Ahttps?://[^/]+}, "")
    end

    def append_query(url, transform)
      query = Bunnycdn::Transformer.new(transform).to_query_string
      query.empty? ? url : "#{url}?#{query}"
    end

    def upload_source_url(source, transform)
      return unless Bunnycdn::Support.upload_source?(source)

      return bunny_upload_url(source, **transform) if respond_to?(:bunny_upload_url, true)

      config = Bunnycdn.configuration
      if config.active_storage_uploads? && respond_to?(:active_storage_upload_url, true)
        return send(:active_storage_upload_url, source, **transform)
      end

      Bunnycdn::UrlBuilder.upload_url(source.key, **transform) if source.respond_to?(:key)
    rescue StandardError
      nil
    end
  end
end
