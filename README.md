# PCMS XML Flow

Windmill flow for importing NBA PCMS (Player Contract Management System) XML data extracts into PostgreSQL.

## Overview

This flow:
1. Downloads a ZIP file from S3 containing PCMS XML extracts
2. Parses all XML files to JSON (saved in `.shared/` for downstream scripts)
3. Transforms and upserts data into the `pcms` schema tables
4. Tracks lineage and audit information for all ingested records

## Directory Structure

```
.
├── import_pcms_data.flow/    # Main import flow
│   ├── flow.yaml             # Flow definition
│   ├── lineage_management_*  # Step A: S3 download, extraction, XML→JSON parsing
│   ├── players_&_people.*    # Step B: People/teams import
│   ├── contracts_*           # Step C: Contracts, versions, bonuses, salaries
│   └── ...                   # Additional import steps (D-L)
├── new_pcms_schema.flow/     # Schema creation flow (PostgreSQL DDL)
├── .shared/                  # Shared data between flow steps
│   └── nba_pcms_full_extract/  # Extracted XML files (and JSON equivalents)
├── utils.ts                  # Shared utilities (Windmill: f/ralph/utils.ts)
├── docs/                     # Bun best practices documentation
└── agents/                   # AI agent configurations
```

## Key Tables (pcms schema)

- `pcms_lineage` - Tracks each import run (file hash, status, timestamps)
- `pcms_lineage_audit` - Per-record audit trail
- `people` - Players, coaches, agents
- `teams` - NBA/G-League/WNBA teams
- `contracts` - Player contracts
- `contract_versions` - Contract terms per version
- `salaries` - Yearly salary breakdowns
- `team_exceptions` - Cap exceptions (MLE, BAE, trade exceptions)
- `lookups` - Reference data (contract types, statuses, etc.)

## Local Development

```bash
# Install dependencies
bun install

# Run a script locally (requires POSTGRES_URL env var)
POSTGRES_URL="postgres://..." bun run import_pcms_data.flow/lineage_management_*.ts
```

## Flow Inputs

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dry_run` | boolean | false | Preview changes without writing to DB |
| `s3_key` | string | `pcms/nba_pcms_full_extract.zip` | S3 key for the PCMS ZIP file |

## Architecture Notes

- **same_worker: true** - All steps run on the same worker, sharing `.shared/` directory
- **Lineage step parses XML→JSON** - Downstream scripts work with JSON, not XML
- **Hash-based change detection** - Only changed records are updated
- **Bun runtime** - Uses Bun for fast I/O and native APIs
