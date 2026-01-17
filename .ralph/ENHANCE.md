# PCMS Enhancement: team_code + Draft Pick Summaries

Reference docs:
- `TODO.md` — Full issue list with column mappings per script
- `DRAFT_PICKS.md` — Draft pick summaries schema and parsing details
- `migrations/003_team_code_and_draft_picks.sql` — Schema changes (already applied)
- `migrations/004_draft_pick_summaries.sql` — Draft pick summaries table (already applied)

## Helper Pattern (add to each script)

```typescript
// Build team_id → team_code lookup map
const lookups: any = await Bun.file(`${baseDir}/lookups.json`).json();
const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
const teamCodeMap = new Map<number, string>();
for (const t of teamsData) {
  if (t.team_id && t.team_code) {
    teamCodeMap.set(t.team_id, t.team_code);
  }
}

// Usage in row mapping:
team_code: teamCodeMap.get(record.team_id) ?? null,
```

---

## Phase 1: Update Scripts for team_code

- [x] `players_&_people.inline_script.ts` — add `team_code`, `draft_team_code`, `dlg_returning_rights_team_code`, `dlg_team_code`
- [x] `contracts,_versions,_bonuses_&_salaries.inline_script.ts` — add `team_code`, `sign_and_trade_to_team_code` to contracts table
- [x] `trades,_transactions_&_ledger.inline_script.ts` — add `from_team_code`, `to_team_code`, `rights_team_code`, `sign_and_trade_team_code` to transactions; `team_code` to ledger_entries (also fix null team_id filter), trade_groups, trade_team_details, trade_teams
- [x] `draft_picks.inline_script.ts` — add `original_team_code`, `current_team_code`
- [ ] `team_exceptions_&_usage.inline_script.ts` — add `team_code`
- [ ] `team_budgets.inline_script.ts` — add `team_code` to team_budget_snapshots, tax_team_status, team_tax_summary_snapshots
- [ ] `system_values,_rookie_scale_&_nca.inline_script.ts` — add `team_code` to non_contract_amounts
- [ ] `transaction_waiver_amounts.inline_script.ts` — add `team_code`
- [ ] `two-way_daily_statuses.inline_script.ts` — add `status_team_code`, `contract_team_code`, `signing_team_code`
- [ ] `two-way_utility.inline_script.ts` — add `contract_team_code`, `signing_team_code` to two_way_contract_utility; `team_code`, `opposition_team_code` to two_way_game_utility
- [ ] `waiver_priority_&_ranks.inline_script.ts` — add `team_code`
- [ ] `lookups.inline_script.ts` — for teams table, use `team_code` from source data (not `team_name_short`)

---

## Phase 2: New Scripts

- [ ] Create `draft_pick_summaries.inline_script.ts` + update `flow.yaml` — import from `draft_pick_summaries.json`, see DRAFT_PICKS.md for schema
- [ ] Create `generate_nba_draft_picks.inline_script.ts` + update `flow.yaml` — generate NBA draft picks from `players.json` (see TODO.md for pattern)
