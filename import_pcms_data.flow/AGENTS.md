# import_pcms_data.flow - Agent Guide

## Flow Steps

| Step | Name | Purpose |
|------|------|---------|
| A | Lineage Management | Download S3 ZIP, extract, parse XML→JSON, init lineage |
| B | Players & People | Import people, teams |
| C | Contracts | Contracts, versions, bonuses, salaries |
| D | Team Exceptions | MLE, BAE, trade exceptions, usage |
| E | Trades & Transactions | Trades, transactions, ledger |
| F | System Values | Cap values, rookie scale, NCA |
| G | Two-Way Statuses | Two-way player daily statuses |
| H | Draft Picks | Draft pick ownership |
| I | Team Budgets | Team salary/cap budgets |
| J | Waiver Priority | Waiver wire priority |
| K | Lookups | Reference/lookup tables |
| L | Finalize | Update lineage status |

## Data Flow

```
S3 ZIP → Step A extracts & parses → .shared/*.json → Steps B-K read JSON → Postgres
```

## Step A Critical Responsibilities

1. Download ZIP from S3 using `wmill.loadS3File()`
2. Extract using Bun shell: `await $\`unzip -o ${zip} -d ${dir}\``
3. Parse EVERY XML file to JSON with `fast-xml-parser`
4. Save JSON files to `.shared/` for other steps
5. Write `lineage.json` with context for other steps
6. Insert/update `pcms.pcms_lineage` row

## Steps B-K Pattern

```typescript
// 1. Read pre-parsed JSON
const data = await Bun.file(".shared/nba_pcms_full_extract/player.json").json();

// 2. Transform to DB rows
const rows = data.players.player.map(p => transformPerson(p, provenance));

// 3. Upsert to Postgres
await upsertBatch(sql, 'pcms', 'people', rows, ['person_id']);
```

## XML File → JSON File Mapping

| XML File | JSON Output | Target Tables |
|----------|-------------|---------------|
| `*_player.xml` | `player.json` | people, teams |
| `*_contract.xml` | `contract.json` | contracts, contract_versions, salaries, bonuses |
| `*_team-exception.xml` | `team-exception.json` | team_exceptions, team_exception_usage |
| `*_trade.xml` | `trade.json` | trades |
| `*_transaction.xml` | `transaction.json` | transactions |
| `*_lookup.xml` | `lookup.json` | lookups |
| `*_two-way.xml` | `two-way.json` | two_way_daily_statuses |
| `*_dp-extract.xml` | `dp-extract.json` | draft_picks |
| `*_team-budget.xml` | `team-budget.json` | team_budgets |

## Provenance Fields (add to every row)

```typescript
const provenance = {
  source_drop_file: s3_key,      // e.g., "pcms/nba_pcms_full_extract.zip"
  source_hash: hash(rawXml),     // SHA-256 of the XML element
  parser_version: "2.0.0",
  ingested_at: new Date()
};
```

## Environment Variables

- `POSTGRES_URL` - PostgreSQL connection string (set by Windmill)
- S3 credentials managed by Windmill's S3 resource
