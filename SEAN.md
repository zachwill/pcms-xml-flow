# SEAN.md — Sean-style Analyst Tooling: Current State + Roadmap

Status: **2026-01-22**

This repo is building **Sean-style tooling outputs** (Salary Book / Playground, Team Master, Trade Machine, Give/Get) on top of the PCMS ingest, with **Postgres as the source of truth**.

> The `reference/sean/` spreadsheets/specs are directional and may be stale. Treat them as *shape + intent*, not authoritative truth.

---

## 0) What exists today (reality check)

### Ingestion flow

The Windmill flow in `import_pcms_data.flow/` is currently **Python-only** (`*.inline_script.py`).

After imports complete, we run a dedicated refresh step:

- `import_pcms_data.flow/refresh_caches.inline_script.py`

which refreshes tool-facing caches in Postgres.

### Tool-facing warehouse/cache tables (canonical artifacts)

#### Player-level: `pcms.salary_book_warehouse`

- one row per active player
- cap/tax/apron grids (2025–2030)
- agent fields, age normalization, option normalization
- some trade-context columns exist for 2025

Refresh:

```sql
SELECT pcms.refresh_salary_book_warehouse();
```

Key migrations:
- `migrations/013_salary_book_warehouse.sql`
- `migrations/016_refresh_salary_book_warehouse_fast.sql`
- `migrations/017_salary_book_age_and_option_normalization.sql`

#### Team-level totals: `pcms.team_salary_warehouse`

- one row per `(team_code, salary_year)`
- totals + subtotals by budget buckets
- joins year constants (`pcms.league_system_values`)
- tax status fields are tool-friendly but preserve missingness via explicit flags and source tracking

Refresh:

```sql
SELECT pcms.refresh_team_salary_warehouse();
```

Key migrations:
- `migrations/019_team_salary_summary.sql`
- `migrations/021_team_salary_summary_tax_status_flags.sql`
- `migrations/022_team_salary_summary_tax_status_fallback.sql`
- `migrations/023_rename_team_salary_summary_to_team_salary_warehouse.sql`

#### Exceptions: `pcms.exceptions_warehouse`

- one row per usable exception instance (`team_exception_id`)
- filtered: `record_status_lk='APPR' AND COALESCE(remaining_amount,0) > 0`
- **important fix:** PCMS `team_exceptions.team_code` is often blank; we derive `team_code` via `team_id → pcms.teams.team_code`
- preserves missingness via:
  - `team_code_source` (raw PCMS value)
  - `has_source_team_code`

Refresh:

```sql
SELECT pcms.refresh_exceptions_warehouse();
```

Key migrations:
- `migrations/020_exceptions_warehouse.sql`
- `migrations/028_fix_exceptions_warehouse_team_code_and_lookups.sql`

#### Team Master drilldowns (fidelity helpers)

- `pcms.dead_money_warehouse` (NBA-only; salary_year>=2025)
  - refresh: `SELECT pcms.refresh_dead_money_warehouse();`
- `pcms.cap_holds_warehouse` (**snapshot-scoped**: filtered to budget snapshot membership)
  - refresh: `SELECT pcms.refresh_cap_holds_warehouse();`

---

## 1) Trade tooling: adapter + primitives + planner (current state)

### Adapter (NOT a warehouse table)

To make trade math sane, we added an adapter view over the wide player warehouse:

- `pcms.salary_book_yearly` (one row per `(player_id, salary_year)` for 2025–2030)

### Primitives

- `pcms.fn_post_trade_apron(team_code, salary_year, outgoing_ids[], incoming_ids[])`
  - delta-method post-trade apron total using `pcms.team_salary_warehouse.apron_total` baseline

- `pcms.fn_tpe_trade_math(...)`
  - CBA Article VII 6(j) TPE logic
  - cap amounts for “Salary” math; apron only for the 6(j)(3) padding gate

### Planner MVP (TPE-only)

- `pcms.fn_trade_plan_tpe(...) -> jsonb`
  - assigns incoming players into existing TREXC exceptions (expiry-first; largest-that-fits)
  - computes remaining main-leg via `fn_tpe_trade_math`
  - returns UI-friendly objects:
    - `absorption_legs[]` (with absorbed totals + counts)
    - `main_leg` (with totals + max/created fields)
    - `summary` (single object suitable for header rendering)

Key migrations:
- `migrations/026_salary_book_yearly.sql`
- `migrations/027_tpe_trade_math.sql`
- `migrations/029_trade_planner_tpe.sql`
- `migrations/030_trade_planner_tpe_output_totals.sql`
- `migrations/031_trade_planner_tpe_ui_fields.sql`
- `migrations/032_trade_planner_tpe_summary.sql`
- `migrations/033_trade_planner_tpe_summary_delta.sql`

---

## 2) What Sean-style tools need (high level)

| Tool | Purpose | Primary inputs |
|------|---------|----------------|
| Salary Book / Playground | team roster view, sorted by salary | `pcms.salary_book_warehouse` |
| Team Master | one-page team cap sheet | `pcms.team_salary_warehouse` + roster (`salary_book_warehouse`) + drilldowns (`dead_money_warehouse`, `cap_holds_warehouse`, `exceptions_warehouse`) |
| Trade Machine | check legality / limits of a trade | `fn_trade_plan_tpe` (MVP) + `fn_tpe_trade_math` primitives + team totals (`team_salary_warehouse`) |
| Give/Get | multi-team sandbox | Trade Machine inputs + exceptions (`exceptions_warehouse`) |

---

## 3) Current gaps / next steps (aligned with TODO.md)

### Next: Trade planner expansion

The current planner is **TPE-only** and single-team-centric.

Next layers:
- multi-team plans (two+ team proposals, still legged)
- aggregation constraints windows (e.g. Dec 15 → deadline “minimum aggregation” constraints)
- MLE-as-vehicle + apron hard-cap restrictions (depends on reliable exception usage state)

### Next: Fidelity / reconciliation artifact

Add one canonical query/view to reconcile:
- `team_salary_warehouse` totals
- vs roster sums from `salary_book_warehouse`
- explained by `team_budget_snapshots.budget_group_lk`

This becomes the debugging hammer for Team Master + trade tooling.

---

## 4) Agent-facing docs / how to validate quickly

- `TODO.md` — current roadmap + invariants
- `AGENTS.md` — ingest context + “what counts” rules
- `SALARY_BOOK.md` — salary book interpretation
- `SCHEMA.md` — DB schema

### SQL checks

The canonical runnable checks live in `queries/sql/`:

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/run_all.sql
```

---

## 5) Important “don’t regress” notes

- Postgres is the source of truth.
- Tool-friendly booleans are OK, but preserve missingness via explicit flags.
- If a drilldown is meant to reconcile to team totals, scope it to `pcms.team_budget_snapshots` membership (detail tables can contain phantom/superset rows).
