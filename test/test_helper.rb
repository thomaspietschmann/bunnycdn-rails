# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  skip "/test/"
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "bunnycdn"
require "minitest/autorun"
