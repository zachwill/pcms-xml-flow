# TODO - PCMS XML Flow

## Current Status (2026-01-18)

### ✅ Completed

1. **Updated AGENTS.md** - Now reflects actual 11-step flow structure

2. **Created `scripts/xml-to-json.py`** - Local uv script mirrors Windmill's Python step
   ```bash
   uv run scripts/xml-to-json.py                    # All files
   uv run scripts/xml-to-json.py --single contract  # Just contracts
   ```

3. **Fixed empty object bug** in both Python scripts:
   - `scripts/xml-to-json.py`
   - `import_pcms_data.flow/pcms_xml_to_json.inline_script.py`
   
   **Root cause:** XML elements with no content were parsed as `{}` instead of `null`.
   When inserted into Postgres integer/bigint columns, `{}` became `"[object Object]"`.
   
   **Fix:** Added `return result if result else None` at end of `clean()` function.

4. **Fixed Contracts script duplicate row error** (2026-01-18)
   - **Error:** `ON CONFLICT DO UPDATE command cannot affect row a second time`
   - **Root cause:** Multiple rows with same `(contract_id, version_number, salary_year)` in same batch
   - **Fix:** Added `dedupeByKey()` helper to deduplicate all row arrays before inserting
   - **File:** `import_pcms_data.flow/contracts.inline_script.ts`

5. **Fixed Team Financials missing constraint error** (2026-01-18)
   - **Error:** `there is no unique or exclusion constraint matching the ON CONFLICT specification`
   - **Root cause:** `tax_team_status` and `team_budget_snapshots` tables had serial PKs but scripts assumed composite unique keys
   - **Fix:** 
     - Created `migrations/007_add_missing_unique_indexes.sql` to add unique indexes on `tax_team_status(team_id, salary_year)`, `salaries(contract_id, version_number, salary_year)`, and `contract_versions(contract_id, version_number)`
     - Changed `team_budget_snapshots` to use TRUNCATE + INSERT (7-column key with NULLs is problematic for unique indexes)
   - **File:** `import_pcms_data.flow/team_financials.inline_script.ts`

### 🔄 Next Steps

1. **Run migration 007** to create missing unique indexes
   ```bash
   psql $POSTGRES_URL -f migrations/007_add_missing_unique_indexes.sql
   ```

2. **Re-run Windmill flow** to confirm all steps pass

### 📋 Files Changed

```
scripts/xml-to-json.py                                    # NEW - local uv script
import_pcms_data.flow/pcms_xml_to_json.inline_script.py  # FIXED - empty object handling
import_pcms_data.flow/contracts.inline_script.ts          # FIXED - deduplication
import_pcms_data.flow/team_financials.inline_script.ts    # FIXED - truncate+insert for budget snapshots
migrations/007_add_missing_unique_indexes.sql             # NEW - unique indexes for upserts
AGENTS.md                                                 # UPDATED - accurate flow docs
```

### 🐛 Bug Details (for reference)

**Error message:**
```
PostgresError: invalid input syntax for type bigint: "[object Object]"
Postgres code: 22P02
Context: unnamed portal parameter $5 = '...'
```

**Affected fields in contracts.json:**
- `team_exception_id` 
- `sign_and_trade_id`
- `two_way_service_limit`

These were `{}` (empty object) instead of `null`, causing Bun SQL to stringify them.

**The fix (in `clean()` function):**
```python
# Before: returned empty dict {}
return result

# After: returns None if result is empty
return result if result else None
```
