#!/usr/bin/env bun
import { loop, work, halt } from "./core";

/**
 * PCMS Enhancement Agent
 *
 * Updates import scripts to populate team_code columns and adds new
 * draft pick related scripts.
 *
 * Task file: .ralph/ENHANCE.md
 */

const WORK_PROMPT = `
You are enhancing PCMS import scripts to populate team_code columns and adding new draft pick scripts.

## Your Task
1. Read .ralph/ENHANCE.md for the current task list
2. Pick the FIRST unchecked item and complete it
3. Follow the patterns and references in the task file

## Key Reference Files
- \`TODO.md\` — Full issue details with exact column names per table
- \`DRAFT_PICKS.md\` — Draft pick summaries documentation
- \`.ralph/ENHANCE.md\` — Task list with helper pattern

## For Phase 1 (Update Scripts for team_code)

Each script needs:
1. Build the teamCodeMap from lookups.json (see helper pattern in ENHANCE.md)
2. Add the appropriate team_code columns to row mappings
3. Add team_code to the ON CONFLICT UPDATE clause

Example addition to a row mapping:
\`\`\`typescript
const row = {
  // existing fields...
  team_id: record.team_id,
  team_code: teamCodeMap.get(record.team_id) ?? null,
  // more existing fields...
};
\`\`\`

**Important:** Check TODO.md for the exact column names needed for each script. Some scripts need multiple team_code columns (e.g., from_team_code, to_team_code).

**For trades,_transactions_&_ledger.inline_script.ts:** Also fix the null team_id bug in ledger_entries by filtering out records where team_id is null.

## For Phase 2 (New Scripts)

### draft_pick_summaries.inline_script.ts
- Read \`draft_pick_summaries.json\`
- Map fields: team_id, draft_year, first_round, second_round, is_active (from active_flg)
- Add team_code from lookup
- Upsert to pcms.draft_pick_summaries with ON CONFLICT (team_id, draft_year)
- Update flow.yaml to add step after draft_picks
- See DRAFT_PICKS.md for full schema details

### generate_nba_draft_picks.inline_script.ts
- Read \`players.json\`, filter for NBA players with draft_year and draft_round
- Generate synthetic draft_pick_id: draft_year * 100000 + draft_round * 1000 + pick_number
- Map to draft_picks columns including player_id linkage
- Upsert to pcms.draft_picks with ON CONFLICT (draft_year, round, pick_number_int, league_lk)
- Update flow.yaml to add step after players import
- See TODO.md for the full pattern

## Script Pattern Reference
Look at \`import_pcms_data.flow/players_&_people.inline_script.ts\` for the standard pattern.

## flow.yaml Updates
When adding new steps:
- Use next available letter (check current steps first)
- Follow existing step pattern for input_transforms
- Update finalize_lineage summaries array if needed

## After Completing Each Task
1. Check off the task in .ralph/ENHANCE.md
2. Commit: \`git add -A && git commit -m "enhance: <brief description>"\`
3. Exit after committing (one task per iteration)
`;

loop({
  name: "enhance",
  taskFile: ".ralph/ENHANCE.md",
  timeout: "10m",
  pushEvery: 4,
  maxIterations: 30,

  run(state) {
    if (state.hasTodos) {
      return work(WORK_PROMPT, { thinking: "high" });
    }
    return halt("All enhancement tasks complete");
  },
});
