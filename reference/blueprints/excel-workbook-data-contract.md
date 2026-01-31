# Excel Workbook Data Contract (Postgres → `DATA_*` tables)

**Updated:** 2026-01-31
**Version:** v2-2026-01-31

This document defines the **stable data interface** between:

- Postgres (`pcms.*` warehouses / views / constants), and
- the generated Excel cap workbook (the `DATA_*` sheets that formulas consume).

It exists to prevent the two classic failure modes:

1) the workbook silently drifting from the database model
2) "refresh scripts" becoming a pile of ad-hoc queries no one can reason about

This is a *contract*: if we change a column name/type/meaning, we must update this doc and the exporter/workbook generator together.

---

## Contract scope

### In scope
- baseline datasets embedded in the workbook (tables on `DATA_*` sheets)
- keys, required columns, and semantic meaning
- which dataset drives which UI sheets
- reconciliation expectations (what should match what)

### Out of scope (for now)
- the full scenario engine implementation (journal evaluation)
- any "live DB connection" Excel approach (ODBC/PowerQuery as a default)
- formatting / workbook UX layout (see `excel-cap-book-blueprint.md`)

---

## Global conventions

### 1) No live DB dependency in the workbook
The workbook should be portable/offline.

All DB access happens in an **exporter** (local `uv run` or Windmill step) which writes data into `DATA_*` sheets.

### 2) Prefer warehouses for Excel extracts
Unless there's a strong reason, extract from:
- `pcms.*_warehouse` tables
- stable `pcms.*` views (e.g. `pcms.salary_book_yearly`)

Avoid raw joins over `pcms.salaries`, `pcms.contract_versions`, etc.

### 3) Amount units
All money amounts are **dollars** (integer) unless explicitly documented otherwise.

Excel can format as `$#,##0` and can divide by 1,000,000 for "$M" displays.

### 4) Keys > names
UI sheets may display names, but all joins should be possible via stable keys:
- `player_id`
- `team_code`
- `salary_year`
- `team_exception_id`
- `contract_id` / `version_number` (when needed)

### 5) Year horizon
The workbook should operate over a fixed horizon:
- `base_year` through `base_year + 5` (6 seasons)

Any "wide" salary exports should be relative to `base_year` (see below).

### 6) Relative-year wide columns (recommended)
To avoid changing workbook formulas/references every season, export wide salary columns as **relative-year columns**.

Example mapping when `base_year = 2025`:
- `cap_y0` → `cap_2025`
- `cap_y1` → `cap_2026`
- …
- `cap_y5` → `cap_2030`

Do the same for tax/apron/options/guarantees if included.

---

## Required datasets (v2)

| Dataset | Postgres source | Excel sheet | Excel table | Primary key | Used by |
|---|---|---|---|---|---|
| System values | `pcms.league_system_values` | `DATA_system_values` | `tbl_system_values` | `(league_lk, salary_year)` | cockpit thresholds, % of cap, exception amounts |
| Tax rates | `pcms.league_tax_rates` | `DATA_tax_rates` | `tbl_tax_rates` | `(league_lk, salary_year, bracket_number)` | tax calc + audit |
| Rookie scale | `pcms.rookie_scale_amounts` | `DATA_rookie_scale` | `tbl_rookie_scale` | `(salary_year, pick_number)` | RULES_REFERENCE, fill row generation |
| Minimum scale | `pcms.league_salary_scales` | `DATA_minimum_scale` | `tbl_minimum_scale` | `(salary_year, years_of_service)` | RULES_REFERENCE, min contract identification |
| Team totals (authoritative) | `pcms.team_salary_warehouse` | `DATA_team_salary_warehouse` | `tbl_team_salary_warehouse` | `(team_code, salary_year)` | cockpit readouts + ledger |
| Salary book (wide) | `pcms.salary_book_warehouse` (exported as relative-year columns) | `DATA_salary_book_warehouse` | `tbl_salary_book_warehouse` | `player_id` | roster grid + UI |
| Salary book (yearly) | `pcms.salary_book_yearly` | `DATA_salary_book_yearly` | `tbl_salary_book_yearly` | `(player_id, salary_year)` | trade math + per-year logic |
| Cap holds that count | `pcms.cap_holds_warehouse` | `DATA_cap_holds_warehouse` | `tbl_cap_holds_warehouse` | `non_contract_amount_id` | roster ledger drilldowns |
| Dead money that counts | `pcms.dead_money_warehouse` | `DATA_dead_money_warehouse` | `tbl_dead_money_warehouse` | `transaction_waiver_amount_id` | roster ledger drilldowns |
| Exceptions inventory | `pcms.exceptions_warehouse` | `DATA_exceptions_warehouse` | `tbl_exceptions_warehouse` | `team_exception_id` | TPE/exception UI + plan |
| Draft picks | `pcms.draft_picks_warehouse` | `DATA_draft_picks_warehouse` | `tbl_draft_picks_warehouse` | (varies; see section) | assets UI |

---

