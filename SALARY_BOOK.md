# Salary Book / Playground Data Guide

**Updated:** 2026-01-31

This repo implements **Sean-style salary cap tooling powered by Postgres**: fast, indexed, refreshable **warehouse tables** + a complete set of **trade-math and tax primitives**.

---

## How Close Are We to Sean's Workbook?

We have **near-complete parity** with Sean's Excel workbook for the core analyst use cases.

### ✅ What We Have (matches Sean's functionality)

| Sean Concept | Our Implementation | Status |
|--------------|-------------------|--------|
| **Y Warehouse** (player salary matrix) | `pcms.salary_book_warehouse` | ✅ Complete |
| **Team Summary** (team totals vs cap/tax/apron) | `pcms.team_salary_warehouse` | ✅ Complete |
| **Exceptions** (TPE/MLE/BAE by team) | `pcms.exceptions_warehouse` | ✅ Complete |
| **Tax Array** (luxury tax brackets) | `pcms.league_tax_rates` | ✅ Complete |
| **Tax Payment** (luxury tax calculation) | `pcms.fn_luxury_tax_amount()` | ✅ Complete |
| **System Values** (cap/tax/apron thresholds) | `pcms.league_system_values` | ✅ Complete |
| **Trade Machine** (forward salary matching) | `pcms.fn_tpe_trade_math()` | ✅ Complete |
| **TPE Absorption** (multi-leg trades) | `pcms.fn_trade_plan_tpe()` | ✅ Complete |
| **Can Bring Back** (inverse matching window) | `pcms.fn_trade_salary_range()` | ✅ Complete |
| **Multi-Year Minimums** (Years 2–5) | `pcms.fn_minimum_salary()` | ✅ Complete |
| **Buyout / Waiver scenarios** | `pcms.fn_buyout_scenario()` | ✅ Complete |
| **Rookie Scale** | `pcms.rookie_scale_amounts` | ✅ Complete |
| **Draft Picks** | `pcms.draft_pick_summary_assets` | ✅ Complete |
| **Dead Money** (waiver charges) | `pcms.dead_money_warehouse` | ✅ Complete |
| **Cap Holds** (FA holds) | `pcms.cap_holds_warehouse` | ✅ Complete |
| **Agent Rollups + Percentiles** | `pcms.agents_warehouse` | ✅ Complete |
| **Agency Rollups + Percentiles** | `pcms.agencies_warehouse` | ✅ Complete |
| **Repeater Tax Status** | `pcms.team_salary_warehouse.is_repeater_taxpayer` | ✅ Complete |
| **Apron Status** | `pcms.team_salary_warehouse.apron_level_lk` | ✅ Complete |
| **Contract Protections** | `pcms.contract_protections` | ✅ Complete |
| **Trade Kickers** | `pcms.salary_book_warehouse.trade_kicker_display` | ✅ Complete |
| **Option Types** | `pcms.salary_book_warehouse.option_20xx` | ✅ Complete |
| **Player Consent / Trade Restrictions** | `pcms.salary_book_warehouse.player_consent_lk` + `trade_restriction_*` | ✅ Complete |
| **Min Contract Detection** | `pcms.salary_book_warehouse.is_min_contract` (+ `min_contract_*`) | ✅ Complete |

### ✅ Three Sean primitives we’ve added (now implemented)

| Sean Concept | Primitive | Implementation |
|--------------|----------|----------------|
| **Can Bring Back** (inverse trade matching) | `pcms.fn_can_bring_back()` / `pcms.fn_trade_salary_range()` | `migrations/058_fn_can_bring_back.sql` |
| **Multi-Year Minimums** (Years 2-5 escalators) | `pcms.fn_minimum_salary()` | `migrations/059_fn_minimum_salary.sql` |
| **Buyout / Waiver / Stretch / Set-Off** | `pcms.fn_buyout_scenario()` + helpers | `migrations/060_fn_buyout_primitives.sql` |

### ⏳ Lower Priority (not blocking core use cases)

| Sean Concept | Notes |
|--------------|-------|
| Extension calculator (`the_matrix.json`) | CBA algebra for max extensions |
| High/Low projections (`high_low.json`) | Best/worst case contract outcomes |
| Roster charge penalties | Uses `/174` proration constant |

---

## Key Insight: Sean's Reactive Logic

Sean's workbook is powerful because of its **reactive formulas** — change a team selector or trade inputs, and everything recalculates.

Our Postgres approach delivers the same behavior:
- **Team rosters**: `WHERE team_code = 'BOS'`
- **Trade scenarios**: `fn_trade_plan_tpe('BOS', 2025, ARRAY[player_ids], ...)`
- **Tax projections**: `fn_team_luxury_tax('BOS', 2025)`
- **Multi-year views**: `salary_book_yearly` pivots wide → tall

