# frozen_string_literal: true

module Bunnycdn
  # Translates Cloudinary-style Ruby hash options into Bunny CDN query parameters.
  #
  # Bunny Optimizer uses URL query parameters for on-the-fly image transformations:
  #   https://yourzone.b-cdn.net/image.jpg?width=800&quality=80&saturation=-100
  #
  # This class maps the Cloudinary conventions used throughout the innoq CMS
  # to their Bunny equivalents, making migration straightforward.
  #
  # Verified against https://docs.bunny.net/optimizer/dynamic-images (June 2026).
  # Notable differences from Cloudinary, handled here:
  #   * Bunny has no `grayscale` parameter   → emit `saturation=-100`
  #   * Bunny has no `q_auto`                → emit a configured numeric quality,
  #                                           or omit `quality` entirely
  #   * Bunny enables WebP/AVIF globally     → `fetch_format: :auto` emits nothing
  #   * Bunny cannot rasterize PDFs          → `page:`/`format: :pdf` are dropped
  class Transformer
    # Cloudinary crop modes → Bunny behavior mapping.
    CROP_MODES = {
      limit: :proportional, # Scale down to fit within width/height, keep aspect ratio
      scale: :proportional, # Same as limit for Bunny
      fit: :proportional,
      fill: :crop,          # Crop to exact dimensions
      thumb: :crop          # Crop to exact dimensions (gravity handled separately)
    }.freeze

    # Cloudinary gravity values → Bunny crop_gravity values.
    GRAVITY_MAP = {
      center: "center",
      north: "north",
      south: "south",
      east: "east",
      west: "west",
      north_east: "northeast",
      north_west: "northwest",
      south_east: "southeast",
      south_west: "southwest",
      face: "center" # Bunny exposes face detection via the separate face_crop param
    }.freeze

    # Image formats Bunny can actually convert to. Anything else (e.g. :pdf,
    # used by the talks slides view) is dropped so we return the raw asset URL.
    IMAGE_FORMATS = %w[webp avif jpeg png gif].freeze
    FORMAT_ALIASES = {
      "jpg" => "jpeg"
    }.freeze

    DIRECT_INTEGER_PARAMS = %i[
      blur sepia brightness contrast saturation hue gamma
    ].freeze

    DIRECT_BOOLEAN_PARAMS = %i[
      sharpen flip flop upscaling
    ].freeze

    def initialize(options = {})
      @options = normalize_options(options)
    end

    # Returns a hash of Bunny query parameters.
    def to_params
      params = {}

      apply_dimensions(params)
      apply_crop(params)
      apply_quality(params)
      apply_direct_transformations(params)
      apply_effects(params)
      apply_format(params)

      params.compact
    end

    # Returns the query string portion: "width=800&saturation=-100".
    def to_query_string
      to_params.map { |k, v| "#{k}=#{encode_query_value(v)}" }.join("&")
    end

    private

    def normalize_options(options)
      # Flatten Cloudinary transformation arrays (chained transforms) into one hash.
      if options[:transformation].is_a?(Array)
        merged = {}
        options[:transformation].each { |t| merged.merge!(t.transform_keys(&:to_sym)) }
        options = options.except(:transformation).merge(merged)
      end

      options.transform_keys(&:to_sym)
    end

    def apply_dimensions(params)
      width = Support.transform_dimension(@options[:width])
      height = Support.transform_dimension(@options[:height])
      dpr = @options[:dpr]&.to_f

      if dpr && dpr > 1
        width = (width * dpr).round if width
        height = (height * dpr).round if height
      end

      params[:width] = width if width
      params[:height] = height if height
    end

    def apply_crop(params)
      crop = @options[:crop]&.to_sym
      gravity = @options[:gravity]&.to_sym
      width = params[:width]
      height = params[:height]

      return unless crop

      mode = CROP_MODES[crop] || :proportional
      # Cropping to exact dimensions only makes sense when both are known.
      return unless mode == :crop && width && height

      if crop == :thumb && gravity == :face
        params[:face_crop] = "#{width},#{height}"
      else
        params[:crop] = "#{width},#{height}"
        bunny_gravity = GRAVITY_MAP[gravity] if gravity
        params[:crop_gravity] = bunny_gravity if bunny_gravity
      end

      # The crop/face_crop params already carry the target size; drop the raw
      # width/height so Bunny doesn't also down-scale after cropping.
      params.delete(:width)
      params.delete(:height)
      # For :proportional modes (limit/scale/fit) width/height stay as-is —
      # Bunny scales proportionally when only one or both are given without crop.
    end

    def apply_quality(params)
      quality = @options[:quality]

      if [:auto, "auto"].include?(quality)
        configured_quality = Bunnycdn.configuration.default_quality
        params[:quality] = configured_quality if configured_quality
      elsif quality.is_a?(Integer) || quality.is_a?(String)
        parsed = quality.to_i
        params[:quality] = parsed if parsed.positive?
      end
    end

    def apply_effects(params)
      effect = @options[:effect]
      return unless effect

      case effect.to_s
      when "grayscale", "blackwhite"
        # Bunny has NO grayscale parameter — desaturate completely instead.
        params[:saturation] = -100
      when /\Asharpen(?::\d+)?\z/
        params[:sharpen] = "true" # Bunny sharpen is boolean; intensity is ignored
      when /\Ablur(?::(\d+))?\z/
        params[:blur] = ::Regexp.last_match(1)&.to_i || 5
      when /\Asepia(?::(\d+))?\z/
        params[:sepia] = ::Regexp.last_match(1)&.to_i || 50
      when /\Abrightness(?::(-?\d+))?\z/
        params[:brightness] = ::Regexp.last_match(1)&.to_i || 10
      when /\Acontrast(?::(-?\d+))?\z/
        params[:contrast] = ::Regexp.last_match(1)&.to_i || 10
      when /\Asaturation(?::(-?\d+))?\z/
        params[:saturation] = ::Regexp.last_match(1)&.to_i || 10
      end
    end

    def apply_format(params)
      raw = @options[:format] || @options[:fetch_format]

      # :auto / "auto" → let Bunny's global WebP/AVIF setting handle negotiation.
      # Suppress even the configured default_format so the caller's explicit
      # intent (auto-negotiate) is respected.
      return if !raw.nil? && raw.to_s.casecmp("auto").zero?

      format = normalize_format(raw)
      default = normalize_format(Bunnycdn.configuration.default_format)

      if IMAGE_FORMATS.include?(format)
        params[:format] = format
      elsif IMAGE_FORMATS.include?(default)
        params[:format] = default
      end
      # nil or non-image formats (e.g. :pdf) → serve the original asset untouched.
    end

    def apply_direct_transformations(params)
      params[:optimizer] = string_option(@options[:optimizer]) if @options.key?(:optimizer)
      params[:aspect_ratio] = string_option(@options[:aspect_ratio]) if @options.key?(:aspect_ratio)
      params[:focus_crop] = string_option(@options[:focus_crop]) if @options.key?(:focus_crop)
      params[:tint] = tint_option(@options[:tint]) if @options.key?(:tint)

      DIRECT_INTEGER_PARAMS.each do |key|
        value = integer_option(@options[key])
        params[key] = value if value
      end

      DIRECT_BOOLEAN_PARAMS.each do |key|
        value = boolean_option(@options[key])
        params[key] = value if value
      end

      rotate = integer_option(@options.key?(:rotate) ? @options[:rotate] : @options[:angle])
      params[:rotate] = rotate if rotate
    end

    def integer_option(value)
      Integer(value, exception: false)
    end

    def boolean_option(value)
      return if value.nil?
      return "true" if value == true
      return "false" if value == false
      return "true" if value.is_a?(Numeric) && !value.zero?
      return "false" if value.is_a?(Numeric) && value.zero?

      case value.to_s.downcase
      when "true", "1" then "true"
      when "false", "0" then "false"
      end
    end

    def string_option(value)
      value = value.to_s
      value.empty? ? nil : value
    end

    def tint_option(value)
      value = string_option(value)
      return unless value

      value.delete_prefix("#").downcase
    end

    # Encode query-string values to prevent parameter injection.
    # Commas and colons are left intact: they appear in valid Bunny param values
    # such as crop ("400,300") and aspect_ratio ("16:9"), and Bunny expects them
    # as literal characters.
    def encode_query_value(value)
      value.to_s.gsub(/[ &=+#%<>"']/) { |c| format("%%%02X", c.ord) }
    end

    def normalize_format(value)
      format = value.to_s.downcase
      FORMAT_ALIASES.fetch(format, format)
    end
  end
end
