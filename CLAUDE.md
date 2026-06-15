# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Ruby gem for Bunny CDN image delivery in Rails apps, designed as a migration
path from Cloudinary-style image delivery. It provides transparent `image_tag`
interception, native Bunny helpers, and Cloudinary-compatible helpers — all
backed by the Bunny Optimizer Dynamic Images API.

No HTTP calls at runtime: the gem only builds URLs. Bunny's pull CDN fetches and caches them.

## Commands

```bash
bin/setup                  # install dependencies
bundle exec rake           # default: test + rubocop (run both before committing)
bundle exec rake test      # Minitest only
bundle exec rubocop        # lint only
bin/console                # IRB with gem loaded
```

Run a single test file: `bundle exec ruby test/test_transformer.rb`

## Architecture

```
lib/bunnycdn-rails.rb                 # Bundler auto-require entrypoint (file name must match the gem name)
lib/bunnycdn.rb                       # configuration singleton + require chain
lib/bunnycdn/version.rb               # gem version
lib/bunnycdn/configuration.rb         # validates zone URLs, quality, upload strategy
lib/bunnycdn/transformer.rb           # Cloudinary options → Bunny query params
lib/bunnycdn/url_builder.rb           # assembles full CDN URLs
lib/bunnycdn/support.rb               # shared helpers (URL detection, dimensions, option splitting)
lib/bunnycdn/
  image_helper.rb                     # native helpers: bunny_image_tag, bunny_upload_url, etc.
  view_overrides.rb                   # prepended to ActionView; intercepts image_tag/image_path
  cloudinary_compat.rb                # cl_image_tag, cl_path, cloudinary_url, upload_path
  engine.rb                           # includes helpers + optionally prepends view_overrides
```

### How a URL gets built

1. A view helper (native, Cloudinary-compat, or intercepted `image_tag`) splits options into transform params vs. HTML attributes via `Support.split_options`.
2. `Support.upload_source?` / `upload_path_match` / `absolute_url?` determine the URL type.
3. `Transformer.new(options).to_params` translates Cloudinary-style keys to Bunny query params.
4. `UrlBuilder.upload_url` or `UrlBuilder.static_url` assembles the final URL.

### Upload strategies

**`:active_storage` (default):** Bunny pull zone origin = Rails app. URL = ActiveStorage proxy path (`rails_storage_proxy_path`), which includes the original filename/extension. Works with any storage backend.

**`:mapping`:** Bunny pull zone origin = storage bucket directly. URL = blob key only. The gem automatically adds `optimizer=image` for image-like upload objects. Raw mapping strings do not carry metadata, so callers may need `optimizer: "image"` explicitly when the origin path has no visible extension. Requires bucket as origin; blob keys often lack extensions (use `append_upload_extension` plus an origin/Edge Rule rewrite when needed).

### Non-obvious Cloudinary→Bunny translation

| Cloudinary | Bunny | Gem behavior |
|---|---|---|
| `grayscale` effect | no equivalent | emits `saturation=-100` |
| `quality: :auto` | no `q_auto` | uses `default_quality` if set; otherwise omitted |
| `fetch_format: :auto` | global WebP/AVIF toggle | dropped; enable in Bunny dashboard |
| `page:` (PDF rasterize) | unsupported | dropped silently |
| `flags: "attachment:…"` | unsupported | dropped; use Edge Rules or ActiveStorage |
| chained `transformation: […]` | single-pass only | arrays flattened into one hash |
| `dpr: "2.0"` | no DPR param | multiplied into `width`/`height`, then dropped |

### Configuration validation

`Bunnycdn.configure` → `validate!` enforces:
- Zone URLs must start with `http`
- `default_quality` must be 1–100 or nil
- `upload_strategy` must be `:active_storage` or `:mapping`

### RuboCop style notes

- Double-quoted strings enforced
- ASCII-only comments disabled (allows `→` arrows in mapping tables)
- Most complexity metrics (AbcSize, CyclomaticComplexity, etc.) are disabled

## Testing with a Rails app

The Rails demo app is intentionally kept outside this gem repository. Do not add
`demo_app/` to commits or gem packaging. For integration testing, point an
external Rails app at the local gem with `gem "bunnycdn-rails", path: "../bunny_cdn"`.

## Docs

- `README.md` — full feature guide, transform mapping table, known limitations

Operational/migration docs (runbook, Cloudinary→Bunny migration checklist, cost
estimate) are kept internally (Anytype, innoq project), not in this repository.
