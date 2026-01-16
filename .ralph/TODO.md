# PCMS Script Refactor

Rewrite all flow scripts to follow Bun patterns (see AGENTS.md, TODO.md for context).

## Requirements for Each Script
- Read pre-parsed JSON (not stream XML)
- Use Bun-native APIs (`Bun.file()`, `SQL`, `$`)
- Inline all helpers (no `utils.ts` imports)
- Explicit SQL with `jsonb_populate_recordset`
- Handle `xsi:nil` with `nilSafe()` wrapper
- Batch upserts (500 records)

---

## High Priority

- [ ] `contracts,_versions,_bonuses_&_salaries.inline_script.ts` — contracts, contract_versions, contract_bonuses, salaries, payment_schedules (nested structure)
- [ ] `lookups.inline_script.ts` — lookups table (many sub-tables in JSON)

## Medium Priority

- [ ] `team_exceptions_&_usage.inline_script.ts` — team_exceptions, exception_usage
- [ ] `trades,_transactions_&_ledger.inline_script.ts` — trades, transactions, ledger_entries (3 JSON files)
- [ ] `team_budgets.inline_script.ts` — team_budgets
- [ ] `draft_picks.inline_script.ts` — draft_picks

## Lower Priority

- [ ] `system_values,_rookie_scale_&_nca.inline_script.ts` — system_values, rookie_scale, nca
- [ ] `two-way_daily_statuses.inline_script.ts` — two_way_daily_statuses
- [ ] `waiver_priority_&_ranks.inline_script.ts` — waiver_priority, waiver_ranks
- [ ] `finalize_lineage.inline_script.ts` — just inline the helpers

---

## Completed

- [x] `lineage_management_(s3_&_state_tracking).inline_script.ts`
- [x] `players_&_people.inline_script.ts`
