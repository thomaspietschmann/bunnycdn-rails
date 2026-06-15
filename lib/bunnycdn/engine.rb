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
  end
end
