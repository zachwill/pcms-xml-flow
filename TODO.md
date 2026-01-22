# TODO (next steps)

This file is the “new agent briefing” checklist to go from **PCMS ingestion** → **tooling outputs** (Salary Book / Team Master / Trade Machine / Give-Get) with **Postgres as source of truth**.

As of **2026-01-22**, we are in the **warehouse + rules primitives** phase.

---

## Ground rules / invariants (do not regress)

1) **Postgres is the source of truth**
- Prefer querying `pcms.*` tables over relying on local JSON extracts.

2) **“What counts” for team totals is `pcms.team_budget_snapshots`**
- Detail tables (`non_contract_amounts`, `transaction_waiver_amounts`, etc.) can contain superset/phantom rows.
- Therefore: drilldowns/warehouses MUST be scoped to snapshot membership if they’re meant to reconcile with Team Master totals.

3) **Tool-friendly booleans are OK, but don’t hide missingness**
- Coalesce booleans to `false` for stable outputs, but add `has_*` flags / `*_id` fields to preserve “missing vs false”.

---

## ✅ Current tool-facing warehouse/cache tables (already implemented)

Player-level:
- `pcms.salary_book_warehouse`
  - one row per active player
  - wide grids (2025–2030): cap/tax/apron
  - % cap, age, agent fields, option normalization
  - some trade-context columns exist for 2025 (e.g. `incoming_apron_2025`, `outgoing_buildup_2025`)
- refresh: `SELECT pcms.refresh_salary_book_warehouse();`

Team-level totals:
- `pcms.team_salary_warehouse`
  - one row per `team_code, salary_year`
  - totals + budget group buckets (ROST / FA+QO+DRFPK+PR10D / TERM / 2WAY)
  - joins year constants from `pcms.league_system_values`
  - tax flags with explicit source/missingness tracking
- refresh: `SELECT pcms.refresh_team_salary_warehouse();`

Exceptions:
- `pcms.exceptions_warehouse`
  - one row per usable exception instance (`team_exception_id`)
  - filtered: `record_status_lk='APPR'` and `COALESCE(remaining_amount,0) > 0`
- refresh: `SELECT pcms.refresh_exceptions_warehouse();`

Detail drilldowns (Team Master fidelity):
- `pcms.dead_money_warehouse` (from waiver amounts; resolves team_code via `pcms.teams`; NBA-only; salary_year>=2025)
  - refresh: `SELECT pcms.refresh_dead_money_warehouse();`
- `pcms.cap_holds_warehouse` (from non-contract amounts, but **filtered to snapshot FA buckets**)
  - refresh: `SELECT pcms.refresh_cap_holds_warehouse();`

Flow integration:
- Windmill step refreshes caches post-import: `import_pcms_data.flow/refresh_caches.inline_script.py`

---

## ✅ Trade tooling “adapter” layer (NOT a warehouse table)

These are helper objects to make trade math sane.

- **View:** `pcms.salary_book_yearly` (migration `026_salary_book_yearly.sql`)
  - unpivots `salary_book_warehouse` into one row per `(player_id, salary_year)` for 2025–2030
  - includes `cap_amount`, `tax_amount`, `apron_amount`
  - includes best-effort trade-context fields:
    - `outgoing_apron_amount`, `incoming_apron_amount`
    - `incoming_cap_amount`, `incoming_tax_amount`

- **Function:** `pcms.fn_post_trade_apron(team_code, salary_year, outgoing_player_ids[], incoming_player_ids[])`
  - computes:
    - baseline team apron total from `pcms.team_salary_warehouse.apron_total`
    - outgoing sum from `salary_book_yearly.outgoing_apron_amount` (filtered to `team_code`)
    - incoming sum from `salary_book_yearly.incoming_apron_amount`
    - `post_trade_apron_total = baseline - outgoing + incoming`
  - returns diagnostic counts + `has_team_salary`

---

## ✅ TPE (Traded Player Exception) rule primitive (CBA Article VII 6(j))

We are modeling the **2023 CBA** language from `cba/original/07 BRI.md` Section **6(j)**.

- **Function:** `pcms.fn_tpe_trade_math(...)` (migration `027_tpe_trade_math.sql`)
  - Computes:
    - outgoing “pre-trade Salary” total (cap-based)
    - incoming “post-assignment Salary” total (cap-based)
    - post-trade apron totals (apron-based) via `fn_post_trade_apron`
    - applies 6(j)(3) apron gate (padding goes to $0 if post-trade apron > First Apron)
    - returns `max_replacement_salary` and `created_exception_amount`
  - Supported `tpe_type` values:
    - `standard` (100% + padding)
    - `aggregated_standard` (100% + padding)
    - `expanded` (max of 125%+padding vs min(200%+padding, 100%+tpe_dollar_allowance))
    - `transition` (2023-24 only; only returns for `salary_year=2023`)

