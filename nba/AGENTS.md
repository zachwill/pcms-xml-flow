# AGENTS.md — NBA (`nba`)

## Purpose

The `nba/` lane covers ingesting **official NBA API** data (`nba/api/nba-*.txt`) plus legacy **NGSS** data (`nba/api/ngss.txt`) when NGSS still has required fields.

Target database schema: `nba`.

## Canonical Sources of Truth

Given recent schema evolution, treat these as canonical:

1. **`import_nba_data.flow/`**
   - What we fetch
   - How we transform payloads
   - Which tables are actively written

2. **`nba/migrations/`**
   - Actual DDL and table shape
   - Constraints/indexes and migration history

`nba/schema/` has been removed and should not be reintroduced as a parallel schema spec source.

## Directory Map

- `nba/api/` — API specs/reference docs for official NBA + NGSS endpoints
  - `nba/api/QUERY_TOOL_NOTES.md` — empirically discovered batching/limits patterns
- `nba/samples/` — example payloads
- `nba/inspiration/` — UI/reporting inspiration
- `nba/migrations/` — SQL migrations for `nba.*` tables

## Working Rules

1. **Flow + migrations must stay aligned**
   - If a script in `import_nba_data.flow/` writes a new column/table, add or update a migration.
   - If a migration changes a table shape, update the corresponding flow writer(s).

2. **Prefer UPSERT-friendly table design**
   - Stable PK/UNIQUE constraints
   - Avoid unnecessary view stacks for core ingest paths

3. **Keep analyst-facing tables practical**
   - Wide tables are acceptable when they simplify downstream querying.
   - Use JSONB where source payloads are volatile/highly nested (especially event streams).

4. **Identity conventions**
   - Teams: `team_id`
   - Players: `nba_id`
   - Games: `game_id` (when provided)
   - NGSS-origin tables: `ngss_*` prefix within `nba` schema

## Operational Notes

- Local runner: `uv run scripts/test-nba-import.py ...`
- Default local mode is dry-run unless `--write` is passed.
- Required env vars are defined in `import_nba_data.flow/AGENTS.md`.

## Related Docs

- `import_nba_data.flow/AGENTS.md` — ingest flow behavior and step-by-step responsibilities
- `nba/migrations/README.md` — migration scope/notes
- `scripts/AGENTS.md` — local runner conventions
