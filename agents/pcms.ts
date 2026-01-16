#!/usr/bin/env bun
import { loop, work, generate, halt } from "./core";

/**
 * PCMS Refactor Agent (v3.0)
 * 
 * Simplifies import scripts to use clean JSON output from lineage step.
 * No more nilSafe, safeNum, safeStr - data is already clean!
 */

const WORK_PROMPT = `
You are simplifying PCMS import scripts to use clean JSON.

## Context
The lineage step now outputs CLEAN JSON files:
- snake_case keys (match DB columns)
- null values (not xsi:nil objects)
- No XML wrapper nesting

Scripts no longer need helper functions like nilSafe, safeNum, safeStr.

## Your Task
1. Read .ralph/TODO.md for the current task list
2. Pick the FIRST unchecked script and simplify it
3. Follow the pattern in players_&_people.inline_script.ts

## Reference Files
- AGENTS.md - New architecture overview
- TODO.md - New script pattern
- import_pcms_data.flow/players_&_people.inline_script.ts - Working example

## Key Points
- Read clean JSON: \`await Bun.file(\`\${baseDir}/filename.json\`).json()\`
- Data is already clean - no helper functions needed
- Use Bun's tagged SQL: \`await sql\`INSERT INTO ... \${sql(rows)}\`\`
- Map fields only if JSON key differs from DB column

## JSON Files
- players.json → pcms.people
- contracts.json → pcms.contracts, pcms.contract_versions, pcms.salaries
- transactions.json → pcms.transactions
- ledger.json → pcms.transaction_ledger
- trades.json → pcms.trades
- draft_picks.json → pcms.draft_picks
- team_exceptions.json → pcms.team_exceptions
- lookups.json → pcms.lookups

## After Simplifying
1. Update .ralph/TODO.md (check off the completed script)
2. Commit: \`git add -A && git commit -m "simplify: <script name> to clean JSON pattern"\`
3. Exit after committing
`;

const GENERATE_PROMPT = `
Generate a task list for .ralph/TODO.md to simplify PCMS import scripts.

Check which scripts still have the old pattern (nilSafe, safeNum helpers).

## Scripts to Check
- contracts,_versions,_bonuses_&_salaries.inline_script.ts
- lookups.inline_script.ts
- team_exceptions_&_usage.inline_script.ts
- trades,_transactions_&_ledger.inline_script.ts
- team_budgets.inline_script.ts
- draft_picks.inline_script.ts
- system_values,_rookie_scale_&_nca.inline_script.ts
- two-way_daily_statuses.inline_script.ts
- waiver_priority_&_ranks.inline_script.ts
- finalize_lineage.inline_script.ts

## Task Format
\`\`\`markdown
# PCMS Script Simplification

## TODO
- [ ] contracts,_versions,_bonuses_&_salaries.inline_script.ts
- [ ] ...
\`\`\`

Commit after generating: \`git add -A && git commit -m "chore: generate simplification tasks"\`
`;

loop({
  name: "pcms-simplify",
  taskFile: ".ralph/TODO.md",
  timeout: "8m",
  pushEvery: 4,
  maxIterations: 50,

  run(state) {
    if (state.hasTodos) {
      return work(WORK_PROMPT, { thinking: "medium" });
    }
    return generate(GENERATE_PROMPT, { tools: "read,bash,write" });
  },
});
