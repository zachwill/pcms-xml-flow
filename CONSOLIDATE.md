# CONSOLIDATE.md — Reducing `import_pcms_data.flow/` Script Count

## Why consolidate?
Right now we have ~14 import scripts in `import_pcms_data.flow/` (not counting locks) that all repeat the same handful of patterns:

- resolve `baseDir` from `extract_dir` (subfolder vs direct)
- load `lookups.json` and build a `team_id → team_code` map
- small helper functions (`asArray`, `toIntOrNull`, `normalizeVersionNumber`, etc.)
- batch loops + very repetitive `INSERT … ON CONFLICT DO UPDATE SET …` blocks
- the same return shape (`{ dry_run, started_at, finished_at, tables, errors }`)

The lineage step already gives us “clean JSON” (snake_case + nulls), so the import scripts are mostly *plumbing + upserts*. That makes them great candidates for consolidation without losing clarity.

Constraints:
- Keep scripts below ~600–800 LOC (agent + human readability)
- Preserve some “blast radius” isolation for the huge tables (transactions/ledger)
- Keep ordering constraints clear (players before contracts; lookups before anything that depends on team_code; etc.)

---

## Quick inventory (current scripts)

**Lineage + finalize**
- `lineage_management_(s3_&_state_tracking).inline_script.ts` — S3 zip → XML → clean JSON
- `finalize_lineage.inline_script.ts` — aggregates step summaries

**Entity imports**
- `players_&_people.inline_script.ts` → `pcms.people`
- `contracts,_versions,_bonuses_&_salaries.inline_script.ts` → `pcms.contracts` + related tables
- `trades,_transactions_&_ledger.inline_script.ts` → trades + transactions + ledger + waiver amounts

**“Smaller” feature/table imports**
- `lookups.inline_script.ts` → `pcms.lookups`
- `agents_&_agencies.inline_script.ts` → `pcms.agencies`, `pcms.agents`
- `draft_picks.inline_script.ts` → `pcms.draft_picks`
- `draft_pick_summaries.inline_script.ts` → `pcms.draft_pick_summaries`
- `generate_nba_draft_picks.inline_script.ts` → *also* `pcms.draft_picks`
- `team_exceptions_&_usage.inline_script.ts` → team exceptions tables
- `team_budgets.inline_script.ts` → team budgets + tax summary snapshots
- `system_values,_rookie_scale_&_nca.inline_script.ts` → system values + rookie scale + NCA
- `league_salary_scales_&_protections.inline_script.ts` → salary scales + cap projections
- `waiver_priority_&_ranks.inline_script.ts` → waiver priority + tax rates + tax teams
- `two-way_daily_statuses.inline_script.ts` → two-way daily statuses
- `two-way_utility.inline_script.ts` → two-way utility + capacity + contract utility
- `transaction_waiver_amounts.inline_script.ts` → waiver amounts (duplicated by trades script)

Notable issues/opportunities spotted while reading:
- `pcms.transaction_waiver_amounts` is imported in **two places**:
  - `trades,_transactions_&_ledger…` (reads `transaction_waiver_amounts.json` and upserts)
  - `transaction_waiver_amounts…` (does the same)
  We should pick one home.
- `flow.yaml` passes `extract_dir` inconsistently:
  - many steps use `results.a.extract_dir`
  - some use static `./shared/pcms`
  - `finalize_lineage` summaries array does **not** include some steps (`m`, `n`, `o`, `p`)

---

## Consolidation strategy

### 1) Consolidate code patterns first (shared helpers)
Even if we reduce the *number* of scripts, we should stop copy/pasting the same plumbing.

Create a small shared module (example names):
- `import_pcms_data.flow/_shared.ts`

Put these in there:
- `resolveBaseDir(extractDir)`
- `loadLookups(baseDir)`
- `buildTeamCodeMap(lookups)`
- common scalar coercers: `toIntOrNull`, `toNumOrNull`, `toBoolOrNull`, `toDateOnly`, `normalizeVersionNumber`, `asArray`
- a standard `makeSummary({ startedAt, dryRun, tables, errors })`

This alone will cut LOC by a lot, and makes consolidation safer.

### 2) Consolidate by *domain*, not by “number of JSON files”
The cleanest boundaries we have are:
- **People + identity** (players/people; agents/agencies)
- **Contracts** (contracts + versions + salaries + payment schedules)
- **Transactions/trades/ledger** (very large; keep isolated)
- **Draft assets** (draft picks, summaries, generated NBA picks)
- **League/team configuration** (system values, salary scales, waiver priority + taxes, team budgets)
- **Two-way** (daily statuses + utility/capacity)

This yields fewer scripts while keeping each script mentally coherent.

### 3) Keep “big data” steps isolated
Even if we could merge everything into one script, we shouldn’t.

The biggest tables (and most likely to blow up runtime/memory or hit DB limits) are:
- `pcms.transactions` (~232k)
- `pcms.ledger_entries` (~50k)

Those should remain in a dedicated “transactions” script so failures/retries are simple.

---

## Proposed new script layout (6–7 scripts total)

Below is a concrete proposal that should stay under the 600–800 LOC preference.

