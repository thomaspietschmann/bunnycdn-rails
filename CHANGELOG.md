# Changelog

## [Unreleased]

## [0.2.0]

### Added

- **Responsive `srcset`** — `bunny_image_tag` now accepts a `widths: [400, 800, 1200]`
  keyword to emit a `srcset` with per-width descriptor entries. Pair with `sizes:` for
  a complete responsive image. Source fallback `src` uses the smallest width (`widths.min`).
- **`bunny_picture_tag`** — new helper that wraps sources in a `<picture>` element with
  per-format `<source srcset="…" type="…">` entries (e.g. `:avif`, `:webp`) plus a
  fallback `<img>`. Accepts the same `widths:`, `sizes:`, and transform options as
  `bunny_image_tag`.
- **`bunny_lqip_url`** — returns a tiny, heavily blurred placeholder URL for blur-up lazy
  loading (LQIP pattern). Defaults: `width: 32, quality: 20, blur: 15`.
- **`fetch_format: :auto` suppresses `default_format`** — when `:auto` is explicitly
  passed (as `format: :auto` or `fetch_format: :auto`), the configured `default_format`
  is now bypassed so Bunny's global WebP/AVIF setting negotiates the format instead.
- **SimpleCov** with branch coverage wired into the test suite.
- **CI workflow** (`.github/workflows/ci.yml`) — tests on Ruby 3.3, 3.4, 4.0, and head
  (head with allow-failure); RuboCop enforced on 4.0.
- **Dependabot** config for weekly Bundler + GitHub Actions version bumps.
- **`.ruby-version`** set to `3.4` to pin the recommended development Ruby.

### Fixed

- `bunny_download_url` no longer raises `Bunnycdn::Error` when `uploads_zone_url` is
  not configured (e.g. local development). It now falls back gracefully to the plain
  ActiveStorage path, consistent with all other upload helpers.
- `image_url` in the enhanced (`enhance_image_tag: true`) path no longer silently drops
  transform options when no `static_zone_url` is configured. The transform query string
  produced by `image_path` is now preserved when converting the result to an absolute URL.
- `image_url` `bunny: false` opt-out now correctly propagates to the inner `image_path`
  call, so the CDN is bypassed end-to-end.
- Query-string values are now encoded to prevent parameter injection: characters such as
  `&`, `=`, `+`, `#`, `%`, `<`, `>`, `"`, and `'` are percent-encoded. Commas and colons
  (used in valid Bunny values like `crop=400,300` and `aspect_ratio=16:9`) are left intact.
- `bunny_bg_image_style` now escapes single quotes in the URL so they cannot break out of
  the `url('…')` CSS context.
- Zone URL validation (`uploads_zone_url`, `static_zone_url`) now uses a strict
  `%r{\Ahttps?://}` check instead of the too-permissive `start_with?("http")`.
- `upload_path_pattern` is now validated at configure time: must be a `Regexp` with at
  least 2 capture groups, surfacing misconfiguration immediately rather than producing a
  wrong URL silently.
- `delete_prefix` used in `UrlBuilder#build_url` instead of a regex `sub`.

### Changed

- RuboCop plugin configuration migrated to the modern `plugins:` API (lint_roller).
- `rubocop-minitest`, `rubocop-performance`, and `rubocop-rake` added as development
  dependencies; `irb` pinned to `~> 1.13`.
- `minitest` constraint widened from `~> 5.16` to `>= 5.16, < 7` — lockfile now on 6.x.
- Dependency bumps (within existing constraints): rubocop 1.88, nokogiri 1.19.4,
  i18n 1.15.2, concurrent-ruby 1.3.7, zeitwerk 2.8.2, and others.

### Fixed (from [Unreleased] / included in this release)

- Engine boot no longer clobbers app configuration. The `bunnycdn.configure_from_rails`
  initializer unconditionally reset `enhance_image_tag`, `default_quality`, and
  `default_format` to `nil`, overriding values set in the app's own initializer.

### Removed

- **Breaking (undocumented):** the `config.x.bunnycdn` configuration path. Configure the
  gem via `Bunnycdn.configure` in `config/initializers/bunnycdn.rb`, as documented.

## [0.1.0]

- Initial commit
