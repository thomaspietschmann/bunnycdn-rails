# frozen_string_literal: true

module Bunnycdn
  class Configuration
    # Recognises Cloudinary auto-upload-mapping style paths such as
    # "uploads-production/<key>" or "uploads-staging/<key>". Capture group 1 is
    # the mapping folder, group 2 the blob key. Override via upload_path_pattern
    # if your app uses a different convention.
    DEFAULT_UPLOAD_PATH_PATTERN = %r{\A(uploads-[\w-]+)/(.+)\z}

    # The base URL for the pull zone serving user uploads (ActiveStorage via S3).
    # Example: "https://uploads.b-cdn.net"
    attr_accessor :uploads_zone_url

    # The prefix prepended to ActiveStorage blob keys, per environment.
    # Example: "uploads-production"
    attr_accessor :uploads_prefix

    # The base URL for the pull zone serving static assets (Rails asset pipeline).
    # When set, image_tag/image_path will use this host for asset URLs.
    # Example: "https://static.b-cdn.net"
    # Alternatively, just set `config.asset_host` in Rails – works the same way.
    attr_accessor :static_zone_url

    # Optional default quality for image optimization (1-100). When nil, the
    # gem does not emit a `quality=` parameter unless the caller passes one
    # explicitly, so Bunny's pull-zone settings stay in control.
    # Default: nil
    attr_accessor :default_quality

    # Whether to automatically override Rails image_tag/image_path helpers
    # to route through Bunny CDN. Analogous to Cloudinary's enhance_image_tag.
    # Default: false
    attr_accessor :enhance_image_tag

    # Default image format. Set to nil to let Bunny Optimizer's global WebP
    # setting handle format conversion (recommended).
    # Default: nil
    attr_accessor :default_format

    # Regexp identifying user-upload paths (vs. static asset paths). Must expose
    # two captures: the mapping folder and the blob key.
    # Default: DEFAULT_UPLOAD_PATH_PATTERN
    attr_accessor :upload_path_pattern

    # When true, mapping-mode upload URLs append the file extension derived from
    # the ActiveStorage blob metadata, e.g. "<blob-key>.jpg". This can help
    # Bunny Optimizer treat the URL as an image path, but requires the origin or
    # a Bunny Edge Rule to rewrite "<blob-key>.<ext>" back to the stored object
    # key when the bucket itself stores files under extensionless blob keys.
    # Default: false
    attr_accessor :append_upload_extension

    # How an ActiveStorage attachment is turned into a CDN-fetchable URL:
    #
    #   :active_storage  (default) Bunny pull zone has the Rails app as origin.
    #                    The attachment's own ActiveStorage proxy URL is used
    #                    and CDN-hosted, so the delivery path keeps the original
    #                    filename/extension. Works with ANY service — Disk
    #                    (local), S3, GCS, … — and falls back to the plain
    #                    ActiveStorage URL when no zone is configured.
    #
    #   :mapping         Bunny pull zone has a bucket as origin and serves
    #                    "<blob-key>" directly. Use this only when your origin
    #                    path structure matches the delivered Bunny path and
    #                    Bunny Optimizer can still recognise the object as an
    #                    image (for example via a visible extension or rewrite).
    attr_accessor :upload_strategy

    UPLOAD_STRATEGIES = %i[mapping active_storage].freeze

    def initialize
      @uploads_zone_url = nil
      @uploads_prefix = nil
      @static_zone_url = nil
      @default_quality = nil
      @enhance_image_tag = false
      @default_format = nil
      @upload_path_pattern = DEFAULT_UPLOAD_PATH_PATTERN
      @upload_strategy = :active_storage
      @append_upload_extension = false
    end

    def validate!
      if uploads_zone_url && !uploads_zone_url.start_with?("http")
        raise Error, "uploads_zone_url must be a full URL (https://...)"
      end

      if static_zone_url && !static_zone_url.start_with?("http")
        raise Error, "static_zone_url must be a full URL (https://...)"
      end

      if !default_quality.nil? && (!default_quality.is_a?(Integer) || default_quality <= 0 || default_quality > 100)
        raise Error, "default_quality must be nil or an integer between 1 and 100"
      end

      return if UPLOAD_STRATEGIES.include?(upload_strategy)

      raise Error, "upload_strategy must be one of #{UPLOAD_STRATEGIES.inspect}"
    end

    # True when uploads are delivered through the attachment's own ActiveStorage
    # URL rather than an S3 auto-upload-mapping path.
    def active_storage_uploads?
      upload_strategy == :active_storage
    end
  end
end
