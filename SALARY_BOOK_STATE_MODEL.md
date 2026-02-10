# Salary Book State Model — Official, Live, Scenario

**Status:** Draft spec (2026-02-06)

This doc defines a coherent system-of-record for handling:
- official PCMS data
- external reporting (Spotrac, etc.)
- pre-official cap implications
- manual what-if modeling

It replaces ambiguous terminology and avoids drift between UI-only tables and warehouse truth.

---

## 1) Canonical terms (do not mix these)

1. **Official**
   - Data from current `pcms.*` ingest + warehouse refreshes.
   - Authoritative for published/internal reporting.

2. **Report**
   - Raw external source row (Spotrac, etc.).
   - Immutable evidence record.

3. **Interpretation**
   - Structured event parsed from one report (`SIGNED`, `WAIVED`, etc.).
   - Includes confidence and review status.

4. **State**
   - A computed dataset used by tools.
   - Types: `OFFICIAL`, `LIVE`, `SCENARIO`.

---

## 2) Goals

- Keep Official truth unchanged and reproducible.
- Support fast, coherent “what changed if this report is true?” analysis.
- Ensure every Salary Book number (rows, KPIs, sidebars) updates from one consistent state source.
- Keep assumptions explicit and auditable.
- Avoid parallel ad-hoc logic in Rails.

### Non-goals (v1)

- Perfect NLP of all transaction prose.
- Automatic support for every non-cap event (injuries/fines/suspensions can be informational only).

---

## 3) Design principles

1. **SQL owns state math.** Rails selects a state; Postgres returns coherent rows.
2. **State is materialized.** No expensive event replay per request.
3. **Auditable lineage.** Every derived row maps back to interpretation(s) and assumptions.
4. **Official precedence.** When PCMS lands official transactions, Live interpretations reconcile and retire.
5. **Single lens switch in UI.** No per-widget forks.

---

## 4) Proposed schema (new tables)

## A. External evidence

### `pcms.market_reports`
Raw source records.

Required fields (v1):
- `report_id uuid pk`
- `source_lk text not null` (`SPOTRAC`, later others)
- `source_item_id text not null` (id from source)
- `reported_at timestamptz`
- `effective_date date`
- `raw_action text`
- `raw_description text`
- `raw_payload_json jsonb`
- `ingested_at timestamptz default now()`
- unique `(source_lk, source_item_id)`

### `pcms.market_interpretations`
Structured, typed events parsed from reports.

Required fields (v1):
- `interpretation_id uuid pk`
- `report_id uuid not null references pcms.market_reports(report_id)`
- `event_type_lk text not null`
  - initial enum: `SIGNED`, `WAIVED`, `TRADED`, `OPTION_EXERCISED`, `OPTION_DECLINED`
- `player_id integer` (nullable until resolved)
- `player_name_reported text`
- `from_team_code text`
- `to_team_code text`
- `contract_shape_lk text` (`ROS`, `TEN_DAY`, `TWO_WAY`, `STANDARD`, `UNKNOWN`)
- `years integer`
- `total_amount bigint`
- `option_meta_json jsonb`
- `confidence_score numeric(4,3) not null`
- `review_status_lk text not null`
  - `AUTO_ACCEPTED`, `NEEDS_REVIEW`, `REJECTED`
- `parser_version text not null`
- `notes text`
- `created_at timestamptz default now()`
- `updated_at timestamptz default now()`

### `pcms.market_reconciliations`
Links interpretations to official PCMS transactions when available.

Required fields (v1):
- `interpretation_id uuid not null references pcms.market_interpretations(interpretation_id)`
- `transaction_id integer not null references pcms.transactions(transaction_id)`
- `matched_at timestamptz default now()`
- `match_confidence numeric(4,3)`
- `match_method_lk text`
- primary key `(interpretation_id, transaction_id)`

---

## B. State definitions

### `pcms.salary_states`
Defines a selectable state.

Required fields (v1):
- `state_id uuid pk`
- `state_type_lk text not null` (`OFFICIAL`, `LIVE`, `SCENARIO`)
- `state_name text not null`
- `as_of_date date not null`
- `assumption_profile_lk text not null` (`STRICT`, `BALANCED`, `AGGRESSIVE`)
- `base_official_refreshed_at timestamptz not null`
- `created_by text`
- `is_active boolean default true`
- `created_at timestamptz default now()`
- `updated_at timestamptz default now()`

### `pcms.salary_state_interpretations`
Which interpretations are included in a state.

Required fields (v1):
- `state_id uuid not null references pcms.salary_states(state_id)`
- `interpretation_id uuid not null references pcms.market_interpretations(interpretation_id)`
- `inclusion_lk text not null` (`INCLUDE`, `EXCLUDE`, `WATCH`)
- `assumption_override_json jsonb`
- primary key `(state_id, interpretation_id)`

### `pcms.salary_state_overrides`
Manual scenario-only adjustments (explicit human edits).

Required fields (v1):
- `override_id uuid pk`
- `state_id uuid not null references pcms.salary_states(state_id)`
- `entity_type_lk text not null` (`PLAYER`, `TEAM`, `DEAD_MONEY`, `EXCEPTION`)
- `entity_id text not null`
- `override_type_lk text not null`
- `override_json jsonb not null`
- `created_by text`
- `created_at timestamptz default now()`

### `pcms.salary_state_actions`
Compiled, atomic effects used to build state warehouses.

