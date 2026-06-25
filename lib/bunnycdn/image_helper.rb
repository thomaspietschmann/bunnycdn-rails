# frozen_string_literal: true

module Bunnycdn
  # Native Bunny view helpers, available in all views and controllers when the
  # gem is loaded via the Railtie. These are the helpers to migrate towards
  # once the Cloudinary compatibility layer is no longer needed.
  module ImageHelper
    # MIME types used by bunny_picture_tag for <source type="…"> attributes.
    PICTURE_MIME_TYPES = {
      "webp" => "image/webp",
      "avif" => "image/avif",
      "jpeg" => "image/jpeg",
      "jpg" => "image/jpeg",
      "png" => "image/png",
      "gif" => "image/gif"
    }.freeze

    # <img> tag with a Bunny CDN URL. Supports responsive srcset via `widths:`.
    #
    #   bunny_image_tag(article.header_image, width: 800, alt: "Header")
    #   bunny_image_tag("header.jpg", widths: [400, 800, 1200], sizes: "(max-width: 600px) 100vw, 50vw")
    def bunny_image_tag(source, **options)
      widths = options.delete(:widths)
      transform, html = Bunnycdn::Support.split_options(options)
      # sizes is a valid HTML attribute for srcset images; it flows into html
      # naturally since it is not a TRANSFORM_KEY.

      if widths
        srcset = widths.filter_map do |w|
          url = bunny_image_source_url(source, transform.merge(width: w))
          "#{url} #{w}w" unless url.to_s.empty?
        end.join(", ")
        fallback_url = bunny_image_source_url(source, transform.merge(width: widths.min))
        return "" if fallback_url.to_s.empty?

        image_tag(fallback_url, bunny: false, srcset: srcset, **html)
      else
        url = bunny_image_source_url(source, transform)
        return "" if url.to_s.empty?

        image_tag(url, bunny: false, **html)
      end
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
    #   style: bunny_bg_image_style("header-data-and-ai.jpg", width: 2560)
    def bunny_bg_image_style(path, **)
      url = bunny_static_url(path, **)
      # Escape single quotes so the URL cannot break out of the CSS url('…') context.
      "background-image: url('#{url.gsub("'", "%27")}');"
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

      if Bunnycdn.configuration.uploads_zone_url
        Bunnycdn::UrlBuilder.upload_url(upload_delivery_key(upload))
      else
        # No zone configured (local dev): fall back gracefully like the other helpers.
        active_storage_path(upload)
      end
    end

    # A <picture> element with per-format <source> entries and a fallback <img>.
    #
    #   bunny_picture_tag(article.header_image,
    #                     formats: [:avif, :webp],
    #                     widths: [400, 800, 1200],
    #                     sizes: "(max-width: 600px) 100vw, 50vw",
    #                     alt: "Header")
    #
    # Each format gets its own <source srcset="…" type="…"> element. The fallback
    # <img> uses the original format with srcset support when widths are given.
    def bunny_picture_tag(source, formats: [:webp], widths: nil, sizes: nil, **options)
      transform, = Bunnycdn::Support.split_options(options)

      source_tags = formats.map do |fmt|
        fmt_key = fmt.to_s.downcase
        mime = PICTURE_MIME_TYPES.fetch(fmt_key, "image/#{fmt_key}")
        fmt_opts = transform.merge(format: fmt.to_sym)

        if widths
          srcset = widths.filter_map do |w|
            url = bunny_image_source_url(source, fmt_opts.merge(width: w))
            "#{url} #{w}w" unless url.to_s.empty?
          end.join(", ")
          sizes_attr = sizes ? " sizes=\"#{sizes}\"" : ""
          "<source srcset=\"#{srcset}\" type=\"#{mime}\"#{sizes_attr}>"
        else
          url = bunny_image_source_url(source, fmt_opts)
          "<source srcset=\"#{url}\" type=\"#{mime}\">"
        end
      end

      # Fallback <img> — reuse bunny_image_tag so all strategies and edge cases
      # (upload detection, AS path, srcset, etc.) are handled consistently.
      img_opts = options.dup
      img_opts[:widths] = widths if widths
      img_opts[:sizes] = sizes if sizes
      img_html = bunny_image_tag(source, **img_opts)

      return "" if img_html.to_s.empty?

      "<picture>#{source_tags.join}#{img_html}</picture>"
    end

    # Returns a tiny, blurred placeholder URL for blur-up lazy loading (LQIP).
    #
    #   data_lqip: bunny_lqip_url(article.header_image, width: 32, quality: 20)
    #
    # Pair with a full-resolution URL (bunny_upload_url / bunny_image_tag) and
    # a lazy-loading JS library that swaps the placeholder for the full image.
    def bunny_lqip_url(source, width: 32, quality: 20, blur: 15)
      bunny_image_source_url(source, width: width, quality: quality, blur: blur)
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
