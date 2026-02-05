# Rails stack + gems (what to steal)

Rolling summary of stack choices observed in:
- `reference/basecamp/fizzy.txt`
- `reference/basecamp/campfire.txt`

Both apps are **Rails 8-era** and track Rails from GitHub `main` (so they’re effectively “edge Rails”). Great for patterns, but we’ll likely pick a stable Rails release for our own app unless we intentionally want edge.

---

## Common “Rails omakase” posture

Both:
- **Hotwire-first UI**
  - Turbo + Stimulus
- **No JS bundler**
  - `importmap-rails`
  - `propshaft`
- Security tooling in CI
  - Brakeman
  - Bundler-audit
  - Importmap audit
- Deployment/runtime leans on:
  - Puma
  - Thruster

---

## Fizzy (OSS + SaaS)

### Gems (from `fizzy.txt` → `Gemfile`)
- Core
  - `rails` (github `rails/rails`, branch `main`)
- Assets/UI
  - `importmap-rails`, `propshaft`, `turbo-rails`, `stimulus-rails`
  - `lexxy` (Basecamp editor)
- DB + realtime + jobs + cache
  - `solid_cable`
  - `solid_cache`
  - `solid_queue`
  - `sqlite3` + `trilogy` (supports both)
- Deployment/runtime
  - `kamal`
  - `thruster`
  - `bootsnap`
- Features
  - `geared_pagination`
  - `web-push`
  - `image_processing`
  - markdown + code highlighting (`redcarpet`, `rouge`)
- Ops
  - `mission_control-jobs`
  - `autotuner`

### SaaS Gemfile additions (from `fizzy.txt` → `Gemfile.saas`)
- Payments + SaaS glue: `stripe`, `activeresource`, `queenbee`, `fizzy-saas`
- Telemetry/metrics:
  - `rails_structured_logging`
  - `sentry-ruby`, `sentry-rails`
  - `yabeda*`

### Config signals worth copying
- `config/puma.rb` runs Solid Queue inside Puma by default (`plugin :solid_queue`) unless disabled.
- Solid Queue config in `config/queue.yml` + recurring schedules in `config/recurring.yml`.

---

## Campfire

### Gems (from `campfire.txt` → `Gemfile`)
- Core
  - `rails` (github `rails/rails`, branch `main`)
- DB + realtime + jobs
  - `sqlite3`
  - `redis` (ActionCable)
  - `resque` + `resque-pool`
- Assets/UI
  - `propshaft` (github `rails/propshaft`)
  - `importmap-rails` (github `rails/importmap-rails`)
  - `turbo-rails` (github `hotwired/turbo-rails`)
  - `stimulus-rails`
  - ActionText/Trix
- Other notable
  - `kredis`
  - `geared_pagination`
  - `web-push`, `rqrcode`, `image_processing`
  - `sentry-ruby`, `sentry-rails`
  - `thruster`

### Config signals worth copying
- `Procfile` + `bin/boot` pattern for a single-container deploy (web + redis + workers).

---

## What this suggests for *our* app

Likely “default stance”:
- Start Hotwire-first with importmap + propshaft.
- Keep the UI server-rendered as long as possible.
- Background jobs:
  - Consider Solid Queue (DB-backed) since we’re already Postgres-first.
  - Redis remains optional (ActionCable scaling, caching, etc).

Hard difference to adapt:
- We are Postgres and already store data in many schemas.
- Our likely DB posture:
  - Read from `pcms.*_warehouse`
  - Write to our own schema (`web.*`)
