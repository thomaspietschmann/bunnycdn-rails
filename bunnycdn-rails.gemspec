# frozen_string_literal: true

require_relative "lib/bunnycdn/version"

Gem::Specification.new do |spec|
  spec.name = "bunnycdn-rails"
  spec.version = Bunnycdn::VERSION
  spec.authors = ["Thomas Pietschmann"]
  spec.email = ["thomas.pietschmann@innoq.com"]

  spec.summary = "Rails integration for Bunny CDN image delivery and optimization."
  spec.description = "Bunny CDN integration for Rails apps. Provides image transformation URL helpers, " \
                     "automatic CDN URL generation for ActiveStorage uploads, and Cloudinary-compatible " \
                     "delivery helpers for migration. Supports Bunny Optimizer's Dynamic Images API " \
                     "(resize, crop, format conversion, effects) via simple Ruby helpers."
  spec.homepage = "https://github.com/thomaspietschmann/bunnycdn-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select { |f| File.file?(File.join(__dir__, f)) }.reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ .github/ .idea/ Gemfile .gitignore .rubocop.yml CLAUDE.md .DS_Store])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "actionview", ">= 7.0"
  spec.add_dependency "railties", ">= 7.0"
end
