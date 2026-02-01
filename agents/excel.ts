#!/usr/bin/env bun
import { loop, work, halt, supervisor } from "./core";

/**
 * excel.ts — Excel Cap Book Build Agent
 *
 * Purpose:
 * - Turn the Blueprints in reference/blueprints/ into a real, self-contained Excel workbook
 *   populated from Postgres (pcms.*).
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

Every 4 commits, review:

1) reference/blueprints/*
   - mental models + workbook architecture + data refresh + data contract
2) .ralph/EXCEL.md
   - current backlog (ensure tasks are concrete, ordered, and not stale)
3) excel/
   - templates and exporter scripts created so far

SUPERVISOR CHECKLIST

**Blueprint alignment**
- Is the workbook staying self-contained (no external refs)?
- Are totals driven by authoritative "what counts" sources (team_salary_warehouse)?
- Are we following the data contract for DATA_* tables (keys, columns, semantics)?
- Are policies/assumptions explicit (not hidden defaults)?

**Implementation hygiene**
- Are we using warehouse tables/views (pcms.*_warehouse, salary_book_yearly) rather than raw joins?
- Does the exporter record META fields (refreshed_at, base_year, as-of date, exporter git sha)?
- Do we fail fast or loudly mark FAILED when validations/reconciliation break?

**Backlog hygiene**
- Are tasks small enough to complete + commit in one iteration?
- Are follow-up tasks added when new work is discovered?
- Is the backlog ordering still correct?

If you make changes:
- Update .ralph/EXCEL.md (reorder/add/remove tasks)
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
You are building the next-generation Sean-style Excel cap workbook.

Your task: ${state.nextTodo}

REQUIRED READING (before coding)
1) excel/AGENTS.md
2) .ralph/EXCEL.md (backlog + rules)
3) reference/blueprints/README.md
4) reference/blueprints/mental-models-and-design-principles.md
5) reference/blueprints/excel-cap-book-blueprint.md
6) reference/blueprints/excel-workbook-data-refresh-blueprint.md
7) reference/blueprints/excel-workbook-data-contract.md

If you need DB field meanings, also read:
- SALARY_BOOK.md
- SCHEMA.md

RULES
- Prefer offline/self-contained workbooks (no live DB connections inside Excel by default).
- Prefer extracting from pcms.*_warehouse and stable views (e.g. pcms.salary_book_yearly).
- Do one logical chunk of work per iteration.
- Update ${TASK_FILE}: check off ONLY the completed task; add follow-ups if you discover gaps.
- Commit and exit:
  - git add -A && git commit -m "excel: <short summary>"
  - Exit immediately
        `,
        {
          model: "claude-opus-4-5-thinking",
          // model: "gemini-3-flash",
          provider: "google-antigravity",
          thinking: "high",
          timeout: "10m",
        },
      );
    }

    // We intentionally do NOT auto-generate tasks for this agent.
    return halt("No tasks in " + TASK_FILE);
  },
});
