# Salary Book / Playground Data Guide

Status: **2026-01-22**

This repo targets **Sean-style tooling powered by Postgres**: fast, indexed, refreshable **warehouse tables** + a small set of **trade-math primitives**.

---

## Canonical source for Salary Book / Playground

### `pcms.salary_book_warehouse` (table)

For almost all “Salary Book / Playground” style queries, use:

- **Table:** `pcms.salary_book_warehouse`
- **Refresh function:** `SELECT pcms.refresh_salary_book_warehouse();`
- **Shape:** wide + **one-row-per-active-player** (UI-friendly)
- **Grids:** cap/tax/apron 2025–2030
- **Normalized fields:**
  - `age` is **decimal years** (see migration `017_salary_book_age_and_option_normalization.sql`)
  - `option_20xx`: `'NONE'` normalized to `NULL`

Example (team roster):

```sql
SELECT player_name, cap_2025, cap_2026, trade_kicker_display, agent_name
FROM pcms.salary_book_warehouse
WHERE team_code = 'BOS'
ORDER BY cap_2025 DESC NULLS LAST;
```

Example (name search):

```sql
SELECT player_name, team_code, cap_2025
FROM pcms.salary_book_warehouse
WHERE lower(player_name) LIKE '%curry%'
ORDER BY cap_2025 DESC NULLS LAST;
```

---

## Trade tooling: adapter view over the Salary Book

### `pcms.salary_book_yearly` (view)

The player warehouse is intentionally wide (columns like `cap_2025`, `cap_2026`, …). For trade math we want a consistent one-row-per-year shape.

Use:

- **View:** `pcms.salary_book_yearly`
- **Shape:** one row per `(player_id, salary_year)`
- **Years:** 2025–2030

Key columns:
- `cap_amount`, `tax_amount`, `apron_amount`
- trade-context columns (best-effort, mostly for 2025 today):
  - `incoming_cap_amount`, `incoming_tax_amount`
  - `incoming_apron_amount`, `outgoing_apron_amount`

Example (yearly amounts for a player):

```sql
SELECT salary_year, team_code, cap_amount, tax_amount, apron_amount
FROM pcms.salary_book_yearly
WHERE player_id = 201939  -- example
ORDER BY salary_year;
```

**Important trade design choice:**
- TPE salary matching uses **cap** amounts.
- Apron values are used only for the CBA 6(j)(3) padding gate.

---

## Trade planner: how Salary Book feeds Trade Machine behavior

The planner and primitives consume `salary_book_yearly`:

- `pcms.fn_post_trade_apron(...)`
- `pcms.fn_tpe_trade_math(...)`
- `pcms.fn_trade_plan_tpe(...)` (TPE-only planner MVP)

`fn_trade_plan_tpe` produces UI-friendly output objects (`absorption_legs`, `main_leg`, `summary`) so client tooling does not have to re-sum salaries.

---

## How “active player” is chosen (warehouse refresh logic)

The refresh function selects **one contract per player** from `pcms.contracts` where:

- `contracts.record_status_lk IN ('APPR','FUTR')`
- prefer `APPR` over `FUTR`, then newest `signing_date`, then newest `contract_id`
- choose latest `contract_versions.version_number` within that contract

Important:
- Team assignment prefers `contracts.team_code` (falls back to `people.team_code`).
- Population includes `people.league_lk IN ('NBA','DLG')` (two-way / G League-linked players are often `DLG`).

---

## Raw model (for debugging / extending the warehouse)

If you need to validate a number or add a new derived column, these are the underlying tables:

```
pcms.contracts (1 per contract)
  └── pcms.contract_versions (1+ per contract, amendments)
        └── pcms.salaries (1 per version per year)
pcms.people (player identity)
pcms.agents (agent identity)
pcms.league_system_values (cap/tax constants by year)
```

### Key salary fields (from `pcms.salaries`)

| Field | Meaning |
|------|---------|
| `contract_cap_salary` | cap hit (Salary Book “cap” grid) |
| `contract_tax_salary` | tax salary |
| `contract_tax_apron_salary` | apron salary |
| `total_salary` | actual paid salary |
| `likely_bonus` / `unlikely_bonus` | incentives |
| `option_lk` | option type (PLYR/TEAM/etc; warehouse normalizes NONE→NULL) |
| `option_decision_lk` | option decision (picked up/declined/pending) |

### Contract / version flags (from `pcms.contract_versions`)

| Field | Meaning |
|------|---------|
| `is_two_way` | two-way contract flag |
| `is_poison_pill` / `poison_pill_amount` | poison pill mechanics |
| `is_no_trade` | no-trade clause |
| `is_trade_bonus` / `trade_bonus_percent` | trade kicker |

---

## Notes on views

There are also “warehouse-ish” views used as scaffolding / debugging:

- `migrations/012_analyst_views.sql` creates:
  - `pcms.vw_active_contract_versions`
  - `pcms.vw_salary_pivot_2024_2030`
  - `pcms.vw_y_warehouse`

The current direction is **table-first** (use `salary_book_warehouse`), so treat views as optional.

---

## Validation / checks

Run the repo’s runnable SQL checks:

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/run_all.sql
```

---

## Related docs

- `TODO.md` — roadmap + invariants
- `SEAN.md` — tool mapping + current state
- `AGENTS.md` — ingestion context + “what counts” rules
- `SCHEMA.md` — schema reference
- `import_pcms_data.flow/contracts.inline_script.py` — how contracts/salaries are imported
- `queries/README.md` — how we structure runnable SQL checks
