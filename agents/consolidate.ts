#!/usr/bin/env bun
import { loop, work, halt } from "./core";

/**
 * Consolidate Import Scripts Agent
 *
 * Reduces import_pcms_data.flow/ from 18 scripts to ~10 by merging related domains.
 * Task list in .ralph/CONSOLIDATE.md
 */

const WORK_PROMPT = `
You are consolidating PCMS import scripts in \`import_pcms_data.flow/\`.

## Your Task
1. Read \`.ralph/CONSOLIDATE.md\` for the current task
2. Pick the FIRST unchecked item and complete it

## Reference Files

**Must read before each task:**
- \`.ralph/CONSOLIDATE.md\` — Task checklist and target structure
- \`SCHEMA.md\` — Postgres table definitions (columns, types, PKs)
- \`import_pcms_data.flow/flow.yaml\` — Current flow definition

**Existing scripts to reference:**
- \`import_pcms_data.flow/*.ts\` — Current import scripts (copy patterns, helpers)

**JSON structure (if needed):**
\`\`\`bash
# Sample record
bun -e "const d = await Bun.file('.shared/nba_pcms_full_extract/players.json').json(); console.log(d[0])"
\`\`\`

## Script Pattern

Each script is **self-contained** with inline helpers:

\`\`\`typescript
import { SQL } from "bun";
import { readdir } from "node:fs/promises";

const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (inline, not shared)
// ─────────────────────────────────────────────────────────────────────────────

function toIntOrNull(val: unknown): number | null {
  if (val === "" || val === null || val === undefined) return null;
  const num = Number(val);
  return Number.isNaN(num) ? null : num;
}

function asArray<T = any>(val: any): T[] {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export async function main(dry_run = false, extract_dir = "./shared/pcms") {
  const startedAt = new Date().toISOString();
  const tables: { table: string; attempted: number; success: boolean }[] = [];

  try {
    // Find extract directory
    const entries = await readdir(extract_dir, { withFileTypes: true });
    const subDir = entries.find(e => e.isDirectory());
    const baseDir = subDir ? \`\${extract_dir}/\${subDir.name}\` : extract_dir;

    // Build team lookup
    const lookups: any = await Bun.file(\`\${baseDir}/lookups.json\`).json();
    const teamsData: any[] = lookups?.lk_teams?.lk_team || [];
    const teamCodeMap = new Map<number, string>();
    for (const t of teamsData) {
      if (t?.team_id && (t?.team_code || t?.team_name_short)) {
        teamCodeMap.set(Number(t.team_id), String(t.team_code ?? t.team_name_short));
      }
    }

    // Read JSON
    const data: any[] = await Bun.file(\`\${baseDir}/file.json\`).json();
    console.log(\`Found \${data.length} records\`);

    if (dry_run) {
      return { dry_run: true, started_at: startedAt, finished_at: new Date().toISOString(), tables: [], errors: [] };
    }

    const ingestedAt = new Date();

    // Transform rows
    const rows = data.map(d => ({
      id: d.id,
      // ... map fields
      ingested_at: ingestedAt,
    }));

    // UPFRONT DEDUPE (not per-batch)
    const seen = new Map<number, any>();
    for (const r of rows) seen.set(r.id, r);
    const deduped = [...seen.values()];

    // Batch insert
    const BATCH_SIZE = 100;
    for (let i = 0; i < deduped.length; i += BATCH_SIZE) {
      const batch = deduped.slice(i, i + BATCH_SIZE);
      await sql\`
        INSERT INTO pcms.table_name \${sql(batch)}
        ON CONFLICT (id) DO UPDATE SET
          field = EXCLUDED.field,
          ingested_at = EXCLUDED.ingested_at
      \`;
    }
    tables.push({ table: "pcms.table_name", attempted: deduped.length, success: true });

    return { dry_run: false, started_at: startedAt, finished_at: new Date().toISOString(), tables, errors: [] };
  } catch (e: any) {
    return { dry_run, started_at: startedAt, finished_at: new Date().toISOString(), tables: [], errors: [e.message] };
  }
}
\`\`\`

## Key Rules

### 1. Self-contained scripts
Each script has its own helpers inline. No shared module.

### 2. Upfront deduping
Dedupe the entire dataset BEFORE batching:
\`\`\`typescript
const seen = new Map<number, any>();
for (const r of rows) seen.set(r.primary_key, r);
const deduped = [...seen.values()];
\`\`\`

### 3. Reasonable batch sizes
- Small tables (<1k): BATCH_SIZE = 100-500
- Large tables (>10k): BATCH_SIZE = 100-200

### 4. FK ordering
When merging scripts, respect foreign key order:
- agencies → agents → people
- contracts → versions → salaries

### 5. When merging scripts
- Copy ALL table upsert logic from source scripts
- Keep all helpers needed by merged tables
- Test each table upsert works

### 6. When deleting old scripts
- Remove from \`flow.yaml\` first
- Then delete the .ts and .lock files

## After Each Task

1. Check off the task in \`.ralph/CONSOLIDATE.md\`
2. Commit: \`git add -A && git commit -m "feat(consolidate): <description>"\`
`;

loop({
  name: "consolidate",
  taskFile: ".ralph/CONSOLIDATE.md",
  timeout: "10m",
  pushEvery: 4,
  maxIterations: 20,

  run(state) {
    if (state.hasTodos) {
      return work(WORK_PROMPT, { thinking: "high" });
    }
    return halt("All consolidation tasks complete");
  },
});
