#!/usr/bin/env bun
import { readFileSync } from "node:fs";

import { loop, work, generate, halt, runPi } from "./core";

/**
 * design.ts — UX/design evolution loop for web/
 *
 * Intent:
 * - Converge non-Salary-Book surfaces toward the Salary Book + Noah quality bar.
 * - Work in concrete, committable chunks — not multi-step ceremonies.
 * - Keep Salary Book read-only except approved Tankathon surface work.
 */

const TASK_FILE = ".ralph/DESIGN.md";

// ── Knowledge the agent should have access to ──────────────────

const DESIGN_DOCS = [
  "web/AGENTS.md",
  "web/docs/design_guide.md",
  "web/docs/datastar_sse_playbook.md",
  "reference/sites/INTERACTION_MODELS.md",
];

const SALARY_BOOK_EXEMPLARS = [
  "web/app/views/salary_book/show.html.erb",
  "web/app/views/salary_book/_team_section.html.erb",
  "web/app/views/salary_book/_player_row.html.erb",
  "web/app/views/salary_book/_sidebar_team.html.erb",
  "web/app/views/salary_book/_sidebar_player.html.erb",
  "web/app/views/salary_book/_sidebar_agent.html.erb",
  "web/app/views/salary_book/_maincanvas.html.erb",
];

const NOAH_EXEMPLARS = [
  "web/app/views/ripcity/noah/show.html.erb",
  "web/app/views/ripcity/noah/_maincanvas.html.erb",
  "web/app/views/ripcity/noah/_sidebar_base.html.erb",
  "web/app/controllers/ripcity/noah_controller.rb",
  "web/app/javascript/ripcity/noah_shotchart.js",
];

const TARGET_SURFACES = [
  "web/app/views/team_summary/",
  "web/app/views/system_values/",
  "web/app/views/two_way_utility/",
  "web/app/views/players/",
  "web/app/views/teams/",
  "web/app/views/agents/",
  "web/app/views/agencies/",
  "web/app/views/drafts/",
  "web/app/views/draft_selections/",
  "web/app/views/trades/",
  "web/app/views/transactions/",
  "web/app/controllers/",
  "web/app/helpers/",
  "web/app/javascript/",
  "web/test/integration/",
];

const SALARY_BOOK_ALLOWED = [
  "web/app/views/salary_book/_maincanvas_tankathon_frame.html.erb",
];

const SALARY_BOOK_FORBIDDEN_EXACT = new Set<string>([
  "web/app/controllers/salary_book_controller.rb",
  "web/app/controllers/salary_book_switch_controller.rb",
  "web/app/helpers/salary_book_helper.rb",
]);

const ENTITY_OVERRIDE_PATTERN =
  /\[ENTITY-OVERRIDE\]|supervisor\s+override\s*:\s*entity|entity\s+override\s*:\s*allowed/i;

const COMMIT_TITLE_SCHEMA = "design: [TRACK] /surface — outcome";

// ── Strategy (compact) ─────────────────────────────────────────

const STRATEGY = `
## North star
- Salary Book + Noah are the reference taste and interaction grammar.
- Non-Salary surfaces should converge toward explorer workbenches
  (fast scan, dense rows, low-friction pivots).
- Preserve canonical patch boundaries: #commandbar, #maincanvas,
  #rightpanel-base, #rightpanel-overlay.
- Ship coherent chunk outcomes, not isolated style edits.
`.trim();

const TANKATHON_RULES = `
## Tankathon rules (when touching Tankathon UX)
- Standings rows are non-clickable scan rows.
- No hover/cursor affordance for non-actions.
- Highlight implications from selected team perspective (keeps vs conveys).
- Team-column-first pick context before record metrics.
- Validate conveyance direction using pcms.draft_pick_summary_assets
  and pcms.draft_pick_shorthand_assets before changing implication labels.
`.trim();

// ── Guardrails ─────────────────────────────────────────────────

function bullets(items: string[]): string {
  return items.map((x) => `- ${x}`).join("\n");
}

