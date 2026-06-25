# frozen_string_literal: true

require "test_helper"

class TestUrlBuilder < Minitest::Test
  def setup
    Bunnycdn.reset_configuration!
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.uploads_prefix = "uploads-production"
      config.static_zone_url = "https://static.b-cdn.net"
      config.default_quality = 85
    end
  end

  # === Upload URLs ===

  # The blob key is served from the pull zone root (Bunny pull zone origin = the
  # upload bucket). The Cloudinary mapping folder is NOT part of the URL.
  def test_upload_url_basic
    url = Bunnycdn::UrlBuilder.upload_url("abc123key")

    assert_equal "https://uploads.b-cdn.net/abc123key", url
  end

  def test_upload_url_with_transforms
    url = Bunnycdn::UrlBuilder.upload_url("abc123key", width: 800, quality: 80)

    assert_equal "https://uploads.b-cdn.net/abc123key?width=800&quality=80", url
  end

  def test_upload_url_with_optimizer
    url = Bunnycdn::UrlBuilder.upload_url("abc123key", width: 800, optimizer: "image", saturation: -100)

    assert_equal "https://uploads.b-cdn.net/abc123key?width=800&optimizer=image&saturation=-100", url
  end

  def test_upload_url_ignores_mapping_prefix_config
    Bunnycdn.configuration.uploads_prefix = "uploads-production"
    url = Bunnycdn::UrlBuilder.upload_url("abc123key")

    assert_equal "https://uploads.b-cdn.net/abc123key", url
  end

  def test_upload_url_raises_without_zone
    Bunnycdn.configuration.uploads_zone_url = nil
    assert_raises(Bunnycdn::Error) do
      Bunnycdn::UrlBuilder.upload_url("abc123key")
    end
  end

  # === Static URLs ===

  def test_static_url_basic
    url = Bunnycdn::UrlBuilder.static_url("images/header.jpg")

    assert_equal "https://static.b-cdn.net/images/header.jpg", url
  end

  def test_static_url_with_transforms
    url = Bunnycdn::UrlBuilder.static_url("images/header.jpg", width: 2560, quality: 80)

    assert_equal "https://static.b-cdn.net/images/header.jpg?width=2560&quality=80", url
  end

  def test_static_url_strips_leading_slash
    url = Bunnycdn::UrlBuilder.static_url("/assets/header.jpg")

    assert_equal "https://static.b-cdn.net/assets/header.jpg", url
  end

  def test_static_url_strips_trailing_slash_from_base
    Bunnycdn.configuration.static_zone_url = "https://static.b-cdn.net/"
    url = Bunnycdn::UrlBuilder.static_url("images/header.jpg")

    assert_equal "https://static.b-cdn.net/images/header.jpg", url
  end

  # === Generic build_url ===

  def test_build_url_no_transforms
    url = Bunnycdn::UrlBuilder.build_url("https://cdn.example.com", "file.jpg")

    assert_equal "https://cdn.example.com/file.jpg", url
  end

  def test_build_url_with_transforms
    url = Bunnycdn::UrlBuilder.build_url("https://cdn.example.com", "file.jpg", width: 500)

    assert_equal "https://cdn.example.com/file.jpg?width=500", url
  end

  def test_build_url_ignores_html_attributes
    url = Bunnycdn::UrlBuilder.build_url("https://cdn.example.com", "file.jpg",
                                         width: 500, class: "hero", alt: "Photo")

    assert_equal "https://cdn.example.com/file.jpg?width=500", url
  end

  # === Real-world CMS patterns ===

  def test_cms_og_image_url
    url = Bunnycdn::UrlBuilder.upload_url("blobkey123",
                                          secure: true, fetch_format: :auto, quality: :auto,
                                          crop: :limit, width: 2000)

    assert_equal "https://uploads.b-cdn.net/blobkey123?width=2000&quality=85", url
  end

  def test_cms_avatar_thumb_url
    url = Bunnycdn::UrlBuilder.upload_url("avatar_key",
                                          transformation: [
                                            { width: 85, height: 85, gravity: :center, crop: :thumb,
                                              effect: :grayscale, quality: :auto, dpr: "2.0" },
                                            { effect: "sharpen:100" }
                                          ])
    # 85 × 2.0 = 170, crop thumb + center
    assert_includes url, "crop=170,170"
    assert_includes url, "crop_gravity=center"
    assert_includes url, "sharpen=true"
    assert_includes url, "quality=85"
  end

  def test_cms_bg_image_style_url
    url = Bunnycdn::UrlBuilder.static_url("assets/header-data-and-ai-3b5432cc.jpg",
                                          width: 2560, quality: :auto)

    assert_equal "https://static.b-cdn.net/assets/header-data-and-ai-3b5432cc.jpg?width=2560&quality=85", url
  end
end
