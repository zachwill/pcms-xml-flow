#!/usr/bin/env bun
import { loop, work, generate, supervisor } from "./core";

/**
 * rails.ts — Rails + Datastar (web/) product loop
 *
 * Current direction:
 * - Salary Book is active product work (not maintenance).
 * - Finish Salary Book v1 interaction contract, then ship Trade Machine MVP.
 * - Continue entity explorer densification in parallel, without regressing tool UX.
 *
 * Backlog / task tracking:
 * - .ralph/RAILS.md (canonical roadmap + TODOs)
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
You are the supervisor for the Rails + Datastar web product loop.

Every 4 commits, review progress and keep the roadmap accurate.

REVIEW INPUTS:
1) ${TASK_FILE} (canonical roadmap / priorities)
2) web/AGENTS.md (Rails + Datastar conventions)
3) web/specs/00-ui-philosophy.md
4) web/specs/01-salary-book.md
5) web/specs/02-team-header-and-draft-assets.md
6) web/specs/03-trade-machine.md
7) web/MIGRATION_MEMO.md

SUPERVISOR CHECKLIST:
- Is the worker advancing the highest-priority unchecked task (P0/P1 first unless roadmap says otherwise)?
- Is Salary Book staying dense/instrument-like (not docs/prose UI)?
- Are toggles/signals truthful (avoid shipping inert controls unless explicitly marked deferred)?
- Are routes + pages HTML-first with stable Datastar patch boundaries and flatcase signals?
- Are entity routes still canonical slug-first with numeric fallback redirects?
- Is cap/CBA/trade math staying in Postgres primitives (not reimplemented in Ruby/JS)?
- Are completed items actually complete (not placeholders) and reflected in ${TASK_FILE}?

IF ROADMAP NEEDS ADJUSTMENT:
- Reorder tasks when dependencies changed
- Split oversized tasks into shippable increments
- Merge/remove stale tasks
- Preserve clear P0→P4 ordering and keep "done" status truthful

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
You are implementing the Rails + Datastar web product roadmap.

CURRENT TASK:
${state.nextTodo}

Read the full context at the top of ${TASK_FILE} before coding.

KEY REFERENCES:
- ${TASK_FILE} — canonical roadmap + TODOs
- web/AGENTS.md — conventions + guardrails
- web/specs/00-ui-philosophy.md — core invariants
- web/specs/01-salary-book.md — Salary Book interaction contract
- web/specs/02-team-header-and-draft-assets.md — header + draft details
- web/specs/03-trade-machine.md — trade overlay requirements
- web/MIGRATION_MEMO.md — implementation mapping

STYLE CONVENTIONS:
- Prefer Tailwind utility classes in .html.erb.
- Keep JS minimal and idempotent.
- Keep business math in Postgres.

EXECUTION:
1) Read relevant existing files in web/ first.
2) Implement the task completely.
3) Run targeted verification commands relevant to your change.
4) Check off the completed item in ${TASK_FILE}.
5) If needed, append concise follow-up TODOs/notes in ${TASK_FILE}.
6) Commit and exit:
   git add -A && git commit -m "rails: <short summary>"
        `,
        {
          // provider: "openai-codex",
          model: "gpt-5.3-codex",
          thinking: "high",
          timeout: "12m",
        },
      );
    }

    const contextBlock = state.context ? `\nFocus area: ${state.context}\n` : "";

    return generate(
      `
${TASK_FILE} has no unchecked tasks.
${contextBlock}

Audit current implementation and generate the next prioritized backlog.

INPUTS:
- ${TASK_FILE}
- web/AGENTS.md
- web/specs/00-ui-philosophy.md
- web/specs/01-salary-book.md
- web/specs/02-team-header-and-draft-assets.md
- web/specs/03-trade-machine.md
- web/MIGRATION_MEMO.md
- current state of web/

BACKLOG REQUIREMENTS:
- Keep priorities explicit (P0 salary-book completion before P1+ unless evidence says otherwise)
- Use actionable checkbox tasks:
  - [ ] Task description
      - Context/notes
      - File paths or spec pointers
- Remove stale tasks and avoid duplicate TODOs.

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
