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

### 🔄 Next Steps

1. ~~**Regenerate all JSON files locally**~~ ✅ Done - 22 files regenerated, no empty objects

2. **Deploy updated Windmill script** - The fix in `pcms_xml_to_json.inline_script.py` needs to be synced to Windmill
   ```bash
   wmill sync push
   ```

3. **Re-run Windmill flow** to confirm Contracts step passes

### 📋 Files Changed

```
scripts/xml-to-json.py                              # NEW - local uv script
import_pcms_data.flow/pcms_xml_to_json.inline_script.py  # FIXED - empty object handling
AGENTS.md                                           # UPDATED - accurate flow docs
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
