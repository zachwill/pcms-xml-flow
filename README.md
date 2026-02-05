# PCMS XML Flow

Windmill flow for importing NBA PCMS (Player Contract Management System) XML data into PostgreSQL.

## Architecture

```
S3 ZIP → Extract → XML → Clean JSON → PostgreSQL
                          ↑
                    snake_case keys
                    null (not xsi:nil)
                    flat structure
```

1. **Step A** downloads ZIP from S3, extracts XML, parses to **clean JSON**
2. **Steps B-G** read clean JSON and upsert directly to Postgres
3. No transformation needed in import scripts—JSON keys already match DB columns

## Quick Start

```bash
# Generate clean JSON from XML (for local dev)
uv run scripts/xml-to-json.py

# Test a single import script
uv run scripts/test-import.py lookups --dry-run
uv run scripts/test-import.py contracts

# Run all import scripts
uv run scripts/test-import.py all
```

## Flow Steps (7 total)

| ID | Step | Description |
|----|------|-------------|
| A | PCMS XML to JSON | S3 → extract → XML → clean JSON |
| B | Lookups | Reference tables (43 lookup tables) |
| C | People & Identity | Agencies, agents, people |
| D | Contracts | Contracts, versions, salaries, bonuses |
| E | Transactions & Exceptions | Trades, ledger, waiver amounts, team exceptions |
| F | League Config & Draft | System values, rookie scale, salary scales, draft |
| G | Team Financials & Two-Way | Team budgets, tax rates, cap projections, two-way |

## Clean JSON Files

The lineage step produces these files in `shared/pcms/nba_pcms_full_extract/`:

| File | Target Table |
|------|--------------|
| `players.json` | `pcms.people` |
| `contracts.json` | `pcms.contracts`, `contract_versions`, `salaries` |
| `transactions.json` | `pcms.transactions` |
| `ledger.json` | `pcms.ledger_entries` |
| `trades.json` | `pcms.trades`, `trade_teams`, `trade_groups` |
| `draft_picks.json` | `pcms.draft_picks` (DLG/WNBA) |
| `draft_pick_summaries.json` | `pcms.draft_pick_summaries` |
| `team_exceptions.json` | `pcms.team_exceptions`, `team_exception_usage` |
| `team_budgets.json` | `pcms.team_budget_snapshots`, `tax_team_status` |
| `two_way.json` | `pcms.two_way_daily_statuses` |
| `two_way_utility.json` | `pcms.two_way_contract_utility`, `two_way_game_utility` |
| `lookups.json` | `pcms.lookups`, `pcms.teams` |
| `yearly_system_values.json` | `pcms.league_system_values` |
| `cap_projections.json` | `pcms.league_salary_cap_projections` |

## Directory Structure

```
.
├── import_pcms_data.flow/        # Windmill flow (7 Python steps)
│   ├── flow.yaml                 # Flow definition
│   ├── pcms_xml_to_json.*.py     # Step A: S3 → XML → clean JSON
│   ├── lookups.*.py              # Step B: Lookup tables
│   ├── people_&_identity.*.py    # Step C: People, agents, agencies
│   ├── contracts.*.py            # Step D: Contracts
│   ├── transactions.*.py         # Step E: Transactions & exceptions
│   ├── league_config.*.py        # Step F: League config & draft
│   └── team_financials.*.py      # Step G: Team financials & two-way
├── migrations/                   # SQL migrations for pcms schema + warehouses
├── scripts/                      # Local runners (XML→JSON, import harness, etc.)
├── queries/                      # SQL assertions / smoke tests
├── web/                          # Rails + Datastar UI (canonical app)
├── prototypes/                   # Archived prototypes (React Salary Book)
├── reference/                    # Reference packs (Datastar, workbook exports, etc.)
├── agents/                       # Autonomous coding agents
├── AGENTS.md                     # Repo map + conventions
├── SALARY_BOOK.md                # Salary-cap warehouses + primitives guide
└── SCHEMA.md                     # Auto-generated pcms schema reference
```

## Import Script Pattern

All Python import scripts follow the same pattern:

```python
# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]"]
# ///

import os
import json
from pathlib import Path
import psycopg

def main(dry_run: bool = False, extract_dir: str = "./shared/pcms"):
    base_dir = find_extract_dir(extract_dir)
    
    # Read clean JSON
    with open(base_dir / "players.json") as f:
        players = json.load(f)
    
    # Upsert (keys already match columns)
    if not dry_run:
        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        upsert(conn, "pcms.people", rows, ["person_id"])
        conn.close()
```

## Flow Inputs

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dry_run` | boolean | `false` | Preview without DB writes |
| `s3_key` | string | `pcms/nba_pcms_full_extract.zip` | S3 key for ZIP |

## Key Design Decisions

- **Python everywhere** — All flow steps use Python + psycopg
- **Clean once, use everywhere** — XML quirks handled in Step A, not every script
- **snake_case keys** — JSON keys match Postgres columns directly
- **same_worker: true** — All steps share `./shared/` directory
