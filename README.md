# PCMS XML Flow

Windmill flow for importing NBA PCMS (Player Contract Management System) XML data into PostgreSQL.

## Overview

1. Downloads ZIP from S3 containing PCMS XML extracts
2. Parses all XML → JSON once (lineage step)
3. Downstream scripts read JSON, transform, upsert to `pcms` schema
4. Tracks lineage and audit info for all records

## Quick Start

```bash
# Install dependencies
bun install

# Generate JSON files for local development
bun run scripts/parse-xml-to-json.ts

# Explore data structure
bun run scripts/show-all-paths.ts
bun run scripts/inspect-json-structure.ts player --sample

# Run a step locally
POSTGRES_URL="postgres://..." bun run import_pcms_data.flow/players_&_people.inline_script.ts
```

## Directory Structure

```
.
├── import_pcms_data.flow/       # Main import flow
│   ├── flow.yaml                # Windmill flow definition
│   ├── lineage_management_*.ts  # Step A: S3 → extract → XML→JSON
│   ├── players_&_people.*.ts    # Step B: People/teams
│   └── ...                      # Steps C-L
├── new_pcms_schema.flow/        # PostgreSQL DDL
├── scripts/                     # Dev tools
│   ├── parse-xml-to-json.ts     # Generate JSON from XML
│   ├── inspect-json-structure.ts
│   └── show-all-paths.ts
├── .shared/                     # Extracted data
│   └── nba_pcms_full_extract/   # XML + JSON files
├── docs/                        # Bun best practices
├── AGENTS.md                    # AI agent instructions
└── TODO.md                      # Refactoring progress
```

## Data Volumes

| Entity | Records |
|--------|---------|
| Players | 14,421 |
| Contracts | 8,071 |
| Transactions | 232,417 |
| Ledger entries | 50,713 |
| Trades | 1,731 |
| Draft picks | 1,169 |

## Key Tables (pcms schema)

- `pcms_lineage` - Import run tracking
- `people` - Players, coaches, agents
- `teams` - NBA/G-League/WNBA teams
- `contracts` - Player contracts
- `contract_versions` - Contract terms per version
- `salaries` - Yearly salary breakdowns
- `team_exceptions` - Cap exceptions (MLE, BAE, etc.)
- `lookups` - Reference data

## Flow Inputs

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dry_run` | boolean | false | Preview without DB writes |
| `s3_key` | string | `pcms/nba_pcms_full_extract.zip` | S3 key for ZIP |

## Architecture

- **same_worker: true** - All steps share `.shared/` directory
- **XML parsed once** - Lineage step creates JSON, downstream reads JSON
- **Hash-based dedup** - Only changed records updated (`source_hash`)
- **Bun runtime** - Native Postgres, fast I/O, shell integration
