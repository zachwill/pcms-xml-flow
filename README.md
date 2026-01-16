# PCMS XML Flow

Windmill flow for importing NBA PCMS (Player Contract Management System) XML data into PostgreSQL.

## Architecture (v3.0)

```
S3 ZIP → Extract → XML → Clean JSON → PostgreSQL
                          ↑
                    snake_case keys
                    null (not xsi:nil)
                    flat structure
```

1. **Lineage step** downloads ZIP, extracts XML, parses to **clean JSON**
2. **Import scripts** read clean JSON and insert directly to Postgres
3. No transformation needed—JSON keys already match DB columns

## Quick Start

```bash
# Install dependencies
bun install

# Generate clean JSON from XML (for local dev)
bun run scripts/parse-xml-to-json.ts

# Run a step locally
POSTGRES_URL="postgres://..." bun run import_pcms_data.flow/players_&_people.inline_script.ts
```

## Clean JSON Files

The lineage step produces these files in `.shared/nba_pcms_full_extract/`:

| File | Records | Target Table |
|------|---------|--------------|
| `players.json` | 14,421 | `pcms.people` |
| `contracts.json` | 8,071 | `pcms.contracts`, `contract_versions`, `salaries` |
| `transactions.json` | 232,417 | `pcms.transactions` |
| `ledger.json` | 50,713 | `pcms.transaction_ledger` |
| `trades.json` | 1,731 | `pcms.trades` |
| `draft_picks.json` | 1,169 | `pcms.draft_picks` |
| `team_exceptions.json` | nested | `pcms.team_exceptions` |
| `lookups.json` | 43 tables | `pcms.lookups` |

## Directory Structure

```
.
├── import_pcms_data.flow/       # Windmill flow
│   ├── flow.yaml                # Flow definition (steps A-L)
│   ├── lineage_management_*.ts  # Step A: S3 → XML → clean JSON
│   ├── players_&_people.*.ts    # Step B: Insert players
│   └── ...                      # Steps C-L
├── scripts/
│   ├── parse-xml-to-json.ts     # Dev tool: XML → clean JSON
│   ├── inspect-json-structure.ts
│   └── show-all-paths.ts
├── .shared/
│   ├── nba_pcms_full_extract/   # Clean JSON output
│   └── nba_pcms_full_extract_xml/ # Source XML (local dev)
├── AGENTS.md                    # Architecture details
└── TODO.md                      # Remaining work
```

## Import Script Pattern

Scripts are simple—just read and insert:

```typescript
import { SQL } from "bun";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

export async function main(dry_run = false, ..., extract_dir = "./shared/pcms") {
  // Read clean JSON
  const players = await Bun.file(`${baseDir}/players.json`).json();

  // Insert (keys already match columns)
  await sql`INSERT INTO pcms.people ${sql(rows)} ON CONFLICT ...`;
}
```

## Flow Inputs

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dry_run` | boolean | `false` | Preview without DB writes |
| `s3_key` | string | `pcms/nba_pcms_full_extract.zip` | S3 key for ZIP |

## Key Design Decisions

- **Clean once, use everywhere** — XML quirks handled in lineage step, not every script
- **snake_case keys** — JSON keys match Postgres columns directly
- **same_worker: true** — All steps share `.shared/` directory
- **Bun runtime** — Native Postgres, fast file I/O, shell integration
