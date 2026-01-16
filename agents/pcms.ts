#!/usr/bin/env bun
import { loop, work, generate, halt } from "./core";

/**
 * PCMS Refactor Agent
 * 
 * Refactors all flow scripts to:
 * 1. Read pre-parsed JSON (not stream XML)
 * 2. Use Bun-native APIs (Bun.file(), $ shell, SQL)
 * 3. Inline helpers (no utils.ts imports)
 * 
 * Reference completed scripts for patterns:
 * - lineage_management_(s3_&_state_tracking).inline_script.ts
 * - players_&_people.inline_script.ts
 */

const WORK_PROMPT = `
You are refactoring PCMS XML Flow scripts to use Bun-native APIs.

## Your Task
1. Read .ralph/TODO.md for the current task list
2. Pick the FIRST unchecked script and refactor it
3. Follow the patterns in AGENTS.md and TODO.md (standard script pattern)

## Reference Files (READ THESE FIRST)
- AGENTS.md - Project context, Bun best practices, JSON structure
- TODO.md - Standard script pattern with all helpers
- import_pcms_data.flow/players_&_people.inline_script.ts - Working example

## Key Patterns
- Read JSON: \`const data = await Bun.file(\`\${baseDir}/filename.json\`).json();\`
- Access data: \`data["xml-extract"]["<type>-extract"]["<entity>"]\`
- Handle nil: \`nilSafe(val)\` for \`{ "@_xsi:nil": "true" }\`
- Hash: \`new Bun.CryptoHasher("sha256").update(data).digest("hex")\`
- Postgres: \`import { SQL } from "bun"; const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });\`

## Explore Data Structure
Run these to understand the JSON structure:
- \`bun run scripts/show-all-paths.ts\` - See all data paths
- \`bun run scripts/inspect-json-structure.ts <type> --sample\` - See field samples

## After Refactoring
1. Update .ralph/TODO.md (check off the completed script)
2. Commit: \`git add -A && git commit -m "refactor: <script name> to Bun-native APIs"\`
3. Exit after committing

## Important
- Inline ALL helpers (nilSafe, safeNum, safeStr, safeBool, hash, etc.)
- Do NOT import from utils.ts
- Match the exact structure of players_&_people.inline_script.ts
`;

const GENERATE_PROMPT = `
Generate a fresh task list for .ralph/TODO.md to refactor PCMS flow scripts.

## Scripts to Refactor (ALL are equal priority)
Check which scripts still need refactoring by comparing against the completed ones.

Completed scripts (use as reference):
- lineage_management_(s3_&_state_tracking).inline_script.ts ✅
- players_&_people.inline_script.ts ✅

Scripts that may need refactoring:
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
Use this format in .ralph/TODO.md:

\`\`\`markdown
# PCMS Script Refactor

Refactor all scripts to use Bun-native APIs (read JSON, not XML).

## Scripts

- [ ] contracts,_versions,_bonuses_&_salaries.inline_script.ts
- [ ] lookups.inline_script.ts
... (one line per script that needs work)

## Reference
- Pattern: TODO.md (standard script pattern)
- Example: players_&_people.inline_script.ts
\`\`\`

## Instructions
1. Check each script to see if it's already refactored (uses Bun.file, SQL from bun, etc.)
2. Add only scripts that still need work to the TODO list
3. Commit: \`git add -A && git commit -m "chore: generate pcms refactor tasks"\`
4. Exit after committing
`;

loop({
  name: "pcms-refactor",
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
