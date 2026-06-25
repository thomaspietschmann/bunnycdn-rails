# frozen_string_literal: true

require "test_helper"

class TestCloudinaryCompat < Minitest::Test
  include Bunnycdn::CloudinaryCompat

  Upload = Struct.new(:key, :filename, :content_type) do
    def attached?
      true
    end
  end

  def setup
    Bunnycdn.reset_configuration!
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.uploads_prefix = "uploads-production"
      config.static_zone_url = "https://static.b-cdn.net"
      config.default_quality = 85
    end
  end

  # Stub image_tag for testing (we don't load Rails here)
  def image_tag(source, **options)
    attrs = options.map { |k, v| "#{k}=\"#{v}\"" }.join(" ")
    attrs.empty? ? "<img src=\"#{source}\" />" : "<img src=\"#{source}\" #{attrs} />"
  end

  def rails_storage_proxy_path(upload, only_path: true)
    raise ArgumentError, "only_path must be true" unless only_path

    "/rails/active_storage/blobs/proxy/#{upload.key}/#{upload.filename}"
  end

  # === cl_path ===

  # The mapping folder (uploads-production/) selects the bucket/zone and is
  # stripped — Bunny serves the blob key from the pull zone root.
  def test_cl_path_upload
    url = cl_path("uploads-production/abc123", width: 800, quality: :auto, crop: :limit)

    assert_equal "https://uploads.b-cdn.net/abc123?width=800&quality=85", url
  end

  def test_cl_path_upload_staging_prefix_is_also_stripped
    url = cl_path("uploads-staging/abc123", width: 800)

    assert_equal "https://uploads.b-cdn.net/abc123?width=800", url
  end

  def test_cl_path_static
    url = cl_path("images/header.jpg", width: 2000, secure: true)

    assert_equal "https://static.b-cdn.net/images/header.jpg?width=2000", url
  end

  def test_cl_path_with_all_cms_options
    url = cl_path("uploads-production/blobkey",
                  secure: true, fetch_format: :auto, quality: :auto,
                  crop: :limit, width: 2000)

    assert_equal "https://uploads.b-cdn.net/blobkey?width=2000&quality=85", url
  end

  # === cl_image_tag ===

  def test_cl_image_tag_generates_img
    html = cl_image_tag("uploads-production/abc123",
                        width: 400, quality: :auto, class: "hero", alt: "Header")

    assert_includes html, "<img src=\"https://uploads.b-cdn.net/abc123?width=400&quality=85\""
    assert_includes html, "class=\"hero\""
    assert_includes html, "alt=\"Header\""
  end

  def test_cl_image_tag_staff_avatar
    html = cl_image_tag("uploads-production/avatar_key",
                        width: 1600, height: 1600,
                        gravity: :center, crop: :thumb,
                        fetch_format: :auto, quality: :auto,
                        effect: :grayscale,
                        class: "avatar__image", loading: "lazy")

    assert_includes html, "saturation=-100" # grayscale → desaturate (Bunny has no grayscale)
    refute_includes html, "grayscale"
    assert_includes html, "crop=1600,1600"
    assert_includes html, "class=\"avatar__image\""
    assert_includes html, "loading=\"lazy\""
  end

  def test_cl_image_tag_accepts_active_storage_source
    Bunnycdn.configure { |config| config.upload_strategy = :active_storage }
    upload = Upload.new("avatar-key", "avatar.jpg", "image/jpeg")

    html = cl_image_tag(upload, width: 400, quality: :auto, class: "avatar")

    assert_includes html,
                    "src=\"https://uploads.b-cdn.net/rails/active_storage/blobs/proxy/avatar-key/avatar.jpg?width=400&quality=85\""
    assert_includes html, "class=\"avatar\""
  end

  def test_cl_path_accepts_active_storage_source_with_default_strategy
    upload = Upload.new("avatar-key", "avatar.jpg", "image/jpeg")

    url = cl_path(upload, saturation: -100)

    assert_equal "https://uploads.b-cdn.net/rails/active_storage/blobs/proxy/avatar-key/avatar.jpg?saturation=-100", url
  end

  def test_cl_path_omits_quality_when_auto_has_no_default
    Bunnycdn.configuration.default_quality = nil

    url = cl_path("uploads-production/abc123", width: 800, quality: :auto)

    assert_equal "https://uploads.b-cdn.net/abc123?width=800", url
  end

  def test_cl_path_accepts_mapping_source_and_forces_optimizer_for_images
    Bunnycdn.configure { |config| config.upload_strategy = :mapping }
    upload = Upload.new("avatar-key", "avatar.jpg", "image/jpeg")

    url = cl_path(upload, saturation: -100)

    assert_equal "https://uploads.b-cdn.net/avatar-key?optimizer=image&saturation=-100", url
  end

  def test_cl_path_appends_extension_for_mapping_source_when_enabled
    Bunnycdn.configure do |config|
      config.upload_strategy = :mapping
      config.append_upload_extension = true
    end
    upload = Struct.new(:key, :filename, :content_type) do
      def attached?
        true
      end
    end.new("avatar-key", "avatar.jpg", "image/jpeg")

    url = cl_path(upload, width: 320)

    assert_equal "https://uploads.b-cdn.net/avatar-key.jpg?width=320&optimizer=image", url
  end

  # === Absolute URLs (BannerBear renders, S3 fallbacks) pass through untouched ===

  def test_cl_path_passes_through_absolute_url
    url = cl_path("https://cdn.bannerbear.com/render/abc.png", width: 400)

    assert_equal "https://cdn.bannerbear.com/render/abc.png", url
  end

  def test_cl_image_tag_passes_through_absolute_url
    html = cl_image_tag("https://example.s3.eu-central-1.amazonaws.com/key.pdf",
                        width: "1600", page: 2, class: "slide")

    assert_includes html, "src=\"https://example.s3.eu-central-1.amazonaws.com/key.pdf\""
    assert_includes html, "class=\"slide\""
  end

  # === Display dimensions become HTML attributes, not CDN resizes ===

  def test_percentage_width_becomes_html_attribute
    html = cl_image_tag("uploads-production/abc123", width: "100%")

    assert_includes html, "width=\"100%\""
    refute_includes html, "?width" # not a CDN transform
  end

  def test_px_height_becomes_unitless_html_attribute
    html = cl_image_tag("uploads-production/abc123", height: "400px")

    assert_includes html, "height=\"400\""
    refute_includes html, "height=400&"
  end

  # === cl_image_path ===

  def test_cl_image_path
    url = cl_image_path("uploads-production/abc123", width: 800, quality: :auto)

    assert_equal "https://uploads.b-cdn.net/abc123?width=800&quality=85", url
  end

  # === cloudinary_url ===

  def test_cloudinary_url_ignores_flags
    url = cloudinary_url("uploads-production/pdf_key", flags: "attachment:my-book")

    assert_equal "https://uploads.b-cdn.net/pdf_key", url
    refute_includes url, "attachment"
    refute_includes url, "flags"
  end

  # === upload_path ===

  def test_upload_path_with_attachment_stub
    upload = Struct.new(:key).new("abc123blob")
    path = upload_path(upload)

    assert_equal "uploads-production/abc123blob", path
  end

  def test_upload_path_with_string
    path = upload_path("raw_key")

    assert_equal "uploads-production/raw_key", path
  end
end
