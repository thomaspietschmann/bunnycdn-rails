# frozen_string_literal: true

require "test_helper"
require "action_view"
require "nokogiri"
require "uri"

class TestImageHelper < Minitest::Test
  class View < ActionView::Base
    include Bunnycdn::CloudinaryCompat
    prepend Bunnycdn::ViewOverrides
  end

  Upload = Struct.new(:key, :filename, :content_type)

  def setup
    Bunnycdn.reset_configuration!
    Bunnycdn.configure do |config|
      config.static_zone_url = "https://static.b-cdn.net"
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.upload_strategy = :mapping
      config.enhance_image_tag = true
    end
    @view = View.with_empty_template_cache.empty
  end

  def test_image_class_and_css_class_are_kept_separate_in_all_image_helpers
    %i[bunny_image_tag image_tag cl_image_tag].each do |helper|
      html = @view.public_send(helper, "photo.jpg", image_class: :thumbnail, class: "rounded")
      img = Nokogiri::HTML.fragment(html).at_css("img")

      assert_equal "class=thumbnail", URI(img["src"]).query
      assert_equal "rounded", img["class"]
      refute img.key?("image_class")
    end
  end

  def test_image_class_reaches_upload_and_static_url_helpers
    upload = Upload.new("photo-key", "photo.jpg", "image/jpeg")

    assert_equal "https://uploads.b-cdn.net/photo-key?class=thumbnail&optimizer=image",
                 @view.bunny_upload_url(upload, image_class: :thumbnail)
    assert_equal "https://static.b-cdn.net/photo.jpg?class=hero",
                 @view.bunny_static_url("photo.jpg", image_class: :hero)
  end

  def test_image_class_with_string_key
    html = @view.bunny_image_tag("photo.jpg", "image_class" => "thumbnail", "class" => "rounded")
    img = Nokogiri::HTML.fragment(html).at_css("img")

    assert_equal "class=thumbnail", URI(img["src"]).query
    assert_equal "rounded", img["class"]
  end

  def test_new_input_extensions_force_optimizer_without_content_type
    %w[HEIC heif avif tga pbm].each do |extension|
      upload = Upload.new("photo-key", "photo.#{extension}", nil)

      assert_equal "https://uploads.b-cdn.net/photo-key?width=800&optimizer=image&format=webp",
                   @view.bunny_upload_url(upload, width: 800, format: :webp)
    end
  end

  def test_heic_and_heif_content_types_provide_missing_extensions
    Bunnycdn.configuration.append_upload_extension = true
    %w[heic heif].each do |format|
      upload = Upload.new("photo-key", nil, "image/#{format}")

      assert_equal "https://uploads.b-cdn.net/photo-key.#{format}?optimizer=image",
                   @view.bunny_upload_url(upload)
    end
  end

  def test_explicit_non_image_content_type_does_not_force_optimizer
    upload = Upload.new("file-key", "misleading.heic", "application/pdf")

    assert_equal "https://uploads.b-cdn.net/file-key", @view.bunny_upload_url(upload)
  end

  def test_heic_upload_can_disable_optimizer
    upload = Upload.new("photo-key", "photo.heic", nil)

    assert_equal "https://uploads.b-cdn.net/photo-key", @view.bunny_upload_url(upload, optimizer: nil)
  end

  def test_picture_tag_renders_in_an_erb_template
    html = @view.render(inline: '<%= bunny_picture_tag("photo.jpg", formats: [:avif, :webp], alt: "Photo") %>')
    picture = Nokogiri::HTML.fragment(html).at_css("picture")

    refute_nil picture
    types = picture.css("source").map { |source| source["type"] }

    assert_equal ["image/avif", "image/webp"], types
    assert_equal "Photo", picture.at_css("img")["alt"]
  end

  def test_picture_tag_escapes_attributes_without_double_escaping
    sizes = '100vw" onload="alert(1)'
    html = @view.bunny_picture_tag("photo.jpg", widths: [400, 800], sizes: sizes, quality: 80)
    picture = Nokogiri::HTML.fragment(html).at_css("picture")
    source = picture.at_css("source")

    assert_predicate html, :html_safe?
    assert_equal sizes, source["sizes"]
    refute source.key?("onload")
    assert_includes source["srcset"], "width=400&quality=80&format=webp 400w"
    assert_includes source["srcset"], "width=800&quality=80&format=webp 800w"
  end

  def test_picture_tag_escapes_remote_urls
    url = 'https://example.test/photo.jpg?x=" onerror="alert(1)'
    html = @view.bunny_picture_tag(url)
    source = Nokogiri::HTML.fragment(html).at_css("source")

    assert_equal url, source["srcset"]
    refute source.key?("onerror")
  end

  def test_picture_tag_passes_image_classes_to_all_sources_and_fallback
    html = @view.bunny_picture_tag("photo.jpg", image_class: :hero, widths: [400, 800], class: "rounded")
    picture = Nokogiri::HTML.fragment(html).at_css("picture")

    assert_includes picture.at_css("source")["srcset"], "class=hero"
    assert_includes picture.at_css("img")["src"], "class=hero"
    assert_equal "rounded", picture.at_css("img")["class"]
  end

  def test_picture_tag_rejects_input_only_or_unknown_output_formats
    %i[heic heif svg unknown].each do |format|
      assert_raises(ArgumentError) { @view.bunny_picture_tag("photo.jpg", formats: [format]) }
    end
  end

  def test_picture_tag_returns_empty_for_missing_upload
    assert_empty @view.bunny_picture_tag(nil)
  end
end
