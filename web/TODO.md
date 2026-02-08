# web/TODO.md — Schema & Data Gaps Audit

**Generated:** 2026-02-07  
**Source:** Comparison of Sean's workbook (`reference/warehouse/`) vs `pcms.*` schema

---

## Summary

The **data foundation is strong** — salaries, contracts, protections, cap holds, dead money, trade matching functions all work. The gaps are mostly:

1. **Display/derived fields** (position, tier/band)
2. **Empty schema tables** awaiting data (depth_charts, ui_projections, waiver_priority_ranks)
3. **Advanced multi-team trade tooling** (The Matrix equivalent)

---

## Priority Ranking

| Priority | Gap | Impact | Effort |
|----------|-----|--------|--------|
| **High** | Player position missing from salary_book_warehouse | Analyst UX (filtering by pos) | Medium — need source |
| **High** | Salary tier/band not computed | Analyst mental model | Medium — compute from cap % |
| **Medium** | depth_charts empty | Starter/bench context | ? (depends on XML source) |
| **Medium** | GLG teams missing | Two-way context | Low — add teams data |
| **Low** | Multi-team trade planner | Advanced tooling | High |
| **Low** | Pick grid view | UX convenience | Low — create view |

---

## Detailed Gaps

### 1. Player Position (`Pos` column)

**Sean has:** Position (PG, SG, SF, PF, C) in Y warehouse column `AN`

**We have:**
- `pcms.lookups` with `lk_positions` (lookup codes exist)
- `pcms.depth_charts.position_lk` column — but **table is empty**
- **No position on `salary_book_warehouse`** or `people`

**Gap:** Position is not exposed on players. The `depth_charts` table exists but has 0 rows. Either PCMS XML doesn't provide position, or we're not importing it.

**Action:** Investigate PCMS XML for position data. If not available, consider enriching from NBA API (`nba.*` schema) or SportRadar (`sr.*`).

---

### 2. Salary Tier / Band (`Tier`, `Top`, `Bottom`, `SB`)

**Sean has:**
- `Tier` (1–10) salary band classification
- `Top` / `Bottom` (rank within tier)
- `SB` display string like `"6 | 1-12"`

**We have:** Nothing. No tier, no salary band concept.

**Gap:** This is **analyst-derived classification**, not raw PCMS data. Sean computes it based on salary relative to cap.

**Action:** Add computed columns to `salary_book_warehouse` or create a view:
```sql
-- Example tier logic (needs refinement based on Sean's actual bands)
CASE
  WHEN pct_cap_2025 >= 0.35 THEN 1
  WHEN pct_cap_2025 >= 0.30 THEN 2
  WHEN pct_cap_2025 >= 0.25 THEN 3
  -- ... etc
END AS salary_tier
```

---

### 3. G-League / Affiliate Data (`ga.json`)

**Sean has:** `ga.json` sheet with G-League rosters, two-way depth charts

**We have:**
- `pcms.teams` has `league_lk` column but **0 GLG teams**
- `pcms.two_way_utility_warehouse` (89 rows) — two-way player tracking
- `pcms.two_way_daily_statuses` (28k rows)

**Gap:** GLG (G-League) teams themselves are missing from `pcms.teams`. Two-way tracking exists but the parent G-League rosters/teams aren't present.

**Action:** Import GLG teams into `pcms.teams` (or create separate G-League team reference).

---

### 4. `depth_charts` is Empty

**Schema exists:** 19 columns including `position_lk`, `depth_rank`, `is_starter`

**Rows:** 0

**Gap:** Either we're not importing depth chart data from PCMS, or it's not in the XML feed.

**Action:** Check if PCMS XML contains depth chart data. If not, consider populating from NBA API or leaving as UI-driven.

---

### 5. `ui_projections` / `ui_projected_salaries` / `ui_projection_overrides` are Empty

These tables exist for **scenario planning** (user-defined salary projections).

**Rows:** 0 in all three tables

**Gap:** Schema is ready, but no data — these are **UI-driven** tables, not XML-sourced.

**Action:** No action needed. Rails app will populate these when projection features are built.

---

### 6. Multi-Team Trade Planning Function

**Sean has:** `the_matrix.json` — 4-team trade scenario calculator with:
- Proration (days responsible based on trade date)
- Roster fill logic (auto-add minimums to reach 12/14)
- Trade validity checks per apron level (Expanded vs Standard mode)
- Pick exchange tracking

