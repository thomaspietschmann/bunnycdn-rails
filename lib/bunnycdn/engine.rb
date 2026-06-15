# frozen_string_literal: true

require "rails/engine"

module Bunnycdn
  class Engine < ::Rails::Engine
    initializer "bunnycdn.view_helpers" do
      ActiveSupport.on_load(:action_view) do
        include Bunnycdn::ImageHelper
      end
    end

    initializer "bunnycdn.view_overrides" do
      ActiveSupport.on_load(:action_view) do
        prepend Bunnycdn::ViewOverrides if Bunnycdn.configuration.enhance_image_tag
      end
    end

    initializer "bunnycdn.configure_from_rails" do |app|
      config = Bunnycdn.configuration

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:bunnycdn)
        bunny = app.config.x.bunnycdn

        config.uploads_zone_url ||= bunny.respond_to?(:uploads_zone_url) ? bunny.uploads_zone_url : nil
        config.uploads_prefix ||= bunny.respond_to?(:uploads_prefix) ? bunny.uploads_prefix : nil
        config.static_zone_url ||= bunny.respond_to?(:static_zone_url) ? bunny.static_zone_url : nil
        config.enhance_image_tag = bunny.enhance_image_tag if bunny.respond_to?(:enhance_image_tag)
        config.default_quality = bunny.default_quality if bunny.respond_to?(:default_quality)
        config.default_format = bunny.default_format if bunny.respond_to?(:default_format)
      end
    end
  end
end
