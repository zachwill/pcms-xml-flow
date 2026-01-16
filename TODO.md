# TODO - PCMS XML Flow v3.0

## What Changed

**Before (v2.x):** Each script had 50+ lines of helper functions (`nilSafe`, `safeNum`, `safeStr`, etc.) to handle messy XML-parsed JSON.

**After (v3.0):** Lineage step outputs CLEAN JSON with snake_case keys and proper nulls. Import scripts just read and insert.

## Completed ✅

- [x] `scripts/parse-xml-to-json.ts` - Outputs clean JSON for local dev
- [x] `lineage_management_(s3_&_state_tracking).inline_script.ts` - Outputs clean JSON in flow
- [x] `players_&_people.inline_script.ts` - Simplified (270 → 110 lines)

## TODO: Simplify Import Scripts

All these scripts need to be rewritten to the new simple pattern:

- [ ] `contracts,_versions,_bonuses_&_salaries.inline_script.ts`
- [ ] `lookups.inline_script.ts`
- [ ] `team_exceptions_&_usage.inline_script.ts`
- [ ] `trades,_transactions_&_ledger.inline_script.ts`
- [ ] `team_budgets.inline_script.ts`
- [ ] `draft_picks.inline_script.ts`
- [ ] `system_values,_rookie_scale_&_nca.inline_script.ts`
- [ ] `two-way_daily_statuses.inline_script.ts`
- [ ] `waiver_priority_&_ranks.inline_script.ts`
- [ ] `finalize_lineage.inline_script.ts`

## New Script Pattern

```typescript
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

export async function main(dry_run = false, lineage_id?: number, s3_key?: string, extract_dir = "./shared/pcms") {
  const startedAt = new Date().toISOString();

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find(e => e.isDirectory());
    const baseDir = subDir ? `${extract_dir}/${subDir.name}` : extract_dir;

    // Read clean JSON (already snake_case, nulls handled)
    const data: any[] = await Bun.file(`${baseDir}/FILENAME.json`).json();
    console.log(`Found ${data.length} records`);

    if (dry_run) {
      return { dry_run: true, started_at: startedAt, finished_at: new Date().toISOString(), tables: [...], errors: [] };
    }

    // Map JSON fields to DB columns (only if names differ)
    const rows = data.map(d => ({
      ...d,
      // Add any provenance fields
      source_drop_file: s3_key,
      ingested_at: new Date(),
    }));

    // Upsert
    await sql`
      INSERT INTO pcms.TABLE_NAME ${sql(rows)}
      ON CONFLICT (PRIMARY_KEY) DO UPDATE SET
        field1 = EXCLUDED.field1,
        updated_at = EXCLUDED.updated_at
    `;

    return { dry_run: false, started_at: startedAt, finished_at: new Date().toISOString(), tables: [...], errors: [] };
  } catch (e: any) {
    return { dry_run, started_at: startedAt, finished_at: new Date().toISOString(), tables: [], errors: [e.message] };
  }
}
```

## Clean JSON Files Reference

| JSON File | Records | Tables |
|-----------|---------|--------|
| `players.json` | 14,421 | `pcms.people` |
| `contracts.json` | 8,071 | `pcms.contracts`, `pcms.contract_versions`, `pcms.salaries` |
| `transactions.json` | 232,417 | `pcms.transactions` |
| `ledger.json` | 50,713 | `pcms.transaction_ledger` |
| `trades.json` | 1,731 | `pcms.trades` |
| `draft_picks.json` | 1,169 | `pcms.draft_picks` |
| `team_exceptions.json` | nested | `pcms.team_exceptions`, `pcms.exception_usage` |
| `team_budgets.json` | nested | `pcms.team_budgets` |
| `lookups.json` | 43 tables | `pcms.lookups` |
| `yearly_system_values.json` | 112 | `pcms.system_values` |
| `rookie_scale_amounts.json` | 1,556 | `pcms.rookie_scale` |
| `non_contract_amounts.json` | 3,998 | `pcms.non_contract_amounts` |
| `two_way.json` | nested | `pcms.two_way_*` |
| `tax_rates.json` | 119 | `pcms.tax_rates` |
| `tax_teams.json` | 265 | `pcms.tax_teams` |

## Nested Structures

Some files have nested data that maps to multiple tables:

**contracts.json:**
```
contract
  └── versions.version[]
        └── salaries.salary[]
        └── bonuses.bonus[]
        └── payment_schedules.payment_schedule[]
```

**team_exceptions.json:**
```
exception_teams
  └── team_exception[]
        └── team_exception_detail[]
```

For these, extract and flatten in the import script:
```typescript
const contracts = await Bun.file(`${baseDir}/contracts.json`).json();

// Flatten versions
const versions = contracts.flatMap(c => 
  (c.versions?.version || []).map(v => ({ contract_id: c.contract_id, ...v }))
);

// Flatten salaries
const salaries = versions.flatMap(v =>
  (v.salaries?.salary || []).map(s => ({ version_id: v.version_id, ...s }))
);
```
