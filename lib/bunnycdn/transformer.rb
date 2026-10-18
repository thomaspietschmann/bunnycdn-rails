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
  # Verified against https://bunny.net/docs/optimizer/dynamic-images (October 2026).
  # Bunny applies operations in a fixed order: crop (crop, aspect_ratio,
  # focus_crop, face_crop) → resize (width, height) → flip/flop/rotate →
  # blur/sharpen → color adjustments → format/quality.
  #
  # Notable differences from Cloudinary, handled here:
  #   * Bunny `crop=W,H` is a pixel cut-out of the ORIGINAL image, not a
  #     "scale to fill" → Cloudinary `crop: :fill`/`:thumb` becomes
  #     `aspect_ratio=W:H` + `width`/`height` (crop to ratio, then resize)
  #   * Bunny has no `grayscale` parameter   → emit `saturation=-100`
  #   * Bunny has no `q_auto`                → emit a configured numeric quality,
  #                                           or omit `quality` entirely
  #   * Bunny enables WebP/AVIF globally     → `fetch_format: :auto` emits nothing
  #   * Bunny `upscaling` is `off|resampling`, not a boolean
  #   * Bunny `rotate` only accepts multiples of 90 degrees
  #   * Bunny cannot rasterize PDFs          → `page:`/`format: :pdf` are dropped
  class Transformer
    # Cloudinary crop modes → Bunny behavior mapping.
    #   :proportional  scale within width/height, keep aspect ratio (no crop)
    #   :fill          crop to the W:H aspect ratio, then scale to W×H
    #   :pixel         cut W×H pixels out of the original (Bunny `crop=`)
    CROP_MODES = {
      limit: :proportional, # Scale down to fit within width/height, keep aspect ratio
      scale: :proportional, # Same as limit for Bunny
      fit: :proportional,
      fill: :fill,          # Crop to aspect ratio, then scale to exact dimensions
      lfill: :fill,         # Same as fill (Bunny never upscales unless asked)
      thumb: :fill,         # Same as fill (face gravity handled separately)
      crop: :pixel          # Extract exactly W×H pixels from the original
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
      south_west: "southwest"
    }.freeze

    # Cloudinary gravity values that mean "find the face(s)" → Bunny face_crop.
    FACE_GRAVITIES = %i[face faces].freeze

    # Raw Bunny crop syntax: "W,H" or "W,H,X,Y" (pixels of the original image).
    PIXEL_CROP = /\A\d+,\d+(?:,\d+,\d+)?\z/

    # Image formats Bunny can actually convert to. Anything else (e.g. :pdf,
    # used by the talks slides view) is dropped so we return the raw asset URL.
    IMAGE_FORMATS = %w[webp avif jpeg png gif].freeze
    FORMAT_ALIASES = {
      "jpg" => "jpeg"
    }.freeze

    # Documented value ranges; out-of-range values are clamped so Cloudinary
    # scales (e.g. blur 1–2000) degrade gracefully instead of being rejected.
    INTEGER_RANGES = {
      blur: 0..100,
      sepia: 0..100,
      hue: 0..100,
      brightness: -100..100,
      contrast: -100..100,
      saturation: -100..100,
      gamma: -100..100
    }.freeze

    DIRECT_INTEGER_PARAMS = INTEGER_RANGES.keys.freeze

    DIRECT_BOOLEAN_PARAMS = %i[
      sharpen flip flop
    ].freeze

    # Bunny rotates in 90-degree steps only.
    ROTATIONS = [-270, -180, -90, 0, 90, 180, 270].freeze

    UPSCALING_MODES = %w[off resampling].freeze

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
      crop = @options[:crop]
      return if crop.nil?

      # Raw Bunny syntax ("800,600" / "800,600,10,20") is passed through as-is.
      if crop.to_s.match?(PIXEL_CROP)
        params[:crop] = crop.to_s
        params[:crop_gravity] = bunny_gravity
        return
      end

      case CROP_MODES[crop.to_sym] || :proportional
      when :fill then apply_fill_crop(params)
      when :pixel then apply_pixel_crop(params)
        # :proportional → width/height stay as-is; Bunny scales proportionally.
      end
    end

    # Cloudinary fill/thumb: crop to the target aspect ratio, then resize.
    # Bunny: `aspect_ratio=W:H` (crop runs first) + `width`/`height` (resize).
    # Bunny documents crop_gravity for `crop=` only; it is emitted here as a
    # best-effort hint, the aspect_ratio crop itself is centred.
    def apply_fill_crop(params)
      width = params[:width]
      height = params[:height]

      params[:face_crop] = "true" if face_gravity?

      # Cropping to an exact ratio only makes sense when both dimensions are known.
      return unless width && height

      params[:aspect_ratio] = reduce_ratio(width, height) unless @options.key?(:aspect_ratio)
      params[:crop_gravity] = bunny_gravity unless face_gravity?
    end

    # Cloudinary `crop: :crop` extracts W×H pixels from the original, optionally
    # at an x/y offset — exactly what Bunny's `crop=` does.
    def apply_pixel_crop(params)
      width = params.delete(:width)
      height = params.delete(:height)
      return unless width && height

      x = integer_option(@options[:x])
      y = integer_option(@options[:y])

      if x && y
        params[:crop] = "#{width},#{height},#{x},#{y}"
      else
        params[:crop] = "#{width},#{height}"
        params[:crop_gravity] = bunny_gravity
      end
    end

    def face_gravity?
      FACE_GRAVITIES.include?(@options[:gravity]&.to_sym)
    end

    def bunny_gravity
      gravity = @options[:gravity]&.to_sym
      GRAVITY_MAP[gravity] if gravity
    end

    def reduce_ratio(width, height)
      divisor = width.gcd(height)
      "#{width / divisor}:#{height / divisor}"
    end

    def apply_quality(params)
      quality = @options[:quality]

      if [:auto, "auto"].include?(quality)
        configured_quality = Bunnycdn.configuration.default_quality
        params[:quality] = configured_quality if configured_quality
      else
        parsed = Support.transform_dimension(quality)
        params[:quality] = parsed if parsed && (0..100).cover?(parsed)
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
        params[:blur] = clamp(:blur, ::Regexp.last_match(1)&.to_i || 5)
      when /\Asepia(?::(\d+))?\z/
        params[:sepia] = clamp(:sepia, ::Regexp.last_match(1)&.to_i || 50)
      when /\Abrightness(?::(-?\d+))?\z/
        params[:brightness] = clamp(:brightness, ::Regexp.last_match(1)&.to_i || 10)
      when /\Acontrast(?::(-?\d+))?\z/
        params[:contrast] = clamp(:contrast, ::Regexp.last_match(1)&.to_i || 10)
      when /\Asaturation(?::(-?\d+))?\z/
        params[:saturation] = clamp(:saturation, ::Regexp.last_match(1)&.to_i || 10)
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
      params[:class] = string_option(@options[:image_class]) if @options.key?(:image_class)
      params[:optimizer] = string_option(@options[:optimizer]) if @options.key?(:optimizer)
      params[:aspect_ratio] = aspect_ratio_option(@options[:aspect_ratio]) if @options.key?(:aspect_ratio)
      params[:focus_crop] = string_option(@options[:focus_crop]) if @options.key?(:focus_crop)
      params[:face_crop] = face_crop_option(@options[:face_crop]) if @options.key?(:face_crop)
      params[:tint] = tint_option(@options[:tint]) if @options.key?(:tint)

      DIRECT_INTEGER_PARAMS.each do |key|
        value = integer_option(@options[key])
        params[key] = clamp(key, value) if value
      end

      DIRECT_BOOLEAN_PARAMS.each do |key|
        value = boolean_option(@options[key])
        params[key] = value if value
      end

      params[:upscaling] = upscaling_option(@options[:upscaling]) if @options.key?(:upscaling)

      rotate = rotate_option(@options.key?(:rotate) ? @options[:rotate] : @options[:angle])
      params[:rotate] = rotate if rotate
    end

    def integer_option(value)
      Integer(value, exception: false)
    end

    def clamp(key, value)
      range = INTEGER_RANGES[key]
      range ? value.clamp(range) : value
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

    # Bunny: `upscaling=off|resampling`. Booleans are accepted for convenience.
    def upscaling_option(value)
      mode = value.to_s.downcase
      return mode if UPSCALING_MODES.include?(mode)

      case boolean_option(value)
      when "true" then "resampling"
      when "false" then "off"
      end
    end

    # Bunny: `face_crop=true` (keep all faces in frame) or `face_crop=W,H`
    # (W×H pixels of the original, centred on the faces).
    def face_crop_option(value)
      return value.to_s if value.to_s.match?(/\A\d+,\d+\z/)

      "true" if boolean_option(value) == "true"
    end

    # Bunny only rotates in 90-degree steps between -270 and 270. Other
    # multiples of 90 are normalised; arbitrary angles are dropped.
    def rotate_option(value)
      degrees = integer_option(value)
      return unless degrees && (degrees % 90).zero?

      ROTATIONS.include?(degrees) ? degrees : degrees % 360
    end

    def string_option(value)
      value = value.to_s
      value.empty? ? nil : value
    end

    # Bunny: "W:H". Cloudinary also allows numeric ratios such as 1.5 → "3:2".
    def aspect_ratio_option(value)
      return string_option(value) unless value.is_a?(Numeric)
      return if value <= 0

      ratio = value.to_r.rationalize(Rational(1, 1000))
      "#{ratio.numerator}:#{ratio.denominator}"
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
      value.to_s.b.gsub(/[^a-zA-Z0-9_.~,:-]/) { |c| format("%%%02X", c.ord) }
    end

    def normalize_format(value)
      format = value.to_s.downcase
      FORMAT_ALIASES.fetch(format, format)
    end
  end
end
