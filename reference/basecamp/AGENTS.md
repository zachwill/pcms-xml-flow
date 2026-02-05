# AGENTS.md — `reference/basecamp/`

This folder contains **text dumps of two large, production Rails codebases** (Basecamp/37signals) used as **reference material** while we design/build a Rails site for this repo.

These are not meant to be runnable here — treat them as a searchable “Rails patterns library” for:

- Rails 8-era defaults (Hotwire, importmap, propshaft)
- Controller/model organization in real production apps
- Authentication/session patterns (`Current`)
- Background jobs + realtime + caching (Solid* vs Redis/Resque)
- Deploy/CI/security conventions

## What’s in here

- `fizzy.txt` — full codebase dump
- `campfire.txt` — full codebase dump

Both dumps follow the same structure:

1) A **Directory Structure** tree
2) Repeated blocks:

```text
================
File: path/to/file.rb
================
...contents...
```

## How to navigate these dumps

Use ripgrep to jump to a file’s block header, then open the dump near that line number.

```bash
rg -n "^File: config/routes\\.rb$" reference/basecamp/fizzy.txt
rg -n "^File: app/controllers/concerns/authentication\\.rb$" reference/basecamp/campfire.txt
```

(In pi, open using `read` with an `offset` around the returned line number.)

## Curated extracted notes

We keep small, repo-relevant notes under:

- `reference/basecamp/specs/`

Start here:
- `reference/basecamp/specs/00-index.md`

## High-signal observations (so far)

### Shared Rails stack
- Both track **Rails from GitHub `main`**.
- Both are Hotwire-first and avoid JS bundlers:
  - `importmap-rails`
  - `propshaft`
  - `turbo-rails`
  - `stimulus-rails`
- Both treat security + audits as first-class CI steps.

### Fizzy
- Rails defaults: `config.load_defaults 8.1`.
- Multi-tenant capable:
  - tenant prefix handled via Rack `SCRIPT_NAME` rewriting (`AccountSlug` middleware)
  - many components are made script-name aware (Turbo streams, ActionCable, mailers).
- Auth is identity-first + passwordless:
  - `Identity` + `MagicLink` codes
  - signed cookie sessions
  - optional Bearer token auth for API access tokens.
- Uses DB-backed Rails primitives:
  - `solid_queue`, `solid_cache`, `solid_cable`
  - recurring schedules via `config/recurring.yml`
- Deployment:
  - `kamal` + `thruster`
- Strong “Rails extensions” posture:
  - `lib/rails_ext/*` loaded via initializer (explicit patch library)
  - covers: replica helpers, UUIDv7 type (MySQL/SQLite), ActiveStorage authorization + direct-upload expiry tweaks, ActionMailer job SMTP retry/ignore rules, etc.
  - See: `reference/basecamp/specs/09-rails-ext-inventory.md`
- Hotwire polish:
  - `turbo_refreshes_with method: :morph, scroll: :preserve`
  - View Transitions meta tag is conditional (`ViewTransitions` disables it on refresh)
  - `stale_when_importmap_changes` in `ApplicationController` (importmap cache busting)
  - See: `reference/basecamp/specs/06-ui-hotwire-patterns.md`

### Campfire
- Rails defaults: `config.load_defaults 8.2`.
- Auth is simple + practical:
  - email/password (`has_secure_password`)
  - cookie session tokens (`has_secure_token`)
  - optional bot auth via `bot_key`.
- Uses:
  - SQLite primary DB
  - Redis for ActionCable
  - Resque for jobs
- Shipping/realtime UI patterns:
  - Turbo Streams broadcasts with `maintain_scroll` support via a Stimulus controller.
- Single-container deploy pattern:
  - `Procfile` + `bin/boot` process monitor.

## How this applies to *our* Rails app in this repo

Current reality (Feb 2026):

- The canonical Rails + Datastar app lives in `web/`.
- Postgres remains the source of truth.
- Treat `pcms.*_warehouse` tables as the stable read API.
- Rails owns a separate schema (**`web`**) for write-side concerns:
  - slug registry + aliases
  - saved views/preferences
  - annotations/notes, scenarios/trade artifacts
  - auth/session tables (if/when we need them)

So:
- `pcms` schema: imported + derived warehouse data (read side)
- `web` schema: Rails-owned tables (write side)
