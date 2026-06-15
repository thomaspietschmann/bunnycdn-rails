# frozen_string_literal: true

module Bunnycdn
  # Cloudinary-compatible delivery helpers for migration
  # (cl_image_tag, cl_image_path, cl_path, cloudinary_url, upload_path).
  #
  # Include it wherever the app currently includes Cloudinary's CloudinaryHelper
  # — in ApplicationHelper for views, and in the few POROs that build URLs
  # outside of views (content preprocessors, markdown rewriting):
  #
  #   module ApplicationHelper
  #     include Bunnycdn::CloudinaryCompat
  #   end
  #
  # cl_path / cl_image_path / cloudinary_url only build URLs and work in any
  # context. cl_image_tag additionally calls image_tag and therefore needs a
  # view context (ActionView::Helpers::AssetTagHelper), exactly like before.
  module CloudinaryCompat
    include Bunnycdn::ImageHelper

    # Generates an <img> tag with a Bunny CDN URL. Transformation options become
    # query parameters; display-only width/height (%, px) and real HTML
    # attributes (class, alt, loading, …) are passed straight to image_tag.
    def cl_image_tag(source, options = {})
      transform, html = Bunnycdn::Support.split_options(options)
      image_tag(cl_path(source, **transform), **html)
    end

    # Returns a Bunny CDN URL string (no <img> tag).
    def cl_image_path(source, options = {})
      cl_path(source, **options)
    end

    # Builds a full Bunny CDN URL from a source and transformation options.
    #
    # The source may be:
    #   * an absolute URL (BannerBear render, S3 fallback) → returned untouched
    #   * an upload path "uploads-<env>/<key>"             → uploads pull zone
    #   * a static asset path                              → static pull zone
    def cl_path(source, **options)
      upload_url = upload_source_url(source, options)
      return upload_url if upload_url

      source = source.to_s
      config = Bunnycdn.configuration

      return source if Bunnycdn::Support.absolute_url?(source)

      if (match = Bunnycdn::Support.upload_path_match(source))
        # match[1] is the Cloudinary mapping folder (bucket selector), match[2]
        # the blob key. Only the key is part of the Bunny URL.
        Bunnycdn::UrlBuilder.upload_url(match[2], **options)
      elsif config.static_zone_url
        Bunnycdn::UrlBuilder.build_url(config.static_zone_url, source, options)
      else
        # No static zone configured (e.g. local dev): keep the asset path and
        # just append any transform params so nothing breaks.
        query = Bunnycdn::Transformer.new(options).to_query_string
        query.empty? ? source : "#{source}?#{query}"
      end
    end

    # Compatibility helper for Cloudinary-style cloudinary_url calls.
    #
    # Bunny has no per-request Content-Disposition, so `flags:
    # "attachment:name"` is dropped here. Force the download via a Bunny Edge
    # Rule on the pull zone, or route the link through ActiveStorage with
    # `rails_blob_url(blob, disposition: "attachment")`.
    def cloudinary_url(source, **options)
      cl_path(source, **options.except(:flags))
    end

    # Builds the prefixed upload path for an ActiveStorage attachment,
    # e.g. "uploads-production/<blob-key>". Mirrors the app's own upload_path.
    def upload_path(upload)
      prefix = Bunnycdn.configuration.uploads_prefix
      key = upload.respond_to?(:key) ? upload_delivery_key(upload) : upload.to_s
      prefix ? "#{prefix}/#{key}" : key.to_s
    end

    private

    def upload_source_url(source, options)
      return unless Bunnycdn::Support.upload_source?(source)

      return bunny_upload_url(source, **options) if respond_to?(:bunny_upload_url, true)

      config = Bunnycdn.configuration
      return active_storage_upload_url(source, **options) if config.active_storage_uploads?

      Bunnycdn::UrlBuilder.upload_url(upload_delivery_key(source), **options) if source.respond_to?(:key)
    rescue StandardError
      nil
    end
  end
end