## Dataset definitions

### A) `tbl_system_values`

**Source:** `pcms.league_system_values`

**Filters:**
- `league_lk = 'NBA'`
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `(league_lk, salary_year)`

**Required columns (v2):**
- `league_lk`
- `salary_year`
- Thresholds:
  - `salary_cap_amount`
  - `tax_level_amount`
  - `tax_apron_amount`
  - `tax_apron2_amount`
  - `minimum_team_salary_amount`
- Exception amounts:
  - `non_taxpayer_mid_level_amount` (full MLE)
  - `taxpayer_mid_level_amount` (taxpayer MLE)
  - `room_mid_level_amount` (room MLE)
  - `bi_annual_amount` (BAE)
  - `tpe_dollar_allowance`
- Two-way amounts:
  - `two_way_salary_amount`
  - `two_way_dlg_salary_amount`
- Salary limits:
  - `maximum_salary_25_pct`
  - `maximum_salary_30_pct`
  - `maximum_salary_35_pct`
  - `average_salary_amount`
  - `max_trade_cash_amount`
- Season calendar:
  - `days_in_season`
  - `season_start_at`
  - `season_end_at`

**Used by:**
- cockpit thresholds + "room under X" readouts
- % of cap calculations
- exception/signing tooling

---

### B) `tbl_tax_rates`

**Source:** `pcms.league_tax_rates`

**Filters:**
- `league_lk = 'NBA'`
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `(league_lk, salary_year, bracket_number)`

**Note:** `pcms.league_tax_rates` does *not* currently store `bracket_number`.
For the workbook export, derive it deterministically as:
- `bracket_number = ROW_NUMBER() OVER (PARTITION BY league_lk, salary_year ORDER BY lower_limit)`

**Required columns:**
- `league_lk`
- `salary_year`
- `bracket_number`
- `lower_limit`
- `upper_limit`
- `tax_rate_non_repeater`
- `tax_rate_repeater`
- `base_charge_non_repeater`
- `base_charge_repeater`

**Used by:**
- luxury tax calculation + audit

---

### C) `tbl_rookie_scale`

**Source:** `pcms.rookie_scale_amounts`

**Filters:**
- `league_lk = 'NBA'`
- `salary_year BETWEEN base_year AND base_year + 5`
- `is_active = TRUE`

**Primary key:** `(salary_year, pick_number)`

**Required columns:**
- `salary_year`
- `league_lk`
- `pick_number`
- `salary_year_1` (year 1 salary)
- `salary_year_2` (year 2 salary)
- `salary_year_3` (year 3 salary / option)
- `salary_year_4` (year 4 salary / option)
- `option_amount_year_3`
- `option_amount_year_4`
- `is_baseline_scale`

**Used by:**
- RULES_REFERENCE rookie scale table
- fill row generation (when filling with rookie minimums)

---

### D) `tbl_minimum_scale`

**Source:** `pcms.league_salary_scales`

**Filters:**
- `league_lk = 'NBA'`
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `(salary_year, years_of_service)`

**Required columns:**
- `salary_year`
- `league_lk`
- `years_of_service` (0-10+)
- `minimum_salary_amount`

**Used by:**
- RULES_REFERENCE minimum salary table
- minimum contract identification
- fill row generation (when filling with veteran minimums)

---

### E) `tbl_team_salary_warehouse` (authoritative totals)

**Source:** `pcms.team_salary_warehouse`

**Filters:**
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `(team_code, salary_year)`

**Required columns:**
- identifiers: `team_code`, `salary_year`
- totals: `cap_total`, `tax_total`, `apron_total`
- bucket subtotals: `cap_rost`, `cap_fa`, `cap_term`, `cap_2way` (and tax/apron equivalents)
- roster counts: `roster_row_count`, `two_way_row_count` (plus FA/TERM counts if used)
- thresholds: `salary_cap_amount`, `tax_level_amount`, `tax_apron_amount`, `tax_apron2_amount`
- derived room fields: `over_cap`, `room_under_tax`, `room_under_apron1`, `room_under_apron2`
- status flags: `is_taxpayer`, `is_repeater_taxpayer`, `apron_level_lk`

**Used by:**
- cockpit primary readouts (these should come from here)
- authoritative ledger totals

**Reconciliation expectation:**
- Any workbook "counting totals" should match this table's totals for the selected team/year/mode.

---

### F) `tbl_salary_book_warehouse` (wide, UI-friendly)

**Source:** `pcms.salary_book_warehouse`

**Filters:**
- `league_lk = 'NBA'`
- (optional) exclude rows with no team, depending on desired UI behavior

**Primary key:** `player_id` (note: underlying reality can have multiple contracts; warehouse picks a primary identity)

**Export shape (recommended):**
- keep identifiers + metadata columns
- export salary columns as relative-year columns (`cap_y0..cap_y5`, `tax_y0..tax_y5`, `apron_y0..apron_y5`)

