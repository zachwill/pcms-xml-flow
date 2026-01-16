#!/usr/bin/env bun
import { loop, work, generate, halt, supervisor } from "./core";
import { readFileSync } from "fs";

const VALIDATION_MARKER = "<!-- SR_SCHEMA_VALIDATED -->";
const TASK_FILE = ".ralph/SR_SCHEMA.md";

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
    return /## Phase 2|## DDL Generation/i.test(content);
  } catch {
    return false;
  }
}

loop({
  name: "sr-schema",
  taskFile: TASK_FILE,
  timeout: "10m",
  pushEvery: 3,
  maxIterations: 50,

  supervisor: supervisor(
    `
    Review the generated DDL in \`f/ralph/new_sr_schema.flow/\`.

    Cross-reference against:
    - \`backlog/ralph/sr/AGENTS.md\` — design philosophy, naming conventions
    - \`backlog/ralph/sr/schema/*.txt\` — source specifications

    Check:
    - Does every .txt spec have a corresponding CREATE TABLE?
    - Are provenance columns present (source_api, source_endpoint, fetched_at, source_hash)?
    - Are naming conventions followed (snake_case, sr_id for players, sr_team_id for teams)?
    - Is source_api supporting nba, ncaa, gleague, intl?
    - Are statistical columns using short abbreviations (fgm, fga, fg_pct, etc.)?
    - Is JSONB used appropriately (pbp, roster_json, etc.)?
    - Are PRIMARY KEY / UNIQUE constraints suitable for UPSERT?
    - Are files under 500 LOC?

    If issues found:
    - Remove validation marker if present: \`${VALIDATION_MARKER}\`
    - Add tasks to \`${TASK_FILE}\`
    - Commit: git add -A && git commit -m "sr-schema: supervisor review"
    `,
    { every: 6, thinking: "medium" }
  ),

  run(state) {
    // Done: no todos + validation marker
    if (!state.hasTodos && hasValidationMarker()) {
      return halt("SR schema DDL generation complete");
    }

    // Work: has todos → do one item
    if (state.hasTodos) {
      return work(
        `
        You are generating Postgres DDL for the SportRadar (sr) schema.

        Your task: ${state.nextTodo}

        ## Required Reading (if not already familiar)

        1. \`backlog/ralph/sr/AGENTS.md\` — design philosophy, naming conventions, provenance requirements
        2. \`backlog/ralph/sr/schema/*.txt\` — table specifications to convert
        3. \`backlog/ralph/sr/data/\` — data pipeline context (if exists)
        4. \`backlog/ralph/sr/docs/\` — API endpoint documentation

        ## Output

        Write DDL to \`f/ralph/new_sr_schema.flow/inline_script_*.pg.sql\`

        ## DDL Conventions

        - First file must include: \`CREATE SCHEMA IF NOT EXISTS sr;\`
        - Use \`SET search_path TO sr;\` after schema creation
        - No FK constraints — add comments like \`-- FK: references teams(sr_team_id)\`
        - Include \`CREATE INDEX\` statements for common joins/filters
        - Keep files under 500 lines (600-800 max if necessary)
        - Balanced comments: not verbose, not absent

        ## SportRadar-Specific

        - Use \`sr_id\` for player identifiers (SportRadar UUIDs)
        - Use \`sr_team_id\` for team identifiers
        - \`source_api\` should be one of: nba, ncaa, gleague, intl
        - PBP stored as JSONB (pbp_json) with one row per game

        ## File Management

        - If creating a new inline_script file, update \`f/ralph/new_sr_schema.flow/flow.yaml\`
        - Add the new module following the existing pattern

        When done:
        - Check off ONLY this task in \`${TASK_FILE}\`
        - git add -A && git commit -m "sr-schema: <summary>"
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
        \`${TASK_FILE}\` needs a DDL generation plan.
        ${contextBlock}
        ## Step 1: Read Everything

        You MUST thoroughly read:
        1. \`backlog/ralph/sr/AGENTS.md\` — design philosophy, conventions
        2. ALL files in \`backlog/ralph/sr/schema/*.txt\` — table specifications
        3. \`backlog/ralph/sr/data/\` — data pipeline context (if exists)
        4. \`backlog/ralph/sr/docs/\` — API endpoint documentation (nba, ncaa, gleague, intl)

        ## Step 2: Plan File Split

        Group tables logically and estimate LOC. Target ~400-500 LOC per file.
        Consider: core entities (teams, players, seasons) → games/schedule → stats → pbp/injuries

        ## Step 3: Create Checklist

        Write to \`${TASK_FILE}\`:

        \`\`\`markdown
        # SR Schema Generation

        **Output directory:** \`f/ralph/new_sr_schema.flow/\`

        ## Phase 1: Planning
        - [x] Read backlog/ralph/sr/AGENTS.md
        - [x] Read all backlog/ralph/sr/schema/*.txt
        - [x] Read backlog/ralph/sr/data/ and docs/
        - [x] Plan file split

        ## Phase 2: DDL Generation
        - [ ] inline_script_0.inline_script.pg.sql — schema + <table list>
        - [ ] inline_script_1.inline_script.pg.sql — <table list>
        - [ ] ... (as many as needed)

        ## Phase 3: Validation
        - [ ] Cross-check all .txt specs have CREATE TABLE
        - [ ] Verify provenance columns per AGENTS.md
        \`\`\`

        Commit: git add -A && git commit -m "sr-schema: create generation plan"
        `,
        { thinking: "high" }
      );
    }

    // Validate: all Phase 2 items done, no marker → run validation
    return work(
      `
      \`${TASK_FILE}\` has no remaining DDL generation tasks. Run validation.
      ${contextBlock}
      ## Validation Process

      ### Step 1: Spec Coverage

      For EVERY file in \`backlog/ralph/sr/schema/*.txt\`:
      - Confirm there's a corresponding CREATE TABLE in \`f/ralph/new_sr_schema.flow/\`
      - Verify column names and types match the spec
      - Verify constraints (PK, UNIQUE) are present

      ### Step 2: Convention Compliance

      Check against \`backlog/ralph/sr/AGENTS.md\`:
      - Provenance columns: source_api, source_endpoint, fetched_at, source_hash
      - Naming: snake_case, sr_id for players, sr_team_id for teams
      - Statistical columns: fgm, fga, fg_pct, fg2m, fg2a, etc.
      - source_api enum: nba, ncaa, gleague, intl
      - JSONB usage: pbp_json, roster_json, depth_chart_json

      ### Step 3: File Quality

      - All files under 600 LOC
      - flow.yaml correctly references all inline_script files
      - DDL is syntactically valid

      ## Output

      If gaps found:
      - Add tasks to \`${TASK_FILE}\`
      - Commit: git add -A && git commit -m "sr-schema: validation found gaps"

      If complete:
      - Add validation summary to \`${TASK_FILE}\`
      - Add marker: \`${VALIDATION_MARKER}\`
      - Commit: git add -A && git commit -m "sr-schema: validation complete"
      `,
      { thinking: "high", timeout: "12m" }
    );
  },
});
