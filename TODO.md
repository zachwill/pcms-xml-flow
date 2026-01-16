# TODO - PCMS XML Flow Refactor

## Goal

Refactor all flow scripts to:
1. Read pre-parsed JSON (not stream XML)
2. Use Bun-native APIs (`Bun.file()`, `$` shell, `SQL`)
3. Inline helpers (no `utils.ts` imports)

## Progress

### ✅ Completed

- [x] `lineage_management_(s3_&_state_tracking).inline_script.ts`
  - Downloads ZIP from S3, extracts, parses ALL XML → JSON
  - Writes `lineage.json` context file
  - Uses `$`, `Bun.file()`, `Bun.write()`

- [x] `players_&_people.inline_script.ts`
  - Reads `*_player.json`
  - Upserts to `pcms.people` and `pcms.teams`

- [x] Dev scripts created
  - `scripts/parse-xml-to-json.ts`
  - `scripts/inspect-json-structure.ts`
  - `scripts/show-all-paths.ts`

### 🔴 TODO - High Priority

- [ ] `contracts,_versions,_bonuses_&_salaries.inline_script.ts`
  - Source: `*_contract.json` → `data["xml-extract"]["contract-extract"]["contract"]`
  - Tables: `contracts`, `contract_versions`, `contract_bonuses`, `salaries`, `payment_schedules`
  - Note: Nested structure (contract → versions → salaries)

- [ ] `lookups.inline_script.ts`
  - Source: `*_lookup.json` → `data["xml-extract"]["lookups-extract"]`
  - Table: `lookups` (many sub-tables)

### 🟡 TODO - Medium Priority

- [ ] `team_exceptions_&_usage.inline_script.ts`
  - Source: `*_team-exception.json`

- [ ] `trades,_transactions_&_ledger.inline_script.ts`
  - Sources: `*_trade.json`, `*_transaction.json`, `*_ledger.json`

- [ ] `team_budgets.inline_script.ts`
  - Source: `*_team-budget.json`

- [ ] `draft_picks.inline_script.ts`
  - Source: `*_dp-extract.json`

### 🟢 TODO - Lower Priority

- [ ] `system_values,_rookie_scale_&_nca.inline_script.ts`
- [ ] `two-way_daily_statuses.inline_script.ts`
- [ ] `waiver_priority_&_ranks.inline_script.ts`
- [ ] `finalize_lineage.inline_script.ts` (minor - just inline helpers)

### 🧹 Cleanup

- [ ] Remove/trim `utils.ts` after all scripts updated
- [ ] Test full flow end-to-end

---

## JSON Data Paths

Run `bun run scripts/show-all-paths.ts` for complete reference.

Key paths:
```typescript
// Players (14,421)
data["xml-extract"]["player-extract"]["player"]

// Contracts (8,071)
data["xml-extract"]["contract-extract"]["contract"]

// Transactions (232,417)
data["xml-extract"]["transaction-extract"]["transaction"]

// Ledger (50,713)
data["xml-extract"]["ledger-extract"]["transactionLedgerEntry"]

// Trades (1,731)
data["xml-extract"]["trade-extract"]["trade"]

// Draft picks (1,169)
data["xml-extract"]["dp-extract"]["draftPick"]

// Lookups (many sub-arrays)
data["xml-extract"]["lookups-extract"]["lkContractTypes"]["lkContractType"]
```

---

## Standard Script Pattern