### A) `core_people.inline_script.ts`
**Inputs**: `players.json`, `lookups.json`

**Outputs**:
- `pcms.people`
- `pcms.agencies`
- `pcms.agents`

Rationale:
- `agents_&_agencies` already depends on `players.json` + `lookups.json`.
- This is “identity-ish” data and changes together.

Notes:
- Upsert order: agencies → agents → people (or people first; FK constraints dictate)
- Still fine as one script: people is ~14k rows (batchable), agencies/agents are small.

### B) `contracts.inline_script.ts`
Keep mostly as-is:
- `pcms.contracts`
- `pcms.contract_versions`
- `pcms.contract_bonuses`
- `pcms.salaries`
- `pcms.payment_schedules`

Rationale:
- This script is already a cohesive unit and moderately complex.

### C) `transactions.inline_script.ts`
Keep as the dedicated “big data” pipeline:
- `pcms.trades`
- `pcms.trade_teams`
- `pcms.trade_team_details`
- `pcms.trade_groups`
- `pcms.transactions`
- `pcms.ledger_entries`
- `pcms.transaction_waiver_amounts`

Rationale:
- This is already grouped well.
- If we keep waiver amounts here, we can remove `transaction_waiver_amounts.inline_script.ts` entirely.

### D) `draft.inline_script.ts`
**Inputs**: `draft_picks.json`, `draft_pick_summaries.json`, `players.json`, `lookups.json`

**Outputs**:
- `pcms.draft_picks` (from extract + generated NBA picks)
- `pcms.draft_pick_summaries`

Rationale:
- Draft picks + summaries are conceptually one “draft assets” unit.
- `generate_nba_draft_picks` currently upserts into the same table as `draft_picks`.

Implementation idea:
- Upsert extracted picks first, then upsert generated NBA picks using the unique constraint `(draft_year, round, pick_number_int, league_lk)`.

### E) `team_financials.inline_script.ts`
**Inputs**: `team_budgets.json`, `waiver_priority.json`, `tax_rates.json`, `tax_teams.json`, `lookups.json`

**Outputs**:
- `pcms.team_budget_snapshots`
- `pcms.team_tax_summary_snapshots`
- `pcms.waiver_priority`
- `pcms.waiver_priority_ranks`
- `pcms.league_tax_rates`
- `pcms.tax_team_status`

Rationale:
- All of these are “team/year financial state” and tax/waiver configuration.
- This keeps `system_values` separate (next script) to avoid a mega-file.

### F) `league_config.inline_script.ts`
**Inputs**: `yearly_system_values.json`, `rookie_scale_amounts.json`, `non_contract_amounts.json`, `yearly_salary_scales.json`, `cap_projections.json`, `lookups.json`

**Outputs**:
- `pcms.league_system_values`
- `pcms.rookie_scale_amounts`
- `pcms.non_contract_amounts`
- `pcms.league_salary_scales`
- `pcms.league_salary_cap_projections`

Rationale:
- These are “league-level constants + projections”.
- Combining these two current scripts is likely still under ~800 LOC.

### G) `two_way.inline_script.ts`
**Inputs**: `two_way.json`, `two_way_utility.json`, `lookups.json`

**Outputs**:
- `pcms.two_way_daily_statuses`
- `pcms.two_way_game_utility`
- `pcms.two_way_contract_utility`
- `pcms.team_two_way_capacity`

Rationale:
- Both current scripts are two-way domain, share parsing quirks, and share team code lookup.

---

## What stays *not* consolidated
- `lineage_management…` should remain its own step. It’s operationally distinct and already has a lot of logic.
- `finalize_lineage…` stays a small aggregator.

---

## Flow (`flow.yaml`) implications

If we collapse the scripts as above, `flow.yaml` becomes easier:
- fewer modules
- clearer ordering
- fewer places to forget to pass `extract_dir`
- fewer missing items in the `finalize_lineage` summaries array

Recommended cleanups while we’re here:
1. Use `results.a.extract_dir ?? './shared/pcms'` for *every* step (remove `static: ./shared/pcms`).
2. Ensure every import step contributes to `finalize_lineage` summaries.
3. Remove the redundant `transaction_waiver_amounts` step if waiver amounts live in the transactions script.

---

## Stretch goal: data-driven “import jobs” inside fewer scripts
Once we have `_shared.ts`, we can go one step further without building an unmaintainable mega-script:

Inside each domain script, define small “jobs”:

```ts
const jobs = [
  {
    name: "pcms.league_salary_scales",
    source: () => Bun.file(`${baseDir}/yearly_salary_scales.json`).json(),
    map: (rows) => rows.map(toScaleRow).filter(Boolean),
    upsert: (rows) => sql`INSERT INTO ...`,
  },
  // ...
];
```

That lets each script stay organized as a list of independent import blocks, while still being one Windmill step.

---

## Suggested next steps
1. Add `import_pcms_data.flow/_shared.ts` and update current scripts to use it (no behavior changes).
2. Remove duplication first (transaction waiver amounts).
3. Consolidate scripts one domain at a time, keeping each new file under ~800 LOC.
4. Update `flow.yaml` after each consolidation so the flow stays runnable.