function gitStdout(args: string[]): string {
  const result = Bun.spawnSync({ cmd: ["git", ...args], stdout: "pipe", stderr: "pipe" });
  if (result.exitCode !== 0) return "";
  return Buffer.from(result.stdout).toString("utf8").trim();
}

function gitLines(args: string[]): string[] {
  const out = gitStdout(args);
  if (!out) return [];
  return out.split("\n").map((l) => l.trim()).filter(Boolean);
}

function readTaskFileContent(): string {
  try { return readFileSync(TASK_FILE, "utf8"); } catch { return ""; }
}

function hasEntityOverride(taskContent: string): boolean {
  return ENTITY_OVERRIDE_PATTERN.test(taskContent);
}

function pendingChangedPaths(): string[] {
  const unstaged = gitLines(["diff", "--name-only"]);
  const staged = gitLines(["diff", "--cached", "--name-only"]);
  return Array.from(new Set([...unstaged, ...staged]));
}

function forbiddenSalaryBookPaths(paths: string[]): string[] {
  return paths.filter((p) => {
    if (p.startsWith("web/app/views/salary_book/")) return !SALARY_BOOK_ALLOWED.includes(p);
    if (SALARY_BOOK_FORBIDDEN_EXACT.has(p)) return true;
    if (p.startsWith("web/test/integration/salary_book")) return true;
    return false;
  });
}

function evaluateGuards(state: { hasTodos: boolean; nextTodo: string | null }): string[] {
  const errors: string[] = [];
  const taskContent = readTaskFileContent();
  const entityOverrideEnabled = hasEntityOverride(taskContent);

  if (state.hasTodos && /\[ENTITY\]/i.test(state.nextTodo ?? "") && !entityOverrideEnabled) {
    errors.push(
      `Blocked: ${state.nextTodo}. [ENTITY] requires override marker in ${TASK_FILE}.`
    );
  }

  const pendingForbidden = forbiddenSalaryBookPaths(pendingChangedPaths());
  if (pendingForbidden.length > 0) {
    errors.push(`Diff touches forbidden Salary Book paths: ${pendingForbidden.join(", ")}`);
  }

  return errors;
}

function logGuardFailure(scope: string, errors: string[]): void {
  console.log(`[${scope} Guard][FAIL]`);
  for (const e of errors) console.log(`- ${e}`);
}

// ── Prompts ────────────────────────────────────────────────────

const SUPERVISOR_PROMPT = `
You are supervising the design-evolution loop.

${STRATEGY}
${TANKATHON_RULES}

Task file: ${TASK_FILE}

Review the recent commits (git log --oneline -10, then read changed files).

Check:
1. Is each commit tied to one surface and one flow outcome?
2. Are changes improving hierarchy, wayfinding, or interaction predictability?
3. Are Datastar patch boundaries and response semantics still correct?
4. Is this real UX movement, not style-only churn?

If drift:
- Revert low-value churn.
- Tighten task wording in ${TASK_FILE}.
- Add corrective tasks.

Design reference (read as needed):
${bullets(DESIGN_DOCS)}

Quality exemplars (read-only — do not edit):
Salary Book: ${bullets(SALARY_BOOK_EXEMPLARS)}
Noah: ${bullets(NOAH_EXEMPLARS)}

After review, commit:
  git add -A && git commit -m "design: [PROCESS] supervisor review"
`.trim();

