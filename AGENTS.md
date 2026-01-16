# AGENTS.md - PCMS XML Flow

## Project Context

Windmill flow that imports NBA PCMS XML data into PostgreSQL. Runs on Bun runtime.

## Key Files

```
import_pcms_data.flow/
├── flow.yaml                    # Flow definition (steps A-L sequential)
├── lineage_management_*.ts      # Step A: S3 download, extract, XML→JSON ✅
├── players_&_people.*.ts        # Step B: People/teams import ✅
├── contracts_*.ts               # Step C: Contracts, versions, salaries (needs update)
├── ...                          # Steps D-K (need update)
└── finalize_lineage.*.ts        # Step L: Mark complete

scripts/
├── parse-xml-to-json.ts         # Dev tool: generate JSON from XML
├── inspect-json-structure.ts    # Dev tool: explore JSON structure
└── show-all-paths.ts            # Dev tool: quick path reference

.shared/nba_pcms_full_extract/   # Extracted data (XML + JSON)
docs/bun-*.md                    # Bun best practices
```

## Architecture

1. **Step A (lineage)**: Downloads ZIP from S3, extracts, parses ALL XML → JSON, writes `lineage.json`
2. **Steps B-K**: Read pre-parsed JSON from `.shared/`, transform, upsert to Postgres
3. **Step L (finalize)**: Updates lineage status to SUCCESS/FAILED

## Bun Best Practices (MUST FOLLOW)

```typescript
// ✅ File I/O
const data = await Bun.file("./data.json").json();
await Bun.write("./out.json", JSON.stringify(obj));

// ✅ Shell commands
import { $ } from "bun";
await $`unzip -o ${zipPath} -d ${outDir}`.quiet();

// ✅ Directories
import { mkdir, readdir, rm } from "node:fs/promises";

// ✅ Postgres
import { SQL } from "bun";
const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ✅ Hashing
const hash = new Bun.CryptoHasher("sha256").update(data).digest("hex");

// ❌ DON'T use: execSync, fs.readFileSync, require("child_process")
```

## JSON Structure

All parsed JSON follows this pattern:
```typescript
data["xml-extract"]["<type>-extract"]["<entity>"]  // Array of records
```

**Important:** `xsi:nil="true"` becomes `{ "@_xsi:nil": "true" }` - use `nilSafe()` helper:
```typescript
function nilSafe(val: unknown): unknown {
  if (val && typeof val === "object" && "@_xsi:nil" in val) return null;
  return val;
}
```

## Data Paths (Quick Reference)

```typescript
// Players (14,421 records)
data["xml-extract"]["player-extract"]["player"]

// Contracts (8,071 records, nested versions/salaries)
data["xml-extract"]["contract-extract"]["contract"]

// Transactions (232,417 records)
data["xml-extract"]["transaction-extract"]["transaction"]

// Lookups (many sub-tables)
data["xml-extract"]["lookups-extract"]["lkContractTypes"]["lkContractType"]
```

Run `bun run scripts/show-all-paths.ts` for complete reference.

## Local Development

```bash
# Generate JSON from XML (one-time, for local dev)
bun run scripts/parse-xml-to-json.ts

# Explore JSON structure
bun run scripts/inspect-json-structure.ts contract --sample

# Run a step locally
POSTGRES_URL="postgres://..." bun run import_pcms_data.flow/players_&_people.inline_script.ts
```

## Common Pitfalls

1. **Don't stream XML** - Read pre-parsed JSON instead
2. **Don't import from utils.ts** - Inline helpers in each script
3. **Handle nil objects** - Check for `{ "@_xsi:nil": "true" }` 
4. **Use hash-based dedup** - `source_hash` column for change detection
