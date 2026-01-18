# AGENTS.md - PCMS XML Flow

## Project Context

Windmill flow that imports NBA PCMS (Player Contract Management System) XML data into PostgreSQL. Runs on Bun runtime (with Python for XML parsing).

## Architecture (v3.0)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Step T: PCMS XML to JSON (Python)                                          │
│                                                                             │
│    S3 ZIP → Extract → XML → Clean JSON                                      │
│    nba_pcms_full_extract_player.xml    →    players.json                   │
│    nba_pcms_full_extract_contract.xml  →    contracts.json                 │
│    ...                                 →    ...                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Steps K-G: Import scripts (Bun/TypeScript)                                 │
│                                                                             │
│    const players = await Bun.file("players.json").json();                  │
│    await sql`INSERT INTO pcms.people ${sql(rows)}`;                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Step L: Finalize Lineage (aggregate results, report errors)               │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key insight:** Clean the data ONCE during XML parsing (Python), not in every import script.

## Flow Steps (11 total)

| ID | Step | Script | Description |
|----|------|--------|-------------|
| T | PCMS XML to JSON | `pcms_xml_to_json.inline_script.py` | S3 → extract → XML → clean JSON |
| K | Lookups | `lookups.inline_script.ts` | Reference tables (43 lookup tables) |
| B | People & Identity | `people_&_identity.inline_script.ts` | Agencies, agents, people |
| R | Draft | `draft.inline_script.ts` | Draft picks & summaries |
| C | Contracts | `contracts.inline_script.ts` | Contracts, versions, salaries, bonuses |
| D | Team Exceptions | `team_exceptions.inline_script.ts` | Team exceptions & usage |
| E | Transactions | `transactions_(trades,_ledger,_waiver_amounts).inline_script.ts` | Trades, ledger, waiver amounts |
| F | League Config | `league_config.inline_script.ts` | System values, rookie scale, salary scales |
| H | Team Financials | `team_financials.inline_script.ts` | Team budgets, tax rates, cap projections |
| G | Two-Way | `two-way.inline_script.ts` | Two-way daily statuses & utility |
| L | Finalize | `finalize_lineage.inline_script.ts` | Aggregate results, report errors |

## Directory Structure

```
.
├── import_pcms_data.flow/           # Windmill flow (11 steps)
│   ├── flow.yaml                    # Flow definition
│   ├── pcms_xml_to_json.*.py        # Step T: Python XML parser
│   ├── lookups.*.ts                 # Step K: Lookup tables
│   ├── people_&_identity.*.ts       # Step B: People, agents, agencies
│   ├── draft.*.ts                   # Step R: Draft picks & summaries
│   ├── contracts.*.ts               # Step C: Contracts, versions, salaries
│   ├── team_exceptions.*.ts         # Step D: Team exceptions
│   ├── transactions_*.ts            # Step E: Trades, ledger, waiver amounts
│   ├── league_config.*.ts           # Step F: System values, scales
│   ├── team_financials.*.ts         # Step H: Budgets, tax, projections
│   ├── two-way.*.ts                 # Step G: Two-way statuses
│   └── finalize_lineage.*.ts        # Step L: Finalize
│
├── scripts/                         # Dev tools
│   ├── parse-xml-to-json.ts         # Local XML → JSON (mirrors Step T)
│   ├── inspect-json-structure.ts    # Explore JSON structure
│   └── show-all-paths.ts            # Path reference
│
├── .shared/
│   ├── nba_pcms_full_extract/       # Clean JSON output
│   └── nba_pcms_full_extract_xml/   # Source XML (local dev)
│
├── AGENTS.md                        # This file
├── README.md                        # Project overview
└── SCHEMA.md                        # Target database schema
```

## Clean JSON Files

The Python lineage step (T) produces these clean JSON files:

| File | Description |
|------|-------------|
| `players.json` | Players/people |
| `contracts.json` | Contracts with nested versions/salaries |
| `transactions.json` | Transaction history |
| `ledger.json` | Ledger entries |
| `trades.json` | Trade records |
| `draft_picks.json` | Draft picks (DLG/WNBA) |
| `draft_pick_summaries.json` | Draft pick summaries by team/year |
| `team_exceptions.json` | Team exceptions & usage |
| `team_budgets.json` | Team budget snapshots |
| `team_transactions.json` | Team transactions (cap hold adjustments) |
| `transaction_waiver_amounts.json` | Waiver amount calculations |
| `two_way.json` | Two-way daily statuses |
| `two_way_utility.json` | Two-way game/contract utility |
| `lookups.json` | Reference data (43 tables) |
| `cap_projections.json` | Salary cap projections |
| `yearly_system_values.json` | League system values by year |
| `yearly_salary_scales.json` | Salary scales by year |
| `rookie_scale_amounts.json` | Rookie scale amounts |
| `non_contract_amounts.json` | Non-contract amounts (cap holds, etc.) |
| `tax_rates.json` | Tax rate tiers |
| `tax_teams.json` | Team tax status by year |

## Clean JSON Format

All JSON files have:
- **snake_case keys** (match DB columns directly)
- **null values** (not `{ "@xsi:nil": "true" }`)
- **No XML wrapper nesting** (just the array of records)

```typescript
// Clean player record
{
  "player_id": 201839,
  "first_name": "Steve",
  "last_name": "Newman",
  "birth_date": "1984-10-25",
  "team_id": 1612709911,
  "agency_id": null,           // ← was { "@xsi:nil": "true" }
  "draft_year": null,          // ← was { "@xsi:nil": "true" }
  ...
}
```

## Import Script Pattern

Scripts are simple—just read clean JSON and insert:

```typescript
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

export async function main(dry_run = false, extract_dir = "./shared/pcms") {
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
# Generate clean JSON from XML (one-time, mirrors Step T)
bun run scripts/parse-xml-to-json.ts

# Explore structure
bun run scripts/show-all-paths.ts

# Run a step locally
POSTGRES_URL="postgres://..." bun run import_pcms_data.flow/people_\&_identity.inline_script.ts
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

## Flow Configuration

Key settings in `flow.yaml`:
- **`same_worker: true`** — All steps share `./shared/` directory
- **`extract_dir: './shared/pcms'`** — All import scripts read from here
- **Step T runs first** — Produces JSON before import scripts run
