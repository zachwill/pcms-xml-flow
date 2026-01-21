#!/usr/bin/env bun
/**
 * python.ts — Convert TypeScript import scripts to Python/Polars
 *
 * This agent converts the verbose TypeScript import scripts to concise
 * Python scripts using Polars for transforms and psycopg for upserts.
 */
import { loop, work, generate, halt } from "./core";

const TASK_FILE = ".ralph/PYTHON.md";

loop({
  name: "python",
  taskFile: TASK_FILE,
  timeout: "8m",

  run(state) {
    if (state.hasTodos) {
      return work(
        `
You are converting TypeScript/Bun import scripts to Python/Polars.

## Current Task
Look at ${TASK_FILE} for your current task.

## Guidelines

### Stack
- **Polars** for all transforms (not Pandas)
- **psycopg** (v3) with \`executemany\` or \`copy\` for bulk loads
- Python 3.11+

### Pattern to follow
Each script should:
1. Read clean JSON with \`pl.read_json()\`
2. Rename columns with \`.rename()\` or \`.with_columns()\`
3. Derive columns with \`.with_columns(pl.when(...).then(...)...)\`
4. Flatten nested with \`.explode()\` + \`.unnest()\`
5. Dedupe with \`.unique(subset=[...])\`
6. Upsert via shared helper (see lib/db.py)

### Self-contained scripts
Each script must be fully self-contained (Windmill requirement). Include the upsert helper inline:

\`\`\`python
import os
import json
import polars as pl
import psycopg

def upsert(conn, table: str, rows: list[dict], conflict_keys: list[str]):
    """Upsert rows to a table. Generates ON CONFLICT DO UPDATE for all non-key columns."""
    if not rows:
        return 0
    cols = list(rows[0].keys())
    update_cols = [c for c in cols if c not in conflict_keys]
    
    placeholders = ", ".join([f"%s" for _ in cols])
    col_list = ", ".join(cols)
    conflict = ", ".join(conflict_keys)
    updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])
    
    sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO UPDATE SET {updates}"
    
    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(r[c] for c in cols) for r in rows])
    conn.commit()
    return len(rows)
\`\`\`

### Consolidation targets
We're consolidating 10 TypeScript scripts into ~5-6 Python scripts:

| Python Script | Replaces | Tables |
|---------------|----------|--------|
| lookups.py | lookups.inline_script.ts | pcms.lookups |
| people.py | people_&_identity.inline_script.ts | pcms.people, pcms.agencies, pcms.agents |
| contracts.py | contracts.inline_script.ts | pcms.contracts, pcms.contract_versions, pcms.contract_bonuses, pcms.salaries, pcms.payment_schedules, pcms.contract_protections |
| transactions.py | transactions_*.ts + team_exceptions.ts | pcms.trades, pcms.trade_teams, pcms.trade_team_details, pcms.trade_groups, pcms.transactions, pcms.ledger_entries, pcms.transaction_waiver_amounts, pcms.team_exceptions, pcms.team_exception_usage |
| league.py | league_config.ts + draft.ts | pcms.league_system_values, pcms.rookie_scale_amounts, pcms.non_contract_amounts, pcms.league_salary_scales, pcms.league_salary_cap_projections, pcms.league_tax_rates, pcms.apron_constraints, pcms.draft_picks, pcms.draft_pick_summaries |
| teams.py | team_financials.ts + two-way.ts | pcms.team_budget_snapshots, pcms.team_tax_summary_snapshots, pcms.tax_team_status, pcms.waiver_priority, pcms.waiver_priority_ranks, pcms.team_transactions, pcms.two_way_daily_statuses, pcms.two_way_contract_utility, pcms.two_way_game_utility, pcms.team_two_way_capacity |
| finalize.py | finalize_lineage.inline_script.ts | (aggregates results) |

## Actions
1. Pick the next unchecked task
2. Implement it following the pattern above
3. Check off completed items in ${TASK_FILE}
4. Commit: git add -A && git commit -m "<what you did>"
5. Exit after committing
      `,
        { thinking: "medium", model: "gemini-3-flash", timeout: "8m" }
      );
    }

    // No tasks - should not happen since we manually populate
    return halt("No tasks in " + TASK_FILE);
  },
});
