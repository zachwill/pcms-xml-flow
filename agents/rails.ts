#!/usr/bin/env bun
import { loop, work, generate, supervisor } from "./core";

/**
 * rails.ts — Rails + Datastar (web/) Salary Book Port Agent
 *
 * Goal:
 * - Recreate the Bun + React prototype in prototypes/salary-book-react/
 *   as a Rails + Datastar tool in web/.
 *
 * Canonical tool URL:
 * - /tools/salary-book
 *
 * Backlog / task tracking:
 * - .ralph/RAILS.md
 *
 * Usage:
 *   bun agents/rails.ts
 *   bun agents/rails.ts --once
 *   bun agents/rails.ts --dry-run
 */

const TASK_FILE = ".ralph/RAILS.md";

loop({
  name: "rails",
  taskFile: TASK_FILE,
  timeout: "15m",
  pushEvery: 4,
  maxIterations: 200,
  continuous: false,

  supervisor: supervisor(
    `
You are the supervisor for the Rails + Datastar Salary Book port.

Every 4 commits, review progress and keep the backlog healthy.

REVIEW INPUTS:
1) .ralph/RAILS.md (current backlog)
2) web/specs/01-salary-book.md (interaction + layout spec)
3) reference/datastar/AGENTS.md (Datastar conventions)
4) prototypes/salary-book-react/ (reference implementation)

SUPERVISOR CHECKLIST:
- Is the agent making real progress toward the next TODO?
- Are we returning HTML fragments with stable IDs (not scattered JSON)?
- Are Datastar signals flatcase? DOM refs underscore-prefixed?
- Is custom JS minimal? (Scroll spy is probably the only real need)
- Are the completed items actually done, or do they need follow-up?

IF BACKLOG NEEDS ADJUSTMENT:
- Reorder tasks if dependencies are wrong
- Add notes/context to upcoming tasks if the agent seems confused
- Split tasks that are too big, merge tasks that are too granular
- Move completed items to the "Done" section

AFTER REVIEW:
- Update ${TASK_FILE} if needed
- git add -A && git commit -m "rails: supervisor review"
    `,
    {
      every: 4,
      provider: "openai-codex",
      model: "gpt-5.2",
      thinking: "xhigh",
      timeout: "15m",
    },
  ),

  run(state) {
    if (state.hasTodos) {
      return work(
        `
You are porting the Salary Book from the Bun + React prototype to Rails + Datastar.

CURRENT TASK:
${state.nextTodo}

Read the full context at the top of ${TASK_FILE} before coding.

KEY REFERENCES:
- web/AGENTS.md — Rails app conventions
- web/specs/01-salary-book.md — interaction + layout spec
- reference/datastar/AGENTS.md — Datastar conventions (READ THIS)
- prototypes/salary-book-react/ — markup/UX reference

EXECUTION:
1) Read relevant existing files in web/ first
2) Implement the task completely
3) Check off the completed item in ${TASK_FILE}
4) If the task reveals follow-up work, add it as a note or new TODO
5) Commit and exit:
   git add -A && git commit -m "rails: <short summary>"
        `,
        {
          provider: "google-antigravity",
          model: "claude-opus-4-5-thinking",
          thinking: "high",
          timeout: "10m",
        },
      );
    }

    const contextBlock = state.context ? `\nFocus area: ${state.context}\n` : "";

    return generate(
      `
${TASK_FILE} has no unchecked tasks.
${contextBlock}

Review what's been built and generate the next logical backlog.

INPUTS:
- web/specs/01-salary-book.md (what we're building toward)
- prototypes/salary-book-react/ (reference implementation)
- Current state of web/ (what exists now)

BACKLOG FORMAT:
- [ ] Task description
    - Context/notes for the coding agent
    - Pointers to relevant files or spec sections

After writing tasks:
- git add -A && git commit -m "rails: generate backlog"
      `,
      {
        provider: "google-antigravity",
        model: "claude-opus-4-5-thinking",
        thinking: "high",
        timeout: "10m",
      },
    );
  },
});
