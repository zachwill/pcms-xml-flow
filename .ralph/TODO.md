# PCMS Script Refactor

Refactor all scripts to use Bun-native APIs (read JSON, not XML).

## Scripts

- [ ] contracts,_versions,_bonuses_&_salaries.inline_script.ts
- [ ] lookups.inline_script.ts
- [ ] team_exceptions_&_usage.inline_script.ts
- [ ] trades,_transactions_&_ledger.inline_script.ts
- [ ] team_budgets.inline_script.ts
- [ ] draft_picks.inline_script.ts
- [ ] system_values,_rookie_scale_&_nca.inline_script.ts
- [ ] two-way_daily_statuses.inline_script.ts
- [ ] waiver_priority_&_ranks.inline_script.ts
- [ ] finalize_lineage.inline_script.ts

## Reference

- **Pattern**: See TODO.md for standard script pattern with all helpers
- **Example**: `import_pcms_data.flow/players_&_people.inline_script.ts`
- **Data paths**: Run `bun run scripts/show-all-paths.ts`
- **Inspect data**: Run `bun run scripts/inspect-json-structure.ts <type> --sample`

## Key Requirements

1. Read pre-parsed JSON from `.shared/` (not XML)
2. Use `Bun.file()` for file I/O
3. Use `SQL` from `bun` for Postgres
4. Use `Bun.CryptoHasher` for hashing
5. Inline ALL helpers (no imports from utils.ts)
6. Handle `{ "@_xsi:nil": "true" }` with `nilSafe()`
