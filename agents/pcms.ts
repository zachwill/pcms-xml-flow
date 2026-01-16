#!/usr/bin/env bun
import { loop, work, generate, halt, supervisor } from "./core";
import { readFileSync } from "fs";

const VALIDATION_MARKER = "<!-- PCMS_SCHEMA_VALIDATED -->";
const TASK_FILE = ".ralph/PCMS_SCHEMA.md";

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
  name: "pcms-schema",
  taskFile: TASK_FILE,
  timeout: "10m",
  pushEvery: 3,
  maxIterations: 50,

  supervisor: supervisor(
    `
    Review the generated DDL in \`f/ralph/new_pcms_schema.flow/\`.

    Cross-reference against:
    - \`backlog/ralph/pcms/AGENTS.md\` — design philosophy
    - \`backlog/ralph/pcms/schema/AGENTS.md\` — detailed schema conventions
    - \`backlog/ralph/pcms/schema/*.txt\` — source specifications
    - \`backlog/ralph/pcms/data/\` — data pipeline context

    Check:
    - Does every .txt spec have a corresponding CREATE TABLE?
    - Are provenance columns present (source_drop_file, source_hash, parser_version, ingested_at)?
    - Are naming conventions followed (snake_case, salary_year not season)?
    - Are money columns in DOLLARS with appropriate types (bigint for whole, numeric for decimals)?
    - Are PRIMARY KEY / UNIQUE constraints suitable for UPSERT?
    - Is the lineage/audit table structure correct?
    - Are files under 500 LOC?

    If issues found:
    - Remove validation marker if present: \`${VALIDATION_MARKER}\`
    - Add tasks to \`${TASK_FILE}\`
    - Commit: git add -A && git commit -m "pcms-schema: supervisor review"
    `,
    { every: 6, thinking: "medium" }
  ),

  run(state) {
    // Done: no todos + validation marker
    if (!state.hasTodos && hasValidationMarker()) {
      return halt("PCMS schema DDL generation complete");
    }

    // Work: has todos → do one item
    if (state.hasTodos) {
      return work(
        `
        You are generating Postgres DDL for the PCMS schema.

        Your task: ${state.nextTodo}

        ## Required Reading (if not already familiar)

        1. \`backlog/ralph/pcms/AGENTS.md\` — overall design philosophy
        2. \`backlog/ralph/pcms/schema/AGENTS.md\` — detailed schema conventions (CRITICAL)
        3. \`backlog/ralph/pcms/schema/*.txt\` — table specifications to convert
        4. \`backlog/ralph/pcms/data/\` — data pipeline context, entity mappings

        ## Output

        Write DDL to \`f/ralph/new_pcms_schema.flow/inline_script_*.pg.sql\`

        ## DDL Conventions

        - First file must include: \`CREATE SCHEMA IF NOT EXISTS pcms;\`
        - Use \`SET search_path TO pcms;\` after schema creation
        - No FK constraints — add comments like \`-- FK: references people(person_id)\`
        - Include \`CREATE INDEX\` statements for common joins/filters
        - Keep files under 500 lines (600-800 max if necessary)
        - Balanced comments: not verbose, not absent

        ## PCMS-Specific

        - Use \`salary_year\` (not season or season_year) for cap year
        - Money columns in DOLLARS:
          - \`bigint\` for whole-dollar amounts
          - \`numeric\` for decimals or uncertain string-typed fields
        - Provenance columns: source_drop_file, source_hash, parser_version, ingested_at
        - V1 scope is NBA-only (WNBA columns can exist but load as NULL)

        ## File Management

        - If creating a new inline_script file, update \`f/ralph/new_pcms_schema.flow/flow.yaml\`
        - Add the new module following the existing pattern

        When done:
        - Check off ONLY this task in \`${TASK_FILE}\`
        - git add -A && git commit -m "pcms-schema: <summary>"
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
        1. \`backlog/ralph/pcms/AGENTS.md\` — overall design philosophy
        2. \`backlog/ralph/pcms/schema/AGENTS.md\` — detailed conventions (money, lineage, naming)
        3. \`backlog/ralph/pcms/schema/TODO.md\` — remaining cleanup items
        4. ALL files in \`backlog/ralph/pcms/schema/*.txt\` — table specifications
        5. \`backlog/ralph/pcms/data/\` — entity mappings, pipeline architecture, ingestion design

        ## Step 2: Plan File Split

        Group tables logically and estimate LOC. Target ~400-500 LOC per file.

        Consider grouping:
        - Core entities: people, teams, lookups
        - Contracts: contracts, contract_terms, salaries, exceptions
        - Transactions: trades, waivers, transactions, draft_picks
        - Financial: team_budget, tax_and_aprons, rookie_scale, non_contract_amounts
        - Lineage/Audit: lineage, lineage_audit, audit_logs
        - Other: depth_charts, injury_reports, scouting, medical, agencies

        ## Step 3: Create Checklist

        Write to \`${TASK_FILE}\`:

        \`\`\`markdown
        # PCMS Schema Generation

        **Output directory:** \`f/ralph/new_pcms_schema.flow/\`

        ## Phase 1: Planning
        - [x] Read backlog/ralph/pcms/AGENTS.md
        - [x] Read backlog/ralph/pcms/schema/AGENTS.md (conventions)
        - [x] Read all backlog/ralph/pcms/schema/*.txt
        - [x] Read backlog/ralph/pcms/data/
        - [x] Plan file split

        ## Phase 2: DDL Generation
        - [ ] inline_script_0.inline_script.pg.sql — schema + <table list>
        - [ ] inline_script_1.inline_script.pg.sql — <table list>
        - [ ] ... (as many as needed)

        ## Phase 3: Validation
        - [ ] Cross-check all .txt specs have CREATE TABLE
        - [ ] Verify money columns are DOLLARS (bigint/numeric)
        - [ ] Verify provenance columns per schema/AGENTS.md
        \`\`\`

        Commit: git add -A && git commit -m "pcms-schema: create generation plan"
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

      For EVERY file in \`backlog/ralph/pcms/schema/*.txt\`:
      - Confirm there's a corresponding CREATE TABLE in \`f/ralph/new_pcms_schema.flow/\`
      - Verify column names and types match the spec
      - Verify constraints (PK, UNIQUE) are present

      ### Step 2: Convention Compliance

      Check against \`backlog/ralph/pcms/schema/AGENTS.md\`:
      - Provenance columns: source_drop_file, source_hash, parser_version, ingested_at
      - Naming: snake_case, salary_year (not season)
      - Money: DOLLARS, bigint for whole amounts, numeric for decimals
      - IDs: integer for PCMS IDs, bigint if range exceeds integer
      - JSONB: only when genuinely nested/variable, named <domain>_json

      ### Step 3: Data Pipeline Alignment

      Check against \`backlog/ralph/pcms/data/\`:
      - Do entity mappings align with table structure?
      - Is the lineage/audit design implemented correctly?
      - Are UPSERT keys consistent with pipeline expectations?

      ### Step 4: File Quality

      - All files under 600 LOC
      - flow.yaml correctly references all inline_script files
      - DDL is syntactically valid

      ## Output

      If gaps found:
      - Add tasks to \`${TASK_FILE}\`
      - Commit: git add -A && git commit -m "pcms-schema: validation found gaps"

      If complete:
      - Add validation summary to \`${TASK_FILE}\`
      - Add marker: \`${VALIDATION_MARKER}\`
      - Commit: git add -A && git commit -m "pcms-schema: validation complete"
      `,
      { thinking: "high", timeout: "12m" }
    );
  },
});
