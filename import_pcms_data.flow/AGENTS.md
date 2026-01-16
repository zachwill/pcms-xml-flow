# AGENTS.md — PCMS Data Import

## Architecture

This flow uses a **shared directory pattern** for efficiency:

1. **Script 0** downloads the ZIP from S3 once and extracts to `./shared/pcms/`
2. **Scripts 1-10** read XML files directly from `./shared/pcms/` (no S3 calls)

The flow runs with `same_worker: true`, so `./shared/` persists across all scripts.

## Flow Structure

| Script | Summary | XML Files | Target Tables |
|--------|---------|-----------|---------------|
| 0 | Download & Extract | - | pcms_lineage |
| 1 | Players & Teams | all | people, teams |
| 2 | Contracts | *contract* | contracts, contract_versions, contract_bonuses, salaries, payment_schedules |
| 3 | Team Exceptions | *team-exception* | team_exceptions, team_exception_usage |
| 4 | Trades & Transactions | *trade*, *transaction*, *ledger*, *waiver-amounts* | trades, trade_teams, trade_team_details, trade_groups, transactions, ledger_entries, transaction_waiver_amounts |
| 5 | System Values | *system-values*, *rookie-scale*, *nca* | league_system_values, rookie_scale_amounts, non_contract_amounts |
| 6 | Two-Way Statuses | *two-way* | two_way_daily_statuses |
| 7 | Draft Picks | *_dp* | draft_picks |
| 8 | Agencies & Reports | all | agencies, agents, depth_charts, injury_reports, medical_intel, scouting_reports |
| 9 | Waiver & Tax | *waiver-priority*, *tax-rates*, *tax-teams*, *team-budget* | waiver_priority, waiver_priority_ranks, league_tax_rates, tax_team_status, team_budget_snapshots |
| 10 | Lookups | *lookup* | lookups |

## Environment Variables

- `POSTGRES_URL` — database connection
- S3 credentials via Windmill's native S3 integration

## Coding Guidelines

### Imports & Database
```typescript
import { SQL } from "bun";
import { hash, upsertBatch, createSummary, finalizeSummary, safeNum, safeBool, safeBigInt, PCMSStreamParser } from "/f/ralph/utils.ts";
import { readdirSync, createReadStream } from "fs";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
const PARSER_VERSION = "2.0.0";
const SHARED_DIR = "./shared/pcms";
```

### Reading from Shared Directory
```typescript
// List XML files
const xmlFiles = readdirSync(SHARED_DIR).filter(f => f.endsWith('.xml'));

// Find specific file
const xmlFile = xmlFiles.find(f => f.includes('contract'));

// Stream parse
const stream = createReadStream(`${SHARED_DIR}/${xmlFile}`);
for await (const chunk of stream) {
  await streamParser.parseChunk(chunk);
}
```

### Getting Lineage Context
```typescript
// Preferred: flow passes lineage_id/s3_key from step a
const row = await resolvePCMSLineageContext(sql, {
  lineageId: lineage_id,
  s3Key: s3_key,
  sharedDir: extract_dir
});

// Fallbacks (handled by resolvePCMSLineageContext):
// - Read `./shared/pcms/lineage.json`
// - Query `pcms.pcms_lineage` for the latest PROCESSING row

const provenance = { source_drop_file: row.s3_key, parser_version: PARSER_VERSION, ingested_at: new Date() };
```

### Provenance Columns (every table)
- `source_drop_file`: S3 key (e.g., `pcms/nba_pcms_2025_extract.zip`)
- `source_hash`: SHA-256 of the XML content
- `parser_version`: SemVer string (e.g., `"2.0.0"`)
- `ingested_at`: timestamp of ingestion

### Money Conventions
- All amounts in **DOLLARS** (not cents)
- Use `bigint` for whole-dollar amounts
- Use `numeric` for decimal amounts or rates

### Naming Conventions
- Use `salary_year` (not season)
- Use `snake_case` for all columns
- Use `*_lk` suffix for lookup codes (e.g., `position_lk`)

### Error Handling
- Resilient: log errors per entity, continue processing
- Track failures in `pcms.pcms_lineage_audit` with `operation_type = 'FAILED'`
- Return `ImportSummary` with `errors[]` array

### File Size
Keep scripts under 500 LOC. Split by entity domain.

## Adding New Entity Types

1. Identify which XML file contains the entity
2. Add to appropriate script (or create new one if >500 LOC)
3. Create transform function: `function transformEntity(e: any, prov: any) { ... }`
4. Add streaming parser and batch upsert logic
5. Update this AGENTS.md table
