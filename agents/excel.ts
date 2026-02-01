#!/usr/bin/env bun
import { loop, work, halt, supervisor } from "./core";

/**
 * excel.ts — Excel Cap Book Build Agent
 *
 * Purpose:
 * - Build dense, beautiful, reactive Excel workbooks for salary cap analysts
 * - Use XlsxWriter with modern Excel features (FILTER, XLOOKUP, LET, LAMBDA)
 * - Populate from Postgres (pcms.*)
 *
 * This agent does NOT generate its own backlog.
 * You must seed tasks in:
 *   - .ralph/EXCEL.md
 *
 * Usage:
 *   bun agents/excel.ts
 *   bun agents/excel.ts --once
 *   bun agents/excel.ts --dry-run
 */

const TASK_FILE = ".ralph/EXCEL.md";

loop({
  name: "excel",
  taskFile: TASK_FILE,
  timeout: "12m",
  pushEvery: 4,
  maxIterations: 200,

  supervisor: supervisor(
    `
You are the supervisor for the Excel cap workbook build.

THE THREE PILLARS (the guiding light):
1. Correct data — Authoritative Postgres data into DATA_* sheets
2. Modern Excel — FILTER, XLOOKUP, LET, LAMBDA via XlsxWriter
3. Dense, beautiful, reactive UI — Inputs drive the view, everything reacts

Every 4 commits, review:

1) excel/
   - UI.md (authoritative PLAYGROUND spec; do not shortcut)
   - AGENTS.md (folder context)
   - XLSXWRITER.md (patterns)
   - capbook/ implementation

2) reference/blueprints/
   - README.md (the guiding light)
   - excel-cap-book-blueprint.md (vision + principles)
   - data-contract.md (DATA_ sheet specs)

3) reference/blueprints/specs/
   - playground.md (legacy notes; defer to excel/UI.md)

4) .ralph/EXCEL.md
   - current backlog (ensure tasks are concrete and ordered)

SUPERVISOR CHECKLIST

**Three pillars alignment**
- Is data coming from authoritative warehouses (pcms.*_warehouse)?
- Are we using modern Excel formulas (not legacy SUMPRODUCT/INDEX-MATCH)?
- Is the UI dense and reactive (inputs drive the view)?

**Implementation hygiene**
- Does the exporter record META fields (timestamp, base_year, as_of, git SHA)?
- Are we following XLSXWRITER.md patterns (_xlpm. prefixes, ANCHORARRAY, etc.)?
- Are input cells light yellow? Is formatting consistent (Aptos Narrow, alignment)?

**Backlog hygiene**
- Are tasks small enough to complete in one iteration?
- Is the ordering correct?

If you make changes:
- Update .ralph/EXCEL.md
- Commit: git add -A && git commit -m "excel: supervisor review"
    `,
    {
      every: 6,
      model: "gpt-5.2",
      provider: "openai-codex",
      thinking: "high",
      timeout: "15m",
    },
  ),

  run(state) {
    if (state.hasTodos) {
      return work(
        `
You are building Excel workbooks for NBA salary cap analysts.

Your task: ${state.nextTodo}

THE THREE PILLARS
1. Correct data — DATA_* sheets from Postgres warehouses
2. Modern Excel — FILTER, XLOOKUP, LET, LAMBDA (no legacy hacks)
3. Dense, beautiful, reactive UI — Inputs drive the view

REQUIRED READING (before coding)
1) excel/AGENTS.md — folder context
2) excel/XLSXWRITER.md — formula patterns + gotchas
3) reference/blueprints/README.md — the guiding light
4) reference/blueprints/excel-cap-book-blueprint.md — vision + principles
5) reference/blueprints/data-contract.md — DATA_ sheet specs
6) excel/UI.md — authoritative PLAYGROUND UI spec (do not shortcut)
7) reference/blueprints/specs/playground.md — legacy notes (defer to excel/UI.md)

RULES
- Use modern Excel: FILTER, XLOOKUP, LET, LAMBDA, dynamic arrays
- Follow XLSXWRITER.md patterns (use_future_functions, _xlpm. prefixes, ANCHORARRAY)
- Input cells are light yellow. Numbers right-aligned. Aptos Narrow font.
- Workbook is offline/self-contained (no live DB connections)
- Do one logical chunk of work per iteration
- Update ${TASK_FILE}: check off completed task, add follow-ups if needed
- Commit and exit:
  - git add -A && git commit -m "excel: <short summary>"
  - Exit immediately
        `,
        {
          model: "claude-opus-4-5-thinking",
          provider: "google-antigravity",
          thinking: "high",
          timeout: "10m",
        },
      );
    }

    return halt("No tasks in " + TASK_FILE);
  },
});
