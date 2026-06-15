# frozen_string_literal: true

require_relative "bunnycdn/version"
require_relative "bunnycdn/configuration"
require_relative "bunnycdn/support"
require_relative "bunnycdn/transformer"
require_relative "bunnycdn/url_builder"

module Bunnycdn
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.validate!
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

require_relative "bunnycdn/image_helper"
require_relative "bunnycdn/view_overrides"
require_relative "bunnycdn/cloudinary_compat"
require_relative "bunnycdn/engine" if defined?(Rails::Railtie)
