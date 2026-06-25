# frozen_string_literal: true

require "test_helper"

class TestSupport < Minitest::Test
  S = Bunnycdn::Support

  def test_absolute_url_detection
    assert S.absolute_url?("https://cdn.bannerbear.com/x.png")
    assert S.absolute_url?("http://example.com/x.png")
    assert S.absolute_url?("//example.com/x.png")
    refute S.absolute_url?("uploads-production/abc123")
    refute S.absolute_url?("images/header.jpg")
    refute S.absolute_url?("/assets/header-abc.jpg")
  end

  def test_transform_dimension
    assert_equal 800, S.transform_dimension(800)
    assert_equal 800, S.transform_dimension("800")
    assert_nil S.transform_dimension("100%")
    assert_nil S.transform_dimension("400px")
    assert_nil S.transform_dimension("auto")
    assert_nil S.transform_dimension(nil)
  end

  def test_html_dimension
    assert_equal "100%", S.html_dimension("100%")
    assert_equal "400", S.html_dimension("400px")
    assert_equal "auto", S.html_dimension("auto")
    assert_nil S.html_dimension(800)
    assert_nil S.html_dimension("800")
  end

  def test_split_options_separates_transforms_html_and_display_dims
    transform, html = S.split_options(
      width: 800, height: "100%", crop: :limit,
      class: "hero", alt: "Photo", loading: "lazy"
    )

    assert_equal({ width: 800, crop: :limit }, transform)
    assert_equal({ height: "100%", class: "hero", alt: "Photo", loading: "lazy" }, html)
  end

  def test_upload_path_match_captures_env_and_key
    Bunnycdn.reset_configuration!
    match = S.upload_path_match("uploads-staging/abc123def")

    assert_equal "uploads-staging", match[1]
    assert_equal "abc123def", match[2]
  end

  def test_upload_path_match_is_nil_for_static_and_absolute
    Bunnycdn.reset_configuration!

    assert_nil S.upload_path_match("images/header.jpg")
    assert_nil S.upload_path_match("https://cdn.example.com/x.png")
  end

  def test_upload_path_pattern_is_configurable
    Bunnycdn.reset_configuration!
    Bunnycdn.configuration.upload_path_pattern = %r{\A(media)/(.+)\z}
    match = S.upload_path_match("media/key123")

    assert_equal "media", match[1]
    assert_equal "key123", match[2]
  ensure
    Bunnycdn.reset_configuration!
  end
end
