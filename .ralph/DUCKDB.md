# DuckDB Migration: Script Checklist

## Reference Documentation

**Read these before writing scripts:**
- `DUCKDB_MIGRATION.md` — Migration plan, domain sketches, upsert strategies
- `docs/duckdb-friendly.md` — Friendly SQL: QUALIFY, FROM-first, EXCLUDE, trailing commas
- `docs/duckdb-functions.md` — Window functions, aggregates, date/string functions
- `docs/duckdb-json.md` — JSON reading, extraction, `json_transform()`, UNNEST
- `SCHEMA.md` — Target Postgres table definitions
- `AGENTS.md` — JSON file inventory with record counts

---

## Context

This agent creates DuckDB scripts for `duckdb_test.flow/` that replace the current TypeScript import scripts. The lineage step (Bun) produces clean JSON with:
- snake_case keys (match DB columns directly)
- Real nulls (not XML nil objects)
- Flattened structures where possible

**DuckDB advantages:**
- Vectorized JSON reads
- `QUALIFY` for clean deduplication (no nested subquery)
- Dot notation for nested JSON access
- Native Postgres attachment

**Hard-coded JSON path:** `./shared/pcms/nba_pcms_full_extract/`

---

## Windmill DuckDB Syntax

```sql
-- result_collection=last_statement_all_rows

ATTACH '$res:f/env/postgres' AS pg (TYPE postgres);
SET TimeZone='UTC';
```

---

## Key DuckDB Patterns

### 1. Team Lookup View

```sql
CREATE OR REPLACE TEMP VIEW v_teams AS
SELECT
  t.team_id::BIGINT AS team_id,
  COALESCE(t.team_code, t.team_name_short) AS team_code,
FROM read_json_auto('./shared/pcms/nba_pcms_full_extract/lookups.json') AS lookups,
UNNEST(lookups.lk_teams.lk_team) AS t;
```

### 2. Deduplication with QUALIFY (preferred)

```sql
-- ✅ Use QUALIFY (cleaner, no nested subquery)
SELECT * EXCLUDE(rn)
FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY pk_col ORDER BY record_changed_at DESC NULLS LAST
  ) AS rn
  FROM source
)
QUALIFY rn = 1;

-- Alternative: keep rn in subquery (if you need it for debugging)
SELECT * EXCLUDE(rn)
FROM (
  SELECT *, ROW_NUMBER() OVER (...) AS rn FROM source
) WHERE rn = 1;
```

### 3. JSON Access Patterns

```sql
-- Dot notation (when read_json_auto infers structure)
SELECT player.first_name, player.team_id FROM players;

-- Path extraction (when structure is ambiguous)
SELECT j->>'$.first_name', j->>'$.team_id' FROM (SELECT * FROM read_json('file.json'));

-- Nested arrays with UNNEST
SELECT c.contract_id, v.version_number
FROM read_json_auto('contracts.json') c,
UNNEST(c.versions) AS v;

-- Deep nesting: chain UNNEST
SELECT c.contract_id, v.version_id, s.salary_id
FROM read_json_auto('contracts.json') c,
UNNEST(c.versions) AS v,
UNNEST(v.salaries) AS s;
```

### 4. Type Casting

```sql
-- Safe casts (return NULL on failure)
TRY_CAST(col AS INTEGER)
TRY_CAST(col AS DATE)
TRY_CAST(col AS TIMESTAMP)

-- Direct casts (error on failure)
col::INTEGER
col::BIGINT
col::VARCHAR
```

### 5. Upsert into Postgres

```sql
-- INSERT BY NAME with ON CONFLICT
INSERT INTO pg.pcms.people BY NAME (
  SELECT * FROM v_deduped
)
ON CONFLICT (person_id) DO UPDATE SET
  first_name = EXCLUDED.first_name,
  last_name = EXCLUDED.last_name,
  ingested_at = EXCLUDED.ingested_at;
```

### 6. Summary with FILTER

```sql
SELECT
  'people_identity' AS step,
  count(*) AS total_rows,
  count(*) FILTER (WHERE team_id IS NOT NULL) AS with_team,
  now() AS finished_at;
```

### 7. Friendly SQL Features

