# TODO / Known Issues — PCMS XML Flow

Last updated: 2026-01-17

This file is intentionally **kept current** so it doesn’t become stale. At this point the “critical path” work to get a full end-to-end import running has been completed; what remains are optional improvements and a few accepted source-data limitations.

---

## ✅ Completed (no longer TODO)

### Team Code migration + imports
- **Migration:** `migrations/003_team_code_and_draft_picks.sql`
  - Renamed `pcms.teams.team_name_short` → `team_code`
  - Added `team_code` columns to many tables + indexes
  - Added `player_id` to `pcms.draft_picks`
- **Import scripts updated to populate `team_code` on new inserts** (team_id → team_code map from `lookups.json`)
  - `import_pcms_data.flow/players_&_people.inline_script.ts`
  - `import_pcms_data.flow/contracts,_versions,_bonuses_&_salaries.inline_script.ts`
  - `import_pcms_data.flow/trades,_transactions_&_ledger.inline_script.ts`
  - `import_pcms_data.flow/draft_picks.inline_script.ts`
  - `import_pcms_data.flow/team_exceptions_&_usage.inline_script.ts`
  - `import_pcms_data.flow/team_budgets.inline_script.ts`
  - `import_pcms_data.flow/system_values,_rookie_scale_&_nca.inline_script.ts`
  - `import_pcms_data.flow/transaction_waiver_amounts.inline_script.ts`
  - `import_pcms_data.flow/two-way_daily_statuses.inline_script.ts`
  - `import_pcms_data.flow/two-way_utility.inline_script.ts`
  - `import_pcms_data.flow/waiver_priority_&_ranks.inline_script.ts`
  - `import_pcms_data.flow/lookups.inline_script.ts` (teams now prefer `team_code`)

### NBA draft picks generation
- **Problem:** PCMS `draft_picks.json` contains only DLG/WNBA picks.
- **Fix:** `import_pcms_data.flow/generate_nba_draft_picks.inline_script.ts`
  - Generates historical NBA picks from `players.json` draft fields
  - Upserts into `pcms.draft_picks`
- **Flow step added:** `import_pcms_data.flow/flow.yaml` (step “Generate NBA Draft Picks”)

### Draft pick summaries (future picks)
- **Migration:** `migrations/004_draft_pick_tables.sql`
  - Creates `pcms.draft_pick_summaries` (raw PCMS text)
  - Creates `pcms.draft_pick_ownership` (normalized/enriched table; currently not populated)
- **Import script:** `import_pcms_data.flow/draft_pick_summaries.inline_script.ts`
- **Flow step added:** `import_pcms_data.flow/flow.yaml` (step “Draft Pick Summaries”)

### Ledger entries import failures
- **Problem:** a small number of ledger rows have `team_id = null` (WNBA “WREN” rows), plus occasional in-batch duplicates can trigger `ON CONFLICT ... cannot affect row a second time`.
- **Fix implemented in:** `import_pcms_data.flow/trades,_transactions_&_ledger.inline_script.ts`
  - Filters out `team_id == null`
  - Dedupes by `transaction_ledger_entry_id` within each batch

### Two-way daily statuses row-count issue
- The importer now processes the full extract (28,659 records in the current `.shared/nba_pcms_full_extract/two_way.json`) and populates team codes.
  - File: `import_pcms_data.flow/two-way_daily_statuses.inline_script.ts`

---

## 🟡 Optional improvements (nice-to-have)

### Lookups import batching / dedupe
- Current script uses a very small batch size to avoid in-batch duplicate conflicts.
- Improvement: dedupe transformed rows by `(lookup_type, lookup_code)` before insert, then increase batch size.
  - File: `import_pcms_data.flow/lookups.inline_script.ts`

### Draft pick ownership parsing
- `pcms.draft_pick_ownership` exists (migration 004) but isn’t populated yet.
- If/when needed: write a parser that converts the free-text summaries (“To SAS(58) | may have …”) into structured rows.

### Teams metadata enrichment (source limitation)
- In the PCMS extract, many NBA teams have NULLs for:
  - `city`, `state_lk`, `country_lk`, `division_name`, `conference_name`, `first_game_date`
- Options if analysts need it: seed/enrich from another source (NBA API, curated CSV, etc.).

---

## 🟢 Accepted source-data limitations

These are expected to remain empty/NULL because the PCMS extract doesn’t contain the data:
- Empty tables (not present in extract): `apron_constraints`, `depth_charts`, `waiver_priority` (source file empty), etc.
- Always-NULL columns in `pcms.league_system_values`: `rsa_from_year`, `rsa_to_year`, `yss_from_year`, `yss_to_year`, `ysv_from_year`, `ysv_to_year`, plus related league fields.

---

## 📋 Validation checklist (current expected counts)

These counts come from the current clean JSON in `.shared/nba_pcms_full_extract/` and dry-run execution of the import scripts.

### Draft pick summaries
- [ ] `SELECT COUNT(*) FROM pcms.draft_pick_summaries;` = **450**
- [ ] `SELECT COUNT(*) FROM pcms.draft_pick_summaries WHERE draft_year >= 2026;` = **210**

### Two-way daily statuses
- [ ] `SELECT COUNT(*) FROM pcms.two_way_daily_statuses;` ≈ **28,659**

### Ledger entries
- Source `ledger.json` length: **50,713**
- Rows filtered out due to `team_id IS NULL`: **15**
- [ ] `SELECT COUNT(*) FROM pcms.ledger_entries;` = **50,698**

### Draft picks
- Source `draft_picks.json` (DLG + WNBA only): **1,169** (944 DLG + 225 WNBA)
- Generated NBA picks (from player draft info): **~1,831** (varies with dedupe / missing pick numbers)
- [ ] `SELECT COUNT(*) FROM pcms.draft_picks WHERE league_lk = 'NBA';` ≈ **1,831**
- [ ] `SELECT COUNT(*) FROM pcms.draft_picks WHERE league_lk IN ('DLG','WNBA');` = **1,169**

### Team code completeness (spot checks)
- [ ] No missing codes where a team id exists:

```sql
SELECT 'people' as tbl, COUNT(*) FROM pcms.people WHERE team_id IS NOT NULL AND team_code IS NULL
UNION ALL
SELECT 'contracts', COUNT(*) FROM pcms.contracts WHERE signing_team_id IS NOT NULL AND team_code IS NULL
UNION ALL
SELECT 'transactions', COUNT(*) FROM pcms.transactions WHERE to_team_id IS NOT NULL AND to_team_code IS NULL
UNION ALL
SELECT 'ledger_entries', COUNT(*) FROM pcms.ledger_entries WHERE team_id IS NOT NULL AND team_code IS NULL
UNION ALL
SELECT 'draft_pick_summaries', COUNT(*) FROM pcms.draft_pick_summaries WHERE team_id IS NOT NULL AND team_code IS NULL;
```

---

## Local dev note (common footgun)

If you run scripts locally and pass `extract_dir = ".shared"`, the importer may pick the XML directory (`.shared/nba_pcms_full_extract_xml`) instead of the clean JSON directory.

Use:
- `extract_dir = ".shared/nba_pcms_full_extract"` (clean JSON)
