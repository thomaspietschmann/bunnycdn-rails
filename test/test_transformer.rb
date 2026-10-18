# frozen_string_literal: true

require "test_helper"

class TestTransformer < Minitest::Test
  def setup
    Bunnycdn.reset_configuration!
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.default_quality = 85
    end
  end

  # === Basic dimensions ===

  def test_width_only
    t = Bunnycdn::Transformer.new(width: 800)

    assert_equal({ width: 800 }, t.to_params)
  end

  def test_height_only
    t = Bunnycdn::Transformer.new(height: 600)

    assert_equal({ height: 600 }, t.to_params)
  end

  def test_width_and_height
    t = Bunnycdn::Transformer.new(width: 800, height: 600)

    assert_equal({ width: 800, height: 600 }, t.to_params)
  end

  def test_string_width_pixels_is_not_a_transform
    # "500px" is a display dimension (admin previews) — it must NOT become a
    # CDN resize. The view helper turns it into an HTML width attribute instead.
    t = Bunnycdn::Transformer.new(width: "500px")

    assert_equal({}, t.to_params)
  end

  def test_string_width_percent_is_not_a_transform
    t = Bunnycdn::Transformer.new(width: "100%")

    assert_equal({}, t.to_params)
  end

  def test_string_width_number
    t = Bunnycdn::Transformer.new(width: "1600")

    assert_equal({ width: 1600 }, t.to_params)
  end

  # === DPR (Device Pixel Ratio) ===

  def test_dpr_multiplies_width
    t = Bunnycdn::Transformer.new(width: 400, dpr: "2.0")
    params = t.to_params

    assert_equal 800, params[:width]
  end

  def test_dpr_multiplies_width_and_height
    t = Bunnycdn::Transformer.new(width: 400, height: 300, dpr: "2.0")
    params = t.to_params

    assert_equal 800, params[:width]
    assert_equal 600, params[:height]
  end

  # === Crop modes ===

  def test_crop_limit_keeps_width_height
    t = Bunnycdn::Transformer.new(width: 800, crop: :limit)
    params = t.to_params

    assert_equal 800, params[:width]
    refute params.key?(:crop)
  end

  def test_crop_scale_keeps_width_height
    t = Bunnycdn::Transformer.new(width: 400, crop: :scale)
    params = t.to_params

    assert_equal 400, params[:width]
    refute params.key?(:crop)
  end

  def test_crop_fill_with_dimensions
    # Bunny's crop=W,H is a pixel cut-out of the original; Cloudinary :fill is
    # "crop to ratio, then scale". That is aspect_ratio + width/height on Bunny.
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :fill)
    params = t.to_params

    assert_equal "4:3", params[:aspect_ratio]
    assert_equal 400, params[:width]
    assert_equal 300, params[:height]
    refute params.key?(:crop)
  end

  def test_crop_fill_keeps_explicit_aspect_ratio
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :fill, aspect_ratio: "16:9")

    assert_equal "16:9", t.to_params[:aspect_ratio]
  end

  def test_crop_fill_with_width_only_and_aspect_ratio
    t = Bunnycdn::Transformer.new(width: 400, crop: :fill, aspect_ratio: "1:1")
    params = t.to_params

    assert_equal({ width: 400, aspect_ratio: "1:1" }, params)
  end

  def test_crop_lfill_behaves_like_fill
    t = Bunnycdn::Transformer.new(width: 300, height: 300, crop: :lfill)

    assert_equal "1:1", t.to_params[:aspect_ratio]
  end

  def test_crop_crop_extracts_pixels_from_original
    t = Bunnycdn::Transformer.new(width: 800, height: 600, crop: :crop)
    params = t.to_params

    assert_equal "800,600", params[:crop]
    refute params.key?(:width)
    refute params.key?(:height)
  end

  def test_crop_crop_with_offset
    t = Bunnycdn::Transformer.new(width: 800, height: 600, x: 10, y: 20, crop: :crop, gravity: :north)
    params = t.to_params

    assert_equal "800,600,10,20", params[:crop]
    refute params.key?(:crop_gravity) # positioned crops ignore gravity
  end

  def test_raw_bunny_crop_string_passes_through
    t = Bunnycdn::Transformer.new(crop: "800,600", gravity: :north, width: 400)
    params = t.to_params

    assert_equal "800,600", params[:crop]
    assert_equal "north", params[:crop_gravity]
    assert_equal 400, params[:width] # Bunny resizes after cropping
  end

  def test_raw_bunny_positioned_crop_string_passes_through
    t = Bunnycdn::Transformer.new(crop: "800,600,10,20")

    assert_equal "crop=800,600,10,20", t.to_query_string
  end

  def test_crop_thumb_with_gravity_center
    t = Bunnycdn::Transformer.new(width: 200, height: 200, crop: :thumb, gravity: :center)
    params = t.to_params

    assert_equal "1:1", params[:aspect_ratio]
    assert_equal "center", params[:crop_gravity]
    assert_equal 200, params[:width]
    refute params.key?(:crop)
  end

  def test_crop_thumb_with_gravity_face
    # face_crop=true keeps the detected faces in frame; aspect_ratio + width
    # then produce the thumbnail. face_crop=W,H would be a pixel cut-out.
    t = Bunnycdn::Transformer.new(width: 600, height: 600, crop: :thumb, gravity: :face)
    params = t.to_params

    assert_equal "true", params[:face_crop]
    assert_equal "1:1", params[:aspect_ratio]
    assert_equal 600, params[:width]
    assert_equal 600, params[:height]
    refute params.key?(:crop)
    refute params.key?(:crop_gravity)
  end

  def test_crop_thumb_with_gravity_faces_alias
    t = Bunnycdn::Transformer.new(width: 300, height: 200, crop: :thumb, gravity: :faces)

    assert_equal "true", t.to_params[:face_crop]
  end

  def test_face_gravity_without_height_still_enables_face_crop
    t = Bunnycdn::Transformer.new(width: 300, crop: :thumb, gravity: :face)
    params = t.to_params

    assert_equal({ width: 300, face_crop: "true" }, params)
  end

  def test_gravity_auto_is_dropped
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :fill, gravity: :auto)

    refute t.to_params.key?(:crop_gravity)
  end

  def test_direct_face_crop_boolean
    assert_equal "face_crop=true", Bunnycdn::Transformer.new(face_crop: true).to_query_string
    assert_equal "", Bunnycdn::Transformer.new(face_crop: false).to_query_string
  end

  def test_direct_face_crop_dimensions
    assert_equal "face_crop=800,1000", Bunnycdn::Transformer.new(face_crop: "800,1000").to_query_string
  end

  # === Quality ===

  def test_quality_auto_uses_default
    t = Bunnycdn::Transformer.new(quality: :auto)
    params = t.to_params

    assert_equal 85, params[:quality]
  end

  def test_quality_auto_is_omitted_without_default
    Bunnycdn.configuration.default_quality = nil

    t = Bunnycdn::Transformer.new(quality: :auto)

    refute t.to_params.key?(:quality)
  end

  def test_quality_explicit
    t = Bunnycdn::Transformer.new(quality: 75)
    params = t.to_params

    assert_equal 75, params[:quality]
  end

  def test_quality_accepts_api_boundaries_as_integers_and_strings
    [0, "0", 100, "100"].each do |quality|
      assert_equal quality.to_i, Bunnycdn::Transformer.new(quality: quality).to_params[:quality]
    end
  end

  def test_quality_auto_preserves_zero_default
    Bunnycdn.configure { |config| config.default_quality = 0 }

    assert_equal "quality=0", Bunnycdn::Transformer.new(quality: :auto).to_query_string
  end

  def test_invalid_quality_is_omitted
    [-1, "-1", 101, "101", "85invalid", "", 85.5, nil, false].each do |quality|
      refute Bunnycdn::Transformer.new(quality: quality).to_params.key?(:quality), quality.inspect
    end
  end

  def test_image_class_maps_to_bunny_class_without_using_css_class
    params = Bunnycdn::Transformer.new(image_class: :thumbnail, class: "rounded", width: 300).to_params

    assert_equal({ width: 300, class: "thumbnail" }, params)
  end

  def test_empty_image_class_is_omitted
    [nil, ""].each do |name|
      assert_empty Bunnycdn::Transformer.new(image_class: name).to_params
    end
  end

  def test_image_class_in_transformation_array
    params = Bunnycdn::Transformer.new(transformation: [{ image_class: :hero }]).to_params

    assert_equal({ class: "hero" }, params)
  end

  def test_image_class_query_encodes_utf8_and_control_characters
    name = "Größe\n\t\"&quality=0#/test"
    query = Bunnycdn::Transformer.new(image_class: name).to_query_string

    assert_equal "class=Gr%C3%B6%C3%9Fe%0A%09%22%26quality%3D0%23%2Ftest", query
  end

  def test_heic_and_heif_are_not_output_formats
    %i[heic heif].each do |format|
      refute Bunnycdn::Transformer.new(format: format).to_params.key?(:format)
    end
  end

  # === Effects ===

  def test_effect_grayscale_maps_to_saturation
    # Bunny has no grayscale parameter — it must desaturate via saturation=-100.
    t = Bunnycdn::Transformer.new(effect: :grayscale)
    params = t.to_params

    assert_equal(-100, params[:saturation])
    refute params.key?(:grayscale)
  end

  def test_effect_sharpen
    t = Bunnycdn::Transformer.new(effect: :sharpen)
    params = t.to_params

    assert_equal "true", params[:sharpen]
  end

  def test_effect_sharpen_with_amount
    t = Bunnycdn::Transformer.new(effect: "sharpen:100")
    params = t.to_params

    assert_equal "true", params[:sharpen]
  end

  def test_effect_blur
    t = Bunnycdn::Transformer.new(effect: "blur:10")
    params = t.to_params

    assert_equal 10, params[:blur]
  end

  def test_effect_sepia
    t = Bunnycdn::Transformer.new(effect: "sepia:75")
    params = t.to_params

    assert_equal 75, params[:sepia]
  end

  def test_direct_bunny_adjustments
    t = Bunnycdn::Transformer.new(
      aspect_ratio: "16:9",
      blur: 4,
      brightness: -10,
      contrast: 15,
      saturation: -25,
      hue: 30,
      gamma: 20,
      tint: "AaFfFf",
      sepia: 60
    )

    assert_equal({
                   aspect_ratio: "16:9",
                   blur: 4,
                   sepia: 60,
                   brightness: -10,
                   contrast: 15,
                   saturation: -25,
                   hue: 30,
                   gamma: 20,
                   tint: "aaffff"
                 }, t.to_params)
  end

  def test_tint_normalizes_optional_hash_prefix
    t = Bunnycdn::Transformer.new(tint: "#ff00aa")

    assert_equal "tint=ff00aa", t.to_query_string
  end

  def test_direct_bunny_boolean_and_rotation_options
    t = Bunnycdn::Transformer.new(
      optimizer: "image",
      sharpen: true,
      flip: true,
      flop: "false",
      rotate: "90",
      upscaling: false,
      focus_crop: "320,180"
    )

    assert_equal({
                   optimizer: "image",
                   focus_crop: "320,180",
                   sharpen: "true",
                   flip: "true",
                   flop: "false",
                   upscaling: "off",
                   rotate: 90
                 }, t.to_params)
  end

  # === upscaling (Bunny: off | resampling) ===

  def test_upscaling_accepts_bunny_modes
    assert_equal "resampling", Bunnycdn::Transformer.new(upscaling: "resampling").to_params[:upscaling]
    assert_equal "off", Bunnycdn::Transformer.new(upscaling: :off).to_params[:upscaling]
  end

  def test_upscaling_true_means_resampling
    assert_equal "resampling", Bunnycdn::Transformer.new(upscaling: true).to_params[:upscaling]
  end

  def test_upscaling_unknown_value_is_dropped
    refute Bunnycdn::Transformer.new(upscaling: "bicubic").to_params.key?(:upscaling)
  end

  # === rotate (90-degree steps only) ===

  def test_rotate_accepts_documented_values
    [-270, -180, -90, 0, 90, 180, 270].each do |deg|
      assert_equal deg, Bunnycdn::Transformer.new(rotate: deg).to_params[:rotate]
    end
  end

  def test_rotate_normalizes_other_right_angles
    assert_equal 0, Bunnycdn::Transformer.new(rotate: 360).to_params[:rotate]
    assert_equal 90, Bunnycdn::Transformer.new(rotate: 450).to_params[:rotate]
  end

  def test_rotate_drops_arbitrary_angles
    refute Bunnycdn::Transformer.new(angle: 45).to_params.key?(:rotate)
  end

  # === Documented value ranges are clamped ===

  def test_integer_params_are_clamped_to_documented_ranges
    t = Bunnycdn::Transformer.new(blur: 500, sepia: -5, hue: 120, brightness: -300, gamma: 101)

    assert_equal({ blur: 100, sepia: 0, hue: 100, brightness: -100, gamma: 100 }, t.to_params)
  end

  def test_effect_blur_is_clamped
    assert_equal 100, Bunnycdn::Transformer.new(effect: "blur:300").to_params[:blur]
  end

  # === aspect_ratio ===

  def test_numeric_aspect_ratio_becomes_ratio_string
    assert_equal "3:2", Bunnycdn::Transformer.new(aspect_ratio: 1.5).to_params[:aspect_ratio]
    assert_equal "1:1", Bunnycdn::Transformer.new(aspect_ratio: 1).to_params[:aspect_ratio]
  end

  def test_non_positive_aspect_ratio_is_dropped
    refute Bunnycdn::Transformer.new(aspect_ratio: 0).to_params.key?(:aspect_ratio)
  end

  def test_cloudinary_angle_maps_to_bunny_rotate
    t = Bunnycdn::Transformer.new(angle: "-90")

    assert_equal(-90, t.to_params[:rotate])
  end

  # === Format ===

  def test_fetch_format_auto_is_ignored
    t = Bunnycdn::Transformer.new(fetch_format: :auto)
    params = t.to_params

    refute params.key?(:format)
  end

  def test_explicit_format
    t = Bunnycdn::Transformer.new(format: :webp)
    params = t.to_params

    assert_equal "webp", params[:format]
  end

  def test_jpg_format_maps_to_bunny_jpeg
    t = Bunnycdn::Transformer.new(format: :jpg)
    params = t.to_params

    assert_equal "jpeg", params[:format]
  end

  def test_default_format_when_configured
    Bunnycdn.configuration.default_format = :webp
    t = Bunnycdn::Transformer.new({})
    params = t.to_params

    assert_equal "webp", params[:format]
  end

  def test_default_jpg_format_maps_to_bunny_jpeg
    Bunnycdn.configuration.default_format = :jpg
    t = Bunnycdn::Transformer.new({})
    params = t.to_params

    assert_equal "jpeg", params[:format]
  end

  # === Transformation arrays (Cloudinary chaining) ===

  def test_transformation_array_flattened
    t = Bunnycdn::Transformer.new(
      transformation: [
        { width: 85, height: 85, gravity: :center, crop: :thumb,
          effect: :grayscale, quality: :auto, dpr: "2.0" },
        { effect: "sharpen:100" }
      ]
    )
    params = t.to_params
    # DPR 2.0 × 85 = 170
    assert_equal 170, params[:width]
    assert_equal 170, params[:height]
    assert_equal "1:1", params[:aspect_ratio]
    assert_equal "center", params[:crop_gravity]
    # sharpen from second transformation overrides grayscale from first
    assert_equal "true", params[:sharpen]
    assert_equal 85, params[:quality]
  end

  # === Query string output ===

  def test_query_string
    t = Bunnycdn::Transformer.new(width: 800, quality: 80)

    assert_equal "width=800&quality=80", t.to_query_string
  end

  def test_query_string_includes_optimizer
    t = Bunnycdn::Transformer.new(width: 800, optimizer: "image", saturation: -100)

    assert_equal "width=800&optimizer=image&saturation=-100", t.to_query_string
  end

  def test_empty_query_string
    t = Bunnycdn::Transformer.new({})

    assert_equal "", t.to_query_string
  end

  # === Real-world CMS patterns ===

  def test_cms_staff_avatar_hero
    t = Bunnycdn::Transformer.new(
      width: 1600, height: 1600,
      gravity: :center, crop: :thumb,
      fetch_format: :auto, quality: :auto,
      effect: :grayscale
    )
    params = t.to_params

    assert_equal 1600, params[:width]
    assert_equal "1:1", params[:aspect_ratio]
    assert_equal "center", params[:crop_gravity]
    assert_equal(-100, params[:saturation])
    refute params.key?(:grayscale)
    assert_equal 85, params[:quality]
  end

  def test_cms_og_image
    t = Bunnycdn::Transformer.new(
      secure: true, fetch_format: :auto, quality: :auto,
      crop: :limit, width: 2000
    )
    params = t.to_params

    assert_equal 2000, params[:width]
    assert_equal 85, params[:quality]
    refute params.key?(:crop) # :limit → proportional → no crop param
  end

  def test_cms_teaser_image
    t = Bunnycdn::Transformer.new(
      width: 680, dpr: "2.0",
      fetch_format: :auto, quality: :auto, crop: :limit
    )
    params = t.to_params

    assert_equal 1360, params[:width] # 680 × 2.0
    assert_equal 85, params[:quality]
  end

  def test_cms_responsive_srcset_variant
    t = Bunnycdn::Transformer.new(
      secure: true, quality: :auto, fetch_format: :auto,
      crop: :limit, width: 1024
    )
    params = t.to_params

    assert_equal 1024, params[:width]
    assert_equal 85, params[:quality]
  end

  # === Unsupported Cloudinary features dropped gracefully ===

  def test_pdf_format_is_dropped
    # Bunny can't rasterize PDFs; format: :pdf must not leak into the query.
    t = Bunnycdn::Transformer.new(format: :pdf)

    refute t.to_params.key?(:format)
  end

  def test_pdf_page_extraction_is_dropped
    t = Bunnycdn::Transformer.new(width: 400, page: "1", fetch_format: :auto, quality: :auto)
    params = t.to_params

    refute params.key?(:page)
    assert_equal 400, params[:width]
  end

  def test_attachment_flags_are_dropped
    t = Bunnycdn::Transformer.new(flags: "attachment:my-book")

    refute t.to_params.key?(:flags)
    assert_equal "", t.to_query_string
  end

  def test_dpr_rounds_instead_of_truncating
    t = Bunnycdn::Transformer.new(width: 681, dpr: "1.5")

    assert_equal 1022, t.to_params[:width] # 1021.5 rounds to 1022, not 1021
  end

  def test_blackwhite_effect_also_desaturates
    t = Bunnycdn::Transformer.new(effect: :blackwhite)

    assert_equal(-100, t.to_params[:saturation])
  end

  # === fetch_format: :auto suppresses default_format ===

  def test_fetch_format_auto_suppresses_default_format
    # :auto must suppress even a configured default_format so the caller's
    # explicit intent (let Bunny auto-negotiate) is respected.
    Bunnycdn.configuration.default_format = :webp
    t = Bunnycdn::Transformer.new(fetch_format: :auto)

    refute t.to_params.key?(:format)
  end

  def test_format_auto_suppresses_default_format
    Bunnycdn.configuration.default_format = :webp
    t = Bunnycdn::Transformer.new(format: :auto)

    refute t.to_params.key?(:format)
  end

  # === Additional crop / gravity coverage ===

  def test_crop_fit_keeps_width_height
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :fit)
    params = t.to_params

    assert_equal 400, params[:width]
    assert_equal 300, params[:height]
    refute params.key?(:crop)
  end

  def test_crop_fill_requires_both_dimensions
    # Without height, :fill falls through to proportional — no crop param.
    t = Bunnycdn::Transformer.new(width: 400, crop: :fill)
    params = t.to_params

    assert_equal 400, params[:width]
    refute params.key?(:crop)
  end

  def test_gravity_north
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :fill, gravity: :north)
    params = t.to_params

    assert_equal "4:3", params[:aspect_ratio]
    assert_equal "north", params[:crop_gravity]
  end

  def test_gravity_north_east
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :fill, gravity: :north_east)
    params = t.to_params

    assert_equal "northeast", params[:crop_gravity]
  end

  def test_gravity_south_west
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :fill, gravity: :south_west)
    params = t.to_params

    assert_equal "southwest", params[:crop_gravity]
  end

  # === Effects: parameterized brightness / contrast / saturation ===

  def test_effect_brightness_with_value
    t = Bunnycdn::Transformer.new(effect: "brightness:-20")

    assert_equal(-20, t.to_params[:brightness])
  end

  def test_effect_brightness_default
    t = Bunnycdn::Transformer.new(effect: "brightness")

    assert_equal 10, t.to_params[:brightness]
  end

  def test_effect_contrast_with_value
    t = Bunnycdn::Transformer.new(effect: "contrast:30")

    assert_equal 30, t.to_params[:contrast]
  end

  def test_effect_saturation_with_value
    t = Bunnycdn::Transformer.new(effect: "saturation:50")

    assert_equal 50, t.to_params[:saturation]
  end

  def test_effect_blur_default
    t = Bunnycdn::Transformer.new(effect: "blur")

    assert_equal 5, t.to_params[:blur]
  end

  def test_effect_sepia_default
    t = Bunnycdn::Transformer.new(effect: "sepia")

    assert_equal 50, t.to_params[:sepia]
  end

  # === Additional format coverage ===

  def test_format_png
    t = Bunnycdn::Transformer.new(format: :png)

    assert_equal "png", t.to_params[:format]
  end

  def test_format_avif
    t = Bunnycdn::Transformer.new(format: :avif)

    assert_equal "avif", t.to_params[:format]
  end

  def test_format_gif
    t = Bunnycdn::Transformer.new(format: :gif)

    assert_equal "gif", t.to_params[:format]
  end

  # === DPR edge cases ===

  def test_dpr_one_is_no_op
    t = Bunnycdn::Transformer.new(width: 400, dpr: "1.0")

    assert_equal 400, t.to_params[:width]
  end

  def test_dpr_less_than_one_is_no_op
    t = Bunnycdn::Transformer.new(width: 400, dpr: "0.5")

    assert_equal 400, t.to_params[:width]
  end

  # === boolean_option edge cases ===

  def test_boolean_option_numeric_one
    t = Bunnycdn::Transformer.new(sharpen: 1)

    assert_equal "true", t.to_params[:sharpen]
  end

  def test_boolean_option_numeric_zero
    t = Bunnycdn::Transformer.new(flop: 0)

    assert_equal "false", t.to_params[:flop]
  end

  def test_boolean_option_string_one
    t = Bunnycdn::Transformer.new(flip: "1")

    assert_equal "true", t.to_params[:flip]
  end

  def test_boolean_option_string_zero
    t = Bunnycdn::Transformer.new(flip: "0")

    assert_equal "false", t.to_params[:flip]
  end

  # === Query value encoding ===

  def test_query_encoding_prevents_ampersand_injection
    t = Bunnycdn::Transformer.new(optimizer: "image&evil=true")
    qs = t.to_query_string

    refute_includes qs, "&evil="
    assert_includes qs, "%26"
  end

  def test_query_encoding_leaves_commas_intact
    t = Bunnycdn::Transformer.new(width: 400, height: 300, crop: :crop)
    qs = t.to_query_string

    assert_includes qs, "crop=400,300"
  end

  def test_query_encoding_leaves_colons_intact
    t = Bunnycdn::Transformer.new(aspect_ratio: "16:9")
    qs = t.to_query_string

    assert_includes qs, "aspect_ratio=16:9"
  end
end
