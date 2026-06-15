# frozen_string_literal: true

module Bunnycdn
  # Shared helpers used by both the URL/transform layer and the Rails view
  # integration. Kept dependency-free so it can be required from anywhere.
  module Support
    module_function

    # Matches absolute URLs (http, https, protocol-relative). Sources that look
    # like this are foreign origins (e.g. BannerBear renders, S3 fallbacks) and
    # must be passed through untouched — they are not Bunny pull-zone paths.
    ABSOLUTE_URL = %r{\A(?:[a-z][a-z0-9+.-]*:)?//}i

    def absolute_url?(source)
      source.to_s.match?(ABSOLUTE_URL)
    end

    # True for objects Rails can resolve as uploaded files rather than asset
    # pipeline paths: ActiveStorage attachments/blobs/variants and compatible
    # objects exposing a storage key or service URL.
    def upload_source?(source)
      return false if source.nil? || source.is_a?(String) || source.is_a?(Symbol)
      return source.attached? if source.respond_to?(:attached?)
      return true if source.respond_to?(:key) || source.respond_to?(:url)

      source.class.name.to_s.start_with?("ActiveStorage::")
    end

    # Returns the MatchData when source is a user-upload path (per the configured
    # upload_path_pattern), or nil for static assets / absolute URLs. Capture 1
    # is the mapping folder, capture 2 the blob key.
    def upload_path_match(source)
      Bunnycdn.configuration.upload_path_pattern.match(source.to_s)
    end

    # The integer pixel value to use as a CDN transform, or nil when the value
    # is a display-only dimension (percentage, px suffix, "auto", …) that must
    # not become a query parameter.
    def transform_dimension(value)
      case value
      when Integer then value
      when /\A\d+\z/ then value.to_i
      end
    end

    # The value to emit as an HTML width/height attribute when a dimension is
    # not a CDN transform (admin previews use width: "100%", height: "400px").
    # Returns nil for plain pixel transforms.
    def html_dimension(value)
      case value.to_s
      when /\A\d+%\z/ then value.to_s # "100%" → keep the percentage
      when /\A(\d+)px\z/ then ::Regexp.last_match(1) # "400px" → "400" (HTML wants unitless)
      when "auto" then "auto"
      end
    end

    # Split a mixed options hash into [transform_options, html_options].
    #
    # Transformation keys go to the first hash, everything else (class, alt,
    # loading, …) to the second. width/height are special-cased: a display-only
    # value (%, px, auto) is moved to the HTML side so it renders at the
    # intended size instead of producing a tiny CDN resize.
    def split_options(options)
      transform = {}
      html = {}

      options.each do |key, value|
        if UrlBuilder::TRANSFORM_KEYS.include?(key.to_sym)
          transform[key] = value
        else
          html[key] = value
        end
      end

      %i[width height].each do |dim|
        next unless transform.key?(dim) || transform.key?(dim.to_s)

        raw = transform[dim] || transform[dim.to_s]
        display = html_dimension(raw)
        next unless display

        html[dim] = display
        transform.delete(dim)
        transform.delete(dim.to_s)
      end

      [transform, html]
    end
  end
end
