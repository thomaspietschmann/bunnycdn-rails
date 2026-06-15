# Changelog

## [Unreleased]

### Fixed

- Engine boot no longer clobbers app configuration. The `bunnycdn.configure_from_rails`
  initializer copied values from `config.x.bunnycdn` (an `ActiveSupport::OrderedOptions`,
  whose `respond_to?` is always true and whose unset keys read as `nil`), which
  unconditionally reset `enhance_image_tag`, `default_quality`, and `default_format`
  to `nil` — overriding values set in the app's own initializer.

### Removed

- **Breaking (undocumented):** the `config.x.bunnycdn` configuration path. It was
  never referenced in the README or tests and was the sole source of the boot bug
  above. Configure the gem via `Bunnycdn.configure` in `config/initializers/bunnycdn.rb`
  (gem defaults + explicit overrides), as documented.

## [0.1.0]

- Initial commit
