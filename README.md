# Bunnycdn Rails

Rails integration for [Bunny CDN](https://bunny.net/cdn/) with on-the-fly image
optimization — designed as a migration path for Rails apps that currently use
Cloudinary for image delivery. It provides a transparent `image_tag` override,
native helpers, and Cloudinary-compatible delivery helpers for migration, all
backed by Bunny Optimizer's Dynamic Images API.

## Why

Bunny.net is an EU-based ([Slovenia](https://bunny.net)) CDN with a flat-rate
image optimizer. This gem provides Ruby/Rails integration so an existing
Cloudinary-based delivery setup can be migrated to Bunny CDN with focused code
changes.

## Features

- **`enhance_image_tag` mode** — transparently intercepts Rails' `image_tag`,
  `image_path` and `image_url` in the spirit of Cloudinary's
  `enhance_image_tag`. Many existing image delivery calls can remain unchanged
  while you migrate.
- **Native helpers** — `bunny_image_tag`, `bunny_upload_url`,
  `bunny_static_url`, `bunny_bg_image_style`, `bunny_upload_path`, and
  `bunny_download_url`.
- **Cloudinary-compatible delivery helpers** — `cl_image_tag`, `cl_image_path`,
  `cl_path`, `cloudinary_url`, `upload_path` for common image-delivery migration
  cases.
- **Two upload strategies** — the default `:active_storage` path works with
  **S3, local Disk, and any ActiveStorage service** (Bunny pull zone over the
  Rails app), while `:mapping` remains available for direct bucket origins and
  now forces `optimizer=image` for image-like upload objects.
- **Common transform mapping** — resize, crop, face-crop, optional quality, DPR,
  grayscale, blur, sharpen, sepia, and simple transformation arrays, translated
  to Bunny's parameters where Bunny has a matching delivery feature.
- **No upload step, no manifest** — Bunny is a pull CDN; there is no
  `.cloudinary.static` equivalent and no `sync_static` rake task.

## Requirements

- Rails 7.0+ (`actionview`, `railties`).
- An asset pipeline that fingerprints assets — **Propshaft or Sprockets**. The
  gem is pipeline-agnostic: it delegates to Rails' own `image_path`, so the
  fingerprint your pipeline already produces is what busts the CDN cache. (This
  is why no static manifest is needed.)

## How it works

Bunny is a transparent **pull** CDN, not an upload target. Nothing is uploaded
ahead of time; Bunny lazily fetches and caches from an origin on first request.

- **Static assets** — point a pull zone at your web server (or set Rails'
  `config.asset_host` to it). `image_tag('logo.png', width: 200)` resolves the
  fingerprinted path through the asset pipeline and rewrites it to
  `https://static.b-cdn.net/assets/logo-<digest>.png?width=200`.
- **User uploads** — point a pull zone at your upload origin. In the default
  `:active_storage` mode the gem CDN-hosts Rails' stable ActiveStorage proxy
  path (including the original filename/extension). In `:mapping` mode it
  builds `https://uploads.b-cdn.net/<blob-key>?width=…` for direct bucket
  origins.
- **Transforms** — appended as query parameters; Bunny Optimizer processes once
  and caches at the edge.

## Installation

```ruby
gem "bunnycdn-rails"
```

## Configuration

Create `config/initializers/bunnycdn.rb`.

For most Rails apps, `uploads_zone_url`, `static_zone_url`,
`enhance_image_tag`, and the default `:active_storage` upload strategy are the
important settings. The `uploads_prefix`, `upload_path_pattern`, and
`append_upload_extension` options are mainly for legacy Cloudinary-style mapping
paths or direct bucket-origin setups.

```ruby
Bunnycdn.configure do |config|
  # Pull zone for user uploads.
  #
  # With the default :active_storage strategy, this pull zone should use your
  # Rails app as its origin. The gem serves ActiveStorage proxy paths through
  # this host, so it works with Disk, S3, R2, GCS, and other ActiveStorage
  # services.
  #
  # With :mapping, this pull zone should use your bucket as its origin.
  config.uploads_zone_url = ENV["BUNNY_UPLOADS_ZONE_URL"]   # https://uploads.b-cdn.net

  # Pull zone for static assets (origin = your web server). Optional:
  # you can also set Rails' config.asset_host to the same URL instead.
  config.static_zone_url = ENV["BUNNY_STATIC_ZONE_URL"]     # https://static.b-cdn.net

  # Intercept image_tag/image_path/image_url and rewrite eligible image sources
  # to Bunny URLs. Set false if you only want to call bunny_* helpers explicitly.
  config.enhance_image_tag = true

  # Optional default quality (1-100). Leave nil to use Bunny's pull-zone
  # quality setting from the dashboard instead of emitting `quality=...`.
  config.default_quality = nil

  # Leave nil to let Bunny Optimizer's global WebP/AVIF setting choose the
  # format (the equivalent of Cloudinary fetch_format: :auto). Default: nil.
  config.default_format = nil

  # :active_storage (default, recommended) or :mapping — see "Upload strategies".
  config.upload_strategy = :active_storage

  # Only needed by upload_path/bunny_upload_path for legacy Cloudinary-style
  # path migration, not by the default ActiveStorage delivery path.
  # config.uploads_prefix = "uploads-production" # example only; pick your own

  # Optional: change how legacy upload strings are detected. The regexp must
  # expose two captures: mapping folder and blob key.
  # config.upload_path_pattern = %r{\A(uploads-[\w-]+)/(.+)\z}

  # Optional for :mapping only: append the ActiveStorage filename extension to
  # blob-key URLs, e.g. "<blob-key>.jpg". Your bucket origin or Bunny Edge Rule
  # must then rewrite that path back to the stored object key.
  # config.append_upload_extension = false
end
```

### Configuration options

| Option | Default | Use when |
|---|---:|---|
| `uploads_zone_url` | `nil` | You want upload/ActiveStorage URLs served through Bunny. Required for production upload CDN delivery. |
| `static_zone_url` | `nil` | You want asset-pipeline images served through Bunny without relying on Rails' `config.asset_host`. |
| `enhance_image_tag` | `false` | You want existing `image_tag`, `image_path`, and `image_url` calls to be rewritten automatically. |
| `upload_strategy` | `:active_storage` | Use `:active_storage` for a Rails-app origin; use `:mapping` only for direct bucket origins. |
| `default_quality` | `nil` | Set a numeric fallback for `quality: :auto`; leave nil to use Bunny dashboard settings. |
| `default_format` | `nil` | Usually leave nil and enable WebP/AVIF in Bunny Optimizer settings. |
| `uploads_prefix` | `nil` | Only for `upload_path`/`bunny_upload_path` and legacy mapping strings like `uploads-production/<key>`. |
| `upload_path_pattern` | `uploads-*` prefix pattern | Only when your legacy mapping strings use a different prefix convention. |
| `append_upload_extension` | `false` | Only for `:mapping` bucket origins that need visible extensions for image optimization. |

### Bunny dashboard setup

1. **Uploads pull zone** — origin = your Rails app for the default
   `:active_storage` strategy, or your bucket only when you explicitly use
   `:mapping`. Enable Bunny Optimizer → Dynamic Image API.
2. **Static pull zone** — origin = your web server.
3. **WebP/AVIF** — enable in Optimizer → Settings (replaces `fetch_format: :auto`).

## Upload strategies

ActiveStorage stores files under a content-addressed `blob.key`. How that maps
to a CDN URL depends on where the file actually lives:

### `:active_storage` (default, recommended)

Point a Bunny pull zone at your Rails app; the gem uses the attachment's stable
ActiveStorage proxy path and CDN-hosts it:

`https://uploads.b-cdn.net/rails/active_storage/blobs/proxy/.../avatar.jpg`

That keeps the original filename/extension in the delivery URL, so Bunny
Optimizer can transform uploads without any custom blob-key handling. Storage
still happens through your normal ActiveStorage service (Disk, S3, GCS, …).

```ruby
config.upload_strategy = :active_storage
```

### `:mapping` — direct bucket origin

Your files sit in a bucket whose objects are addressable as
`https://bucket/<key>`. A Bunny pull zone with that bucket as origin serves
`https://uploads.b-cdn.net/<key>`. This is the direct equivalent of Cloudinary's
auto-upload-mapping (the `uploads-production/` mapping folder pointed at the
bucket). The mapping folder is **not** part of the delivered URL — it only
selects the bucket/zone and is stripped.

When you pass an Active Storage upload object to `image_tag`, `bunny_image_tag`,
`bunny_upload_url`, `cl_image_tag`, or `cl_path`, the gem automatically appends
`optimizer=image` for image-like uploads in `:mapping` mode. That lets Bunny
Optimizer process extensionless blob keys served directly from the bucket.

For legacy raw mapping strings such as `uploads-production/<key>`, the gem has
no metadata to tell images and PDFs apart. In those cases, pass
`optimizer: "image"` explicitly if your origin path has no file extension.

If your origin still needs a visible extension in the path, you can opt into
`config.append_upload_extension = true` and rewrite `<key>.<ext>` back to the
stored object key at the origin / via a Bunny Edge Rule.

## Usage

When the gem is loaded in a Rails app, the Railtie makes the native `bunny_*`
helpers available in views automatically. Include the compatibility module only
when you still need Cloudinary-style `cl_*` helpers during a migration.

### Transparent (recommended) — `enhance_image_tag`

Your existing calls just work and route through Bunny whenever the gem can
resolve them to an upload/static origin:

```erb
<%= image_tag "header.jpg", width: 2560, quality: 80 %>
<%= image_tag user.avatar, width: 200, height: 200, crop: :thumb, gravity: :face %>
<%= image_tag "logo.png", alt: "Brand" %>
```

Opt out per call when you explicitly want Rails' normal behaviour:

```erb
<%= image_tag user.avatar, bunny: false, alt: "Original Active Storage URL" %>
```

### Native helpers

`bunny_image_tag` is the native helper to use in new views. It accepts the same
delivery source types as the Cloudinary compatibility helper:

- ActiveStorage attachments, blobs, variants, or compatible objects responding
  to `attached?`, `key`, or `url`;
- legacy upload path strings matching `upload_path_pattern`, for example
  `uploads-production/abc123`;
- static asset path strings, resolved through Rails' `image_path` when called
  from a view;
- absolute URLs, passed through unchanged.

```ruby
bunny_image_tag(article.header_image, width: 800, alt: "Header")
bunny_image_tag(bunny_upload_path(article.header_image), width: 800, alt: "Header")
bunny_image_tag("images/header.jpg", width: 1600, crop: :limit)
bunny_image_tag("https://example.com/image.jpg", alt: "Remote image")
```

URL-only helpers are more specific:

```ruby
bunny_upload_url(article.og_image, width: 2000, crop: :limit)
bunny_static_url("images/header.jpg", width: 1600)
bunny_bg_image_style("header.jpg", width: 2560)   # => "background-image: url('…')"
bunny_upload_path(article.header_image)           # => "uploads-production/<blob-key>"
```

`bunny_upload_url` expects an upload-like object. In the default
`:active_storage` strategy it returns a Bunny URL over the Rails proxy path, so
no custom upload key naming is needed. In `:mapping` strategy it automatically
adds `optimizer=image` for image-like uploads so Bunny can optimize direct
bucket objects without visible file extensions. `bunny_static_url` expects a
path that Bunny can fetch directly; it does not run Rails' asset pipeline by
itself. In views, prefer `bunny_image_tag` when you want Rails asset-path
resolution plus a rendered `<img>` tag.

`bunny_upload_path` builds the legacy mapping path used by Cloudinary-style
migrations. `bunny_download_url` builds a direct CDN URL for downloadable files
when `uploads_zone_url` is configured; Bunny cannot set a per-request download
filename, so use an Edge Rule or ActiveStorage for forced downloads.

### Cloudinary compatibility (migration aid)

```ruby
# app/helpers/application_helper.rb
module ApplicationHelper
  include Bunnycdn::CloudinaryCompat
end
```

```ruby
cl_image_tag upload_path(article.header_image), width: 800, crop: :limit,
             fetch_format: :auto, quality: :auto, class: "hero"
cl_path upload_path(user.avatar), width: 200, height: 200, crop: :thumb,
        gravity: :face, effect: :grayscale
```

## Transform mapping

| Cloudinary | Bunny | Notes |
|---|---|---|
| `width:` / `height:` | `width` / `height` | scale proportionally |
| `crop: :limit` / `:scale` / `:fit` | width/height only | proportional, no crop param |
| `crop: :fill` / `:thumb` | `crop=W,H` | center-crop to exact size |
| `crop: :thumb, gravity: :face` | `face_crop=W,H` | face detection |
| `gravity: :north…` | `crop_gravity=…` | |
| `quality: :auto` | `quality=<default_quality>` or omitted | uses configured fallback only when set |
| `quality: 75` | `quality=75` | |
| `fetch_format: :auto` | *(omitted)* | enable WebP globally in Optimizer |
| `format: :jpg` | `format=jpeg` | Bunny documents `jpeg` |
| `effect: :grayscale` | `saturation=-100` | **Bunny has no grayscale param** |
| `effect: "blur:10"` | `blur=10` | |
| `effect: :sharpen` | `sharpen=true` | boolean only (intensity ignored) |
| `aspect_ratio:` / `gamma:` / `hue:` / `tint:` | same Bunny params | passed through |
| `flip:` / `flop:` / `rotate:` / `upscaling:` | same Bunny params | normalized |
| `angle: "-90"` | `rotate=-90` | Cloudinary alias |
| `dpr: "2.0"` | *(multiplies width/height)* | |
| `transformation: [...]` | *(flattened/merged)* | |
| `width: "100%"` / `"400px"` | *(HTML attribute)* | display sizes, not CDN resizes |
| absolute URL source | *(passed through)* | external renders, S3 fallbacks |

## Known limitations (Bunny ≠ Cloudinary)

- **No grayscale parameter** → emulated with `saturation=-100` (handled).
- **No `q_auto`** → optional numeric fallback via `default_quality`; otherwise
  leave quality control to Bunny's dashboard settings.
- **No per-request download filename** (`flags: "attachment:name"`) → the flag is
  dropped. Force downloads via a Bunny Edge Rule or
  `rails_blob_url(blob, disposition: "attachment")`.
- **No PDF page rasterization** (`page: N`) → dropped. Bunny cannot turn a PDF
  page into an image; pre-render server-side or render client-side (PDF.js).
- **No chained/overlay transformations** — arrays are flattened into one pass.

## Releasing

Manual release is the default path for now.

1. Pick the next version in `lib/bunnycdn/version.rb`.
2. Update `CHANGELOG.md`.
3. Run the checks:
   ```bash
   bundle exec rake test
   bundle exec rubocop --config .rubocop.yml lib test bunnycdn-rails.gemspec Rakefile
   bundle exec rake build
   ```
4. Sign in to RubyGems:
   ```bash
   gem signin
   ```
5. Push the built gem:
   ```bash
   gem push pkg/bunnycdn-rails-<version>.gem
   ```

If your shell picks the macOS system Ruby by default, prefix the commands with
`mise exec ruby@4.0.4 --`.

`rake release` also works once you are ready for a tag-and-push flow, but it
is not required for the first releases.

## Development

```bash
bin/setup
bundle exec rake test
bundle exec rubocop
```

The transform mapping table and "Known limitations" section above cover the
Cloudinary→Bunny migration details.

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgements

Some helper ergonomics and migration ideas in this gem were inspired by the
[Cloudinary Ruby on Rails SDK](https://github.com/cloudinary/cloudinary_gem),
especially for Rails apps that already use Cloudinary-style image helpers.

Parts of this project were built with AI assistance.

This gem is currently in active development and may change before a stable 1.0
release. It is provided as-is, without any warranty.

This project is independent and is not affiliated with, endorsed by, or
sponsored by Cloudinary, BunnyWay d.o.o., or bunny.net. Product names and
trademarks belong to their respective owners.
