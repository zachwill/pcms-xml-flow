# web/ — Rails + Datastar

This directory is the **canonical** web app for this repo.

- Backend: Rails
- UI runtime: Datastar (HTML-first morph/patch + signals)
- Data source: Postgres (`pcms.*` warehouses + `pcms.fn_*` primitives)

React prototype (reference only): `prototypes/salary-book-react/`

## Requirements

- Ruby (see `web/.ruby-version`)
- `POSTGRES_URL` pointing at a database that already has the `pcms` schema loaded

### macOS (Homebrew) notes

If you install Ruby via Homebrew on macOS, you likely need Homebrew’s LLVM in
`PATH` when building native gems (Ruby 3.4 expects `stdckdint.h`).

```bash
brew install ruby@3.4 llvm

export PATH="/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"
```

## Setup

```bash
cd web
bundle install

# Rails-owned tables live in a dedicated schema (defaults to `web`).
# Create it once:
psql "$POSTGRES_URL" -c "CREATE SCHEMA IF NOT EXISTS web"

# Optional: use a different schema name (rare; default is `web`)
# export RAILS_APP_SCHEMA=web_dev
# psql "$POSTGRES_URL" -c "CREATE SCHEMA IF NOT EXISTS web_dev"

bin/rails db:migrate

# Starts Rails + Tailwind watcher (recommended)
bin/dev
```

Notes:
- Repo convention is `POSTGRES_URL`. Rails convention is `DATABASE_URL`. We support both.
- Destructive DB reset tasks are intentionally blocked in this app (including `db:seed:replant`, `db:reset`, and `bin/setup --reset`) to protect `web.users`.
- Rails writes its own tables to `RAILS_APP_SCHEMA` (default: `web`).
  - Override the full search path via `DB_SCHEMA_SEARCH_PATH` if you want to include read-side schemas (ex: `pcms`):
    - `export DB_SCHEMA_SEARCH_PATH="web,pcms,public"`
  - Schema dumping is disabled by default (`schema_dump: false`) to avoid hanging on large warehouse databases; if you enable it, Rails is configured to dump only the Rails schema.
- `web/config/master.key` is ignored (do not commit it).
- Datastar requires CSP `unsafe-eval` (configured in `config/initializers/content_security_policy.rb`).

## Authentication + roles

- Authentication is enforced for non-localhost hosts.
  - Requests on `localhost`, `127.0.0.1`, `::1`, and `*.localhost` bypass auth.
- Login routes:
  - `GET /login`
  - `POST /login`
  - `DELETE /logout`
- Roles are stored on `web.users.role` with hierarchy:
  - `viewer` < `front_office` < `admin`
- Session cookie lifetime:
  - Auth sessions use cookie store with `expire_after: 90.days`.
  - Session validity also depends on a stable `SECRET_KEY_BASE` across deploys.
- Admin-only routes (current defaults):
  - `/liveline`
- Bulk user import from CSV:
  - `web/docs/users_csv_import.md`

Create an admin user:

```bash
cd web
WEB_ADMIN_EMAIL="you@example.com" WEB_ADMIN_PASSWORD="change-me" bin/rails db:seed
```

Or in console:

```ruby
User.create!(email: "you@example.com", role: "admin", password: "change-me")
```

To restrict a controller action by role:

```ruby
class SomeController < ApplicationController
  require_role :front_office      # front_office + admin
  # aliases also work: :fo, "front-office"
  # or: require_role :admin, only: :destroy
end
```

## Where to look next

- `web/AGENTS.md` (front door + non-negotiables)
- `web/docs/README.md` (operational playbooks)
- `reference/sites/INTERACTION_MODELS.md` (current interaction thesis)
- `reference/datastar/insights.md` + `reference/datastar/rails.md` (Datastar conventions)
- `prototypes/salary-book-react/docs/legacy-web-specs/*` (archived OG specs)

Backlog is tracked in PRs/issues (we intentionally avoid a `web/TODO.md` file to reduce staleness).