function workerPrompt(nextTodo: string | null): string {
  return `
You are executing one design task. Read the task, read the relevant files, implement, commit.

## Current task
${nextTodo}

${STRATEGY}
${TANKATHON_RULES}

## How to work
1. Read ${TASK_FILE} for context.
2. Read the target files for this task (the views, controller, JS listed in the task or that you discover).
3. Read 1-2 exemplar files to calibrate taste (pick from the lists below based on relevance).
4. Implement the change.
5. Check off the task in ${TASK_FILE} and add a one-line note if useful.
6. Commit: git add -A && git commit -m "${COMMIT_TITLE_SCHEMA}"

If the task is bigger than you can finish, do as much as you can, commit what you have,
and add a follow-up unchecked task to ${TASK_FILE} for the remainder.

## Design system reference (read as needed, not all up front)
${bullets(DESIGN_DOCS)}

## Quality exemplars (read-only — study for taste, do not edit)
Salary Book:
${bullets(SALARY_BOOK_EXEMPLARS)}
Noah:
${bullets(NOAH_EXEMPLARS)}

## Implementation scope (allowed to edit)
${bullets(TARGET_SURFACES)}

## Salary Book exception (only this file)
${bullets(SALARY_BOOK_ALLOWED)}

## Hard rules
1. Do NOT edit Salary Book files except the one allowed exception above.
2. Do NOT edit Salary Book controllers/helpers/tests.
3. [ENTITY] work is blocked unless override marker exists in ${TASK_FILE}.
4. Keep changes to one coherent chunk. No drive-by class sweeps.
5. Business/CBA math stays in SQL, not Ruby/JS.
6. Density is the design — rows, links, data. Not cards, not whitespace.
7. Commit early. Partial progress > timeout with nothing saved.
  `.trim();
}

function generatePrompt(context: string | null): string {
  const contextBlock = context ? `\nFocus area: ${context}\n` : "";

  return `
${TASK_FILE} has no unchecked tasks.${contextBlock}
Generate a fresh design-evolution backlog.

${STRATEGY}

Read first:
${bullets(DESIGN_DOCS)}

Study these exemplars for quality bar:
Salary Book: ${bullets(SALARY_BOOK_EXEMPLARS.slice(0, 3))}
Noah: ${bullets(NOAH_EXEMPLARS.slice(0, 2))}

Then audit these surfaces (read their current files):
${bullets(TARGET_SURFACES)}

## Task format
Each task should be a concrete, achievable unit of work (one iteration = one task).
Do NOT write tasks that require multi-step ceremony or approval gates.

Format:
- [ ] [P1|P2|P3] [INDEX|TOOL|PROCESS] /surface — concrete outcome
  Files: list of files to change
  Why: one sentence on the flow problem being fixed

Backlog rules:
1. Tasks are user-flow outcomes, not cosmetic sweeps.
2. Each task = one surface + one outcome, achievable in ~10 minutes of focused coding.
3. Break big changes into multiple sequential tasks.
4. If a task touches interaction patterns, say what the new pattern should be.
5. Do not create tasks that modify Salary Book (exception: Tankathon frame).
6. Prioritize: P1 = broken/confusing flows, P2 = convergence toward exemplar quality, P3 = polish.

After writing:
  git add -A && git commit -m "design: [PROCESS] generate backlog"
  `.trim();
}

// ── Loop ───────────────────────────────────────────────────────

loop({
  name: "design",
  taskFile: TASK_FILE,
  timeout: "15m",
  pushEvery: 4,
  maxIterations: 240,
  continuous: true,

  supervisor: {
    every: 6,
    async run(state) {
      const errors = evaluateGuards(state);
      if (errors.length > 0) {
        logGuardFailure("Supervisor", errors);
        throw new Error("Supervisor guardrail check failed.");
      }

      await runPi(SUPERVISOR_PROMPT, {
        role: "supervisor",
        provider: "openai-codex",
        model: "gpt-5.3-codex",
        thinking: "high",
        timeout: "15m",
      });
    },
  },

  run(state) {
    const errors = evaluateGuards(state);
    if (errors.length > 0) {
      logGuardFailure("Loop", errors);
      return halt("Guardrails failed. Resolve violations before continuing.");
    }

    if (state.hasTodos) {
      return work(workerPrompt(state.nextTodo), {
        provider: "openai-codex",
        model: "gpt-5.3-codex",
        thinking: "high",
        timeout: "12m",
      });
    }

    return generate(generatePrompt(state.context), {
      provider: "openai-codex",
      model: "gpt-5.3-codex",
      thinking: "high",
      timeout: "15m",
    });
  },
});
