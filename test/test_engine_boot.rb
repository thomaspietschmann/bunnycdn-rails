# frozen_string_literal: true

require "test_helper"
require "rails"
require "active_support/ordered_options"
require "action_view/railtie"
require "action_view/base"
require "bunnycdn/engine"

# Regression test for the engine-boot config-clobbering bug.
#
# A former `bunnycdn.configure_from_rails` engine initializer copied values from
# `config.x.bunnycdn` (an ActiveSupport::OrderedOptions) into the gem config:
#
#   config.enhance_image_tag = bunny.enhance_image_tag if bunny.respond_to?(:enhance_image_tag)
#
# OrderedOptions#respond_to? is always true (via respond_to_missing?) and unset
# keys read as nil, so the `respond_to?` guards never protected anything — the
# assignments unconditionally reset enhance_image_tag/default_quality/default_format
# to nil, clobbering whatever the app had set in its own initializer. The fix
# removed that initializer entirely; configuration now flows only through gem
# defaults + `Bunnycdn.configure`. These tests guard against reintroduction.
class TestEngineBoot < Minitest::Test
  def setup
    Bunnycdn.reset_configuration!
  end

  def teardown
    Bunnycdn.reset_configuration!
  end

  def test_engine_boot_does_not_clobber_app_configuration
    Bunnycdn.configure do |config|
      config.enhance_image_tag = true
      config.default_quality = 85
      config.default_format = "webp"
    end

    run_bunnycdn_engine_initializers

    assert Bunnycdn.configuration.enhance_image_tag,
           "engine boot must not reset app-configured enhance_image_tag"
    assert_equal 85, Bunnycdn.configuration.default_quality
    assert_equal "webp", Bunnycdn.configuration.default_format
  end

  def test_engine_defines_no_configure_from_rails_initializer
    names = Bunnycdn::Engine.initializers.map { |init| init.name.to_s }

    refute_includes names, "bunnycdn.configure_from_rails",
                    "the config.x.bunnycdn copy path was the sole bug source; do not reintroduce it"
  end

  def test_view_overrides_prepended_when_enhance_image_tag_enabled
    Bunnycdn.configure { |config| config.enhance_image_tag = true }

    run_bunnycdn_engine_initializers

    assert_includes ActionView::Base.ancestors, Bunnycdn::ViewOverrides
  end

  private

  # Runs the gem's own engine initializers against an app double whose
  # `config.x.bunnycdn` is an empty OrderedOptions — exactly the boot condition
  # that triggered the original clobber.
  def run_bunnycdn_engine_initializers
    app = Struct.new(:config).new(
      Struct.new(:x).new(
        Struct.new(:bunnycdn).new(ActiveSupport::OrderedOptions.new)
      )
    )

    Bunnycdn::Engine.initializers
                    .select { |init| init.name.to_s.start_with?("bunnycdn.") }
                    .each { |init| init.run(app) }
  end
end
