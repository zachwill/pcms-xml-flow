# TODO (next steps braindump)

This file is a “what I’d do next” braindump to get from **PCMS ingestion** → **Sean-style tooling** (Salary Book / Playground, Team Master, Trade Machine, Give/Get).

As of 2026-01-22 we already have a working **player-level cache table**:

- `pcms.salary_book_warehouse` (one row per active player; currently ~528)
- `pcms.refresh_salary_book_warehouse()` (view-independent; truncate/insert)

That table already contains:
- cap/tax/apron salary grids (2025–2030)
- % of cap
- age (decimal)
- agent name
- option fields (with `'NONE'` normalized to `NULL`)
- trade flags / best-effort trade-math columns

The next work is mostly about building the **team-level “cap sheet”** and the **trade tooling parameters**.

---

## P0 — Team totals: build `pcms.team_salary_summary` (table + refresh)

### Why
Sean’s tools depend on team totals that are **not** just “sum of player contracts”.
They include budget groups like:
- roster players
- free agent/cap holds
- terminated/dead money
- two-way
- etc.

In our DB, the best source for this is already present:
- `pcms.team_budget_snapshots` (has `cap_amount`, `tax_amount`, `apron_amount`, `budget_group_lk`, `team_code`, `salary_year`)

So the next core artifact should be:

### Proposed table
`pcms.team_salary_summary` (one row per `team_code, salary_year`)

Suggested columns:
- keys: `team_code`, `salary_year`
- totals (all budget groups):
  - `cap_total`, `tax_total`, `apron_total`, `mts_total`
- subtotals by budget_group_lk (at least):
  - `cap_rost`, `cap_fa`, `cap_term`, `cap_2way`
  - `tax_rost`, `tax_fa`, `tax_term`, `tax_2way`
  - `apron_rost`, `apron_fa`, `apron_term`, `apron_2way`
- counts:
  - `roster_row_count`, `fa_row_count`, `term_row_count`, `two_way_row_count`
- year constants (from `pcms.league_system_values`):
  - `salary_cap_amount`, `tax_level_amount`, `tax_apron_amount`, `tax_apron2_amount`, `minimum_team_salary_amount`
  - convenience deltas:
    - `over_cap = cap_total - salary_cap_amount`
    - `room_under_tax = tax_level_amount - tax_total`
    - `room_under_apron1 = tax_apron_amount - apron_total`
    - `room_under_apron2 = tax_apron2_amount - apron_total`
- tax status (from `pcms.tax_team_status`):
  - `is_taxpayer`, `is_repeater_taxpayer`, `is_subject_to_apron`, `apron_level_lk`
- timestamps:
  - `refreshed_at`

### Refresh strategy
Create `pcms.refresh_team_salary_summary()`:
- **source of truth:** aggregate `pcms.team_budget_snapshots`
- join `pcms.league_system_values` on (league_lk='NBA', salary_year)
- join `pcms.tax_team_status` on (team_code, salary_year)

Implementation notes:
- table-first approach like `salary_book_warehouse`: truncate/insert is fine initially
- if lock contention becomes an issue: switch to swap-table refresh pattern

### Indexes
- PK/unique: `(team_code, salary_year)`
- common query patterns:
  - `(salary_year, cap_total desc)`
  - `(salary_year, apron_total desc)`

### Acceptance tests
- row count: 30 teams × each present salary_year (currently budget snapshots cover 2025–2031)
- sanity checks:
  - team totals should be stable and non-null for teams/years that exist
  - top cap totals for 2025 should look plausible

---

## P0 — Exceptions: build `pcms.exceptions_warehouse` (table + refresh)

### Why
Give/Get + Trade Machine need instant lookup of team exceptions (TPE/MLE/BAE/etc).

### Source tables
- `pcms.team_exceptions`
- optional enrich: `pcms.team_exception_usage` (history)

### Proposed table
`pcms.exceptions_warehouse` (one row per exception instance)

Suggested columns:
- keys: `team_exception_id`
- `team_code`, `team_id`, `salary_year`
- `exception_type_lk` (+ optional description via `pcms.lookups`)
- `effective_date`, `expiration_date`
- `original_amount`, `remaining_amount`
- `trade_exception_player_id` (+ player_name join)
- `record_status_lk`
- `refreshed_at`

Filters:
- `record_status_lk` active-ish (confirm which codes are in use)
- `remaining_amount > 0` for “usable” exceptions

Indexes:
- `(team_code, salary_year)`
- `(team_code, remaining_amount desc)`

---

## P1 — Trade matching rules: create `pcms.trade_rules` and (optional) helper function

### Why
Trade Machine needs the CBA “bands” table (Sean hardcodes it in Excel).
We should store it in DB for reuse.

### Inputs / helpers we already have
- `pcms.league_system_values` has max trade cash, etc.
- `pcms.apron_constraints` exists (apron restriction codes); can help future “2nd apron rule” logic.

### Proposed table
`pcms.trade_rules` (seeded for 2024/2025 to start)

Suggested columns:
- `salary_year`
- `rule_type` ('EXPANDED', 'STANDARD')
- `threshold_low`, `threshold_high`
- `multiplier`, `flat_adder`
- `description`

Optional helper:
- `pcms.fn_trade_max_incoming(outgoing bigint, salary_year int, rule_type text)`

---

## P1 — Hook refresh into the ingestion flow

After PCMS import completes, refresh the caches:

- `SELECT pcms.refresh_salary_book_warehouse();`
- `SELECT pcms.refresh_team_salary_summary();` (once created)
- `SELECT pcms.refresh_exceptions_warehouse();` (once created)

This can be:
- a new Windmill step at the end of the flow
- or part of “Finalize” step

---

## P2 — “Team Master” + “Playground” tool queries

Once the two caches exist (players + teams), implement tool-facing queries (or API endpoints):

### Playground / Salary Book
- roster: `salary_book_warehouse where team_code=? order by cap_2025 desc`
- optionally join `pcms.depth_charts` for positions/roles

### Team Master
- header: `team_salary_summary` row for team + year
- roster breakdown: `salary_book_warehouse` roster + subtotals compared to `team_salary_summary`

---

## P2 — Dead money / cap holds alignment (fidelity)

We have multiple sources for “non-player” cap amounts:
- `pcms.team_budget_snapshots` already includes FA/TERM/2WAY groups (recommended for team totals)
- `pcms.transaction_waiver_amounts` exists (dead money detail)
- `pcms.non_contract_amounts` exists (cap holds / non-contract items)

Next steps:
- decide which is the “source of truth” per tool:
  - team totals: `team_budget_snapshots`
  - drill-down detail: waiver amounts and non-contract amounts

---

## P3 — Performance / operational hardening

- swap-table refresh (avoid `TRUNCATE` lock)
- incremental refresh by salary_year (if needed)
- add trigram index for player search if UI needs fuzzy matching:
  - `CREATE EXTENSION IF NOT EXISTS pg_trgm;`
  - `CREATE INDEX ... USING gin (player_name gin_trgm_ops)`

---

## Notes / gotchas to remember

- Team assignment: prefer `contracts.team_code` over `people.team_code`.
- Active player population includes `people.league_lk IN ('NBA','DLG')`.
- `SUM(bigint)` returns `numeric` in Postgres; cast back if you want bigint.
