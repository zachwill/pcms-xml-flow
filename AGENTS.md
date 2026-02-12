# pcms-xml-flow — Agent Handoff (repo root)

This file is a **routing guide**.
Detailed implementation rules live in per-folder `AGENTS.md` files.

---

## First decision: which camp are you in?

Most work in this repo falls into one of these two camps:

### 1) Windmill + database work
You are likely touching one or more of:
- `*.flow/` (ingest/import scripts)
- `migrations/` (SQL schema/functions/warehouses)
- `queries/` (SQL assertions)
- `scripts/test-*-import.py` (local runners)

Start here:
- PCMS XML ingest flow code: `import_pcms_data.flow/` (see `flow.yaml` + inline scripts)
- Local runners + XML→JSON: `scripts/AGENTS.md`
- DB schema/warehouses/primitives: `migrations/AGENTS.md`
- SQL assertions: `queries/AGENTS.md`

### 2) Rails web app work (**most likely scenario**)
If you are working on UI, interactions, controllers/views, Datastar patching, or tool UX:
- **Go directly to `web/AGENTS.md` first.**

That file contains hard rules, response/SSE decision trees, and patch-boundary conventions.

> If unsure, default to **`web/AGENTS.md`**.

---

## Additional lanes

### Sean-style salary-cap / trade tooling
- Mental models + workbook blueprints: `reference/blueprints/README.md`
- High-level doc (data + primitives): `SALARY_BOOK.md`
- Evidence/specs (current workbook): `reference/warehouse/AGENTS.md`
- PCMS mental models (frontend-derived): `reference/pcms/MENTAL_MODELS.md`
- DB primitives + caches: `migrations/AGENTS.md`
- Assertion tests: `queries/AGENTS.md`

### Official NBA API → `nba.*`
- Windmill flow: `import_nba_data.flow/AGENTS.md`
- Schema docs/specs: `nba/AGENTS.md`

### SportRadar → `sr.*`
- Windmill flow: `import_sr_data.flow/AGENTS.md`
- Schema docs/specs: `sr/AGENTS.md`

### React prototype (reference implementation)
- `prototypes/salary-book-react/AGENTS.md`

### Autonomous agent loops (TypeScript)
- `agents/AGENTS.md`

### Archived legacy material
- `archive/AGENTS.md`

---

## Repo-wide conventions

- Prefer `uv run` for Python scripts.
- Most local runners default to **dry-run** (no DB writes) unless you pass `--write`.
- Rails app (`web/`) Ruby is pinned by `web/.ruby-version` (Ruby 3.4.x).
  - On macOS, `/usr/bin/ruby` is often Ruby 2.6 — make sure Ruby 3.4 is first in `PATH` before running `bundle`, `bin/rails`, or `bin/dev`.
  - Homebrew example (includes gem bin dir so `foreman` works):
    - `export PATH="/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"`
- Database connection: `POSTGRES_URL`
- Common API keys:
  - `NBA_API_KEY` (official NBA API)
  - `SPORTRADAR_API_KEY` (SportRadar)

---

## Smoke test / assertions

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/run_all.sql
```

If you don't have access to `psql`, use the `psql.ts` tool instead.

---

## Scratch data (`shared/`)

- `shared/` is a local extract/scratch directory (gitignored).
- Windmill flows use `same_worker: true`, so all steps share `./shared/`.

See: `shared/AGENTS.md`
