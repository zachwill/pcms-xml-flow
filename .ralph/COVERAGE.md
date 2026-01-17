# PCMS Coverage: Fill Missing Tables

Reference docs:
- `TODO.md` — Section 7 (priorities) and Section 8 (coverage audit)
- `SCHEMA.md` — Target table definitions
- `SEAN.md` — Analyst requirements and implementation plan
- `import_pcms_data.flow/transaction_waiver_amounts.inline_script.ts` — Import script pattern
- `migrations/006_team_transactions.sql` — Team transactions table (just created)

## Context

This agent fills coverage gaps identified in TODO.md Section 8:

1. **team_transactions.json** — 80,130 records, produced by lineage but NOT imported
2. **Contract sub-tables** — nested in contracts.json but not normalized to their own tables

---

## Phase 1: Team Transactions (the "top missing piece")

Source: `.shared/nba_pcms_full_extract/team_transactions.json` (80,130 records)

### JSON Structure (from source file)

```json
{
  "team_transaction_id": 11138,
  "team_id": 1610612761,
  "team_code": null,              // NOT in source - must add from lookups
  "team_transaction_type_lk": "ADJCH",
  "team_ledger_seqno": 2,
  "transaction_date": "2012-07-17",
  "cap_adjustment": null,
  "cap_hold_adjustment": 1,
  "tax_adjustment": null,
  "tax_apron_adjustment": null,
  "mts_adjustment": null,
  "protection_count_flg": null,
  "comments": null,
  "record_status_lk": "DEL",
  "create_date": "2015-01-22T16:18:25.367-05:00",
  "last_change_date": "2015-03-07T03:43:15.927-05:00",
  "record_change_date": "2015-03-07T03:43:15.927-05:00"
}
```

### Target Table (from migration 006)

```sql
pcms.team_transactions (
  team_transaction_id integer PRIMARY KEY,
  team_id integer,
  team_code text,                    -- derived from lookups.json
  team_transaction_type_lk text,
  team_ledger_seqno integer,
  transaction_date date,
  cap_adjustment bigint,
  cap_hold_adjustment integer,
  tax_adjustment bigint,
  tax_apron_adjustment bigint,
  mts_adjustment bigint,
  protection_count_flg boolean,
  comments text,
  record_status_lk text,
  created_at timestamp with time zone,  -- from create_date
  updated_at timestamp with time zone,  -- from last_change_date
  record_changed_at timestamp with time zone,  -- from record_change_date
  ingested_at timestamp with time zone DEFAULT now()
)
```

### Tasks

- [x] Create migration `migrations/006_team_transactions.sql`

- [x] Create import script `import_pcms_data.flow/team_transactions.inline_script.ts`
  
  **Follow the pattern in `transaction_waiver_amounts.inline_script.ts`:**
  
  1. Import SQL from bun, readdir from node:fs/promises
  2. Add helper functions: `toIntOrNull`, `toBoolOrNull`, `resolveBaseDir`
  3. Export `main(dry_run = false, extract_dir = "./shared/pcms")`
  4. Build `teamCodeMap` from `lookups.json` (see pattern below)
  5. Read `team_transactions.json`
  6. Map each record to a row object with proper field mapping:
     - `team_transaction_id` → team_transaction_id (required, skip if null)
     - `team_id` → team_id
     - Derive `team_code` from teamCodeMap.get(team_id)
     - `create_date` → created_at
     - `last_change_date` → updated_at
     - `record_change_date` → record_changed_at
  7. Filter out rows where `team_transaction_id` is null
  8. Batch upsert (BATCH_SIZE = 500) with ON CONFLICT (team_transaction_id) DO UPDATE
  9. Return standard result object: `{ dry_run, started_at, finished_at, tables: [...], errors: [...] }`

  **Team code lookup pattern:**
  ```typescript
  const lookups: any = await Bun.file(`${baseDir}/lookups.json`).json();
  const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
  const teamCodeMap = new Map<number, string>();
  for (const t of teamsData) {
    if (t.team_id && t.team_code) {
      teamCodeMap.set(t.team_id, t.team_code);
    }
  }
  ```

- [ ] Create lock file `import_pcms_data.flow/team_transactions.inline_script.lock`
  
  **Exact content (no extra whitespace):**
  ```
  { "dependencies": {} }
  //bun.lock
  ```

- [ ] Update `import_pcms_data.flow/flow.yaml`
  
  **Add step 's' before step 'l' (finalize).** Insert after step 'p':
  
  ```yaml
      - id: s
        summary: Team Transactions
        value:
          type: rawscript
          content: '!inline team_transactions.inline_script.ts'
          input_transforms:
            dry_run:
              type: javascript
              expr: flow_input.dry_run
            extract_dir:
              type: javascript
              expr: results.a.extract_dir ?? './shared/pcms'
          lock: '!inline team_transactions.inline_script.lock'
          language: bun
  ```
  
  **Also update finalize step summaries array** to include results.s:
  
  Current (missing m,n,o,p,s):
  ```yaml
  expr: >-
    [results.b, results.r, results.c, results.d, results.e, results.f,
    results.g, results.h, results.q, results.i, results.j, results.k]
  ```
  
  Updated:
  ```yaml
  expr: >-
    [results.b, results.r, results.c, results.d, results.e, results.f,
    results.g, results.h, results.q, results.i, results.j, results.k,
    results.m, results.n, results.o, results.p, results.s]
  ```

- [ ] Update `SCHEMA.md` — Add team_transactions table definition (copy from migration 006)

### Validation

After completing all tasks:
```bash
# Run migration
psql $POSTGRES_URL -f migrations/006_team_transactions.sql

# Test import locally
POSTGRES_URL="postgres://..." bun run import_pcms_data.flow/team_transactions.inline_script.ts

# Verify count
psql $POSTGRES_URL -c "SELECT COUNT(*) FROM pcms.team_transactions;"
# Expected: ~80,130

# Check transaction types
psql $POSTGRES_URL -c "SELECT team_transaction_type_lk, COUNT(*) FROM pcms.team_transactions GROUP BY 1 ORDER BY 2 DESC;"
# Expected: ADJCH ~80,123, ADJTM ~5, WADJT ~2
```

---

## Phase 2: Contract Sub-Tables (Future)

These tables exist in SCHEMA.md but are not populated. Data exists inside `contracts.json` as nested structures.

**Defer until Phase 1 is complete and validated.**

### 2a. Contract Bonus Maximums
- Table: `pcms.contract_bonus_maximums`
- Nested in: `contracts[].versions[].bonus_maximums.bonus_maximum[]`
- Estimated: ~159 records

### 2b. Contract Protections
- Table: `pcms.contract_protections`
- Nested in: `contracts[].versions[].protections.protection[]`
- Estimated: ~8,000 records

### 2c. Contract Protection Conditions
- Table: `pcms.contract_protection_conditions`
- Nested in: `protection[].protection_conditions.protection_condition[]`
- Estimated: ~12,000 records

### 2d. Payment Schedule Details
- Table: `pcms.payment_schedule_details`
- Nested in: `salaries[].payment_schedules[].schedule_details.schedule_detail[]`
- Estimated: ~20,000 records

---

## Commit Messages

Use these commit message formats:
- `feat: add team_transactions import script`
- `feat: add team_transactions to flow.yaml`
- `docs: add team_transactions to SCHEMA.md`