**We have:**
- `fn_trade_salary_range()` — 2-team matching range
- `fn_trade_plan_tpe()` — TPE trade planner
- `fn_post_trade_apron()` — post-trade apron calculation
- `fn_can_bring_back()` / `fn_min_outgoing_for_incoming()` — inverse matching

**Gap:** No **multi-team (3-4 party) trade planner** function. The Matrix logic isn't fully implemented.

**Action:** Build `fn_multi_team_trade_validation(...)` or handle in application layer. Low priority unless trade machine is on roadmap.

---

### 7. Pick Database Grid View

**Sean has:** `pick_database.json` — grid showing team × year × round → ownership status

**We have:** `pcms.draft_pick_summary_assets` with detailed asset-level data (swaps, conditionals, endnotes)

**Gap:** Not a gap per se — we have **more detail** than Sean. But a "pick grid" view (like `pick_database.json`) isn't materialized.

**Action:** Create a view or warehouse table that pivots `draft_pick_summary_assets` into a grid format for UI consumption.

---

### 8. Waiver Priority Team Association

**Sean has:** Waiver priority tied to teams

**We have:** `pcms.waiver_priority` (570 rows) with columns: `priority_date`, `seqno`, `status_lk`, `comments` — **no team_id or team_code**

**Gap:** Waiver priority isn't linked to teams. May need a join table or a `team_id` FK.

**Action:** Investigate PCMS XML structure for waiver priority. Add team linkage if available.

---

### 9. `waiver_priority_ranks` is Empty

Related to waiver priority — schema exists, 0 rows.

**Action:** Same as above — investigate source data.

---

## Tables with Data (Healthy)

For reference, these core tables are populated and working:

| Table | Rows | Status |
|-------|------|--------|
| `salary_book_warehouse` | 528 | ✅ Core player salaries |
| `team_salary_warehouse` | 210 | ✅ Team totals by year |
| `cap_holds_warehouse` | 218 | ✅ Cap holds |
| `dead_money_warehouse` | 471 | ✅ Dead money / waivers |
| `exceptions_warehouse` | 87 | ✅ TPE/MLE/BAE |
| `player_rights_warehouse` | 447 | ✅ Bird rights, RFA |
| `two_way_utility_warehouse` | 89 | ✅ Two-way tracking |
| `contract_protections` | 17,782 | ✅ Guarantees |
| `salaries` | 22,288 | ✅ Raw salary rows |
| `contracts` | 8,082 | ✅ Contract records |
| `contract_versions` | 10,453 | ✅ Version history |
| `trades` | 1,750 | ✅ Trade records |
| `draft_pick_summary_assets` | 1,505 | ✅ Pick ownership |
| `league_system_values` | 112 | ✅ CBA constants |
| `league_tax_rates` | 119 | ✅ Tax brackets |
| `rookie_scale_amounts` | 1,556 | ✅ Rookie scale |
| `league_salary_scales` | 440 | ✅ Minimum salary scale |

---

## SQL Functions Available

| Function | Purpose |
|----------|---------|
| `fn_trade_salary_range()` | Min/max incoming for outgoing salary |
| `fn_can_bring_back()` | Max incoming given outgoing |
| `fn_min_outgoing_for_incoming()` | Inverse of above |
| `fn_luxury_tax_amount()` | Calculate luxury tax owed |
| `fn_team_luxury_tax()` | Team-specific tax calculation |
| `fn_all_teams_luxury_tax()` | League-wide tax summary |
| `fn_buyout_scenario()` | Buyout dead money projection |
| `fn_stretch_waiver()` | Stretch provision calculation |
| `fn_setoff_amount()` | Waiver set-off calculation |
| `fn_minimum_salary()` | Min salary by YOS/year |
| `fn_post_trade_apron()` | Post-trade apron total |
| `fn_trade_plan_tpe()` | TPE trade planning |
| `fn_tpe_trade_math()` | TPE allowance calculations |
| `fn_player_current_team_from_transactions()` | Current team lookup |

---

## Next Steps

1. **Quick wins:**
   - [ ] Add salary tier/band computed column to `salary_book_warehouse`
   - [ ] Create pick grid view from `draft_pick_summary_assets`

2. **Investigation needed:**
   - [ ] Check PCMS XML for player position data
   - [ ] Check PCMS XML for depth chart data
   - [ ] Check PCMS XML for waiver priority team linkage
   - [ ] Verify GLG team data availability

3. **Deferred:**
   - [ ] Multi-team trade planner (The Matrix)
   - [ ] UI projection tables (wait for feature build)
