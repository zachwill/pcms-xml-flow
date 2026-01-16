# AGENTS.md - PCMS XML Flow

## Project Context

Windmill flow that imports NBA PCMS XML data into PostgreSQL. Runs on Bun runtime.

## Architecture (v3.0)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Step A: Lineage (downloads ZIP, parses XML → CLEAN JSON)                   │
│                                                                             │
│    XML with xsi:nil, camelCase    →    Clean JSON with nulls, snake_case   │
│    nba_pcms_full_extract_player.xml    players.json                        │
│    nba_pcms_full_extract_contract.xml  contracts.json                      │
│    ...                                 ...                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Steps B-K: Import scripts (read clean JSON, insert to Postgres)           │
│                                                                             │
│    const players = await Bun.file("players.json").json();                  │
│    await sql`INSERT INTO pcms.people ${sql(players)}`;                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key insight:** Clean the data ONCE during XML parsing, not in every script.

## Key Files

```
import_pcms_data.flow/
├── flow.yaml                    # Flow definition (steps A-L)
├── lineage_management_*.ts      # Step A: S3 → extract → XML → CLEAN JSON ✅
├── players_&_people.*.ts        # Step B: Read clean JSON, insert ✅
├── contracts_*.ts               # Step C: (needs simplification)
└── ...                          # Steps D-L

scripts/
├── parse-xml-to-json.ts         # Dev tool: XML → clean JSON (mirrors lineage)
├── inspect-json-structure.ts    # Dev tool: explore JSON
└── show-all-paths.ts            # Dev tool: path reference

.shared/nba_pcms_full_extract/   # Clean JSON files
.shared/nba_pcms_full_extract_xml/ # Source XML files (for local dev)
```

## Clean JSON Files

The lineage step produces these clean JSON files:

| File | Records | Description |
|------|---------|-------------|
| `players.json` | 14,421 | Players/people |
| `contracts.json` | 8,071 | Contracts with nested versions/salaries |
| `transactions.json` | 232,417 | Transaction history |
| `ledger.json` | 50,713 | Ledger entries |
| `trades.json` | 1,731 | Trade records |
| `draft_picks.json` | 1,169 | Draft picks |
| `lookups.json` | 43 tables | Reference data |
| ... | ... | ... |

## Clean JSON Format

All JSON files have:
- **snake_case keys** (match DB columns directly)
- **null values** (not `{ "@_xsi:nil": "true" }`)
- **No XML wrapper nesting** (just the array of records)

```typescript
// Clean player record
{
  "player_id": 201839,
  "first_name": "Steve",
  "last_name": "Newman",
  "birth_date": "1984-10-25",
  "team_id": 1612709911,
  "agency_id": null,           // ← was { "@_xsi:nil": "true" }
  "draft_year": null,          // ← was { "@_xsi:nil": "true" }
  ...
}
```

## Import Script Pattern

Scripts are now simple:

```typescript
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

export async function main(dry_run = false, ..., extract_dir = "./shared/pcms") {
  // Find extract directory
  const entries = await readdir(extract_dir, { withFileTypes: true });
  const subDir = entries.find(e => e.isDirectory());
  const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

  // Read clean JSON
  const players: any[] = await Bun.file(`${baseDir}/players.json`).json();

  // Upsert (data is already clean!)
  await sql`INSERT INTO pcms.people ${sql(rows)} ON CONFLICT ...`;
}
```

**No need for:** `nilSafe()`, `safeNum()`, `safeStr()`, `safeBool()`, `hash()`

## Local Development

```bash
# Generate clean JSON from XML (one-time)
bun run scripts/parse-xml-to-json.ts

# Explore structure
bun run scripts/show-all-paths.ts

# Run a step locally
POSTGRES_URL="postgres://..." bun run import_pcms_data.flow/players_&_people.inline_script.ts
```

## Bun Best Practices

```typescript
// ✅ File I/O
const data = await Bun.file("./data.json").json();
await Bun.write("./out.json", JSON.stringify(obj));

// ✅ Postgres (tagged template for safety)
await sql`INSERT INTO pcms.people ${sql(rows)}`;
await sql`SELECT * FROM pcms.people WHERE person_id = ${id}`;

// ✅ Batch upsert
await sql`
  INSERT INTO pcms.people ${sql(rows)}
  ON CONFLICT (person_id) DO UPDATE SET
    first_name = EXCLUDED.first_name,
    updated_at = EXCLUDED.updated_at
`;
```
