# frozen_string_literal: true

require "test_helper"

class TestBunnycdnRails < Minitest::Test
  def setup
    Bunnycdn.reset_configuration!
  end

  def test_that_it_has_a_version_number
    refute_nil ::Bunnycdn::VERSION
  end

  def test_configure_block
    Bunnycdn.configure do |config|
      config.uploads_zone_url = "https://uploads.b-cdn.net"
      config.uploads_prefix = "uploads-production"
      config.static_zone_url = "https://static.b-cdn.net"
      config.default_quality = 80
    end

    assert_equal "https://uploads.b-cdn.net", Bunnycdn.configuration.uploads_zone_url
    assert_equal "uploads-production", Bunnycdn.configuration.uploads_prefix
    assert_equal "https://static.b-cdn.net", Bunnycdn.configuration.static_zone_url
    assert_equal 80, Bunnycdn.configuration.default_quality
  end

  def test_validates_urls
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure do |config|
        config.uploads_zone_url = "not-a-url"
      end
    end
  end

  def test_upload_strategy_defaults_to_active_storage
    assert_predicate Bunnycdn.configuration, :active_storage_uploads?
    assert_equal :active_storage, Bunnycdn.configuration.upload_strategy
  end

  def test_default_quality_is_optional
    assert_nil Bunnycdn.configuration.default_quality
  end

  def test_active_storage_strategy
    Bunnycdn.configure { |c| c.upload_strategy = :active_storage }

    assert_predicate Bunnycdn.configuration, :active_storage_uploads?
  end

  def test_validates_upload_strategy
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.upload_strategy = :nonsense }
    end
  end

  def test_validates_default_quality
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.default_quality = 0 }
    end
  end

  def test_validates_default_quality_upper_bound
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.default_quality = 101 }
    end
  end

  def test_validates_default_quality_must_be_integer
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.default_quality = 85.5 }
    end
  end

  def test_validates_static_zone_url
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.static_zone_url = "not-a-url" }
    end
  end

  def test_url_validation_rejects_http_prefix_lookalikes
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.uploads_zone_url = "httpfoo://bad" }
    end
  end

  def test_validates_upload_path_pattern_must_be_regexp
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.upload_path_pattern = "not-a-regexp" }
    end
  end

  def test_validates_upload_path_pattern_requires_two_captures
    assert_raises(Bunnycdn::Error) do
      Bunnycdn.configure { |c| c.upload_path_pattern = /\A(.+)\z/ }
    end
  end

  def test_valid_upload_path_pattern_with_two_captures
    Bunnycdn.configure { |c| c.upload_path_pattern = %r{\A(media)/(.+)\z} }

    assert_equal %r{\A(media)/(.+)\z}, Bunnycdn.configuration.upload_path_pattern
  end

  def test_default_quality_boundary_values_are_valid
    Bunnycdn.configure { |c| c.default_quality = 1 }

    assert_equal 1, Bunnycdn.configuration.default_quality

    Bunnycdn.configure { |c| c.default_quality = 100 }

    assert_equal 100, Bunnycdn.configuration.default_quality
  end
end
