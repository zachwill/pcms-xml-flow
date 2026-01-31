#!/usr/bin/env bun
import { loop, work, halt } from "./core";

/**
 * PCMS Coverage Agent
 *
 * Fills coverage gaps identified in TODO.md Section 8:
 * - team_transactions.json (80K records, not imported)
 * - Contract sub-tables (nested in contracts.json but not normalized)
 *
 * Task file: .ralph/COVERAGE.md
 */

const WORK_PROMPT = `
You are filling PCMS coverage gaps by creating import scripts.

## Your Task
1. Read .ralph/COVERAGE.md for the current task list
2. Pick the FIRST unchecked item and complete it
3. Follow the DETAILED instructions in .ralph/COVERAGE.md — they specify exact file contents and patterns

## Key Reference Files
- \`.ralph/COVERAGE.md\` — **The authoritative task list with exact instructions**
- \`import_pcms_data.flow/transaction_waiver_amounts.inline_script.ts\` — Import script pattern to follow
- \`migrations/archive/006_team_transactions.sql\` — Table definition (already created)

## Import Script Pattern

Copy the structure from \`transaction_waiver_amounts.inline_script.ts\`:

\`\`\`typescript
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// Helper functions: toIntOrNull, toBoolOrNull, resolveBaseDir
// (copy from transaction_waiver_amounts.inline_script.ts)

export async function main(dry_run = false, extract_dir = "./shared/pcms") {
  const startedAt = new Date().toISOString();
  try {
    const baseDir = await resolveBaseDir(extract_dir);
    
    // Build teamCodeMap from lookups.json
    const lookups: any = await Bun.file(\`\${baseDir}/lookups.json\`).json();
    const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
    const teamCodeMap = new Map<number, string>();
    for (const t of teamsData) {
      if (t.team_id && t.team_code) teamCodeMap.set(t.team_id, t.team_code);
    }
    
    // Read source JSON
    const data: any[] = await Bun.file(\`\${baseDir}/team_transactions.json\`).json();
    
    // Map to rows, derive team_code, filter nulls
    const rows = data.map(r => ({ ... })).filter(Boolean);
    
    if (dry_run) return { dry_run: true, ... };
    
    // Batch upsert
    const BATCH_SIZE = 500;
    for (let i = 0; i < rows.length; i += BATCH_SIZE) {
      const batch = rows.slice(i, i + BATCH_SIZE);
      await sql\`INSERT INTO pcms.team_transactions \${sql(batch)}
        ON CONFLICT (team_transaction_id) DO UPDATE SET ...\`;
    }
    
    return { dry_run: false, started_at: startedAt, finished_at: new Date().toISOString(), tables: [...], errors: [] };
  } catch (e: any) {
    return { ... errors: [e?.message ?? String(e)] };
  }
}
\`\`\`

## Lock File Content

Create \`.lock\` files with exactly:
\`\`\`
{ "dependencies": {} }
//bun.lock
\`\`\`

## flow.yaml Updates

Add new step before 'l' (finalize). See .ralph/COVERAGE.md for exact YAML to add.

Also update finalize step's summaries array to include the new result.

## After Completing Each Task
1. Mark the task as done in .ralph/COVERAGE.md: \`- [ ]\` → \`- [x]\`
2. Commit: \`git add -A && git commit -m "feat: <brief description>"\`
3. Exit after committing (one task per iteration)
`;

loop({
  name: "coverage",
  taskFile: ".ralph/COVERAGE.md",
  timeout: "10m",
  pushEvery: 4,
  maxIterations: 30,

  run(state) {
    if (state.hasTodos) {
      return work(WORK_PROMPT, { thinking: "high" });
    }
    return halt("All coverage gaps filled");
  },
});