The warehouse tables are pre-aggregated for fast queries. The primitives compose for scenario modeling.

---

## Canonical Tables for Tooling

### What counts vs. drilldown detail (important)

Sean’s mental model distinguishes **what exists** from **what counts**.

- **Authoritative team-year amounts that count** toward cap/tax/aprons: `pcms.team_budget_snapshots` → exposed via `pcms.team_salary_warehouse`.
- **Tool-facing drilldowns** should prefer the `*_warehouse` tables first.
  - `pcms.cap_holds_warehouse` is filtered to holds that actually count (rows in FA/QO/DRFPK/PR10D budget groups, plus rows flagged `is_fa_amount = true` in `team_budget_snapshots`).
  - `pcms.dead_money_warehouse` is the drilldown for termination / waiver charges.

### Player-Level: `pcms.salary_book_warehouse`

One row per player with an **active contract** (`APPR`/`FUTR`) and a resolved `team_code`.

- Amounts are stored in **dollars** (`bigint`).
- 2025 is the current “base” year in the warehouse (2025–2030 columns).
- `cap_hold_20xx` columns expose upcoming FA hold amounts for the player/team row (same eligibility filter as `cap_holds_warehouse`; parallel metadata, do not add on top of `cap_20xx`).
- If a player has multiple overlapping contracts (rookie + extension), we pick the **most recently signed** `APPR/FUTR` contract as the “primary” contract identity.

```sql
SELECT player_name, team_code,
       cap_2025, cap_2026, cap_2027,
       cap_hold_2025, cap_hold_2026, cap_hold_2027,
       option_2025, option_2026,
       trade_kicker_display, agent_name
FROM pcms.salary_book_warehouse
WHERE team_code = 'BOS'
ORDER BY cap_2025 DESC NULLS LAST;
```

Key columns (high-signal for tools):
- `cap_20xx`, `tax_20xx`, `apron_20xx` — Salary Book grids (2025–2030)
- `pct_cap_20xx` — `cap_20xx / salary_cap_amount` for that year
- `pct_cap_percentile_20xx` — league percentile (0–1) for that year’s `% of cap`
- `likely_bonus_20xx`, `unlikely_bonus_20xx` — incentive detail
- `guaranteed_amount_20xx` + `is_fully_guaranteed_20xx` / `is_partially_guaranteed_20xx` / `is_non_guaranteed_20xx`
  - Derived from `pcms.contract_protections`
- `option_20xx`, `option_decision_20xx` — option types/decisions (normalized, `NULL` means no option)
- Trade math primitives (base-year): `outgoing_buildup_2025`, `incoming_salary_2025`, `incoming_tax_2025`, `incoming_apron_2025`
- Trade add-ons: `is_poison_pill`, `poison_pill_amount`, `is_trade_bonus`, `trade_bonus_percent`, `trade_kicker_display`
- Trade restrictions & consent:
  - `is_no_trade`
  - `player_consent_lk`, `player_consent_end_date`, `is_trade_consent_required_now`, `is_trade_preconsented`
  - `trade_restriction_lookup_value`, `trade_restriction_end_date`, `is_trade_restricted_now`
- Contract classification / signing metadata:
  - `contract_type_lookup_value` (rookie scale, vet min, extension, etc.)
  - `signed_method_lookup_value` (Bird, MLE, BAE, minimum, etc.)
  - `exception_type_lookup_value` (if signed via a team exception)
  - `min_contract_lookup_value` + `is_min_contract` (true only for 1–2 year minimums; 3+ year minimums are excluded)

### Player-Level (Yearly): `pcms.salary_book_yearly`

One row per (player, year). This is the most convenient shape for trade math, because every contract becomes a consistent per-year series.

```sql
SELECT salary_year, team_code, cap_amount, tax_amount, apron_amount
FROM pcms.salary_book_yearly
WHERE player_id = 201566
ORDER BY salary_year;
```

### Team-Level: `pcms.team_salary_warehouse`

One row per (team, year). Team totals + cap/tax/apron room. `cap_total` is contract-only (no holds); `cap_total_hold` preserves the snapshot total with holds.

This table is derived from `pcms.team_budget_snapshots` (the authoritative “what counts” ledger).

```sql
SELECT team_code,
       cap_total, tax_total, apron_total,
       salary_cap_amount, tax_level_amount,
       over_cap, room_under_tax, room_under_apron1,
       is_taxpayer, is_repeater_taxpayer, apron_level_lk
FROM pcms.team_salary_warehouse
WHERE salary_year = 2025
ORDER BY tax_total DESC;
```

