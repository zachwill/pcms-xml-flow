#!/usr/bin/env bun
import { loop, work, generate, halt, supervisor } from "./core";
import { readFileSync } from "fs";

const VALIDATION_MARKER = "<!-- PCMS_DATA_VALIDATED -->";
const TASK_FILE = ".ralph/PCMS_DATA.md";

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
  name: "pcms-data",
  taskFile: TASK_FILE,
  timeout: "10m",
  pushEvery: 3,
  maxIterations: 50,

  supervisor: supervisor(
    `
    Review the generated import scripts in \`f/ralph/import_pcms_data.flow/\`.

    Cross-reference against:
    - \`backlog/ralph/pcms/data/\` — pipeline architecture, entity mapping, lineage design
    - \`backlog/ralph/pcms/schema/*.txt\` — table specifications
    - \`f/ralph/new_pcms_schema.flow/\` — generated DDL for column names/types
    - \`f/ralph/utils.ts\` — shared utilities

    Check:
    - Is S3 file detection and streaming implemented correctly?
    - Is XML parsing using streaming (SAX or fast-xml-parser)?
    - Is lineage tracking implemented (pcms_lineage, pcms_lineage_audit)?
    - Does every entity in entity-mapping.md have a corresponding parser?
    - Are provenance columns populated (source_drop_file, source_hash, parser_version, ingested_at)?
    - Is the upsert strategy correct per pipeline-architecture.md?
    - Are money columns in DOLLARS (bigint)?
    - Are files under 500 LOC?
    - Is error handling resilient?

    If issues found:
    - Remove validation marker if present: \`${VALIDATION_MARKER}\`
    - Add tasks to \`${TASK_FILE}\`
    - Commit: git add -A && git commit -m "pcms-data: supervisor review"
    `,
    { every: 6, thinking: "medium" }
  ),

  run(state) {
    // Done: no todos + validation marker
    if (!state.hasTodos && hasValidationMarker()) {
      return halt("PCMS data import scripts complete");
    }

    // Work: has todos → do one item
    if (state.hasTodos) {
      return work(
        `
        You are generating Bun/TypeScript import scripts for the PCMS data pipeline.

        Your task: ${state.nextTodo}

        ## Required Reading (if not already familiar)

        1. \`backlog/ralph/pcms/data/\` — ALL files, especially:
           - \`AGENTS.md\` — overall design philosophy
           - \`README.md\` — pipeline overview
           - \`entity-mapping.md\` — XML element to table mapping (CRITICAL)
           - \`entity-mapping-expansion.md\` — additional mappings
           - \`pipeline-architecture.md\` — S3 → XML → Postgres flow
           - \`parser-design.md\` + \`parser-sketch.ts\` — streaming XML patterns
           - \`lineage-design.md\` + \`lineage-utils.ts\` — audit trail
           - \`incremental-processing.md\` — deduplication via hash
        2. \`f/ralph/new_pcms_schema.flow/*.pg.sql\` — actual DDL for column names
        3. \`f/ralph/utils.ts\` — shared utilities (hash, upsertBatch, etc.)
        4. \`f/ralph/import_pcms_data.flow/AGENTS.md\` — coding conventions for this flow
        5. \`f/blitz/pcms_xml.ts\` — existing S3/SFTP patterns
        6. \`docs/bun-postgres.md\` — Bun SQL patterns

        ## Output

        Write scripts to \`f/ralph/import_pcms_data.flow/inline_script_*.ts\`

        ## Script Conventions

        - Import utilities: \`import { ... } from "/f/ralph/utils.ts";\`
        - Database: \`const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });\`
        - S3: Use Bun's native \`s3\` or \`Bun.S3Client\`
        - XML: Use \`fast-xml-parser\` in streaming mode or SAX
        - Export: \`export async function main(dry_run = false, ...params) { ... }\`
        - Return: ImportSummary object with results per table
        - Keep files under 500 LOC

        ## PCMS-Specific Conventions

        - All money in DOLLARS: use \`bigint\` for whole amounts
        - Use \`salary_year\` (not season)
        - Provenance: source_drop_file, source_hash, parser_version, ingested_at
        - Track lineage in pcms.pcms_lineage and pcms.pcms_lineage_audit

        ## Standard Script Structure

        \`\`\`typescript
        import { SQL, s3 } from "bun";
        import { XMLParser } from "fast-xml-parser";
        import { hash, upsertBatch, createSummary, finalizeSummary } from "/f/ralph/utils.ts";

        const sql = new SQL({ url: Bun.env.POSTGRES_URL!, prepare: false });
        const PARSER_VERSION = "1.0.0";

        // Entity parser
        function parsePerson(raw: any, lineageId: string): PersonRow { ... }

        // Main
        export async function main(
          dry_run = false,
          s3_key?: string,  // Specific file, or scan for unprocessed
          limit?: number
        ) {
          const summary = createSummary(dry_run);
          
          // 1. Find unprocessed S3 files
          // 2. Stream and parse XML
          // 3. Transform to rows
          // 4. Upsert with lineage tracking
          
          return finalizeSummary(summary);
        }
        \`\`\`

        ## File Management

        - If creating a new inline_script file, update \`f/ralph/import_pcms_data.flow/flow.yaml\`
        - Add the new module following the existing pattern
        - Use language: bun

        When done:
        - Check off ONLY this task in \`${TASK_FILE}\`
        - git add -A && git commit -m "pcms-data: <summary>"
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
        1. \`backlog/ralph/pcms/data/\` — ALL files:
           - AGENTS.md
           - README.md
           - entity-mapping.md (CRITICAL — XML to table mapping)
           - entity-mapping-expansion.md
           - pipeline-architecture.md
           - parser-design.md + parser-sketch.ts
           - lineage-design.md + lineage-utils.ts
           - ingestion-design.md
           - incremental-processing.md + incremental-utils.ts
           - error-handling.md
           - types.ts
           - secondary-entities.ts
           - trigger-sketch.ts
           - TODO.md
        2. \`f/ralph/new_pcms_schema.flow/*.pg.sql\` — DDL for exact column names
        3. \`f/ralph/utils.ts\` — shared utilities
        4. \`.ralph/PCMS_SCHEMA.md\` — table inventory from schema generation
        5. \`docs/bun-s3.md\` — S3 streaming patterns

        ## Step 2: Plan Script Organization

        PCMS has a unique architecture:
        - Data arrives as ZIP files in S3 (e.g., \`pcms/*.zip\`)
        - Each ZIP contains XML extracts (e.g., \`nba_pcms_*_extract_player.xml\`)
        - Must track which files have been processed (lineage)
        - Must handle streaming for large files

        Suggested groupings:
        - **lineage.ts** — S3 file detection, lineage tracking (must run first)
        - **core_entities.ts** — people, teams, lookups (from player, team, lookup XMLs)
        - **contracts.ts** — contracts, contract_versions, contract_bonuses, salaries
        - **exceptions.ts** — team_exceptions, team_exception_usage
        - **transactions.ts** — trades, trade_teams, trade_team_details, transactions, ledger_entries
        - **financial.ts** — team_budget_snapshots, league_system_values, rookie_scale_amounts
        - **two_way.ts** — two_way_daily_statuses, two_way_game_utility, two_way_contract_utility
        - **draft_waivers.ts** — draft_picks, draft_rankings, waiver_priority
        - **operations.ts** — depth_charts, injury_reports, scouting_reports, agencies, agents

        ## Step 3: Create Checklist

        Write to \`${TASK_FILE}\`:

        \`\`\`markdown
        # PCMS Data Import Script Generation

        **Output directory:** \`f/ralph/import_pcms_data.flow/\`
        **Source:** S3 ZIP files containing XML extracts

        ## Phase 1: Planning
        - [x] Read backlog/ralph/pcms/data/* (all design docs)
        - [x] Read f/ralph/new_pcms_schema.flow/*.pg.sql (DDL)
        - [x] Read f/ralph/utils.ts (shared utilities)
        - [x] Understand entity-mapping.md (XML → table)
        - [x] Plan script organization

        ## Phase 2: Script Generation
        - [ ] inline_script_0 — lineage.ts: S3 detection, pcms_lineage, pcms_lineage_audit
        - [ ] inline_script_1 — core_entities.ts: people, teams, lookups
        - [ ] inline_script_2 — contracts.ts: contracts, contract_versions, contract_bonuses, salaries, payment_schedules
        - [ ] inline_script_3 — exceptions.ts: team_exceptions, team_exception_usage
        - [ ] inline_script_4 — transactions.ts: trades, trade_teams, trade_team_details, transactions, ledger_entries
        - [ ] inline_script_5 — financial.ts: team_budget_snapshots, league_system_values, rookie_scale_amounts, non_contract_amounts
        - [ ] inline_script_6 — two_way.ts: two_way_daily_statuses, two_way_game_utility, two_way_contract_utility, team_two_way_capacity
        - [ ] inline_script_7 — draft_waivers.ts: draft_picks, draft_rankings, waiver_priority, waiver_priority_ranks
        - [ ] inline_script_8 — operations.ts: depth_charts, injury_reports, scouting_reports, medical_intel, agencies, agents

        ## Phase 3: Validation
        - [ ] All entity mappings from entity-mapping.md have import coverage
        - [ ] Lineage tracking is implemented
        - [ ] Money columns use bigint (DOLLARS)
        - [ ] salary_year naming convention followed
        - [ ] Error handling is resilient
        \`\`\`

        Commit: git add -A && git commit -m "pcms-data: create generation plan"
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

      ### Step 1: Entity Coverage

      For EVERY entity in \`backlog/ralph/pcms/data/entity-mapping.md\`:
      - Confirm there's a corresponding parser function
      - Verify XML element names are correctly mapped
      - Check column names match DDL

      ### Step 2: PCMS-Specific Checks

      - Lineage tracking: pcms_lineage and pcms_lineage_audit populated
      - Money in DOLLARS: bigint for amounts, numeric for rates
      - salary_year used (not season)
      - parser_version tracked

      ### Step 3: Script Quality

      - All files under 500 LOC
      - flow.yaml correctly references all inline_script files
      - dry_run parameter is supported
      - Error handling is resilient
      - S3 streaming is efficient (not loading entire ZIP into memory)

      ## Output

      If gaps found:
      - Add tasks to \`${TASK_FILE}\`
      - Commit: git add -A && git commit -m "pcms-data: validation found gaps"

      If complete:
      - Add validation summary to \`${TASK_FILE}\`
      - Add marker: \`${VALIDATION_MARKER}\`
      - Commit: git add -A && git commit -m "pcms-data: validation complete"
      `,
      { thinking: "high", timeout: "12m" }
    );
  },
});
