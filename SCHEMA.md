# PCMS Postgres Schema Reference

**Auto-generated from migrations/** — Updated 2026-01-31

This document describes the `pcms.*` schema: tables, views, warehouse caches, and functions used by Sean-style tooling (Salary Book, Trade Machine, Team Master).

---

## Quick Navigation

- [Tool-Facing Warehouses](#tool-facing-warehouses) — denormalized caches for UI tools
- [Core Data Tables](#core-data-tables) — raw PCMS imports
- [System / CBA Constants](#system--cba-constants) — league configuration
- [Views](#views) — analyst convenience views
- [Functions](#functions) — trade math + refresh routines

---

## Tool-Facing Warehouses

These are **denormalized cache tables** refreshed periodically. Use these for UI tools.

### `pcms.salary_book_warehouse`

**Purpose:** One-row-per-player salary grid for Salary Book / Playground.

| Column | Type | Description |
|--------|------|-------------|
| `player_id` | integer (PK) | Player ID |
| `player_name` | text | "Last, First" format |
| `league_lk` | text | `NBA` or `DLG` |
| `team_code` | text | Current team (3-letter code) |
| `contract_team_code` | text | Team from contract |
| `person_team_code` | text | Team from people table |
| `signing_team_id` | integer | Original signing team |
| `contract_id` | integer | Active contract ID |
| `version_number` | integer | Contract version |
| `birth_date` | date | Player birth date |
| `age` | integer | Age in years |
| `agent_name` | text | Agent name |
| `agent_id` | integer | Agent ID |
| `cap_2025` … `cap_2030` | bigint | Cap salary per year |
| `pct_cap_2025` … `pct_cap_2030` | numeric | % of salary cap |
| `total_salary_from_2025` | bigint | Sum of cap salaries 2025+ |
| `option_2025` … `option_2030` | text | Option type (PLYR/TEAM/null) |
| `option_decision_2025` … `option_decision_2030` | text | Option decision |
| `is_two_way` | boolean | Two-way contract |
| `is_poison_pill` | boolean | Poison pill flag |
| `poison_pill_amount` | bigint | Poison pill amount |
| `is_no_trade` | boolean | No-trade clause |
| `is_trade_bonus` | boolean | Has trade kicker |
| `trade_bonus_percent` | numeric | Trade bonus % |
| `trade_kicker_amount_2025` | bigint | Trade kicker amount (2025) |
| `trade_kicker_display` | text | Display string (e.g., "15%") |
| `tax_2025` … `tax_2030` | bigint | Tax salary per year |
| `apron_2025` … `apron_2030` | bigint | Apron salary per year |
| `outgoing_buildup_2025` | bigint | Trade-out salary (cap) |
| `incoming_buildup_2025` | bigint | Trade-in salary (cap + kicker) |
| `incoming_salary_2025` | bigint | Incoming salary total |
| `incoming_tax_2025` | bigint | Incoming tax salary |
| `incoming_apron_2025` | bigint | Incoming apron salary |
| `refreshed_at` | timestamptz | Last refresh time |

**Refresh:** `SELECT pcms.refresh_salary_book_warehouse();`

---

### `pcms.team_salary_summary` (aliased as `team_salary_warehouse`)

**Purpose:** Team-level cap/tax/apron totals by year.

| Column | Type | Description |
|--------|------|-------------|
| `team_code` | text (PK) | Team code |
| `salary_year` | integer (PK) | Salary year |
| `cap_total` | bigint | Total cap salary |
| `tax_total` | bigint | Total tax salary |
| `apron_total` | bigint | Total apron salary |
| `mts_total` | bigint | Total MTS salary |
| `cap_rost` / `tax_rost` / `apron_rost` | bigint | Roster subtotals |
| `cap_fa` / `tax_fa` / `apron_fa` | bigint | FA / holds subtotals |
| `cap_term` / `tax_term` / `apron_term` | bigint | Dead money subtotals |
| `cap_2way` / `tax_2way` / `apron_2way` | bigint | Two-way subtotals |
| `roster_row_count` | integer | Active roster count |
| `fa_row_count` | integer | FA / holds count |
| `term_row_count` | integer | Dead money count |
| `two_way_row_count` | integer | Two-way count |
| `salary_cap_amount` | bigint | Cap constant for year |
| `tax_level_amount` | bigint | Tax line for year |
| `tax_apron_amount` | bigint | First apron for year |
| `tax_apron2_amount` | bigint | Second apron for year |
| `minimum_team_salary_amount` | bigint | MTS floor |
| `over_cap` | bigint | Amount over cap |
| `room_under_tax` | bigint | Room below tax line |
| `room_under_apron1` | bigint | Room below first apron |
| `room_under_apron2` | bigint | Room below second apron |
| `is_taxpayer` | boolean | Above tax line |
| `is_repeater_taxpayer` | boolean | Repeater status |
| `is_subject_to_apron` | boolean | Subject to apron rules |
| `apron_level_lk` | text | Apron level code |
| `refreshed_at` | timestamptz | Last refresh time |

**Refresh:** `SELECT pcms.refresh_team_salary_summary();`

---

### `pcms.exceptions_warehouse`

**Purpose:** Active trade exceptions by team.

| Column | Type | Description |
|--------|------|-------------|
| `team_exception_id` | integer (PK) | Exception ID |
| `team_code` | text | Team code |
| `team_id` | integer | Team ID |
| `salary_year` | integer | Salary year |
| `exception_type_lk` | text | Exception type code |
| `exception_type_name` | text | Exception type description |
| `effective_date` | date | Start date |
| `expiration_date` | date | Expiration date |
| `original_amount` | bigint | Original exception amount |
| `remaining_amount` | bigint | Remaining unused amount |
| `trade_exception_player_id` | integer | Related player (for TPEs) |
| `trade_exception_player_name` | text | Related player name |
| `record_status_lk` | text | Status (APPR) |
| `refreshed_at` | timestamptz | Last refresh time |

**Refresh:** `SELECT pcms.refresh_exceptions_warehouse();`

---

### `pcms.dead_money_warehouse`

**Purpose:** Waived / stretched salary (dead money) by team/year.

| Column | Type | Description |
|--------|------|-------------|
| `transaction_waiver_amount_id` | integer (PK) | Waiver amount ID |
| `team_id` | integer | Team ID |
| `team_code` | text | Team code |
| `salary_year` | integer | Salary year |
| `transaction_id` | integer | Related transaction |
| `player_id` | integer | Player ID |
| `player_name` | text | Player name |
| `contract_id` | integer | Contract ID |
| `version_number` | integer | Version number |
| `waive_date` | date | Waive date |
| `cap_value` / `cap_change_value` | bigint | Cap amounts |
| `tax_value` / `tax_change_value` | bigint | Tax amounts |
| `apron_value` / `apron_change_value` | bigint | Apron amounts |
| `mts_value` / `mts_change_value` | bigint | MTS amounts |
| `two_way_salary` | bigint | Two-way salary |
| `option_decision_lk` | text | Option decision |
| `refreshed_at` | timestamptz | Last refresh time |

**Refresh:** `SELECT pcms.refresh_dead_money_warehouse();`

---

### `pcms.cap_holds_warehouse`

**Purpose:** Cap holds / non-contract amounts (FA holds, QO, draft rights).

| Column | Type | Description |
|--------|------|-------------|
| `non_contract_amount_id` | bigint (PK) | Non-contract amount ID |
| `team_id` | integer | Team ID |
| `team_code` | text | Team code |
| `salary_year` | integer | Salary year |
| `player_id` | integer | Player ID |
| `player_name` | text | Player name |
| `amount_type_lk` | text | Amount type (FA/QO/etc) |
| `cap_amount` / `tax_amount` / `apron_amount` | bigint | Amount values |
| `fa_amount` / `qo_amount` / `rofr_amount` | bigint | FA-specific amounts |
| `rookie_scale_amount` | bigint | Rookie scale amount |
| `free_agent_designation_lk` | text | FA designation |
| `free_agent_status_lk` | text | FA status |
| `years_of_service` | integer | Years of service |
| `refreshed_at` | timestamptz | Last refresh time |

**Refresh:** `SELECT pcms.refresh_cap_holds_warehouse();`

---

### `pcms.player_rights_warehouse`

**Purpose:** Draft rights / returning rights ownership.

| Column | Type | Description |
|--------|------|-------------|
| `player_id` | integer (PK) | Player ID |
| `player_name` | text | Player name |
| `league_lk` | text | League code |
| `rights_team_id` | integer | Team holding rights |
| `rights_team_code` | text | Team code |
| `rights_kind` | text | `NBA_DRAFT_RIGHTS` or `DLG_RETURNING_RIGHTS` |
| `rights_source` | text | Source (trade or people table) |
| `source_trade_id` | integer | Trade that conveyed rights |
| `source_trade_date` | date | Trade date |
| `draft_year` / `draft_round` / `draft_pick` | integer | Draft position |
| `draft_team_id` / `draft_team_code` | integer/text | Original drafting team |
| `has_active_nba_contract` | boolean | Has current NBA contract |
| `needs_review` | boolean | Data quality flag |
| `refreshed_at` | timestamptz | Last refresh time |

**Refresh:** `SELECT pcms.refresh_player_rights_warehouse();`

---

### `pcms.draft_pick_trade_claims_warehouse`

**Purpose:** All trade-derived claims per draft pick slot (NOT deterministic ownership).

| Column | Type | Description |
|--------|------|-------------|
| `draft_year` | integer (PK) | Draft year |
| `draft_round` | integer (PK) | Draft round |
| `original_team_id` | bigint (PK) | Original team ID |
| `original_team_code` | text | Original team code |
| `trade_claims_json` | jsonb | Array of all trade claims |
| `claims_count` | integer | Number of claims |
| `distinct_to_teams_count` | integer | Distinct destination teams |
| `has_conditional_claims` | boolean | Has conditional claims |
| `has_swap_claims` | boolean | Has swap claims |
| `latest_trade_id` | bigint | Most recent trade ID |
| `latest_trade_date` | date | Most recent trade date |
| `needs_review` | boolean | Data quality flag |
| `refreshed_at` | timestamptz | Last refresh time |

**Refresh:** `SELECT pcms.refresh_draft_pick_trade_claims_warehouse();`

---

## Core Data Tables

These tables store raw PCMS imports. For UI tools, prefer warehouse tables.

### Contracts / Salaries

| Table | Description |
|-------|-------------|
| `pcms.contracts` | One row per contract |
| `pcms.contract_versions` | Amendments / versions per contract |
| `pcms.salaries` | Salary rows per contract/version/year |
| `pcms.contract_protections` | Guarantee / protection details |
| `pcms.contract_protection_conditions` | Protection condition rules |
| `pcms.contract_bonuses` | Incentive bonuses |
| `pcms.contract_bonus_criteria` | Bonus criteria |
| `pcms.contract_bonus_maximums` | Bonus caps |

### People / Teams

| Table | Description |
|-------|-------------|
| `pcms.people` | Player / person records |
| `pcms.teams` | Team records |
| `pcms.agents` | Agent records |
| `pcms.agencies` | Agency records |

### Transactions / Trades

| Table | Description |
|-------|-------------|
| `pcms.transactions` | All transaction records |
| `pcms.trades` | Trade transaction details |
| `pcms.team_transactions` | Team-facing transaction view |
| `pcms.transaction_waiver_amounts` | Waiver / dead money amounts |

### Draft

| Table | Description |
|-------|-------------|
| `pcms.draft_picks` | Draft pick base records |
| `pcms.draft_pick_summaries` | Team-year draft summaries |
| `pcms.draft_pick_ownership` | Pick ownership records |
| `pcms.draft_selections` | Actual draft selections |
| `pcms.draft_pick_trades` | Draft pick trade line items |

### Team Budget / Status

| Table | Description |
|-------|-------------|
| `pcms.team_budget_snapshots` | Authoritative cap/tax/apron totals per team/year |
| `pcms.team_exceptions` | Team exceptions |
| `pcms.team_exception_usage` | Exception usage records |
| `pcms.tax_team_status` | Taxpayer / repeater / apron status |
| `pcms.team_tax_summary_snapshots` | Historical tax summaries |
| `pcms.team_two_way_capacity` | Two-way roster capacity |
| `pcms.non_contract_amounts` | Cap holds / non-contract amounts |
| `pcms.apron_constraints` | Apron constraint records |

### Other

| Table | Description |
|-------|-------------|
| `pcms.lookups` | Lookup code → description mappings |
| `pcms.depth_charts` | Depth chart records |
| `pcms.injury_reports` | Injury reports |
| `pcms.medical_intel` | Medical intelligence |
| `pcms.scouting_reports` | Scouting reports |
| `pcms.draft_rankings` | Draft rankings |
| `pcms.waiver_priority` | Waiver priority |
| `pcms.waiver_priority_ranks` | Waiver priority rankings |
| `pcms.two_way_daily_statuses` | Two-way day tracking |
| `pcms.two_way_contract_utility` | Two-way utility calcs |
| `pcms.two_way_game_utility` | Two-way game utility |
| `pcms.ledger_entries` | Cap ledger entries |
| `pcms.payment_schedules` | Payment schedule records |
| `pcms.payment_schedule_details` | Payment schedule details |
| `pcms.synergy_instat_links` | External ID links |
| `pcms.audit_logs` | Audit trail |

---

## System / CBA Constants

### `pcms.league_system_values`

CBA constants by league and salary year.

| Column | Type | Description |
|--------|------|-------------|
| `league_lk` | text (PK) | League code (NBA) |
| `salary_year` | integer (PK) | Salary year |
| `salary_cap_amount` | bigint | Salary cap |
| `tax_level_amount` | bigint | Tax line |
| `tax_apron_amount` | bigint | First apron |
| `tax_apron2_amount` | bigint | Second apron |
| `minimum_team_salary_amount` | bigint | MTS floor |
| `average_salary_amount` | bigint | Average player salary |
| `bi_annual_amount` | bigint | Bi-annual exception |
| `mid_level_amount` | bigint | MLE amount |
| `mid_level_apron_amount` | bigint | Taxpayer MLE |
| `room_exception_amount` | bigint | Room exception |
| `minimum_annual_amount` | bigint | Veteran minimum |
| `tpe_dollar_allowance` | bigint | TPE matching allowance |
| `days_in_season` | integer | Days in season (174) |

### `pcms.league_tax_rates`

Luxury tax bracket rates.

| Column | Type | Description |
|--------|------|-------------|
| `salary_year` | integer (PK) | Salary year |
| `league_lk` | text (PK) | League code |
| `bracket_number` | integer (PK) | Bracket (1-6) |
| `lower_limit` | bigint | Bracket floor |
| `upper_limit` | bigint | Bracket ceiling (NULL = infinite) |
| `tax_rate_non_repeater` | numeric | Non-repeater rate |
| `tax_rate_repeater` | numeric | Repeater rate |
| `base_charge_non_repeater` | bigint | Base charge (non-repeater) |
| `base_charge_repeater` | bigint | Base charge (repeater) |

### `pcms.league_salary_scales`

Minimum salary by years of service.

| Column | Type | Description |
|--------|------|-------------|
| `salary_year` | integer (PK) | Salary year |
| `years_of_service` | integer (PK) | YOS (0-10+) |
| `minimum_salary_amount` | bigint | Minimum salary |

### `pcms.rookie_scale_amounts`

Rookie scale salary by pick and year.

| Column | Type | Description |
|--------|------|-------------|
| `draft_year` | integer (PK) | Draft year |
| `draft_pick` | integer (PK) | Pick number |
| `contract_year` | integer (PK) | Contract year (1-4) |
| `salary_amount` | bigint | Salary amount |
| `option_year` | boolean | Is option year |

---

## Views

### `pcms.vw_active_contract_versions`

Active contract + latest version per player.

### `pcms.vw_salary_pivot_2024_2030`

Wide salary pivot by contract/version.

### `pcms.vw_y_warehouse`

Forward-looking player warehouse (2025-2030). Source for `salary_book_warehouse`.

### `pcms.salary_book_yearly`

Yearly unpivot of salary_book_warehouse (one row per player/year).

---

## Functions

### Trade Math Primitives

| Function | Description |
|----------|-------------|
| `pcms.fn_luxury_tax_amount(salary_year, over_tax_amount, is_repeater)` | Calculate luxury tax payment |
| `pcms.fn_team_luxury_tax(team_code, salary_year)` | Team's luxury tax for a year |
| `pcms.fn_all_teams_luxury_tax(salary_year)` | All teams' luxury tax |
| `pcms.fn_tpe_trade_math(team_code, salary_year, traded_ids, replacement_ids, tpe_type)` | TPE trade matching math |
| `pcms.fn_trade_plan_tpe(...)` | TPE trade planner |
| `pcms.fn_post_trade_apron(...)` | Post-trade apron calculation |

### Warehouse Refresh

| Function | Description |
|----------|-------------|
| `pcms.refresh_salary_book_warehouse()` | Refresh salary book cache |
| `pcms.refresh_team_salary_summary()` | Refresh team salary cache |
| `pcms.refresh_exceptions_warehouse()` | Refresh exceptions cache |
| `pcms.refresh_dead_money_warehouse()` | Refresh dead money cache |
| `pcms.refresh_cap_holds_warehouse()` | Refresh cap holds cache |
| `pcms.refresh_player_rights_warehouse()` | Refresh player rights cache |
| `pcms.refresh_draft_pick_trade_claims_warehouse()` | Refresh draft pick claims |
| `pcms.refresh_salary_book_percentiles()` | Refresh salary percentiles |

---

## Related Documentation

- `SALARY_BOOK.md` — Canonical interpretation of contract/salary fields
- `AGENTS.md` — Import pipeline architecture
- `queries/README.md` — SQL assertion tests
- `reference/warehouse/AGENTS.md` — Sean workbook export reference
- `reference/warehouse/specs/` — Detailed worksheet specs
