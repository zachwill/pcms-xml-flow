#!/usr/bin/env bun
import { loop, work, generate, halt, supervisor } from "./core";
import { readFileSync } from "fs";

const VALIDATION_MARKER = "<!-- NBA_DATA_VALIDATED -->";
const TASK_FILE = ".ralph/NBA_DATA.md";

function hasValidationMarker(): boolean {
  try {
    return readFileSync(TASK_FILE, "utf-8").includes(VALIDATION_MARKER);
  } catch {
    return false;
  }
}

function hasAnyChecklistItems(): boolean {
  try {
    return /^\s*[-*+]\s*\[[ xX]\]\s+/m.test(readFileSync(TASK_FILE, "utf-8"));
  } catch {
    return false;
  }
}

function hasPlanningComplete(): boolean {
  try {
    const content = readFileSync(TASK_FILE, "utf-8");
    return /## Phase 2|## Script Generation/i.test(content);
  } catch {
    return false;
  }
}

loop({
  name: "nba-data",
  taskFile: TASK_FILE,
  timeout: "10m",
  pushEvery: 3,
  maxIterations: 50,

  supervisor: supervisor(
    `
    Review the generated import scripts in \`f/ralph/import_nba_data.flow/\`.

    Cross-reference against:
    - \`backlog/ralph/nba/data/\` — pipeline architecture, endpoint mappings, upsert strategy
    - \`backlog/ralph/nba/schema/*.txt\` — table specifications
    - \`f/ralph/new_nba_schema.flow/\` — generated DDL for column names/types
    - \`f/ralph/utils.ts\` — shared utilities

    Check:
    - Does every target table have a corresponding import function?
    - Are provenance columns populated (source_api, source_endpoint, fetched_at, source_hash)?
    - Is the upsert strategy correct (ON CONFLICT with hash-based change detection)?
    - Are API endpoints correctly mapped per \`02-endpoint-table-mapping.md\`?
    - Is rate limiting implemented?
    - Do scripts support dry_run parameter?
    - Are files under 500 LOC?
    - Is error handling resilient (log and continue, not fail-fast)?

    If issues found:
    - Remove validation marker if present: \`${VALIDATION_MARKER}\`
    - Add tasks to \`${TASK_FILE}\`
    - Commit: git add -A && git commit -m "nba-data: supervisor review"
    `,
    { every: 6, thinking: "medium" }
  ),

  run(state) {
    // Done: no todos + validation marker
    if (!state.hasTodos && hasValidationMarker()) {
      return halt("NBA data import scripts complete");
    }

    // Work: has todos → do one item
    if (state.hasTodos) {
      return work(
        `
        You are generating Bun/TypeScript import scripts for the NBA data pipeline.

        Your task: ${state.nextTodo}

        ## Required Reading (if not already familiar)

        1. \`backlog/ralph/nba/data/\` — ALL files, especially:
           - \`01-endpoint-inventory.md\` — available API endpoints
           - \`02-endpoint-table-mapping.md\` — endpoint to table mapping
           - \`03-fetcher-design.md\` and \`03-fetcher.ts\` — fetcher patterns
           - \`04-parser-design.md\` — parsing conventions
           - \`05-upsert-strategy.md\` — conflict columns per table
           - \`07-pipeline-architecture.md\` — overall flow
        2. \`f/ralph/new_nba_schema.flow/*.pg.sql\` — actual DDL for column names
        3. \`f/ralph/utils.ts\` — shared utilities (hash, upsertBatch, createFetcher, etc.)
        4. \`f/ralph/import_nba_data.flow/AGENTS.md\` — coding conventions for this flow
        5. \`docs/bun-postgres.md\` — Bun SQL patterns
        6. \`f/sportradar/utils.ts\` — existing patterns for API clients

        ## Output

        Write scripts to \`f/ralph/import_nba_data.flow/inline_script_*.ts\`

        ## Script Conventions

        - Import utilities: \`import { ... } from "/f/ralph/utils.ts";\`
        - Database: \`const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });\`
        - Export: \`export async function main(dry_run = false, ...params) { ... }\`
        - Return: ImportSummary object with results per table
        - Keep files under 500 LOC (600-800 max if absolutely necessary)

        ## Standard Script Structure

        \`\`\`typescript
        import { SQL } from "bun";
        import { 
          createFetcher, withProvenance, upsertBatch, 
          createSummary, finalizeSummary, safeNum 
        } from "/f/ralph/utils.ts";

        const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });

        // Parser functions
        function parseTeam(raw: any, provenance: Provenance) { ... }

        // Main
        export async function main(dry_run = false, limit?: number) {
          const summary = createSummary(dry_run);
          const fetcher = createFetcher({ baseUrl: "...", sourceApi: "nba", ... });
          
          try {
            const { data, provenance } = await fetcher.get("/api/...");
            const rows = data.map(r => parseTeam(r, provenance));
            
            if (dry_run) {
              summary.tables.push({ table: "nba.teams", attempted: rows.length, success: true });
              return finalizeSummary(summary);
            }
            
            const result = await upsertBatch(sql, "nba", "teams", rows, ["team_id"]);
            summary.tables.push(result);
          } catch (e) {
            summary.errors.push(e.message);
          }
          
          return finalizeSummary(summary);
        }
        \`\`\`

        ## File Management

        - If creating a new inline_script file, update \`f/ralph/import_nba_data.flow/flow.yaml\`
        - Add the new module following the existing pattern
        - Use language: bun

        When done:
        - Check off ONLY this task in \`${TASK_FILE}\`
        - git add -A && git commit -m "nba-data: <summary>"
        - Exit immediately.
        `
      );
    }

    const contextBlock = state.context
      ? `\n\nFocus on:\n<instructions>\n${state.context}\n</instructions>\n`
      : "";

    // Seed: no checklist yet → read everything and create plan
    if (!hasAnyChecklistItems() || !hasPlanningComplete()) {
      return generate(
        `
        \`${TASK_FILE}\` needs a data import script generation plan.
        ${contextBlock}
        ## Step 1: Read Everything

        You MUST thoroughly read:
        1. \`backlog/ralph/nba/data/\` — ALL files:
           - 01-endpoint-inventory.md
           - 02-endpoint-table-mapping.md
           - 03-fetcher-design.md + 03-fetcher.ts
           - 04-parser-design.md + 04-parser-sketches.ts
           - 05-upsert-strategy.md
           - 06-provenance-design.md
           - 07-pipeline-architecture.md
           - 08-error-handling.md + 08-error-handling.ts
           - 09-incremental-processing.md + 09-incremental-sketches.ts
           - 10-ngss-gap-analysis.md
           - 11-staged-processing-schema.md + 11-staged-processing-types.ts
        2. \`f/ralph/new_nba_schema.flow/*.pg.sql\` — DDL for exact column names
        3. \`f/ralph/utils.ts\` — shared utilities
        4. \`.ralph/NBA_SCHEMA.md\` — table inventory from schema generation

        ## Step 2: Plan Script Organization

        Group imports logically by data domain. Target ~300-450 LOC per script.
        Consider dependencies (e.g., teams/players before boxscores).

        Suggested groupings:
        - **core_refs.ts** — teams, players (must run first)
        - **schedule_games.ts** — schedules, games
        - **boxscores.ts** — boxscores_traditional, boxscores_traditional_team, boxscores_advanced
        - **aggregated_stats.ts** — player_stats_aggregated, team_stats_aggregated, lineups
        - **tracking_hustle.ts** — hustle_stats, hustle_events, tracking_stats, tracking_streams
        - **pbp_metadata.ts** — play_by_play, injuries, alerts, pregame_storylines
        - **ngss.ts** — ngss_games, ngss_rosters, ngss_boxscores, ngss_pbp, ngss_officials

        ## Step 3: Create Checklist

        Write to \`${TASK_FILE}\`:

        \`\`\`markdown
        # NBA Data Import Script Generation

        **Output directory:** \`f/ralph/import_nba_data.flow/\`

        ## Phase 1: Planning
        - [x] Read backlog/ralph/nba/data/* (all design docs)
        - [x] Read f/ralph/new_nba_schema.flow/*.pg.sql (DDL)
        - [x] Read f/ralph/utils.ts (shared utilities)
        - [x] Plan script organization

        ## Phase 2: Script Generation
        - [ ] inline_script_0 — core_refs.ts: teams, players
        - [ ] inline_script_1 — schedule_games.ts: schedules, games
        - [ ] inline_script_2 — boxscores.ts: boxscores_traditional, boxscores_traditional_team, boxscores_advanced
        - [ ] inline_script_3 — aggregated_stats.ts: player_stats_aggregated, team_stats_aggregated, lineups
        - [ ] inline_script_4 — tracking_hustle.ts: hustle_stats, hustle_events, tracking_stats, tracking_streams
        - [ ] inline_script_5 — pbp_metadata.ts: play_by_play, injuries, alerts, pregame_storylines
        - [ ] inline_script_6 — ngss.ts: ngss_games, ngss_rosters, ngss_boxscores, ngss_pbp, ngss_officials

        ## Phase 3: Validation
        - [ ] All 24 tables have import coverage
        - [ ] Provenance columns populated correctly
        - [ ] Upsert conflict columns match schema PKs
        - [ ] Rate limiting implemented
        - [ ] Error handling is resilient
        \`\`\`

        Commit: git add -A && git commit -m "nba-data: create generation plan"
        `,
        { thinking: "high" }
      );
    }

    // Validate: all Phase 2 items done, no marker → run validation
    return work(
      `
      \`${TASK_FILE}\` has no remaining script generation tasks. Run validation.
      ${contextBlock}
      ## Validation Process

      ### Step 1: Table Coverage

      For EVERY table in \`f/ralph/new_nba_schema.flow/*.pg.sql\`:
      - Confirm there's a corresponding import function in \`f/ralph/import_nba_data.flow/\`
      - Verify the parser maps to correct column names

      ### Step 2: Upsert Strategy

      Check against \`backlog/ralph/nba/data/05-upsert-strategy.md\`:
      - Conflict columns match documented PKs
      - Hash-based change detection is used
      - Provenance columns are populated

      ### Step 3: Script Quality

      - All files under 500 LOC
      - flow.yaml correctly references all inline_script files
      - dry_run parameter is supported
      - Error handling is resilient (try/catch, log errors, continue)
      - Rate limiting is configured

      ## Output

      If gaps found:
      - Add tasks to \`${TASK_FILE}\`
      - Commit: git add -A && git commit -m "nba-data: validation found gaps"

      If complete:
      - Add validation summary to \`${TASK_FILE}\`
      - Add marker: \`${VALIDATION_MARKER}\`
      - Commit: git add -A && git commit -m "nba-data: validation complete"
      `,
      { thinking: "high", timeout: "12m" }
    );
  },
});