**Design choice (intentional):**
- Use **cap** amounts for “Salary” math (6(j)(1)).
- Use **apron** amounts only for the padding gate (6(j)(3)).

Constants source:
- `pcms.league_system_values`:
  - `tax_apron_amount` (First Apron)
  - `tax_apron2_amount` (Second Apron)
  - `tpe_dollar_allowance` (matches $7.5M × cap ratio term)
  - `max_trade_cash_amount` (5.15% cap cash limit)

---

## P0 — Rewrite “Trade Machine” goal (we are NOT doing old band tables yet)

**Important:** classic old “trade matching bands” (e.g. 125% + $100k / 175% + $5M thresholds) are not present in our 2023-CBA-derived corpus the same way. The closest authoritative, codeable salary-matching logic we extracted is **CBA 6(j) TPE mechanics**.

So the immediate target is:
- Build a **trade planner** that models *real NBA front office behavior*:
  - existing exception usage as a separate leg
  - then the main trade leg that creates/consumes exceptions

---

## P1 — Trade planner MVP (TPE-first)

### Why
To reproduce real workflows like:
- “Use the expiring TPE on the smallest incoming player so it doesn’t count toward the main trade leg.”

### Required concept: multi-leg deal plan
A single trade proposal can be modeled as:
1) **Absorption legs** (acquire players into existing exceptions)
2) **Main trade leg** (players traded away vs players acquired simultaneously)
3) **Resulting exceptions created** (new TPEs) and remaining amounts

### Proposed artifact
Create a *view or function* (start as a function returning JSONB or a table) that:
- inputs:
  - `team_code`, `salary_year`
  - `outgoing_player_ids[]`
  - `incoming_player_ids[]`
  - optional: `exception_ids[]` to constrain which exceptions may be used
- output:
  - the selected absorption assignments (which incoming player is absorbed into which exception)
  - remaining “main trade leg” incoming/outgoing sets
  - computed results:
    - updated exception remaining amounts
    - new TPE created from the main trade leg (via `fn_tpe_trade_math`)
  - diagnostics:
    - rows missing from `salary_book_yearly`
    - baseline team salary missing

### Heuristic (good enough)
- Prefer exceptions that expire sooner.
- For each exception: absorb the **largest incoming contract that fits** (or smallest; decide and document).
- Remove absorbed players from the main trade leg.

### Acceptance tests
- Construct the user-described case:
  - existing TPE = $5M
  - incoming = $15M + $4M
  - outgoing = $22M
  - planner should allocate $4M into the TPE and treat the main leg as $22M out / $15M in.

---

## P2 — Expand planner: MLE-as-vehicle + apron constraints

The user noted: MLE can now be used as an acquisition vehicle, but you must account for apron restrictions.

### Work needed
1) Confirm we can reliably derive:
- remaining MLE (NTMLE/TMLE/Room MLE) amounts
- whether already used / partially used
- from `pcms.team_exception_usage`, `pcms.team_exceptions`, and `pcms.league_system_values`.

2) Add constraint checks:
- Apron transaction restrictions (hard-cap triggers) for using NTMLE/BAE/etc.
- Use `fn_post_trade_apron` + thresholds from `league_system_values`.

---

## P2 — Fidelity / reconciliation artifact (debugging hammer)

Create one canonical reconciliation view/query:
- compares `team_salary_warehouse.cap_rost` vs `SUM(salary_book_warehouse.cap_2025)` (and similar for apron)
- explains deltas by `pcms.team_budget_snapshots.budget_group_lk`
- links to drilldowns:
  - `dead_money_warehouse`
  - `cap_holds_warehouse`
  - `exceptions_warehouse`

---

## P3 — Tool-facing exports (Team Master / Playground / Trade Machine)

Once planner + reconciliation exist:
- Team Master header: `team_salary_warehouse`
- roster grid: `salary_book_warehouse` filtered by team
- exceptions list: `exceptions_warehouse`
- trade machine export:
  - roster rows + exception state + planner outputs (legs + max incoming)

---

## Notes / gotchas

- `salary_year` in PCMS is the start of the cap year:
  - `salary_year=2025` == 2025-26 season.
  - `salary_year=2023` == 2023-24 season (Transition TPE year).
- `SUM(bigint)` returns `numeric` in Postgres; cast back if you need `bigint`.
- For now, `salary_book_yearly` uses special trade-context columns only for 2025; years 2026+ fall back to base cap/tax/apron.
