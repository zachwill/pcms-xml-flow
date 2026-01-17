# Consolidate Import Scripts

## Goal

Reduce `import_pcms_data.flow/` from **18 TypeScript scripts** to **~10 scripts** by:
1. Merging related scripts by domain
2. Doing upfront deduping (not per-batch)
3. Removing duplicate code (transaction_waiver_amounts is in 2 places)

Each script remains **self-contained** (Windmill style) - helpers are inline, not shared.

---

## Current State (18 scripts, ~4500 LOC)

| Script | LOC | Tables |
|--------|-----|--------|
| `lookups` | 220 | lookups, teams |
| `players_&_people` | 189 | people |
| `agents_&_agencies` | 195 | agencies, agents |
| `generate_nba_draft_picks` | 149 | draft_picks |
| `draft_picks` | 190 | draft_picks |
| `draft_pick_summaries` | 110 | draft_pick_summaries |
| `contracts,_versions_...` | 500 | contracts, versions, salaries, bonuses, etc. |
| `team_exceptions_&_usage` | 210 | team_exceptions, team_exception_usage |
| `trades,_transactions_&_ledger` | 653 | trades, trade_*, transactions, ledger, waiver_amounts |
| `transaction_waiver_amounts` | 177 | **DUPLICATE** - remove this |
| `system_values,_rookie_scale_&_nca` | 426 | league_system_values, rookie_scale, nca |
| `league_salary_scales_&_protections` | 184 | salary_scales, cap_projections |
| `team_budgets` | 285 | team_budget_snapshots, tax_summary |
| `waiver_priority_&_ranks` | 329 | waiver_priority, waiver_priority_ranks, tax_rates, tax_team_status |
| `team_transactions` | 146 | team_transactions |
| `two-way_daily_statuses` | 200 | two_way_daily_statuses |
| `two-way_utility` | 310 | two_way_*_utility, team_two_way_capacity |
| `finalize_lineage` | 68 | (aggregator) |

---

## Target State (10 scripts)

| # | New Script | Merges | Tables |
|---|------------|--------|--------|
| 1 | `lookups` | - | lookups, teams |
| 2 | `people_identity` | players + agents/agencies | people, agencies, agents |
| 3 | `draft` | draft_picks + summaries + generate_nba | draft_picks, draft_pick_summaries |
| 4 | `contracts` | - | contracts, versions, salaries, bonuses, payments, protections |
| 5 | `team_exceptions` | - | team_exceptions, team_exception_usage |
| 6 | `transactions` | remove duplicate waiver_amounts script | trades, trade_*, transactions, ledger, waiver_amounts |
| 7 | `league_config` | system_values + salary_scales | league_system_values, rookie_scale, nca, salary_scales, cap_projections, tax_rates, apron_constraints |
| 8 | `team_financials` | budgets + waiver_priority + team_transactions | budget_snapshots, tax_summary, tax_team_status, waiver_priority*, team_transactions |
| 9 | `two_way` | daily_statuses + utility | two_way_daily_statuses, two_way_*_utility, team_two_way_capacity |
| 10 | `finalize_lineage` | - | (aggregator) |

---

## Checklist

### Phase 1: Quick Wins

- [x] **Delete `transaction_waiver_amounts.inline_script.ts`** — already handled in `trades,_transactions_&_ledger`
- [x] **Update `flow.yaml`** — remove step for deleted script

### Phase 2: Merge Scripts

Each merged script should:
- Keep helpers inline (toIntOrNull, asArray, etc.)
- Dedupe **upfront** before batching (not per-batch)
- Use larger batch sizes where safe (100-500 instead of 10)

- [x] **2.1 `people_identity.inline_script.ts`**
  - Merge: `players_&_people` + `agents_&_agencies`
  - Tables: people, agencies, agents
  - Order: agencies → agents → people (FK order)

- [x] **2.2 `draft.inline_script.ts`**
  - Merge: `draft_picks` + `draft_pick_summaries` + `generate_nba_draft_picks`
  - Tables: draft_picks, draft_pick_summaries
  - Logic: PCMS picks first, then generated NBA picks (dedupe by draft_year/round/pick/league)

- [x] **2.3 `league_config.inline_script.ts`**
  - Merge: `system_values,_rookie_scale_&_nca` + `league_salary_scales_&_protections`
  - Tables: league_system_values, rookie_scale_amounts, non_contract_amounts, league_salary_scales, league_salary_cap_projections, league_tax_rates, apron_constraints

- [x] **2.4 `team_financials.inline_script.ts`**
  - Merge: `team_budgets` + `waiver_priority_&_ranks` + `team_transactions`
  - Tables: team_budget_snapshots, team_tax_summary_snapshots, tax_team_status, waiver_priority, waiver_priority_ranks, team_transactions

- [x] **2.5 `two_way.inline_script.ts`**
  - Merge: `two-way_daily_statuses` + `two-way_utility`
  - Tables: two_way_daily_statuses, two_way_contract_utility, two_way_game_utility, team_two_way_capacity

### Phase 3: Cleanup

- [x] Delete old scripts after each merge is tested
- [ ] Update `flow.yaml` with new script names and order
- [ ] Update `finalize_lineage` summaries array to match new steps

---

## Upfront Dedupe Pattern

**Before (per-batch, inefficient):**
```typescript
for (let i = 0; i < rows.length; i += BATCH_SIZE) {
  const batch = rows.slice(i, i + BATCH_SIZE);
  // dedupe within batch only
  const seen = new Map();
  for (const r of batch) seen.set(r.id, r);
  const deduped = [...seen.values()];
  await sql`INSERT ...`;
}
```

**After (upfront, then batch):**
```typescript
// Dedupe entire dataset first
const seen = new Map<number, any>();
for (const r of rows) seen.set(r.id, r);
const deduped = [...seen.values()];

// Then batch insert
for (let i = 0; i < deduped.length; i += BATCH_SIZE) {
  const batch = deduped.slice(i, i + BATCH_SIZE);
  await sql`INSERT ...`;
}
```

---

## Flow Order (after consolidation)

```yaml
modules:
  - t: PCMS XML to JSON (Python)
  - a: Lookups
  - b: People & Identity
  - c: Draft
  - d: Contracts
  - e: Team Exceptions
  - f: Transactions (trades, ledger, waiver amounts)
  - g: League Config
  - h: Team Financials
  - i: Two-Way
  - l: Finalize Lineage
```

---

## Notes

- Scripts stay self-contained (Windmill requirement)
- Inline helpers in each script (toIntOrNull, asArray, buildTeamCodeMap, etc.)
- Target ~500-600 LOC per consolidated script (max ~800-1000 for contracts/transactions)