```sql
-- Trailing commas allowed
SELECT
  col1,
  col2,
  col3,  -- ← OK
FROM table;

-- FROM-first (SELECT optional for simple queries)
FROM my_table WHERE x > 10 ORDER BY y LIMIT 5;

-- Reuse aliases in same SELECT
SELECT
  price * qty AS subtotal,
  subtotal * 0.1 AS tax,
  subtotal + tax AS total
FROM line_items;

-- EXCLUDE columns from SELECT *
SELECT * EXCLUDE (internal_col, rn) FROM my_cte;
```

---

## Script Checklist

Scripts organized by dependency order. Each should be 200-600 LOC (max 800 for complex ones).

### Phase 1: Foundation

- [x] **1. lookups.duckdb.sql** — Reference data (must run first)
  
  **Tables:** `pcms.lookups`, `pcms.teams`
  
  **Source:** `lookups.json` (43 lookup types, ~100 teams)
  
  **Key logic:**
  - Nested structure: `lk_<type>.lk_<type>[]` (e.g., `lk_teams.lk_team[]`)
  - Flatten all lookup types to `(lookup_type, lookup_code, description, ...)`
  - Teams get full columns
  - Dedupe by `(lookup_type, lookup_code)` for lookups, `team_id` for teams
  
  **Lookup types:** `lk_action_codes`, `lk_bonus_types`, `lk_contract_types`, `lk_exception_types`, `lk_leagues`, `lk_teams`, `lk_transaction_types`, ... (43 total)

---

### Phase 2: People & Identity

- [x] **2. people_identity.duckdb.sql** — People, agencies, agents
  
  **Tables:** `pcms.people`, `pcms.agencies`, `pcms.agents`
  
  **Sources:** 
  - `players.json` (14,421) → `pcms.people`
  - `lookups.json` → agencies from `lk_agencies.lk_agency[]`
  - `lookups.json` → agents from `lk_agents.lk_agent[]`
  
  **Key logic:**
  - `player_id` → `person_id` rename
  - Team code joins for: `team_code`, `draft_team_code`, `dlg_team_code`, `dlg_returning_rights_team_code`
  - Dedupe by `person_id`

---

### Phase 3: Draft Assets

- [x] **3. draft_assets.duckdb.sql** — Draft picks and summaries
  
  **Tables:** `pcms.draft_picks`, `pcms.draft_pick_summaries`
  
  **Sources:**
  - `draft_picks.json` (1,169) — DLG/WNBA only!
  - `draft_pick_summaries.json` (450)
  - `players.json` — Generate NBA picks from player draft fields
  
  **Key logic:**
  - PCMS doesn't include NBA picks—generate from players:
    ```sql
    draft_pick_id = draft_year * 100000 + draft_round * 1000 + draft_pick
    ```
  - Union PCMS picks + generated NBA picks
  - Dedupe by `(draft_year, round, pick_number_int, league_lk)`
  - Team code joins for `original_team_code`, `current_team_code`

---

### Phase 4: League Configuration

- [x] **4. league_config.duckdb.sql** — System values, scales, amounts
  
  **Tables:** 
  - `pcms.league_system_values`
  - `pcms.rookie_scale_amounts`
  - `pcms.non_contract_amounts`
  - `pcms.league_salary_scales`
  - `pcms.league_salary_cap_projections`
  - `pcms.league_tax_rates`
  - `pcms.apron_constraints`
  
  **Sources:** `yearly_system_values.json`, `rookie_scale_amounts.json`, `non_contract_amounts.json`, `yearly_salary_scales.json`, `cap_projections.json`
  
  **Key logic:**
  - Small tables with compound keys
  - `league_system_values` PK: `(league_lk, salary_year)`
  - `rookie_scale_amounts` PK: `(salary_year, pick_number, league_lk)`

---

### Phase 5: Contracts (Complex)

- [x] **5. contracts.duckdb.sql** — Contracts and nested tables
  
  **Tables:**
  - `pcms.contracts`
  - `pcms.contract_versions`
  - `pcms.salaries`
  - `pcms.contract_bonuses`
  - `pcms.contract_bonus_criteria`
  - `pcms.contract_bonus_maximums`
  - `pcms.contract_protections`
  - `pcms.contract_protection_conditions`
  - `pcms.payment_schedules`
  - `pcms.payment_schedule_details`
  
  **Source:** `contracts.json` (8,071 contracts, deeply nested)
  
  **Nesting structure:**
  ```
  contracts[]
    .versions[]
      .salaries[]
        .bonus_maximums.bonus_maximum[]
        .payment_schedules.payment_schedule[]
          .schedule_details.schedule_detail[]
      .bonuses.bonus[]
        .bonus_criteria.bonus_criterion[]
      .protections.protection[]
        .protection_conditions.protection_condition[]
  ```
  
  **Key logic:**
  - Multiple UNNEST chains for each nesting level
  - Team code joins for `team_code`, `sign_and_trade_to_team_code`
  - May be 600-800 LOC due to complexity