Required fields (v1):
- `state_id uuid not null references pcms.salary_states(state_id)`
- `action_seq integer not null`
- `source_kind_lk text not null` (`INTERPRETATION`, `OVERRIDE`)
- `source_id uuid`
- `action_type_lk text not null`
  - examples: `SET_PLAYER_TEAM`, `SET_PLAYER_CAP_YEAR`, `ADD_DEAD_MONEY`, `REMOVE_DEAD_MONEY`
- `player_id integer`
- `team_code text`
- `salary_year integer`
- `cap_delta bigint`
- `tax_delta bigint`
- `apron_delta bigint`
- `action_payload_json jsonb`
- primary key `(state_id, action_seq)`

---

## C. State warehouses (tool-facing)

These mirror existing warehouse shapes so Rails can switch by state without rewriting all view logic.

### `pcms.salary_book_warehouse_state`
- Same core columns as `pcms.salary_book_warehouse`
- Added:
  - `state_id uuid not null`
  - `provenance_lk text` (`OFFICIAL`, `INTERPRETED`, `MIXED`)
  - `confidence_score numeric(4,3)`
- PK: `(state_id, player_id)`

### `pcms.team_salary_warehouse_state`
- Same core columns as `pcms.team_salary_warehouse`
- Added:
  - `state_id uuid not null`
  - `official_delta_cap_total bigint`
  - `official_delta_tax_total bigint`
  - `official_delta_apron_total bigint`
  - `state_confidence_score numeric(4,3)`
- PK: `(state_id, team_code, salary_year)`

### `pcms.dead_money_warehouse_state`
- Same core columns as `pcms.dead_money_warehouse`
- Added `state_id`, provenance/confidence
- PK: `(state_id, transaction_waiver_amount_id, salary_year)` or synthetic key if provisional rows exist

---

## 5) Rule model

## Inclusion filter (Live)
Only cap-relevant interpretations apply by default:
- `SIGNED`
- `WAIVED`
- `TRADED`
- `OPTION_EXERCISED`
- `OPTION_DECLINED`

Everything else remains report-only unless explicitly modeled later.

## Confidence + review
- `AUTO_ACCEPTED`: high confidence parse + player/team resolved
- `NEEDS_REVIEW`: ambiguous parse or unresolved identity/team
- `REJECTED`: parser/operator rejected

Live state includes only `AUTO_ACCEPTED` by default.

## Precedence
1. `OFFICIAL` rows are baseline.
2. Included interpretations modify baseline.
3. Scenario overrides (if any) apply last.
4. Reconciled interpretations are retired from active Live state once official transaction is present.

## Assumption profiles
- **STRICT**: apply only deterministic effects; no inferred dollar amounts unless explicit.
- **BALANCED**: allow deterministic CBA inferences (e.g., ROS/10-day estimated from min scale + proration helpers).
- **AGGRESSIVE**: broader inferred assumptions for exploratory what-if work.

---

## 6) Compiler contract (SQL functions)

## `pcms.refresh_market_interpretations()`
- Reads `market_reports`
- Applies parser rules
- Upserts `market_interpretations`

## `pcms.refresh_market_reconciliations(p_days_window int default 7)`
- Attempts to match interpretations to `pcms.transactions`
- Upserts `market_reconciliations`
- Marks interpretations as reconciled/stale where appropriate

## `pcms.refresh_salary_state(p_state_id uuid)`
- Rebuilds one state deterministically:
  1. snapshot official baseline
  2. compile included interpretations + overrides to `salary_state_actions`
  3. materialize `*_warehouse_state` rows

## `pcms.refresh_live_salary_state()`
- Convenience wrapper for the active `LIVE` state id

---

## 7) Web integration (Salary Book)

Goal: one lens switch, no math duplication in Rails.

### Controller pattern
- Add state selector param/signal: `state=official|live|<scenario_uuid>`
- Data-source helper maps:
  - Official → existing `pcms.salary_book_warehouse`, `pcms.team_salary_warehouse`, `pcms.dead_money_warehouse`
  - Non-official → corresponding `*_warehouse_state` filtered by `state_id`

### UI pattern
- Add commandbar lens toggle:
  - `Official`
  - `Live`
  - (later) `Scenario`
- Optional badges on affected rows: `Live` + confidence/provenance indicators.

---

## 8) Handling current `ui_*` tables

Current tables:
- `pcms.ui_projections`
- `pcms.ui_projected_salaries`
- `pcms.ui_projection_overrides`

They are empty and overlap with this state model, but are less explicit about evidence/reconciliation.

### Decision
Adopt this spec as canonical and **deprecate** `ui_*` tables.

### Migration path
1. Build `market_*`, `salary_states`, `salary_state_*`, and `*_warehouse_state` tables.
2. Wire Salary Book to state lens.
3. Verify no app dependencies on `ui_*` tables.
4. Drop `ui_*` tables in a dedicated migration.

---

## 9) Assertions to add

- Schema presence + required indexes for new tables.
- `OFFICIAL` state parity checks:
  - `salary_book_warehouse_state` == `salary_book_warehouse`
  - `team_salary_warehouse_state` == `team_salary_warehouse`
- Reconciliation correctness:
  - reconciled interpretations excluded from active Live state unless explicitly pinned.
- Determinism:
  - same inputs + state config produce same warehouse_state rows.

---

## 10) Why this is coherent

- One vocabulary.
- One state compiler.
- One lens switch in UI.
- Official truth preserved.
- External intel becomes structured, reviewable, and mathematically actionable.
- Scenario planning and external news flow share the same architecture instead of diverging systems.
