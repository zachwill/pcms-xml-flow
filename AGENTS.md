# PCMS XML Flow

Windmill flow: imports NBA PCMS XML → PostgreSQL. Python only.

## Architecture

**Step A** (pcms_xml_to_json): S3 ZIP → XML → clean JSON files  
**Steps B-G**: Read JSON, upsert to `pcms.*` tables

Key: Clean data ONCE in Step A. Import scripts just read JSON and upsert.

## Flow Steps

| Step | Script | Tables |
|------|--------|--------|
| A | `pcms_xml_to_json.inline_script.py` | — (produces JSON) |
| B | `lookups.inline_script.py` | 43 lookup tables |
| C | `people_&_identity.inline_script.py` | agencies, agents, people |
| D | `contracts.inline_script.py` | contracts, versions, salaries, bonuses |
| E | `transactions.inline_script.py` | trades, ledger, waivers, exceptions |
| F | `league_config.inline_script.py` | system values, scales, draft |
| G | `team_financials.inline_script.py` | budgets, tax, cap projections, two-way |

## Key Files

- `import_pcms_data.flow/` — Windmill flow (7 steps)
- `scripts/xml-to-json.py` — Local XML→JSON (mirrors Step A)
- `scripts/test-import.py` — Test import scripts locally
- `shared/pcms/nba_pcms_full_extract/` — Clean JSON output
- `migrations/` — SQL migrations for pcms schema
- `SCHEMA.md` — Target database schema

## JSON Format

All JSON: snake_case keys, null values (not xsi:nil), flat arrays.

## Import Script Pattern

```python
# /// script
# dependencies = ["psycopg[binary]"]
# ///
import json, psycopg
from pathlib import Path

def main(dry_run: bool = False, extract_dir: str = "./shared/pcms"):
    base_dir = find_extract_dir(extract_dir)
    with open(base_dir / "players.json") as f:
        players = json.load(f)
    if not dry_run:
        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        upsert(conn, "pcms.people", players, ["person_id"])
```

Each script has inline `upsert()` and `find_extract_dir()` helpers (no shared imports in Windmill).

## Local Dev

**Always use `uv run` for Python scripts** (handles dependencies automatically).

```bash
uv run scripts/xml-to-json.py              # Generate JSON from XML
uv run scripts/test-import.py lookups      # Test single step
uv run scripts/test-import.py all          # Run all steps
```

## Flow Config

`flow.yaml`: `same_worker: true` so all steps share `./shared/` directory.