---

### Phase 6: Team Exceptions

- [x] **6. team_exceptions.duckdb.sql** — Exceptions and usage
  
  **Tables:** `pcms.team_exceptions`, `pcms.team_exception_usage`
  
  **Source:** `team_exceptions.json` (nested)
  
  **Key logic:**
  - Exceptions contain nested usage arrays
  - Dedupe by `team_exception_id` and `team_exception_detail_id`
  - Team code joins

---

### Phase 7: Transactions (Large)

- [ ] **7. transactions.duckdb.sql** — Trades, transactions, ledger
  
  **Tables:**
  - `pcms.trades`
  - `pcms.trade_teams`
  - `pcms.trade_team_details`
  - `pcms.trade_groups`
  - `pcms.transactions`
  - `pcms.ledger_entries`
  - `pcms.transaction_waiver_amounts`
  
  **Sources:**
  - `trades.json` (1,731, nested)
  - `transactions.json` (232,417) — **LARGEST**
  - `ledger.json` (50,713, ~15 null team_id to filter)
  - `transaction_waiver_amounts.json`
  
  **Key logic:**
  - Filter ledger: `WHERE team_id IS NOT NULL`
  - Dedupe ledger by `transaction_ledger_entry_id`
  - Dedupe transactions by `transaction_id`
  - Trades have nested: `trade_teams[]`, `trade_groups[]`, `trade_team_details[]`
  - **Important:** `ledger_entries` uses NUMERIC PKs, not INTEGER

---

### Phase 8: Team Financials

- [ ] **8. team_financials.duckdb.sql** — Budgets, tax, waiver priority
  
  **Tables:**
  - `pcms.team_budget_snapshots`
  - `pcms.team_tax_summary_snapshots`
  - `pcms.tax_team_status`
  - `pcms.waiver_priority`
  - `pcms.waiver_priority_ranks`
  - `pcms.team_transactions`
  
  **Sources:**
  - `team_budgets.json` (nested by team → year)
  - `waiver_priority.json`
  - `team_transactions.json` (80,130)
  
  **Key logic:**
  - `team_transactions` is already clean (straightforward upsert)
  - Waiver priority has header/detail structure
  - Team code joins throughout

---

### Phase 9: Two-Way

- [ ] **9. two_way.duckdb.sql** — Daily statuses and utility
  
  **Tables:**
  - `pcms.two_way_daily_statuses`
  - `pcms.two_way_contract_utility`
  - `pcms.two_way_game_utility`
  - `pcms.team_two_way_capacity`
  
  **Sources:**
  - `two_way.json` (28,659)
  - `two_way_utility.json` (nested)
  
  **Key logic:**
  - May have hyphenated keys from XML (`daily-status`)
  - Use `json_extract` if `read_json_auto` struggles
  - Composite PK: `(player_id, status_date)`
  - Multiple team_code joins

---

### Phase 10: Flow Integration

- [ ] **10. flow.yaml** — Create flow definition
  
  Create `duckdb_test.flow/flow.yaml` with scripts in order:
  1. lookups → 2. people_identity → 3. draft_assets → 4. league_config
  5. contracts → 6. team_exceptions → 7. transactions → 8. team_financials → 9. two_way

---

## Validation Checklist

| Script | Table | Expected Rows |
|--------|-------|---------------|
| lookups | pcms.lookups | ~500 |
| lookups | pcms.teams | ~100 |
| people_identity | pcms.people | 14,421 |
| draft_assets | pcms.draft_picks | ~2,500 (PCMS + generated NBA) |
| draft_assets | pcms.draft_pick_summaries | 450 |
| contracts | pcms.contracts | 8,071 |
| transactions | pcms.transactions | 232,417 |
| transactions | pcms.ledger_entries | ~50,698 |
| team_financials | pcms.team_transactions | 80,130 |
| two_way | pcms.two_way_daily_statuses | 28,659 |

---

## Commit Format

```
feat(duckdb): add lookups.duckdb.sql
feat(duckdb): add people_identity.duckdb.sql
feat(duckdb): create flow.yaml with all scripts
```
