# Changelog

## [Unreleased]

## [0.4.0] - 2026-10-18

### Fixed

- **`crop: :fill` / `:thumb` no longer emit `crop=W,H`.** Bunny's `crop=` is a
  pixel cut-out of the *original* image applied before resizing, so large
  originals produced tiny centre fragments instead of a scaled, filled image.
  These modes now emit `aspect_ratio=W:H` plus `width`/`height`, which is what
  Bunny documents for "crop to ratio, then resize". `gravity: :face`/`:faces`
  emits `face_crop=true` (keep faces in frame) instead of `face_crop=W,H`.
  Existing URLs change, so Bunny will re-process affected images once.
- `upscaling:` now emits Bunny's documented `off` / `resampling` values;
  `true`/`false` are translated accordingly.
- `rotate:` / `angle:` only emit the documented 90° steps (−270…270); other
  right angles are normalised, arbitrary angles are dropped.
- `blur`, `sepia`, `hue` (0–100) and `brightness`, `contrast`, `saturation`,
  `gamma` (−100…100) are clamped to the documented ranges, including values
  given via Cloudinary `effect:` strings such as `"blur:300"`.

### Added

- `crop: :crop` (Cloudinary pixel crop) maps to Bunny `crop=W,H`, with
  `x:`/`y:` producing the positioned form `crop=W,H,X,Y`. Raw Bunny crop
  strings (`crop: "800,600"`, `crop: "800,600,10,20"`) are passed through.
- `crop: :lfill` is accepted as an alias of `:fill`.
- `face_crop:` is accepted directly (`true` or `"W,H"`).
- `gravity: :faces` is recognised alongside `:face`; `gravity: :auto` is dropped.
- Numeric `aspect_ratio:` values (e.g. `1.5`) are converted to Bunny's
  `W:H` syntax (`3:2`).

### Changed

- Refresh development dependencies: Rails 8.1.4, RuboCop 1.92.0,
  rubocop-minitest 0.41.0, SimpleCov 1.3.2. Re-check the Bunny Dynamic Images
  documentation as of October 18, 2026.

## [0.3.0] - 2026-09-11

### Added

- `image_class:` selects Bunny Optimizer Image Classes (`class=...`) across
  native, enhanced Rails, and Cloudinary-compatible helpers, keeping HTML
  `class:` separate. Supports zones requiring forced transformation classes.
- HEIC/HEIF filename recognition for mapping uploads without MIME metadata,
  plus MIME-to-extension fallback when `append_upload_extension` is enabled.
  TGA and PBM filenames are also recognized as supported Optimizer inputs.
- Real ActionView/ERB coverage for image helpers, preset delivery, and HTML
  escaping, alongside regression tests for quality bounds and input formats.

### Fixed

- Accept the documented quality range **0–100**, including `default_quality: 0`.
  Reject malformed or out-of-range per-image values instead of partially parsing
  strings such as `"85invalid"` or emitting `quality=101`.
- `bunny_picture_tag` now returns Rails-safe markup built with Rails tag helpers.
  Source attributes are escaped and the result renders correctly inside ERB.
  Unsupported output formats now raise `ArgumentError` instead of emitting
  misleading MIME types.
- Query values now also percent-encode UTF-8 bytes and control characters while
  preserving Bunny's comma/colon parameter syntax.

### Changed

- Refresh dependencies, including Rails 8.1.3.1, Rack 3.2.7, RuboCop 1.91.0,
  and SimpleCov 1.2.0. Migrate the coverage filter to SimpleCov's `skip` API.
- Review Bunny's official documentation and changelog as of September 11, 2026.
  Document AVIF/HEIC/HEIF general availability, AVIF's 4-megapixel output limit
  and animation restrictions, and relevant S3/CDN/Edge Scripting platform updates.

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
