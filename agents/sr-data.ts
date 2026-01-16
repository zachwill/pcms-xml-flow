#!/usr/bin/env bun
import { loop, work, generate, halt, supervisor } from "./core";
import { readFileSync } from "fs";

const VALIDATION_MARKER = "<!-- SR_DATA_VALIDATED -->";
const TASK_FILE = ".ralph/SR_DATA.md";

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
  name: "sr-data",
  taskFile: TASK_FILE,
  timeout: "10m",
  pushEvery: 3,
  maxIterations: 50,

  supervisor: supervisor(
    `
    Review the generated import scripts in \`f/ralph/import_sr_data.flow/\`.

    Cross-reference against:
    - \`backlog/ralph/sr/data/\` — pipeline architecture, endpoint mapping, multi-league design
    - \`backlog/ralph/sr/schema/*.txt\` — table specifications
    - \`f/ralph/new_sr_schema.flow/\` — generated DDL for column names/types
    - \`f/ralph/utils.ts\` — shared utilities

    Check:
    - Does every table have a corresponding import function?
    - Is multi-league support implemented (source_api: nba, ncaa, gleague, intl)?
    - Are provenance columns populated (source_api, source_endpoint, fetched_at, source_hash)?
    - Is the upsert strategy correct per upsert.md?
    - Are SportRadar IDs correctly named (sr_id, sr_team_id)?
    - Are derived stats calculated (fg2m, fg2a, fg2_pct)?
    - Is rate limiting implemented (SportRadar is strict)?
    - Are files under 500 LOC?
    - Is error handling resilient?

    If issues found:
    - Remove validation marker if present: \`${VALIDATION_MARKER}\`
    - Add tasks to \`${TASK_FILE}\`
    - Commit: git add -A && git commit -m "sr-data: supervisor review"
    `,
    { every: 6, thinking: "medium" }
  ),

  run(state) {
    // Done: no todos + validation marker
    if (!state.hasTodos && hasValidationMarker()) {
      return halt("SR data import scripts complete");
    }

    // Work: has todos → do one item
    if (state.hasTodos) {
      return work(
        `
        You are generating Bun/TypeScript import scripts for the SportRadar data pipeline.

        Your task: ${state.nextTodo}

        ## Required Reading (if not already familiar)

        1. \`backlog/ralph/sr/data/\` — ALL files, especially:
           - \`AGENTS.md\` — design philosophy
           - \`inventory.md\` — available API endpoints per league
           - \`mapping.md\` — endpoint to table mapping (CRITICAL)
           - \`fetcher.md\` + \`fetcher.ts\` — fetcher patterns
           - \`parser.md\` + \`parser.ts\` — parsing conventions
           - \`upsert.md\` — conflict columns per table
           - \`pipeline.md\` — overall flow
           - \`multi-league.md\` — handling nba/ncaa/gleague/intl
           - \`provenance.md\` + \`provenance.ts\` — provenance tracking
           - \`pbp-strategy.md\` + \`pbp-strategy.ts\` — PBP handling
        2. \`f/ralph/new_sr_schema.flow/*.pg.sql\` — actual DDL for column names
        3. \`f/ralph/utils.ts\` — shared utilities (hash, upsertBatch, etc.)
        4. \`f/ralph/import_sr_data.flow/AGENTS.md\` — coding conventions for this flow
        5. \`f/sportradar/utils.ts\` — existing SportRadar client patterns
        6. \`f/sportradar/ncaa.ts\`, \`f/sportradar/gleague.ts\` — existing implementations
        7. \`docs/bun-postgres.md\` — Bun SQL patterns

        ## Output

        Write scripts to \`f/ralph/import_sr_data.flow/inline_script_*.ts\`

        ## Script Conventions

        - Import utilities: \`import { ... } from "/f/ralph/utils.ts";\`
        - Database: \`const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });\`
        - Export: \`export async function main(dry_run = false, league = "nba", ...params) { ... }\`
        - Return: ImportSummary object with results per table
        - Keep files under 500 LOC

        ## SportRadar-Specific Conventions

        - Use \`sr_id\` for player identifiers (SportRadar UUIDs)
        - Use \`sr_team_id\` for team identifiers
        - \`source_api\` must be one of: nba, ncaa, gleague, intl
        - Calculate derived stats: fg2m = fgm - fg3m, etc.
        - Store PBP as JSONB (pbp_json) — one row per game
        - Rate limit aggressively (SR_RATE_QPS env var, default 1 QPS)

        ## Multi-League Pattern

        Use existing patterns from \`f/sportradar/utils.ts\`:
        \`\`\`typescript
        import { createSportradarClient, fetchSportradarJSON } from "/f/sportradar/utils.ts";

        type League = "nba" | "ncaa" | "gleague" | "intl";

        const LEAGUE_URLS: Record<League, string> = {
          nba: "https://api.sportradar.com/nba/production/v8",
          ncaa: "https://api.sportradar.com/ncaamb/production/v8",
          gleague: "https://api.sportradar.com/nba-g-league/production/v8",
          intl: "https://api.sportradar.com/basketball/production/v3",
        };

        export async function main(dry_run = false, league: League = "nba", ...) {
          const client = createSportradarClient(LEAGUE_URLS[league]);
          const data = await fetchSportradarJSON(client, "games/schedule");
          ...
        }
        \`\`\`
        
        The API key is read from \`SPORTRADAR_API_KEY\` by \`fetchSportradarJSON\`.

        ## File Management

        - If creating a new inline_script file, update \`f/ralph/import_sr_data.flow/flow.yaml\`
        - Add the new module following the existing pattern
        - Use language: bun

        When done:
        - Check off ONLY this task in \`${TASK_FILE}\`
        - git add -A && git commit -m "sr-data: <summary>"
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
        1. \`backlog/ralph/sr/data/\` — ALL files:
           - AGENTS.md
           - inventory.md — API endpoints by league
           - mapping.md — endpoint to table mapping (CRITICAL)
           - fetcher.md + fetcher.ts
           - parser.md + parser.ts
           - upsert.md
           - pipeline.md
           - multi-league.md
           - provenance.md + provenance.ts
           - pbp-strategy.md + pbp-strategy.ts
           - incremental.md + incremental.ts
           - errors.md
        2. \`f/ralph/new_sr_schema.flow/*.pg.sql\` — DDL for exact column names
        3. \`f/ralph/utils.ts\` — shared utilities
        4. \`.ralph/SR_SCHEMA.md\` — table inventory from schema generation

        ## Step 2: Plan Script Organization

        SportRadar serves multiple leagues with similar structure.
        Design scripts to be league-agnostic where possible.

        Suggested groupings:
        - **core.ts** — seasons, teams, players, roster_entries
        - **games_pbp.ts** — games, pbp, injuries, transfers, draft
        - **game_stats.ts** — game_team_stats, game_player_stats, standings, rankings
        - **season_stats.ts** — season_team_statistics, season_player_statistics, splits

        ## Step 3: Create Checklist

        Write to \`${TASK_FILE}\`:

        \`\`\`markdown
        # SR Data Import Script Generation

        **Output directory:** \`f/ralph/import_sr_data.flow/\`
        **Sources:** SportRadar APIs (NBA, NCAA, GLeague, Intl)

        ## Phase 1: Planning
        - [x] Read backlog/ralph/sr/data/* (all design docs)
        - [x] Read f/ralph/new_sr_schema.flow/*.pg.sql (DDL)
        - [x] Read f/ralph/utils.ts (shared utilities)
        - [x] Understand mapping.md (endpoint → table)
        - [x] Plan script organization

        ## Phase 2: Script Generation
        - [ ] inline_script_0 — core.ts: seasons, teams, players, roster_entries
        - [ ] inline_script_1 — games_pbp.ts: games, pbp, injuries, transfers, draft
        - [ ] inline_script_2 — game_stats.ts: game_team_stats, game_player_stats, game_period_scores
        - [ ] inline_script_3 — season_stats.ts: season_team_statistics, season_player_statistics, standings, rankings, splits

        ## Phase 3: Validation
        - [ ] All tables have import coverage
        - [ ] Multi-league support works (nba, ncaa, gleague, intl)
        - [ ] SportRadar IDs correctly named (sr_id, sr_team_id)
        - [ ] Derived stats calculated (fg2m, fg2_pct)
        - [ ] Rate limiting is strict (1 QPS default)
        - [ ] Error handling is resilient
        \`\`\`

        Commit: git add -A && git commit -m "sr-data: create generation plan"
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

      For EVERY table in \`f/ralph/new_sr_schema.flow/*.pg.sql\`:
      - Confirm there's a corresponding import function
      - Verify endpoint mappings per mapping.md

      ### Step 2: Multi-League Checks

      - All scripts accept \`league\` parameter
      - LEAGUE_CONFIG has correct base URLs per league
      - source_api is correctly set to league value

      ### Step 3: SportRadar-Specific Checks

      - sr_id used for players (not player_id)
      - sr_team_id used for teams
      - Derived stats: fg2m, fg2a, fg2_pct calculated
      - PBP stored as pbp_json JSONB
      - Rate limiting: 1 QPS default, respects SR_RATE_QPS env

      ### Step 4: Script Quality

      - All files under 500 LOC
      - flow.yaml correctly references all inline_script files
      - dry_run parameter is supported
      - Error handling is resilient

      ## Output

      If gaps found:
      - Add tasks to \`${TASK_FILE}\`
      - Commit: git add -A && git commit -m "sr-data: validation found gaps"

      If complete:
      - Add validation summary to \`${TASK_FILE}\`
      - Add marker: \`${VALIDATION_MARKER}\`
      - Commit: git add -A && git commit -m "sr-data: validation complete"
      `,
      { thinking: "high", timeout: "12m" }
    );
  },
});
