# Salary Book (web) — Feature/Data Parity Audit

Updated: 2026-01-31

This is a **web UI audit** against what we already have in Postgres + the Sean worksheets in `reference/warehouse/`.

## 0) Current web surfaces (interaction model)

- **Top command bar**: Team selector grid + filter lenses.
- **Main canvas**: scrollable 30-team Salary Book table (players + exceptions + cap holds + dead money + draft assets + totals footer).
- **Right panel**: team context (tabs) + shallow entity overlay (player / agent / pick / team).

## 1) What Postgres already has (tooling inventory)

### 1.1 Warehouse tables (tool-facing)

| Postgres object | Purpose | Web status |
|---|---|---|
| `pcms.salary_book_warehouse` | Player salary matrix (cap/tax/apron columns + trade flags + guarantees + incentives) | **Wired** (players list + player overlay guarantees/incentives detail) |
| `pcms.team_salary_warehouse` | Team totals, rooms, apron/tax flags, roster counts | **Wired** (KPIs + totals footer + sidebar cap outlook) |
| `pcms.exceptions_warehouse` | Trade exceptions by team/year | **Wired** (Exceptions row) |
| `pcms.cap_holds_warehouse` | Cap hold drilldown (only holds that count) | **Wired** (Cap Holds section) |
| `pcms.dead_money_warehouse` | Waiver/dead money drilldown | **Wired** (Dead Money section) |
| `pcms.draft_assets_warehouse` | Draft assets/picks (parsed from PCMS text + endnote refs) | **Wired** (Draft Assets row + draft tab + pick detail) — endnotes now server-side |
| `pcms.draft_pick_trade_claims_warehouse` | Pick claim chain/rights (warehouse) | **Wired** (Pick detail conveyance history) |
| `pcms.player_rights_warehouse` | Draft rights / D-League returning rights | **Wired** (TeamContext → Rights tab) |

### 1.2 Core primitives (functions)

| Function | Purpose | Web status |
|---|---|---|
| `pcms.fn_tpe_trade_math()` | Salary matching (forward) + apron impact | **Wired** (Trade Machine v1 overlay + API) |
| `pcms.fn_trade_plan_tpe()` | Multi-leg TPE planner | **Not exposed** |
| `pcms.fn_trade_salary_range()` / `pcms.fn_can_bring_back()` | “Can bring back” ranges (inverse matching) | **Wired** (Trade Machine v1 range output) |
| `pcms.fn_post_trade_apron()` | Post-trade apron projection | **Wired** (Trade Machine v1 apron delta) |
| `pcms.fn_luxury_tax_amount()` / `pcms.fn_team_luxury_tax()` | Luxury tax math | **Partially exposed** (team-year tax bill now available) |
| `pcms.fn_minimum_salary()` | Multi-year minimum scale (Y2–Y5 escalators + /174 proration) | **Not exposed** |
| `pcms.fn_buyout_scenario()` (+ `fn_stretch_waiver`, `fn_setoff_amount`) | Buyout/stretch/set-off calculator | **Wired** (Buyout calculator view) |

### 1.3 Config/reference tables

| Postgres object | Purpose | Web status |
|---|---|---|
| `pcms.league_system_values` | Cap/tax/apron thresholds, season constants | **Wired** (System Values sidebar view) |
| `pcms.league_tax_rates` | Tax brackets | **Wired** (System Values sidebar view) |
| `pcms.rookie_scale_amounts` | Rookie scale | **Not shown** |
| `pcms.league_salary_scales` | Salary scales (min, etc) | **Not shown** |
| `pcms.apron_constraints` | Apron constraint codes + descriptions | **Not shown** |

## 2) Sean worksheet parity (reference/warehouse)

| Worksheet JSON | Rough meaning | Web status |
|---|---|---|
| `y.json` | Salary Book grid | **Yes** |
| `team_summary.json` | Team totals vs cap/tax/aprons | **Yes (partial)** |
| `exceptions.json` | Team exception inventory | **Yes** |
| `draft_picks.json` | Picks inventory | **Yes (partial)** |
| `contract_protections.json` | Guarantees | **Partial** (tinting/tooltips; no sidebar drilldown) |
| `tax_array.json` | Tax brackets | **Yes** (System Values sidebar view) |
| `system_values.json` | Cap/tax/apron values | **Yes** (System Values sidebar view) |
| `machine.json` | Trade machine | **Partial** (Trade Machine v1 overlay) |
| `minimum_salary_scale.json` | Minimum scale | **Missing** |
| `buyout_calculator.json` / `set-off.json` | Buyout/stretch/set-off | **Partial** (Buyout calculator + stretch/set-off amounts) |
| `the_matrix.json` / `high_low.json` | Extension calculator / projections | **Missing** |

## 3) Biggest “missing from web” gaps (high leverage)

### A) Trade machine (core analyst workflow) — v1 wired

- **Wired**: sidebar overlay + API contract (2-team, players-only, single year).
- **Uses**: `fn_tpe_trade_math()`, `fn_trade_salary_range()`, `fn_post_trade_apron()`.
- **Still missing**: picks/cash legs, ops consideration checks, multi-team, planner suggestions (`fn_trade_plan_tpe()`).

### B) System values + tax table visibility (now implemented)

- Implemented as the **Sidebar → System Values** view (top command bar).
- Shows: cap/tax/apron lines, exception constants, key calendar dates, and the NBA tax bracket table.

### C) Player detail drilldown parity

Player overlay should show (DB-backed, not hand-wavy):
- guarantee amounts + guarantee conditions
- incentives (likely/unlikely) detail (from `pcms.contract_bonuses`)
- signed method + exception instance (Bird/MLE/BAE/minimum, etc)
- trade restriction code + end date

### D) Pick detail timeline + constraints

- Avoid client parsing of clause text.
- Prefer DB-derived `timeline_json` / `constraint_flags` style output.
- Use `draft_assets_warehouse.endnote_refs` + `pcms.endnotes` as the starting point.

## 4) Suggested next build order

1. ✅ **Trade Machine v1**: API endpoint that wraps `fn_tpe_trade_math()` and renders per-team pass/fail + max incoming + apron deltas.
2. ✅ **System Values sidebar view**: cap/tax/apron lines + tax brackets.
3. **Player overlay v2**: guarantees + incentives + signing method block.
4. **Pick overlay v2**: endnote-backed conveyance timeline + Stepien/7-year flags.

---

If you’re extending this doc: keep it **constraint-first**, and prefer “DB object → UI surface” mapping over prose.
