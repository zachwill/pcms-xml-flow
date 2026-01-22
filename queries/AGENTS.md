Status: 2026-01-22

This is a **handoff doc for coding agents** working in `queries/`.

The mission: reproduce Sean’s spreadsheet-driven tooling (Salary Book / Playground, Trade Machine, Give/Get, Team Master, Depth Chart) using the `pcms` Postgres schema.

A key direction we’ve converged on:

- Use **a denormalized “salary book” table** that can be refreshed daily (truncate/insert) and indexed heavily.
- Views and ad-hoc SQL are fine for iteration, but the table is the primary artifact for powering the tools.

---

## Read first

- `SEAN.md` – analyst requirements + gaps
- `SALARY_BOOK.md` – how to reason about contracts/versions/salaries
- `SCHEMA.md` – schema reference
- `reference/sean/specs/*` – spreadsheet output specs

---

## Reality check: database is populated

Using `psql "$POSTGRES_URL"` we verified the DB already has meaningful ingestion.

Key row counts (approx):

- `pcms.people`: ~14k
- `pcms.contracts`: ~8k
- `pcms.contract_versions`: ~10k
- `pcms.salaries`: ~22k
- `pcms.team_transactions`: ~80k
- `pcms.team_exceptions`: ~1.5k
- `pcms.league_system_values`: ~112

“Active players” definition (best-effort, used throughout):

- choose a single contract per player from `pcms.contracts` where `record_status_lk IN ('APPR','FUTR')`
- prefer APPR over FUTR, then newest signing date
- choose latest `contract_versions.version_number` for that contract

This yields ~528 “active players”.

---

## Current state: what we built

### A) The thing that matters: `pcms.salary_book_warehouse` (table)

We created a denormalized cache table designed to power Salary Book / Playground style queries.

- **Table:** `pcms.salary_book_warehouse`
- **Refresh function:** `pcms.refresh_salary_book_warehouse()`
- **Population:** 1 row per active player (currently ~528)
- **Columns:** player identity, team assignment, agent, age, cap salaries (2025–2030), pct-of-cap, options, trade flags, tax/apron, best-effort trade-math columns.
- **Indexes:** team filters + sorting by salary + name search.

Migrations:

- `migrations/013_salary_book_warehouse.sql`
  - creates `pcms.salary_book_warehouse`
  - creates several indexes
  - originally created a refresh function that depended on views
- `migrations/016_refresh_salary_book_warehouse_fast.sql`
  - replaces `pcms.refresh_salary_book_warehouse()` with a **view-independent** implementation
  - computes everything via CTEs (contracts+versions selector + salary pivot + cap constants)
  - sets `statement_timeout=0` inside the function and `lock_timeout=5s`

Why the view-independent refresh matters:

- A prior refresh attempt timed out because it depended on views in a way that caused expensive logic to be inlined twice.
- The current refresh function avoids that entirely.

### B) Helpful, but optional: views / runnable SQL

These exist as scaffolding and for debugging. They are not required if we are table-first.

- `queries/sql/y_warehouse.sql` – runnable CTE query (forward-looking 2025–2030)
- `migrations/012_analyst_views.sql` – created some convenience views:
  - `pcms.vw_active_contract_versions`
  - `pcms.vw_salary_pivot_2024_2030`
  - `pcms.vw_y_warehouse`

If the project direction continues to be table-first, we can treat these views as disposable.

---

## Important gotchas

### 1) Team assignment

Do **not** rely on `pcms.people.team_code` as the primary team source.
In the current DB it’s often blank for many players.

Preferred team source for “roster” exports:

1) `pcms.contracts.team_code` (from the chosen active contract)
2) fallback: `pcms.people.team_code`

Expose both fields in outputs where helpful.

### 2) “Active players” span NBA + DLG in `pcms.people`

Even for NBA-facing tools, many two-way / G League-linked players show up as:

- `pcms.people.league_lk = 'DLG'`

But they still have APPR/FUTR contracts.

If you filter `people.league_lk = 'NBA'` you will undercount (~485).
To match the expected population (~528), use:

- `people.league_lk IN ('NBA','DLG')`

The salary book refresh uses this.

---

## How to run / test

### Refresh the salary book table

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -c "SELECT pcms.refresh_salary_book_warehouse();"
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) FROM pcms.salary_book_warehouse;"  -- expect 528
```

### Salary Book style query examples

Roster for a team sorted by 2025 cap:

```sql
SELECT player_name, cap_2025, cap_2026, trade_kicker_display, agent_name
FROM pcms.salary_book_warehouse
WHERE team_code = 'BOS'
ORDER BY cap_2025 DESC NULLS LAST;
```

Search by name:

```sql
SELECT player_name, team_code, cap_2025
FROM pcms.salary_book_warehouse
WHERE lower(player_name) LIKE '%curry%'
ORDER BY cap_2025 DESC NULLS LAST;
```

---

## What to do next

1) Decide the Salary Book table contract:
   - what years do we want (currently 2025–2030)
   - do we also want a current-year view (2024–2029) for trade tools
   - confirm any additional columns Sean expects (positions, roster status, depth chart, etc.)

2) Build trade tooling inputs off the table (table-first approach):
   - create `pcms.trade_rules` (seed matching bands)
   - create `pcms.expections_warehouse` table or view (team exceptions lookup)

3) Locking/perf improvements if needed:
   - `TRUNCATE` takes an ACCESS EXCLUSIVE lock; if that becomes painful,
     switch to a “swap table” refresh pattern (build new table, then rename).

4) Validate output fidelity vs Sean’s sheet:
   - spot-check a few star players
   - team rosters
   - option display/decisions
   - trade kicker presence
