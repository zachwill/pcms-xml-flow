#!/usr/bin/env bun
import { loop, work, generate, supervisor } from "./core";

/**
 * sean.ts — Sean Workbook Reverse-Engineering Agent
 *
 * Purpose:
 * - The "Sean-style" tooling (Salary Book / Team Master / Trade Machine)
 *   historically referenced `reference/sean/`.
 * - Sean has provided a newer workbook export in `reference/warehouse/`.
 *
 * This agent builds UPDATED mental models by reading the JSON worksheet exports
 * and writing evidence-based specs to:
 *   - reference/warehouse/specs/
 *
 * Backlog / task tracking:
 *   - .ralph/SEAN.md
 *
 * Usage:
 *   bun agents/sean.ts
 *   bun agents/sean.ts --once
 *   bun agents/sean.ts --dry-run
 */

const TASK_FILE = ".ralph/SEAN.md";

loop({
  name: "sean",
  taskFile: TASK_FILE,
  timeout: "10m",
  pushEvery: 4,
  maxIterations: 200,

  supervisor: supervisor(
    `
You are the supervisor for the "Sean workbook" reverse-engineering effort.

Every 4 commits, review the current state of:

1) reference/warehouse/AGENTS.md (file inventory + high-level relationships)
2) reference/warehouse/specs/ (the specs written so far)
3) .ralph/SEAN.md (the backlog)

Checklist:
- Are the specs evidence-based (cite real formulas / row+col examples)?
- Are cross-sheet dependencies documented in BOTH directions?
- Is the mapping to our DB model (pcms.*) plausible and consistent with SCHEMA.md + SALARY_BOOK.md?
- Is the spec template consistent across sheets?
- Are we focusing on the "core" sheets first (y, dynamic_contracts, system_values, team/playground, machine)?

Actions:
- Reorder tasks if dependencies are wrong
- Add missing tasks if a spec reveals another sheet is critical
- Add a TODO section to specs when there are unresolved ambiguities

If you make changes:
- git add -A && git commit -m "sean: supervisor review"
    `,
    {
      every: 4,
      model: "gpt-5.2",
      provider: "openai-codex",
      thinking: "high",
      timeout: "12m",
    }
  ),

  run(state) {
    if (state.hasTodos) {
      return work(
        `
You are reverse-engineering Sean's CURRENT workbook exported as JSON in:
- reference/warehouse/*.json

Your task: ${state.nextTodo}

REQUIRED READING (before writing a spec):
1) reference/warehouse/AGENTS.md
2) .ralph/SEAN.md (spec template + preferred jq/rg commands)
3) SCHEMA.md (authoritative column names)
4) SALARY_BOOK.md (canonical interpretation of contract/salary fields)

IMPORTANT CONTEXT:
- The old folder reference/sean/ is now legacy (≈1 year old) and may be wrong.
- Treat reference/warehouse/*.json as immutable reference artifacts.
- Your output should be NEW docs only: reference/warehouse/specs/*.md

WHAT TO DO (per task):
1) Inspect the relevant JSON file(s) using jq/rg.
   - Identify header rows / section titles
   - Identify key user inputs (team selector, year selector, toggles)
   - Identify outputs (tables, dashboards)
   - Collect a few representative formulas that prove dependencies/logic
2) Write/update the spec:
   - reference/warehouse/specs/<sheet>.md
   - Follow the template in .ralph/SEAN.md
   - Keep it concise, but include enough real evidence that a future engineer can trust it
3) Update .ralph/SEAN.md:
   - Check off ONLY the completed item
   - Add follow-up tasks if you discover missing work
4) Commit and exit:
   - git add -A && git commit -m "sean: spec <sheet>"
   - Exit immediately (one task per iteration)
        `,
        { model: "claude-opus-4-5-thinking", thinking: "high" }
      );
    }

    const contextBlock = state.context
      ? `\nFocus area: ${state.context}\n`
      : "";

    return generate(
      `
${TASK_FILE} has no unchecked tasks.
${contextBlock}

Generate a fresh backlog in ${TASK_FILE}.

Rules:
- Include ONE checkbox task per JSON file in reference/warehouse/.
- Prefer to order tasks:
  1) Core warehouses/constants (y, dynamic_contracts, system_values)
  2) Tool-facing sheets (playground, team, team_summary, machine)
  3) Lookups (draft picks, protections, exceptions)
  4) Small calculators/snapshots (buyouts, set-offs, cover)

Also include a meta-task to create/update:
- reference/warehouse/specs/00-index.md

After writing tasks:
- git add -A && git commit -m "sean: generate backlog"
      `,
      { model: "claude-opus-4-5-thinking", thinking: "medium" }
    );
  },
});
