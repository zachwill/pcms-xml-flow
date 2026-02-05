#!/usr/bin/env bun
import { loop, work, generate, supervisor } from "./core";

/**
 * shorthand.ts — Draft Pick Shorthand Curation Agent (Postgres)
 *
 * Purpose:
 * - Reduce missing shorthand backlog in pcms.draft_pick_shorthand_assets
 * - Curate durable Sean-style shorthand for draft pick assets
 *
 * Canonical backlog:
 * - .ralph/SHORTHAND.md
 *
 * Usage:
 *   bun agents/shorthand.ts
 *   bun agents/shorthand.ts --once
 *   bun agents/shorthand.ts --dry-run
 */

const TASK_FILE = ".ralph/SHORTHAND.md";

loop({
  name: "shorthand",
  taskFile: TASK_FILE,
  timeout: "15m",
  pushEvery: 4,
  maxIterations: 200,
  continuous: false,

  supervisor: supervisor(
    `
You are the supervisor for the Draft Pick Shorthand curation loop.

Every 4 commits, verify that work is:
- Reducing primary_todo_reason='missing_shorthand' for draft_year >= 2026
- Following shorthand rules in ${TASK_FILE}
- Not embedding endnote numbers inside shorthand strings
- Not embedding "To XYZ: " inside shorthand (direction is handled by vw_draft_pick_assets.display_text)

Supervisor routine:
1) Read ${TASK_FILE} and ensure the backlog is ordered and actionable.
2) Run the work-queue query (top endnote clusters) and compare to backlog.
3) If backlog is stale, update it:
   - add new endnote clusters
   - reorder to match impact (row counts)
   - move completed items to Done
4) Sanity check a couple recently-completed clusters:
   - select ... from pcms.vw_draft_pick_assets where <id> = any(effective_endnote_ids)
   - verify display_text direction for outgoing To ... rows
5) Run assertions 062 + 063.

If you make changes:
- git add ${TASK_FILE} && git commit -m "shorthand: supervisor review"
    `,
    {
      every: 4,
      provider: "openai-codex",
      model: "gpt-5.2",
      thinking: "high",
      timeout: "15m",
    },
  ),

  run(state) {
    if (state.hasTodos) {
      return work(
        `
You are curating durable NBA draft-pick shorthand in Postgres.

CURRENT TASK:
${state.nextTodo}

Read the full context and rules at the top of ${TASK_FILE} before doing any DB work.

HARD REQUIREMENT:
- Use: psql "$POSTGRES_URL" -v ON_ERROR_STOP=1

WORKFLOW (per endnote cluster):
1) Pick the endnote id from the task.
2) Query all rows in pcms.vw_draft_pick_assets for that endnote id (draft_year >= 2026).
3) Read pcms.endnotes for that endnote id (and dependencies), and/or the raw text file in:
   /Users/zachwill/blazers/cba-docs/endnotes/revised/
4) Draft a consistent shorthand for the underlying asset.
5) Upsert into pcms.draft_pick_shorthand_assets (ON CONFLICT DO UPDATE), with:
   - source_lk='manual_endnote'
   - endnote_ids (cluster + dependencies)
   - referenced_team_codes
   - useful notes
6) Verify in pcms.vw_draft_pick_assets that:
   - shorthand appears
   - outgoing rows render direction-aware display_text (To XYZ: ...)
7) Run assertions 062 and 063 ONLY.

REPO HYGIENE (important):
- After DB work, update ${TASK_FILE}:
  - check off the completed checkbox
  - append a short entry under Done describing what you added
- Commit and exit:
  - git add ${TASK_FILE} && git commit -m "shorthand: <endnote_id> <short summary>"
  - Exit immediately
        `,
        {
          provider: "google-antigravity",
          model: "claude-opus-4-5-thinking",
          thinking: "high",
          timeout: "12m",
        },
      );
    }

    return generate(
      `
${TASK_FILE} has no unchecked tasks.

Generate a fresh backlog focused on:
- pcms.vw_draft_pick_shorthand_todo
- primary_todo_reason='missing_shorthand'
- draft_year >= 2026

Steps:
1) Run the top-endnote-clusters query from ${TASK_FILE}.
2) Write checkbox tasks for the top clusters (at least the top 20).
   Format suggestion:
   - [ ] Endnote 277 (6 rows) — MEM↔ORL 2029 1st swap
3) Keep/refresh the "Done" section (append-only) and avoid deleting history.

After writing tasks:
- git add ${TASK_FILE} && git commit -m "shorthand: generate backlog"
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
