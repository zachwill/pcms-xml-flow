# TypeScript → Python Conversion

Convert the verbose TypeScript import scripts to concise Python/Polars.

**Each script must be self-contained** (Windmill inline scripts can't share code).

## Consolidation Plan

| Python Script | Replaces | Tables | Est. Lines |
|---------------|----------|--------|------------|
| lookups.py | lookups.inline_script.ts (244 lines) | pcms.lookups | ~80 |
| people.py | people_&_identity.inline_script.ts (352 lines) | people, agencies, agents | ~100 |
| contracts.py | contracts.inline_script.ts (576 lines) | contracts, versions, bonuses, salaries, payment_schedules, protections | ~180 |
| transactions.py | transactions_*.ts (654) + team_exceptions.ts (211) = 865 lines | trades, trade_teams, trade_team_details, trade_groups, transactions, ledger_entries, waiver_amounts, team_exceptions, exception_usage | ~220 |
| league.py | league_config.ts (679) + draft.ts (375) = 1054 lines | system_values, rookie_scale, nca, salary_scales, projections, tax_rates, apron_constraints, draft_picks, draft_summaries | ~250 |
| teams.py | team_financials.ts (539) + two-way.ts (446) = 985 lines | budget_snapshots, tax_summaries, tax_team_status, waiver_priority, waiver_ranks, team_transactions, two_way_daily, two_way_contract_utility, two_way_game_utility, team_two_way_capacity | ~220 |
| finalize.py | finalize_lineage.inline_script.ts (68 lines) | (aggregates results) | ~50 |

**Total: ~4,100 TS lines → ~1,100 Python lines (73% reduction)**

---

## Tasks

### Phase 1: Simple Scripts
- [x] `lookups.inline_script.py` — normalize 43 lookup tables into pcms.lookups (204 lines vs 244 TS)
- [x] `people_&_identity.inline_script.py` — players, agencies, agents (265 lines vs 352 TS)

### Phase 2: Core Data
- [x] `contracts.inline_script.py` — contracts + all nested (versions, bonuses, salaries, payments, protections) (327 lines vs 576 TS)
- [x] `transactions.inline_script.py` — trades, ledger, waiver_amounts, team_exceptions, exception_usage (599 lines vs 865 TS)

### Phase 3: Config & Teams
- [x] `league_config.inline_script.py` — system values, scales, projections, tax rates, apron constraints, draft picks, draft summaries (625 lines vs 1054 TS)
- [x] `team_financials.inline_script.py` — budgets, tax status, waiver priority, two-way

### Phase 4: Finalize & Cleanup
- [ ] `finalize_lineage.inline_script.py` — aggregate results, report errors
- [ ] Update `flow.yaml` to use Python scripts instead of TypeScript
- [ ] Delete old TypeScript scripts

---

## Script Template

Each script follows this pattern:

```python
"""
<Description>

Upserts into:
- pcms.<table1>
- pcms.<table2>
"""
import os
import json
from pathlib import Path
from datetime import datetime
import polars as pl
import psycopg

# ─────────────────────────────────────────────────────────────────────────────
# Helpers (inline - no shared imports in Windmill)
# ─────────────────────────────────────────────────────────────────────────────

def upsert(conn, table: str, rows: list[dict], conflict_keys: list[str]) -> int:
    """Upsert rows. Auto-generates ON CONFLICT DO UPDATE for non-key columns."""
    if not rows:
        return 0
    cols = list(rows[0].keys())
    update_cols = [c for c in cols if c not in conflict_keys]
    
    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)
    conflict = ", ".join(conflict_keys)
    updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])
    
    sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO UPDATE SET {updates}"
    
    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(r[c] for c in cols) for r in rows])
    conn.commit()
    return len(rows)

def find_extract_dir(base: str = "./shared/pcms") -> Path:
    """Find the extract directory (handles nested subdirectory)."""
    base_path = Path(base)
    subdirs = [d for d in base_path.iterdir() if d.is_dir()]
    return subdirs[0] if subdirs else base_path

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(dry_run: bool = False, extract_dir: str = "./shared/pcms"):
    started_at = datetime.now().isoformat()
    tables = []
    
    base_dir = find_extract_dir(extract_dir)
    conn = psycopg.connect(os.environ["POSTGRES_URL"])
    
    try:
        # Read JSON
        data = pl.read_json(base_dir / "data.json")
        
        # Transform with Polars
        rows = (
            data
            .rename({"old_name": "new_name"})
            .with_columns([
                pl.col("some_flg").alias("is_something"),
                pl.lit(datetime.now()).alias("ingested_at"),
            ])
            .unique(subset=["id_column"])
            .to_dicts()
        )
        
        if not dry_run:
            count = upsert(conn, "pcms.table_name", rows, ["id_column"])
            tables.append({"table": "pcms.table_name", "attempted": count, "success": True})
        else:
            tables.append({"table": "pcms.table_name", "attempted": len(rows), "success": True})
        
        return {
            "dry_run": dry_run,
            "started_at": started_at,
            "finished_at": datetime.now().isoformat(),
            "tables": tables,
            "errors": [],
        }
    except Exception as e:
        return {
            "dry_run": dry_run,
            "started_at": started_at,
            "finished_at": datetime.now().isoformat(),
            "tables": tables,
            "errors": [str(e)],
        }
    finally:
        conn.close()
```

---

## Reference: TypeScript → Python Patterns

### JSON Reading
```typescript
// TypeScript
const contracts: any[] = await Bun.file(`${baseDir}/contracts.json`).json();
```
```python
# Python
contracts = pl.read_json(base_dir / "contracts.json")
```

### Column Rename + Derive
```typescript
// TypeScript (verbose - every field explicit)
const row = {
  contract_id: c.contract_id,
  is_sign_and_trade: c.sign_and_trade_flg,
  team_code: signingTeamId ? teamCodeMap.get(signingTeamId) : null,
};
```
```python
# Python (concise)
df = df.rename({"sign_and_trade_flg": "is_sign_and_trade"})
df = df.with_columns([
    pl.col("signing_team_id").map_dict(team_code_map).alias("team_code"),
])
```

### Nested Flattening
```typescript
// TypeScript
for (const c of contracts) {
  const versions = asArray(c?.versions?.version);
  for (const v of versions) {
    versionRows.push({ contract_id: c.contract_id, ...v });
  }
}
```
```python
# Python
versions = (
    contracts
    .select("contract_id", "versions")
    .explode("versions")
    .unnest("versions")
)
```

### Dedupe
```typescript
// TypeScript
const deduped = dedupeByKey(rows, r => `${r.contract_id}|${r.version_number}`);
```
```python
# Python
deduped = df.unique(subset=["contract_id", "version_number"])
```

### Upsert
```typescript
// TypeScript (must list every column 3x)
await sql`
  INSERT INTO pcms.contracts ${sql(rows)}
  ON CONFLICT (contract_id) DO UPDATE SET
    player_id = EXCLUDED.player_id,
    // ... 20 more lines
`;
```
```python
# Python (auto-generates SET clause)
upsert(conn, "pcms.contracts", rows, ["contract_id"])
```