Tip: `cap_rost` is now **contract-only roster salary** (from `salary_book_yearly`). The snapshot “ROST” bucket (holds/rights) is preserved as `cap_rost_hold`. `cap_fa`, `cap_term`, `cap_2way` still mirror the budget-group breakdown.

### Exceptions: `pcms.exceptions_warehouse`

Trade exceptions by team with proration + remaining amounts.

```sql
SELECT team_code, exception_type_lk, exception_type_name,
       trade_exception_player_name,
       remaining_amount, prorated_remaining_amount,
       expiration_date, is_expired
FROM pcms.exceptions_warehouse
WHERE team_code = 'CLE' AND salary_year = 2025
ORDER BY remaining_amount DESC;
```

### Dead Money: `pcms.dead_money_warehouse`

Waiver/buyout termination charges by team **that currently count** in team totals.

- Warehouse semantics are aligned to `team_budget_snapshots` `budget_group_lk = 'TERM'`.
- Superseded waiver transaction streams are excluded (latest contract stream only).
- Historical/raw waiver rows remain available in `pcms.transaction_waiver_amounts`.

```sql
SELECT team_code, player_name, waive_date,
       cap_value, tax_value, apron_value
FROM pcms.dead_money_warehouse
WHERE team_code = 'BOS' AND salary_year = 2025
ORDER BY cap_value DESC;
```

### Cap Holds: `pcms.cap_holds_warehouse`

FA holds / rights amounts that actually count in team totals.

```sql
SELECT team_code, player_name,
       free_agent_designation_lk, free_agent_status_lk,
       cap_amount, tax_amount, apron_amount
FROM pcms.cap_holds_warehouse
WHERE team_code = 'BOS' AND salary_year = 2025
ORDER BY cap_amount DESC;
```

---

## Trade Primitives

### Forward Trade Matching: `fn_tpe_trade_math()`

Given outgoing players, compute max incoming salary under CBA rules.

```sql
SELECT * FROM pcms.fn_tpe_trade_math(
    'BOS',                    -- team_code
    2025,                     -- salary_year
    ARRAY[1628369],           -- traded_player_ids (Jaylen Brown)
    ARRAY[]::integer[],       -- replacement_player_ids
    'expanded'                -- tpe_type ('standard' or 'expanded')
);
```

### Trade Planner: `fn_trade_plan_tpe()`

Full trade scenario with multi-leg absorption. Returns JSON with `absorption_legs`, `main_leg`, `summary`.

```sql
SELECT pcms.fn_trade_plan_tpe(
    'BOS', 2025,
    ARRAY[player1, player2],  -- outgoing
    ARRAY[player3],           -- incoming
    ARRAY[exception_id]       -- TPE to use
);
```

### Can Bring Back / Matching Window: `fn_trade_salary_range()`

For a single outgoing salary amount, return the **matching window** for a simple 2-team trade:

- `min_incoming`: minimum single salary the other team needs to send to acquire this salary
- `max_incoming`: maximum single salary you’re allowed to receive for this salary

```sql
SELECT * FROM pcms.fn_trade_salary_range(30000000, 2025, 'expanded', 'NBA');
```

To build a “Can Bring Back” table for a roster:

```sql
SELECT
  sby.player_name,
  sby.cap_amount AS outgoing_salary,
  r.min_incoming,
  r.max_incoming
FROM pcms.salary_book_yearly sby
CROSS JOIN LATERAL pcms.fn_trade_salary_range(sby.cap_amount, sby.salary_year, 'expanded', 'NBA') r
WHERE sby.salary_year = 2025
  AND sby.team_code = 'BOS'
ORDER BY sby.cap_amount DESC NULLS LAST;
```

---

## Minimum Salary

### Multi-year minimum salaries: `fn_minimum_salary()`

PCMS provides Year 1 minimums; this function derives Years 2–5 using Sean’s escalators.

```sql
-- 2025 minimum for a 4-YOS player, contract year 3
SELECT pcms.fn_minimum_salary(2025, 4, 3, 'NBA') AS min_salary;
```

---

## Buyout / Waiver Modeling

### Buyout scenarios: `fn_buyout_scenario()`

```sql
-- Example shape (player_id required)
SELECT * FROM pcms.fn_buyout_scenario(
  1629027,              -- player_id (example: Trae Young)
  '2026-01-15'::date,   -- waive date
  9000000               -- give-back amount
);
```

Helpers:

```sql
-- Days remaining after waiver clearance (waive_date + 2 days)
SELECT pcms.fn_days_remaining('2026-01-15'::date, '2025-10-20'::date);

-- Stretch provision (2 * remaining_years + 1)
SELECT * FROM pcms.fn_stretch_waiver(30000000, 2);

-- Set-off amount when a waived player signs elsewhere
SELECT pcms.fn_setoff_amount(14104000, 1, 2025, 'NBA');
```

