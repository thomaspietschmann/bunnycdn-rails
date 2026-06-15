# frozen_string_literal: true

module Bunnycdn
  # Native Bunny view helpers, available in all views and controllers when the
  # gem is loaded via the Railtie. These are the helpers to migrate towards
  # once the Cloudinary compatibility layer is no longer needed.
  module ImageHelper
    # <img> tag with a Bunny CDN URL for an image source.
    #
    #   bunny_image_tag(article.header_image, width: 800, alt: "Header")
    #   bunny_image_tag("uploads-production/abc123", width: 800)
    #   bunny_image_tag("header.jpg", width: 1600)
    #   bunny_image_tag("https://example.com/image.jpg", alt: "Remote")
    def bunny_image_tag(source, **options)
      transform, html = Bunnycdn::Support.split_options(options)
      url = bunny_image_source_url(source, transform)

      return "" if url.to_s.empty?

      image_tag(url, bunny: false, **html)
    end

    # Bunny CDN URL for an uploaded file (no <img> tag) — for meta tags, JSON…
    #
    #   bunny_upload_url(article.og_image, width: 2000, crop: :limit)
    #
    # In the default :active_storage strategy the attachment's own
    # ActiveStorage proxy URL is CDN-hosted, which keeps the original
    # filename/extension and also works for the local Disk service — see
    # #active_storage_upload_url. In :mapping strategy the URL is
    # "<uploads_zone>/<blob-key>" (Bunny pull zone over the upload bucket),
    # with `optimizer=image` added automatically for image-like uploads.
    def bunny_upload_url(upload, **options)
      return "" unless attached?(upload)

      if Bunnycdn.configuration.active_storage_uploads?
        active_storage_upload_url(upload, **options)
      elsif Bunnycdn.configuration.uploads_zone_url
        Bunnycdn::UrlBuilder.upload_url(upload_delivery_key(upload), **mapping_upload_options(upload, options))
      else
        # No CDN zone configured (e.g. local dev without BUNNY_UPLOADS_ZONE_URL):
        # fall back to a plain ActiveStorage URL so pages render without errors.
        append_transform_query(active_storage_path(upload), options)
      end
    end

    # Bunny CDN URL for a static asset with transformations.
    #
    #   bunny_static_url("header-data-and-ai.jpg", width: 2560)
    def bunny_static_url(path, **)
      Bunnycdn::UrlBuilder.static_url(path, **)
    end

    # Inline CSS background-image style for CMS-style background image helpers.
    #
    #   bunny_bg_image_style("header-data-and-ai.jpg", width: 2560)
    def bunny_bg_image_style(path, **)
      "background-image: url('#{bunny_static_url(path, **)}');"
    end

    # The prefixed upload path for an ActiveStorage attachment,
    # e.g. "uploads-production/<key>".
    def bunny_upload_path(upload)
      prefix = Bunnycdn.configuration.uploads_prefix
      key = upload.respond_to?(:key) ? upload_delivery_key(upload) : upload.to_s
      prefix ? "#{prefix}/#{key}" : key
    end

    # Direct CDN URL for a downloadable file (PDF, ePub…).
    #
    # Bunny has no per-request Content-Disposition, so a download filename
    # cannot be set here. To force a download with a filename, add an Edge Rule
    # on the pull zone or link through ActiveStorage
    # (`rails_blob_url(blob, disposition: "attachment")`).
    def bunny_download_url(upload)
      return "" unless attached?(upload)

      Bunnycdn::UrlBuilder.upload_url(upload_delivery_key(upload))
    end

    private

    # Accept an ActiveStorage attachment, a blob, or anything responding to key.
    def attached?(upload)
      return false if upload.nil?
      return upload.attached? if upload.respond_to?(:attached?)

      upload.respond_to?(:key)
    end

    def bunny_image_source_url(source, transform)
      return "" if source.nil?
      return bunny_upload_url(source, **transform) if Bunnycdn::Support.upload_source?(source)

      source = source.to_s
      config = Bunnycdn.configuration

      return source if Bunnycdn::Support.absolute_url?(source)

      if (match = Bunnycdn::Support.upload_path_match(source))
        return Bunnycdn::UrlBuilder.upload_url(match[2], **transform) if config.uploads_zone_url

        return append_transform_query(source, transform)
      end

      resolved = resolve_asset_path(source)

      if config.static_zone_url
        Bunnycdn::UrlBuilder.build_url(config.static_zone_url, strip_url_host(resolved), transform)
      else
        append_transform_query(resolved, transform)
      end
    end

    def resolve_asset_path(source)
      respond_to?(:image_path) ? image_path(source) : source
    end

    def append_transform_query(url, transform)
      query = Bunnycdn::Transformer.new(transform).to_query_string
      query.empty? ? url : "#{url}?#{query}"
    end

    # Build a CDN URL from the attachment's own ActiveStorage URL. Works with
    # any service (Disk, S3, GCS…) and needs no separate upload bucket — set up
    # a Bunny pull zone with the Rails app as origin. Falls back to the plain
    # ActiveStorage URL when no zone is configured (e.g. local development).
    def active_storage_upload_url(upload, **options)
      path = active_storage_path(upload)
      host = Bunnycdn.configuration.uploads_zone_url || Bunnycdn.configuration.static_zone_url
      return Bunnycdn::UrlBuilder.build_url(host, strip_url_host(path), options) if host

      query = Bunnycdn::Transformer.new(options).to_query_string
      query.empty? ? path : "#{path}?#{query}"
    end

    # Prefer a stable proxy path (no expiring signature, CDN-cacheable). Fall
    # back to the attachment's #url for setups without proxy routes.
    def active_storage_path(upload)
      if respond_to?(:rails_storage_proxy_path)
        rails_storage_proxy_path(upload, only_path: true)
      else
        upload.url
      end
    rescue StandardError
      upload.url
    end

    def strip_url_host(url)
      url.to_s.sub(%r{\Ahttps?://[^/]+}, "")
    end

    def upload_delivery_key(upload)
      key = upload.key.to_s
      return key unless Bunnycdn.configuration.append_upload_extension

      extension = upload_extension(upload)
      extension ? "#{key}.#{extension}" : key
    end

    def mapping_upload_options(upload, options)
      return options if options.key?(:optimizer) || options.key?("optimizer")
      return options unless image_upload?(upload)

      options.merge(optimizer: "image")
    end

    def upload_extension(upload)
      filename = upload.respond_to?(:filename) ? upload.filename.to_s : nil
      extension = File.extname(filename.to_s).delete_prefix(".").downcase
      return extension unless extension.empty?

      content_type = upload.respond_to?(:content_type) ? upload.content_type.to_s.downcase : ""
      {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp",
        "image/gif" => "gif",
        "image/avif" => "avif",
        "image/svg+xml" => "svg",
        "application/pdf" => "pdf"
      }[content_type]
    end

    def image_upload?(upload)
      target = upload_blob(upload) || upload
      content_type = target.respond_to?(:content_type) ? target.content_type.to_s.downcase : ""
      return content_type.start_with?("image/") unless content_type.empty?

      %w[jpg jpeg png webp gif avif svg bmp tif tiff].include?(upload_extension(target))
    end

    def upload_blob(upload)
      return upload.blob if upload.respond_to?(:blob) && upload.blob

      return upload.attachment.blob if upload.respond_to?(:attachment) && upload.attachment.respond_to?(:blob)

      nil
    rescue StandardError
      nil
    end
  end
end
