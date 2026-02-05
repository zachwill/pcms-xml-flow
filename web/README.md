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
bin/rails server
```

Notes:
- Repo convention is `POSTGRES_URL`. Rails convention is `DATABASE_URL`. We support both.
- Rails writes its own tables to `RAILS_APP_SCHEMA` (default: `web`).
  - Override the full search path via `DB_SCHEMA_SEARCH_PATH` if you want to include read-side schemas (ex: `pcms`):
    - `export DB_SCHEMA_SEARCH_PATH="web,pcms,public"`
  - Schema dumping is disabled by default (`schema_dump: false`) to avoid hanging on large warehouse databases; if you enable it, Rails is configured to dump only the Rails schema.
- `web/config/master.key` is ignored (do not commit it).
- Datastar requires CSP `unsafe-eval` (configured in `config/initializers/content_security_policy.rb`).

## Where to look next

- `web/AGENTS.md` (conventions + directory map)
- `web/TODO.md` (active backlog)
- `web/RAILS_TODO.md` (migration memo from React → Rails)
- `web/specs/*` (interaction invariants)