---

## Luxury Tax

### Luxury Tax: `fn_luxury_tax_amount()`

Calculate luxury tax owed given amount over the tax line.

```sql
-- For a specific team
SELECT * FROM pcms.fn_team_luxury_tax('BOS', 2025);

-- All taxpayers
SELECT * FROM pcms.fn_all_teams_luxury_tax(2025)
WHERE luxury_tax_owed > 0;
```

---

## Differences from Sean's Workbook

### Things We Handle Better

1. **Normalized option types**: Sean uses strings like `'NONE'`, we normalize to `NULL`
2. **Decimal ages**: We compute `age` as decimal years, not integer
3. **Trade kicker states**: We handle `'Used'`, expiration dates, and vesting conditions
4. **Repeater status**: We pull from PCMS `tax_team_status`, not hardcoded IF-chains
5. **Multi-year consistency**: Our yearly view guarantees consistent shape for trade math

### Known Sean Workbook Issues (from our spec analysis)

1. **Hardcoded repeater flags**: Sean's `playground.json` uses IF-chains for 8 teams only
2. **External workbook refs**: Some formulas reference `[2]` (prior-year workbook)
3. **Stale cap holds**: Some cap holds appear for teams that renounced them
4. **Manual overrides**: Some salary values appear manually adjusted

---

## Refresh Functions

Warehouse tables are materialized and need refresh after PCMS imports.

These are run automatically in Windmill step H (`import_pcms_data.flow/refresh_caches.inline_script.py`).

```sql
SELECT pcms.refresh_salary_book_warehouse();
SELECT pcms.refresh_team_salary_warehouse();
SELECT pcms.refresh_team_salary_percentiles();
SELECT pcms.refresh_agents_warehouse();
SELECT pcms.refresh_agents_warehouse_percentiles();
SELECT pcms.refresh_agencies_warehouse();
SELECT pcms.refresh_agencies_warehouse_percentiles();
SELECT pcms.refresh_exceptions_warehouse();
SELECT pcms.refresh_dead_money_warehouse();
SELECT pcms.refresh_cap_holds_warehouse();
SELECT pcms.refresh_player_rights_warehouse();
SELECT pcms.refresh_draft_pick_summary_assets();
```

---

## Raw Model (for debugging)

If you need to trace a number back to source, these are the core PCMS base tables:

```
pcms.contracts (1 per contract)
  └── pcms.contract_versions (1+ per contract, amendments)
        └── pcms.salaries (1 per version per year)
pcms.contract_protections (guarantees by contract/version/year)
pcms.team_budget_snapshots (authoritative team-year "what counts" ledger)
pcms.non_contract_amounts (raw FA holds / rights; filtered into cap_holds_warehouse)
pcms.transaction_waiver_amounts (raw waiver detail; filtered into dead_money_warehouse)
pcms.people (player identity)
pcms.agents (agent identity)
pcms.league_system_values (cap/tax constants by year)
pcms.league_tax_rates (tax brackets with base charges)
```

### Key salary fields (from `pcms.salaries`)

| Field | Meaning |
|-------|---------|
| `contract_cap_salary` | Cap hit (Salary Book "cap" grid) |
| `contract_tax_salary` | Tax salary |
| `contract_tax_apron_salary` | Apron salary |
| `total_salary` | Actual paid salary |
| `likely_bonus` / `unlikely_bonus` | Incentives |
| `option_lk` | Option type (PLYR/TEAM/etc) |

---

## Validation

Run assertion tests to verify warehouse correctness:

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f queries/sql/run_all.sql
```

Compare spot-checks to Sean's data:

```bash
# Find a player in Sean's Y warehouse
jq 'to_entries[] | select(.value.B | test("James.*LeBron"; "i"))' reference/warehouse/y.json

# Compare to our DB
psql "$POSTGRES_URL" -c "
  SELECT player_name, team_code, cap_2025, cap_2026, cap_2027
  FROM pcms.salary_book_warehouse
  WHERE player_name ILIKE '%james%lebron%';
"
```

---

## Related Documentation

| Doc | Purpose |
|-----|---------|
| `TODO.md` | Next implementation priorities |
| `SALARY_BOOK_STATE_MODEL.md` | Official/Live/Scenario state model + external report system-of-record |
| `AGENTS.md` | Pipeline architecture + "what counts" rules |
| `DRAFT_PICKS.md` | Draft pick model + warehouse guidance |
| `reference/warehouse/AGENTS.md` | Sean workbook file guide |
| `reference/warehouse/specs/` | Detailed specs for Sean's sheets |
| `queries/README.md` | How we structure SQL assertion tests |