**Required columns (v1):**
- `player_id`
- `player_name`
- `team_code`
- `league_lk`
- contract identity: `contract_id`, `version_number`
- roster classification: `is_two_way`
- salary columns:
  - `cap_y0..cap_y5`
  - `tax_y0..tax_y5`
  - `apron_y0..apron_y5`

**Recommended metadata columns (high-value for analysts):**
- `age`, `birth_date`, `agent_name`
- option columns (`option_y0..option_y5`, `option_decision_y0..option_decision_y5`)
- guarantee columns (`guaranteed_amount_y0..y5`, `is_fully_guaranteed_y0..y5`, etc.)
- trade fields: `is_trade_bonus`, `trade_bonus_percent`, `trade_kicker_display`, `is_poison_pill`
- restrictions/consent: `is_no_trade`, `player_consent_lk`, `is_trade_consent_required_now`, `trade_restriction_lookup_value`, `is_trade_restricted_now`
- signing method / exception fields: `signed_method_lookup_value`, `exception_type_lookup_value`, `min_contract_lookup_value`

**Used by:**
- roster grid display
- player detail panels

---

### G) `tbl_salary_book_yearly` (tall, calculation-friendly)

**Source:** `pcms.salary_book_yearly` (view)

**Filters:**
- `league_lk = 'NBA'`
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `(player_id, salary_year)`

**Required columns (v1):**
- identifiers: `player_id`, `player_name`, `team_code`, `salary_year`
- amounts: `cap_amount`, `tax_amount`, `apron_amount`

**Trade-math columns (recommended if trade tooling exists):**
- `incoming_cap_amount`, `incoming_tax_amount`
- `incoming_apron_amount`, `outgoing_apron_amount`
- `trade_kicker_amount`, `is_trade_bonus`, `trade_bonus_percent`

**Restriction/metadata columns (nice-to-have for UI + validations):**
- `is_two_way`, `is_poison_pill`, `poison_pill_amount`
- `player_consent_lk`, `is_trade_consent_required_now`, `is_trade_preconsented`
- `is_no_trade`
- `trade_restriction_lookup_value`, `trade_restriction_end_date`, `is_trade_restricted_now`
- `contract_type_lookup_value`, `signed_method_lookup_value`, `exception_type_lookup_value`, `min_contract_lookup_value`

**Used by:**
- any per-year computation (trade matching windows, deltas, scenario effects)

---

### H) `tbl_cap_holds_warehouse`

**Source:** `pcms.cap_holds_warehouse`

**Filters:**
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `non_contract_amount_id`

**Required columns:**
- `non_contract_amount_id`
- `team_code`
- `salary_year`
- `player_id`, `player_name` (may be null for non-player items)
- `cap_amount`, `tax_amount`, `apron_amount`
- designation/status: `free_agent_designation_lk`, `free_agent_status_lk`

**Used by:**
- roster/ledger drilldowns for "FA/holds that count"

---

### I) `tbl_dead_money_warehouse`

**Source:** `pcms.dead_money_warehouse`

**Filters:**
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `transaction_waiver_amount_id`

**Required columns:**
- `transaction_waiver_amount_id`
- `team_code`
- `salary_year`
- `player_id`, `player_name`
- `waive_date`
- values: `cap_value`, `tax_value`, `apron_value`

**Used by:**
- roster/ledger drilldowns for termination rows
- buyout/waive modeling (baseline evidence)

---

### J) `tbl_exceptions_warehouse`

**Source:** `pcms.exceptions_warehouse`

**Filters:**
- `salary_year BETWEEN base_year AND base_year + 5`

**Primary key:** `team_exception_id`

**Required columns:**
- `team_exception_id`
- `team_code`
- `salary_year`
- `exception_type_lk`, `exception_type_name`
- `effective_date`, `expiration_date`
- `original_amount`, `remaining_amount`
- (if present) prorated fields like `prorated_remaining_amount`

**Used by:**
- exception inventory UI
- trade planner / TPE absorption

---

### K) `tbl_draft_picks_warehouse`

**Source:** `pcms.draft_picks_warehouse`

**Filters:**
- typically `draft_year >= base_year` (depending on how the warehouse is defined)

**Primary key:** depends on warehouse design (often `(draft_year, draft_round, original_team_code, owning_team_code)` or a surrogate id).

**Required columns (conceptually):**
- identifiers for pick slot (year/round/original)
- current owner
- protection / notes fields (if modeled)

**Used by:**
- assets dashboard

---

## Change management

### Versioning
The workbook `META` sheet should include:
- `data_contract_version` (string)
- exporter git commit hash

### Compatibility rule
- Additive column additions are OK (workbook ignores unused columns).
- Renames/removals/meaning changes require:
  1) contract update
  2) workbook generator update
  3) exporter update

---

## Next refinement (when we're ready)

Once the workbook generator stabilizes, we should tighten this contract by adding:
- exact column lists (not "recommended")
- explicit nullability rules
- reconciliation queries for each dataset

But this v1 contract is enough to design the exporter and avoid the common drift traps.
