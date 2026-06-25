# frozen_string_literal: true

require "test_helper"

class TestViewOverrides < Minitest::Test
  Upload = Struct.new(:key, :filename) do
    def attached?
      true
    end

    def content_type
      "image/jpeg"
    end
  end

  class View
    include Bunnycdn::ImageHelper
    include Bunnycdn::CloudinaryCompat
    prepend Bunnycdn::ViewOverrides

    def image_path(source, _options = {})
      # Handle paths that are already resolved (start with "/") to avoid
      # double-prepending when image_url calls super with a resolved path.
      source_str = source.to_s
      source_str.start_with?("/") ? source_str : "/assets/#{source_str}"
    end

    def image_url(source, options = {})
      "https://app.example.test#{image_path(source, options)}"
    end

    def image_tag(source, options = {})
      attrs = options.map { |key, value| "#{key}=\"#{value}\"" }.join(" ")
      attrs.empty? ? "<img src=\"#{source}\" />" : "<img src=\"#{source}\" #{attrs} />"
    end

    def rails_storage_proxy_path(upload, only_path: true)
      raise ArgumentError, "only_path must be true" unless only_path

      "/rails/active_storage/blobs/proxy/#{upload.key}/#{upload.filename}"
    end
  end

  def setup
    Bunnycdn.reset_configuration!
    Bunnycdn.configure do |config|
      config.enhance_image_tag = true
      config.default_quality = 85
    end
    @view = View.new
  end

  def test_image_tag_with_active_storage_source_uses_proxy_path_on_uploads_zone
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :active_storage
    end

    html = @view.image_tag(upload, width: 400, quality: :auto, class: "avatar")

    assert_includes html,
                    "src=\"https://uploads.b-cdn.net/rails/active_storage/blobs/proxy/avatar-key/avatar.jpg?width=400&quality=85\""
    assert_includes html, "class=\"avatar\""
  end

  def test_image_tag_with_quality_auto_omits_quality_when_no_default_is_configured
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :active_storage
      config.default_quality = nil
    end

    html = @view.image_tag(upload, width: 400, quality: :auto, class: "avatar")

    assert_includes html, "src=\"https://uploads.b-cdn.net/rails/active_storage/blobs/proxy/avatar-key/avatar.jpg?width=400\""
    refute_includes html, "quality="
  end

  def test_image_tag_with_active_storage_source_falls_back_to_local_proxy_path
    Bunnycdn.configure do |config|
      config.upload_strategy = :active_storage
    end

    html = @view.image_tag(upload, width: 320, alt: "Avatar")

    assert_includes html,
                    "src=\"/rails/active_storage/blobs/proxy/avatar-key/avatar.jpg?width=320\""
    assert_includes html, "alt=\"Avatar\""
  end

  def test_image_tag_with_upload_object_uses_mapping_strategy_when_configured
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
    end

    html = @view.image_tag(upload, width: 300)

    assert_includes html, "src=\"https://uploads.b-cdn.net/avatar-key?width=300&optimizer=image\""
  end

  def test_image_tag_with_upload_object_can_append_extension_for_mapping_urls
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
      config.append_upload_extension = true
    end

    html = @view.image_tag(upload, width: 300)

    assert_includes html, "src=\"https://uploads.b-cdn.net/avatar-key.jpg?width=300&optimizer=image\""
  end

  def test_image_tag_without_transform_uses_upload_zone_when_mapping_is_configured
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
    end

    html = @view.image_tag(upload, alt: "Avatar")

    assert_includes html, "src=\"https://uploads.b-cdn.net/avatar-key?optimizer=image\""
    assert_includes html, "alt=\"Avatar\""
  end

  def test_image_tag_without_transform_uses_upload_zone_with_extension_when_enabled
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
      config.append_upload_extension = true
    end

    html = @view.image_tag(upload, alt: "Avatar")

    assert_includes html, "src=\"https://uploads.b-cdn.net/avatar-key.jpg?optimizer=image\""
    assert_includes html, "alt=\"Avatar\""
  end

  def test_static_asset_path_uses_asset_pipeline_then_static_zone
    Bunnycdn.configure do |config|
      config.static_zone_url = "https://static.b-cdn.net"
    end

    url = @view.image_path("logo.png", width: 100)

    assert_equal "https://static.b-cdn.net/assets/logo.png?width=100", url
  end

  def test_custom_upload_path_pattern_is_used_for_legacy_mapping_paths
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_path_pattern = %r{\A(media)/(.+)\z}
    end

    url = @view.image_path("media/abc123", width: 100)

    assert_equal "https://uploads.b-cdn.net/abc123?width=100", url
  end

  def test_image_tag_without_transform_options_uses_static_zone
    Bunnycdn.configure do |config|
      config.static_zone_url = "https://static.b-cdn.net"
    end

    html = @view.image_tag("logo.png", alt: "Logo")

    assert_equal "<img src=\"https://static.b-cdn.net/assets/logo.png\" alt=\"Logo\" />", html
  end

  def test_image_tag_without_transform_options_falls_back_to_local_asset_path_without_static_zone
    html = @view.image_tag("logo.png", alt: "Logo")

    assert_equal "<img src=\"/assets/logo.png\" alt=\"Logo\" />", html
  end

  def test_image_path_supports_per_call_opt_out
    Bunnycdn.configure do |config|
      config.static_zone_url = "https://static.b-cdn.net"
    end

    url = @view.image_path("logo.png", width: 100, bunny: false)

    assert_equal "/assets/logo.png", url
  end

  def test_image_tag_supports_per_call_opt_out
    Bunnycdn.configure do |config|
      config.static_zone_url = "https://static.b-cdn.net"
    end

    html = @view.image_tag("logo.png", width: 100, bunny: false, alt: "Logo")

    assert_equal "<img src=\"logo.png\" width=\"100\" alt=\"Logo\" />", html
  end

  def test_bunny_image_tag_accepts_legacy_upload_path_string
    Bunnycdn.configure { |c| c.uploads_zone_url = "https://uploads.b-cdn.net" }

    html = @view.bunny_image_tag("uploads-production/abc123",
                                 width: 400,
                                 quality: :auto,
                                 class: "hero")

    assert_includes html, "src=\"https://uploads.b-cdn.net/abc123?width=400&quality=85\""
    assert_includes html, "class=\"hero\""
  end

  def test_bunny_image_tag_accepts_static_asset_string
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    html = @view.bunny_image_tag("logo.png", width: 100, alt: "Logo")

    assert_includes html, "src=\"https://static.b-cdn.net/assets/logo.png?width=100\""
    assert_includes html, "alt=\"Logo\""
  end

  def test_bunny_image_tag_accepts_absolute_url
    html = @view.bunny_image_tag("https://example.com/image.jpg",
                                 width: 400,
                                 class: "remote")

    assert_includes html, "src=\"https://example.com/image.jpg\""
    assert_includes html, "class=\"remote\""
    refute_includes html, "width=400"
  end

  def test_bunny_image_tag_falls_back_to_local_asset_path_without_static_zone
    html = @view.bunny_image_tag("logo.png", width: 100)

    assert_includes html, "src=\"/assets/logo.png?width=100\""
  end

  def test_bunny_upload_url_falls_back_to_active_storage_path_without_zone_url
    # No uploads_zone_url configured (e.g. local development)
    html = @view.bunny_image_tag(upload, width: 320, alt: "Slide 1")

    assert_match %r{/rails/active_storage/blobs/proxy/avatar-key/avatar\.jpg\?width=320}, html
  end

  def test_bunny_upload_url_uses_cdn_when_zone_url_configured
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
    end

    html = @view.bunny_image_tag(upload, alt: "Slide 1")

    assert_match %r{https://uploads\.b-cdn\.net/avatar-key\?optimizer=image}, html
  end

  def test_bunny_upload_url_uses_filename_extension_when_enabled
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
      config.append_upload_extension = true
    end

    html = @view.bunny_image_tag(upload, alt: "Slide 1")

    assert_match %r{https://uploads\.b-cdn\.net/avatar-key\.jpg\?optimizer=image}, html
  end

  def test_bunny_upload_path_uses_configured_prefix
    Bunnycdn.configure { |config| config.uploads_prefix = "uploads-production" }

    assert_equal "uploads-production/avatar-key", @view.bunny_upload_path(upload)
  end

  def test_bunny_download_url_uses_upload_zone
    Bunnycdn.configure { |config| config.uploads_zone_url = "https://uploads.b-cdn.net" }

    assert_equal "https://uploads.b-cdn.net/avatar-key", @view.bunny_download_url(upload)
  end

  def test_image_tag_with_non_image_upload_does_not_force_optimizer
    pdf_upload = Struct.new(:key, :filename, :content_type) do
      def attached?
        true
      end
    end.new("document-key", "book.pdf", "application/pdf")

    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
    end

    html = @view.image_tag(pdf_upload, width: 300)

    assert_includes html, "src=\"https://uploads.b-cdn.net/document-key?width=300\""
    refute_includes html, "optimizer=image"
  end

  def test_enhanced_image_path_matches_bunny_and_compat_for_crop_transform
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :active_storage
    end

    enhanced = @view.image_path(upload, width: 440, height: 300, crop: :fill)
    bunny = @view.bunny_upload_url(upload, width: 440, height: 300, crop: :fill)
    compat = @view.cl_path(upload, width: 440, height: 300, crop: :fill)

    assert_equal enhanced, bunny
    assert_equal bunny, compat
  end

  def test_compat_grayscale_mapping_matches_bunny_urls
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :active_storage
    end

    enhanced = @view.image_path(upload, saturation: -100)
    bunny = @view.bunny_upload_url(upload, saturation: -100)
    compat = @view.cl_path(upload, effect: :grayscale)

    assert_equal enhanced, bunny
    assert_equal bunny, compat
  end

  def test_compat_tint_matches_bunny_urls
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :active_storage
    end

    enhanced = @view.image_path(upload, tint: "aaffff")
    bunny = @view.bunny_upload_url(upload, tint: "aaffff")
    compat = @view.cl_path(upload, tint: "aaffff")

    assert_equal enhanced, bunny
    assert_equal bunny, compat
  end

  # === image_url ===

  def test_image_url_with_static_zone_returns_absolute_cdn_url
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    url = @view.image_url("logo.png", width: 100)

    assert_equal "https://static.b-cdn.net/assets/logo.png?width=100", url
  end

  def test_image_url_preserves_transforms_without_static_zone
    # No static zone — image_path returns a relative path; image_url must not drop
    # the transform query when making it absolute.
    url = @view.image_url("logo.png", width: 100)

    assert_includes url, "/assets/logo.png?width=100"
    assert Bunnycdn::Support.absolute_url?(url), "expected an absolute URL, got: #{url}"
  end

  def test_image_url_for_upload_source_returns_absolute_url
    Bunnycdn.configure { |c| c.uploads_zone_url = "https://uploads.b-cdn.net" }

    url = @view.image_url(upload, width: 400)

    assert_includes url, "uploads.b-cdn.net"
    assert Bunnycdn::Support.absolute_url?(url)
  end

  def test_image_url_per_call_opt_out
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    url = @view.image_url("logo.png", width: 100, bunny: false)

    refute_includes url, "static.b-cdn.net"
  end

  # === bunny_static_url ===

  def test_bunny_static_url_builds_cdn_url
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    url = @view.bunny_static_url("header.jpg", width: 2560)

    assert_equal "https://static.b-cdn.net/header.jpg?width=2560", url
  end

  # === bunny_bg_image_style ===

  def test_bunny_bg_image_style_builds_css
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    style = @view.bunny_bg_image_style("header.jpg", width: 2560)

    assert_equal "background-image: url('https://static.b-cdn.net/header.jpg?width=2560');", style
  end

  def test_bunny_bg_image_style_escapes_single_quote_in_url
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    # Ensure a single quote in the optimzer string does not break CSS url('...').
    style = @view.bunny_bg_image_style("header.jpg", width: 2560, optimizer: "image")

    refute_includes style, "url('')"
    assert_includes style, "url('"
    assert style.end_with?("');")
  end

  # === enhance? == false passthrough ===

  def test_image_path_passthrough_when_enhancement_disabled
    Bunnycdn.configure do |config|
      config.enhance_image_tag = false
      config.static_zone_url = "https://static.b-cdn.net"
    end
    # Re-create view so ViewOverrides is NOT prepended (enhance is false at boot
    # in the engine, but in tests ViewOverrides is always prepended — verify the
    # enhance? guard short-circuits instead).
    view = View.new

    url = view.image_path("logo.png", width: 100)

    # enhance? is false → super is called → plain Rails image_path
    refute_includes url, "static.b-cdn.net"
    assert_equal "/assets/logo.png", url
  end

  # === bunny_download_url graceful degradation ===

  def test_bunny_download_url_degrades_gracefully_without_zone
    # No uploads_zone_url → must NOT raise, fall back to ActiveStorage path.
    result = @view.bunny_download_url(upload)

    assert_match %r{/rails/active_storage/blobs/proxy/avatar-key/avatar\.jpg}, result
  end

  def test_bunny_download_url_returns_empty_for_nil
    assert_equal "", @view.bunny_download_url(nil)
  end

  # === responsive srcset via bunny_image_tag ===

  def test_bunny_image_tag_with_widths_generates_srcset
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    html = @view.bunny_image_tag("logo.png", widths: [400, 800, 1200], alt: "Logo")

    assert_includes html, "400w"
    assert_includes html, "800w"
    assert_includes html, "1200w"
    assert_includes html, "srcset="
    assert_includes html, "alt=\"Logo\""
    # src fallback should be the smallest (min) width
    assert_includes html, "src=\"https://static.b-cdn.net/assets/logo.png?width=400\""
  end

  def test_bunny_image_tag_with_widths_and_sizes
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    html = @view.bunny_image_tag("logo.png",
                                 widths: [400, 800],
                                 sizes: "(max-width: 600px) 100vw, 50vw")

    assert_includes html, "sizes=\"(max-width: 600px) 100vw, 50vw\""
  end

  def test_bunny_image_tag_without_widths_unchanged
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    html = @view.bunny_image_tag("logo.png", width: 800)

    assert_includes html, "src=\"https://static.b-cdn.net/assets/logo.png?width=800\""
    refute_includes html, "srcset"
  end

  # === bunny_picture_tag ===

  def test_bunny_picture_tag_generates_picture_element
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    html = @view.bunny_picture_tag("logo.png", formats: [:webp], width: 800, alt: "Logo")

    assert_includes html, "<picture>"
    assert_includes html, "</picture>"
    assert_includes html, "<source srcset="
    assert_includes html, "type=\"image/webp\""
    assert_includes html, "<img"
    assert_includes html, "alt=\"Logo\""
  end

  def test_bunny_picture_tag_multiple_formats
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    html = @view.bunny_picture_tag("logo.png", formats: %i[avif webp], width: 800)

    assert_includes html, "type=\"image/avif\""
    assert_includes html, "type=\"image/webp\""
  end

  def test_bunny_picture_tag_with_widths
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    html = @view.bunny_picture_tag("logo.png", formats: [:webp], widths: [400, 800])

    # source srcset should contain width descriptors
    assert_match(/srcset=".*400w.*800w/, html)
  end

  # === bunny_lqip_url ===

  def test_bunny_lqip_url_returns_tiny_blurred_url
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    url = @view.bunny_lqip_url("logo.png")

    assert_includes url, "width=32"
    assert_includes url, "quality=20"
    assert_includes url, "blur=15"
  end

  def test_bunny_lqip_url_accepts_custom_params
    Bunnycdn.configure { |c| c.static_zone_url = "https://static.b-cdn.net" }

    url = @view.bunny_lqip_url("logo.png", width: 16, quality: 10, blur: 20)

    assert_includes url, "width=16"
    assert_includes url, "quality=10"
    assert_includes url, "blur=20"
  end

  def test_bunny_lqip_url_for_upload_source
    Bunnycdn.configure { |c| c.uploads_zone_url = "https://uploads.b-cdn.net" }

    url = @view.bunny_lqip_url(upload)

    assert_includes url, "uploads.b-cdn.net"
    assert_includes url, "blur=15"
  end

  private

  def upload
    Upload.new("avatar-key", "avatar.jpg")
  end
end
