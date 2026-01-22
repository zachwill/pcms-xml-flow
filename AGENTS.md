# PCMS XML Flow

Windmill flow: imports NBA PCMS XML → PostgreSQL. Python only.

## Architecture

**Step A** (pcms_xml_to_json): S3 ZIP → XML → clean JSON files  
**Steps B-G**: Read JSON, upsert to `pcms.*` tables

Key: Clean data ONCE in Step A. Import scripts just read JSON and upsert.

## Project Structure

```
import_pcms_data.flow/          # Windmill flow scripts (7 steps)
├── pcms_xml_to_json.inline_script.py   # Step A: XML → JSON
├── lookups.inline_script.py            # Step B: 43 lookup tables
├── people.inline_script.py             # Step C: agencies, agents, people
├── contracts.inline_script.py          # Step D: contracts, versions, salaries, bonuses
├── transactions.inline_script.py       # Step E: trades, ledger, waivers, exceptions
├── league_config.inline_script.py      # Step F: system values, scales, draft
└── team_financials.inline_script.py    # Step G: budgets, tax, cap projections, two-way

shared/pcms/nba_pcms_full_extract/      # Clean JSON files (source data)
scripts/
├── xml-to-json.py              # Local XML→JSON (mirrors Step A)
└── test-import.py              # Test import scripts locally
migrations/                     # SQL migrations for pcms schema
SCHEMA.md                       # Target database schema (READ THIS for column names!)
```

## Running Import Scripts

**Always use `uv run` for Python scripts.**

```bash
# Test runner has TWO modes - dry-run (default) vs write
uv run scripts/test-import.py transactions --dry-run  # Preview only, NO DB writes
uv run scripts/test-import.py transactions --write    # Actually commits to database

# Available script names:
#   lookups, people, contracts, transactions, league_config, team_financials

# Run all steps
uv run scripts/test-import.py all --write
```

**IMPORTANT**: `--dry-run` is the DEFAULT. You MUST use `--write` to commit changes!

---

## Debugging Methodology

When columns are NULL or data is missing after import:

### Step 1: Check Current DB State

```bash
# See which columns are populated vs NULL
psql "$POSTGRES_URL" -c "SELECT 
  COUNT(*) as total,
  COUNT(column1) as col1_populated,
  COUNT(column2) as col2_populated
FROM pcms.some_table;"

# Sample a few rows
psql "$POSTGRES_URL" -c "SELECT * FROM pcms.some_table LIMIT 3;"
```

### Step 2: Find the Import Script

```bash
# Which script handles this table?
grep -n "table_name" import_pcms_data.flow/*.py

# What JSON file does it read?
grep -n "\.json" import_pcms_data.flow/some.inline_script.py | head -10
```

### Step 3: Explore JSON Structure (use jq, don't read full files!)

```bash
# Check top-level structure
jq 'keys' shared/pcms/nba_pcms_full_extract/something.json
jq 'type' shared/pcms/nba_pcms_full_extract/something.json

# Get first record to see available fields
jq '.[0]' shared/pcms/nba_pcms_full_extract/something.json
jq '.some_container[0]' shared/pcms/nba_pcms_full_extract/something.json

# Handle nested structures (VERY COMMON!)
jq '.container["nested-key"][0]' shared/pcms/nba_pcms_full_extract/something.json

# Count records
jq '. | length' shared/pcms/nba_pcms_full_extract/something.json

# Find a specific field across nested structure
jq '.. | .field_name? // empty' shared/pcms/nba_pcms_full_extract/something.json | head
```

### Step 4: Compare JSON Fields to Script

Look for common issues:
- **Field name mismatches**: `season_year` vs `salary_year`
- **Nested data not extracted**: Container has `["sub-key"][]` that script doesn't traverse
- **Data in different JSON file**: Field exists but lives in a separate JSON structure

### Step 5: Fix Pattern - Enrichment Lookup

When data lives in a different structure, build a lookup dict:

```python
# Build lookup from related data
enrichment = {}
for item in related_data:
    key = (item["id"], item["date"])  # composite key
    enrichment[key] = {"extra_field": item["extra_field"]}

# Merge when processing main data
for record in main_data:
    lookup_key = (record["id"], record["date"])
    extra = enrichment.get(lookup_key, {})
    record["extra_field"] = extra.get("extra_field")
```

### Step 6: Test Changes

```bash
# Clear pycache first!
rm -rf import_pcms_data.flow/__pycache__

# Dry-run to verify no errors
uv run scripts/test-import.py transactions --dry-run

# If good, write to DB
uv run scripts/test-import.py transactions --write

# Verify fix
psql "$POSTGRES_URL" -c "SELECT COUNT(*), COUNT(fixed_column) FROM pcms.transactions;"
```

---

## Common Gotchas

1. **Nested JSON keys with hyphens**: Access via `data["hyphen-key"]` not `data.hyphen_key`
2. **Data lives elsewhere**: Sometimes a column's data is in a completely different JSON file/structure - build enrichment lookups
3. **Column doesn't exist in source**: Some schema columns were aggregates or calculated values that don't exist in raw XML - may need to drop from schema
4. **pycache stale**: Always `rm -rf import_pcms_data.flow/__pycache__` before re-testing
5. **Forgot --write**: Dry-run is default - changes won't persist without `--write`!

---

## JSON Format

All JSON: snake_case keys, null values (not xsi:nil), flat arrays.

## Import Script Pattern

Each script has inline `upsert()` and `find_extract_dir()` helpers (no shared imports in Windmill).

```python
# /// script
# dependencies = ["psycopg[binary]"]
# ///
import json, psycopg, os
from pathlib import Path

def main(dry_run: bool = False, extract_dir: str = "./shared/pcms"):
    base_dir = find_extract_dir(extract_dir)
    with open(base_dir / "players.json") as f:
        players = json.load(f)
    if not dry_run:
        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        upsert(conn, "pcms.people", players, ["person_id"])
```

## Flow Config

`flow.yaml`: `same_worker: true` so all steps share `./shared/` directory.