```typescript
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.1.0";
const SHARED_DIR = "./shared/pcms";

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (inline in each script)
// ─────────────────────────────────────────────────────────────────────────────

function hash(data: string): string {
  return new Bun.CryptoHasher("sha256").update(data).digest("hex");
}

function nilSafe(val: unknown): unknown {
  if (val && typeof val === "object" && "@_xsi:nil" in val) return null;
  return val;
}

function safeNum(val: unknown): number | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return isNaN(n) ? null : n;
}

function safeStr(val: unknown): string | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  return String(v);
}

function safeBool(val: unknown): boolean | null {
  const v = nilSafe(val);
  if (v === null || v === undefined) return null;
  if (typeof v === "boolean") return v;
  if (v === 1 || v === "1" || v === "Y" || v === "true") return true;
  if (v === 0 || v === "0" || v === "N" || v === "false") return false;
  return null;
}

function safeBigInt(val: unknown): string | null {
  const v = nilSafe(val);
  if (v === null || v === undefined || v === "") return null;
  try {
    return BigInt(Math.round(Number(v))).toString();
  } catch {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lineage Context
// ─────────────────────────────────────────────────────────────────────────────

interface LineageContext {
  lineage_id: number;
  s3_key: string;
  source_hash: string;
}

async function getLineageContext(extractDir: string): Promise<LineageContext> {
  const file = Bun.file(`${extractDir}/lineage.json`);
  if (await file.exists()) return file.json();
  throw new Error("Lineage file not found");
}

// ─────────────────────────────────────────────────────────────────────────────
// Upsert Helper
// ─────────────────────────────────────────────────────────────────────────────

interface UpsertResult {
  table: string;
  attempted: number;
  success: boolean;
  error?: string;
}

async function upsertBatch<T extends Record<string, unknown>>(
  schema: string,
  table: string,
  rows: T[],
  conflictColumns: string[]
): Promise<UpsertResult> {
  const fullTable = `${schema}.${table}`;
  if (rows.length === 0) {
    return { table: fullTable, attempted: 0, success: true };
  }

  try {
    const allColumns = Object.keys(rows[0]);
    const updateColumns = allColumns.filter(col => !conflictColumns.includes(col));
    const setClauses = updateColumns.map(col => `${col} = EXCLUDED.${col}`).join(", ");
    const conflictTarget = conflictColumns.join(", ");

    const query = `
      INSERT INTO ${fullTable} (${allColumns.join(", ")})
      SELECT * FROM jsonb_populate_recordset(null::${fullTable}, $1::jsonb)
      ON CONFLICT (${conflictTarget}) DO UPDATE SET ${setClauses}
      WHERE ${fullTable}.source_hash IS DISTINCT FROM EXCLUDED.source_hash
    `;

    await sql.unsafe(query, [JSON.stringify(rows)]);
    return { table: fullTable, attempted: rows.length, success: true };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    return { table: fullTable, attempted: rows.length, success: false, error: msg };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, extract_dir = SHARED_DIR) {
  const startedAt = new Date().toISOString();
  const tables: UpsertResult[] = [];
  const errors: string[] = [];

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find(e => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Get lineage context
    const ctx = await getLineageContext(baseDir);

    // Find JSON file
    const files = await readdir(baseDir);
    const jsonFile = files.find(f => f.includes("PATTERN") && f.endsWith(".json"));
    if (!jsonFile) throw new Error("JSON file not found");

    // Read pre-parsed JSON
    console.log(`Reading ${jsonFile}...`);
    const data = await Bun.file(`${baseDir}/${jsonFile}`).json();

    // Extract array: data["xml-extract"]["<type>-extract"]["<entity>"]
    const items: any[] = []; // TODO: navigate to correct path

    // Transform and upsert in batches
    const BATCH_SIZE = 500;
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      const batch = items.slice(i, i + BATCH_SIZE);
      const rows = batch.map(item => ({
        // TODO: transform fields
        source_hash: hash(JSON.stringify(item)),
      }));

      if (!dry_run) {
        const result = await upsertBatch("pcms", "TABLE_NAME", rows, ["PRIMARY_KEY"]);
        tables.push(result);
        if (!result.success) errors.push(result.error!);
      } else {
        tables.push({ table: "pcms.TABLE_NAME", attempted: rows.length, success: true });
      }
    }

    return { dry_run, started_at: startedAt, finished_at: new Date().toISOString(), tables, errors };
  } catch (e: any) {
    errors.push(e.message);
    return { dry_run, started_at: startedAt, finished_at: new Date().toISOString(), tables, errors };
  }
}
```
