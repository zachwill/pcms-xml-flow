#!/usr/bin/env bun
import { readFileSync } from "node:fs";

import { loop, work, generate, halt, runPi } from "./core";

/**
 * design.ts — Design evolution loop (NOT hygiene sweeps)
 *
 * Goal:
 * - Raise the UX/design quality of non-Salary-Book surfaces in web/
 * - Work at the user-flow level (hierarchy, navigation, scan speed, interaction clarity)
 * - Keep Salary Book read-only as the golden reference, except the approved Tankathon surface
 */

const TASK_FILE = ".ralph/DESIGN.md";

const DESIGN_CONTRACT = [
  "web/AGENTS.md",
  "web/docs/design_guide.md",
  "web/docs/datastar_sse_playbook.md",
  "reference/sites/INTERACTION_MODELS.md",
];

const SALARY_BOOK_EXEMPLARS = [
  "web/app/views/tools/salary_book/show.html.erb",
  "web/app/views/tools/salary_book/_player_row.html.erb",
  "web/app/views/tools/salary_book/_team_section.html.erb",
  "web/app/views/tools/salary_book/_sidebar_player.html.erb",
  "web/app/views/tools/salary_book/_sidebar_agent.html.erb",
  "web/app/views/tools/salary_book/_kpi_cell.html.erb",
  "web/app/views/tools/salary_book/_table_header.html.erb",
];

const NON_SALARY_TARGETS = [
  "web/app/views/tools/team_summary/",
  "web/app/views/tools/system_values/",
  "web/app/views/tools/two_way_utility/",
  "web/app/views/entities/",
  "web/app/controllers/entities/",
  "web/app/controllers/tools/",
  "web/app/helpers/",
  "web/app/javascript/",
  "web/test/integration/",
];

const SALARY_BOOK_TANKATHON_ALLOWED = [
  "web/app/views/tools/salary_book/_maincanvas_tankathon_frame.html.erb",
];

const ENTITY_INDEX_SURFACES = [
  "web/app/views/entities/players/index.html.erb",
  "web/app/views/entities/teams/index.html.erb",
  "web/app/views/entities/agents/index.html.erb",
  "web/app/views/entities/agencies/index.html.erb",
  "web/app/views/entities/drafts/index.html.erb",
  "web/app/views/entities/transactions/index.html.erb",
  "web/app/views/entities/trades/index.html.erb",
  "web/app/views/entities/draft_selections/index.html.erb",
];

const TOOL_SURFACES = [
  "web/app/views/tools/team_summary/show.html.erb",
  "web/app/views/tools/system_values/show.html.erb",
  "web/app/views/tools/two_way_utility/show.html.erb",
];

const NORTH_STAR = `
North star:
- Entity index pages are explorer workbenches (Salary Book-like interaction model, not clones).
- They should support fast scanning, meaningful filters/knobs, dense interactive rows, and sidebar drill-ins.
- Canonical pattern: commandbar + maincanvas + rightpanel-base + rightpanel-overlay.
- Salary Book remains read-only and is used as the quality bar for interaction grammar (except approved Tankathon surface work).
- In parallel, tool surfaces (Team Summary, System Values, Two-Way Utility) should evolve toward stronger workbench UX.
`.trim();

const RUBRIC = `
Design evolution rubric (score 1-5, before and after):
1) Scan speed (can a user find what matters quickly?)
2) Information hierarchy (is primary vs secondary obvious?)
3) Interaction predictability (does behavior match user expectation?)
4) Density/readability balance (compact without becoming noisy)
5) Navigation/pivots (can users move to related context with low friction?)
`.trim();

const COMMIT_TITLE_SCHEMA = "design: [TRACK] /surface flow-outcome";
const SUPERVISOR_COMMIT_TITLE = "design: [PROCESS] /supervisor review";
const GENERATE_COMMIT_TITLE = "design: [PROCESS] /backlog generate evolution backlog";

const ENTITY_OVERRIDE_PATTERN =
  /\[ENTITY-OVERRIDE\]|supervisor\s+override\s*:\s*entity|entity\s+override\s*:\s*allowed/i;

const COMPLETED_TASK_PATTERN = /^- \[x\] \[P\d\] \[(INDEX|TOOL|PROCESS|ENTITY)\]/im;

const SALARY_BOOK_FORBIDDEN_EXACT = new Set<string>([
  "web/app/controllers/tools/salary_book_controller.rb",
  "web/app/controllers/tools/salary_book_sse_controller.rb",
  "web/app/helpers/salary_book_helper.rb",
]);

const LOOP_START_SHA = gitStdout(["rev-parse", "HEAD"]);

type GuardReport = { ok: boolean; errors: string[] };
type CommitInfo = { hash: string; subject: string };

function gitStdout(args: string[]): string {
  const result = Bun.spawnSync({ cmd: ["git", ...args], stdout: "pipe", stderr: "pipe" });
  if (result.exitCode !== 0) return "";
  return Buffer.from(result.stdout).toString("utf8").trim();
}

function gitLines(args: string[]): string[] {
  const out = gitStdout(args);
  if (!out) return [];
  return out
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function readTaskFileContent(): string {
  try {
    return readFileSync(TASK_FILE, "utf8");
  } catch {
    return "";
  }
}

function hasEntityOverride(taskContent: string): boolean {
  return ENTITY_OVERRIDE_PATTERN.test(taskContent);
}

function hasCompletedTaskBlocks(taskContent: string): boolean {
  return COMPLETED_TASK_PATTERN.test(taskContent);
}

function workerCommitRegex(allowEntity: boolean): RegExp {
  const tracks = allowEntity ? "INDEX|TOOL|PROCESS|ENTITY" : "INDEX|TOOL|PROCESS";
  return new RegExp(`^design: \\[(${tracks})\\] \\/\\S+ .+$`);
}

function commitsSinceLoopStart(): CommitInfo[] {
  if (!LOOP_START_SHA) return [];

  return gitLines(["log", "--format=%H%x09%s", `${LOOP_START_SHA}..HEAD`])
    .map((line) => {
      const [hash, ...rest] = line.split("\t");
      return { hash: hash?.trim() ?? "", subject: rest.join("\t").trim() };
    })
    .filter((entry) => entry.hash.length > 0);
}

function commitChangedPaths(hash: string): string[] {
  if (!hash) return [];
  return gitLines(["show", "--name-only", "--pretty=format:", "--no-renames", hash]);
}

function pendingChangedPaths(): string[] {
  const unstaged = gitLines(["diff", "--name-only"]);
  const staged = gitLines(["diff", "--cached", "--name-only"]);
  return Array.from(new Set([...unstaged, ...staged]));
}

function forbiddenSalaryBookPaths(paths: string[]): string[] {
  return paths.filter((path) => {
    if (path.startsWith("web/app/views/tools/salary_book/")) {
      return !SALARY_BOOK_TANKATHON_ALLOWED.includes(path);
    }

    if (SALARY_BOOK_FORBIDDEN_EXACT.has(path)) return true;
    if (path.startsWith("web/test/integration/salary_book")) return true;
    return false;
  });
}

function evaluateDesignGuards(state: { hasTodos: boolean; nextTodo: string | null }): GuardReport {
  const errors: string[] = [];
  const taskContent = readTaskFileContent();
  const entityOverrideEnabled = hasEntityOverride(taskContent);

  if (hasCompletedTaskBlocks(taskContent)) {
    errors.push(
      `${TASK_FILE} must remain active-only: remove completed task blocks (- [x] [P*] [TRACK] ...). ` +
        "Archive completion details in git history and keep at most a short audit note."
    );
  }

  if (state.hasTodos && /\[ENTITY\]/i.test(state.nextTodo ?? "") && !entityOverrideEnabled) {
    errors.push(
      `Blocked task: ${state.nextTodo}. [ENTITY] tasks require explicit supervisor override marker ` +
        "([ENTITY-OVERRIDE] or 'supervisor override: ENTITY')."
    );
  }

  const pendingForbidden = forbiddenSalaryBookPaths(pendingChangedPaths());
  if (pendingForbidden.length > 0) {
    errors.push(
      `Blocked working diff touches forbidden Salary Book paths: ${pendingForbidden.join(", ")}`
    );
  }

  const workerTitlePattern = workerCommitRegex(entityOverrideEnabled);
  for (const commit of commitsSinceLoopStart()) {
    const isSupervisorCommit = commit.subject === SUPERVISOR_COMMIT_TITLE;

    if (!isSupervisorCommit) {
      if (!workerTitlePattern.test(commit.subject)) {
        errors.push(
          `Commit title violation (${commit.hash.slice(0, 7)}): "${commit.subject}". ` +
            `Expected schema: ${COMMIT_TITLE_SCHEMA}`
        );
      }

      if (/\[ENTITY\]/i.test(commit.subject) && !entityOverrideEnabled) {
        errors.push(
          `Commit track violation (${commit.hash.slice(0, 7)}): [ENTITY] requires explicit supervisor override.`
        );
      }
    }

    const forbiddenPaths = forbiddenSalaryBookPaths(commitChangedPaths(commit.hash));
    if (forbiddenPaths.length > 0) {
      errors.push(
        `Commit path violation (${commit.hash.slice(0, 7)}): touched forbidden Salary Book paths: ${forbiddenPaths.join(", ")}`
      );
    }
  }

  return { ok: errors.length === 0, errors };
}

function logGuardFailure(scope: "loop" | "supervisor", report: GuardReport): void {
  const prefix = scope === "supervisor" ? "[Supervisor Guard][FAIL]" : "[Design Guard][FAIL]";
  console.log(prefix);
  for (const error of report.errors) {
    console.log(`- ${error}`);
  }
}

const SUPERVISOR_PROMPT = `
You are supervising the design-evolution loop.

PRIMARY OBJECTIVE:
Ensure the worker is making meaningful UX/design improvements (flow-level),
not cosmetic lint sweeps.

STRATEGIC INTENT:
${NORTH_STAR}

HARD GUARDRAIL:
Salary Book remains read-only reference quality, with one approved exception.
Allowed Salary Book edit target (only):
${SALARY_BOOK_TANKATHON_ALLOWED.map((f) => `- ${f}`).join("\n")}
Forbidden edits include (non-exhaustive):
- web/app/views/tools/salary_book/** (except the approved Tankathon file above)
- web/app/controllers/tools/salary_book_controller.rb
- web/app/controllers/tools/salary_book_sse_controller.rb
- web/app/helpers/salary_book_helper.rb
- web/test/integration/salary_book*

COMMIT + TRACK GUARD:
- Worker commit titles must match: ${COMMIT_TITLE_SCHEMA}
- [ENTITY] task/commit tracks are blocked unless task file contains explicit override marker:
  [ENTITY-OVERRIDE] (or "supervisor override: ENTITY")

REVIEW INPUTS:
1) ${TASK_FILE}
2) Recent work (git log --oneline -8 && git diff --name-only HEAD~4 -- web/)
3) ${DESIGN_CONTRACT.join("\n3) ")}

SUPERVISOR CHECKLIST:
- Is each commit tied to one explicit surface + user flow?
- Is the work clearly in one track: INDEX convergence or TOOL evolution?
- If INDEX: did it move toward explorer-workbench behavior (knobs/filters, dense rows, sidebar drill-ins)?
- If TOOL: did it improve planning-workbench UX (clarity, pivots, predictable interactions)?
- Is the change improving hierarchy/behavior/wayfinding (not just class tweaks)?
- Did the worker avoid broad grep-only style chores unless directly supporting a flow fix?
- Are Datastar patch boundaries and response rules still correct?
- Did they avoid touching forbidden Salary Book files (anything outside the approved Tankathon file)?
- Is ${TASK_FILE} active-only (no completed task blocks reintroduced)?
- If a task was completed, was completion evidence captured briefly and archived to git history?

IF DRIFT IS DETECTED:
- Revert low-value cosmetic churn
- Add corrective TODOs emphasizing flow-level outcomes
- Tighten task wording in ${TASK_FILE}

AFTER REVIEW:
- Update ${TASK_FILE} if needed
- git add -A && git commit -m "${SUPERVISOR_COMMIT_TITLE}"
`.trim();

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
      const report = evaluateDesignGuards(state);
      if (!report.ok) {
        logGuardFailure("supervisor", report);
        throw new Error("Design supervisor guardrail check failed. See errors above.");
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
    const report = evaluateDesignGuards(state);
    if (!report.ok) {
      logGuardFailure("loop", report);
      return halt("Design guardrails failed. Resolve violations before continuing the loop.");
    }

    if (state.hasTodos) {
      return work(
        `
You are executing a design-evolution task (flow-level UX improvement).

CURRENT TASK HEADER:
${state.nextTodo}

STRATEGY:
${NORTH_STAR}

INDEX SURFACES:
${ENTITY_INDEX_SURFACES.map((f) => `- ${f}`).join("\n")}

TOOL SURFACES:
${TOOL_SURFACES.map((f) => `- ${f}`).join("\n")}

FIRST, read:
- ${TASK_FILE} (full file, including current task block details)
- ${DESIGN_CONTRACT.join("\n- ")}
- Relevant Salary Book exemplar(s):
${SALARY_BOOK_EXEMPLARS.map((f) => `- ${f}`).join("\n")}

TARGETS:
${NON_SALARY_TARGETS.map((t) => `- ${t}`).join("\n")}
Approved Salary Book exception (only):
${SALARY_BOOK_TANKATHON_ALLOWED.map((f) => `- ${f}`).join("\n")}

HARD RULES:
1) Do NOT edit Salary Book files except the approved Tankathon file above.
2) Do NOT edit Salary Book controllers/helpers/tests.
3) Focus on one surface and one user flow for this task.
4) Respect strategic priority: entity index convergence first, while continuing steady tool evolution.
5) Prioritize hierarchy/interaction/wayfinding over cosmetic class parity.
6) You may edit views/controllers/helpers/minimal JS/tests when required.
7) Keep business/CBA math in SQL (do not reimplement in Ruby/JS).
8) Keep changes coherent and shippable (avoid sprawling refactors).
9) Commit titles must follow: ${COMMIT_TITLE_SCHEMA}.
10) [ENTITY] track is forbidden unless ${TASK_FILE} contains explicit supervisor override marker ([ENTITY-OVERRIDE] or "supervisor override: ENTITY").
11) Keep ${TASK_FILE} active-only: do not leave completed task blocks in the file.

ANTI-PATTERNS (avoid):
- Repo-wide grep/replace for style-only classes
- “Add font-mono/dark variant everywhere” chores with no flow outcome
- Blindly porting Salary Book mechanics where the surface has different goals

REQUIRED TASK COMPLETION STEPS:
1) Implement the flow-level improvement.
2) Run focused verification (tests or targeted checks).
3) Update the current task block in ${TASK_FILE} with:
   - What changed (files)
   - Why this improves the flow
   - Before → after rubric scores (all 5 dimensions)
   - Any follow-up tasks discovered
4) Check off the task, then immediately archive/remove the completed block so ${TASK_FILE} remains active-only (optional: keep one short audit note).
5) Commit:
   git add -A && git commit -m "design: [TRACK] /surface flow-outcome"
        `,
        {
          provider: "openai-codex",
          model: "gpt-5.3-codex",
          thinking: "high",
          timeout: "12m",
        }
      );
    }

    const contextBlock = state.context
      ? `\nFocus area from --context: ${state.context}\n`
      : "";

    return generate(
      `
${TASK_FILE} has no unchecked tasks.
${contextBlock}

Generate a fresh design-evolution backlog (NOT hygiene backlog).

STRATEGY:
${NORTH_STAR}

Read first:
- ${DESIGN_CONTRACT.join("\n- ")}
- Salary Book exemplars (read-only quality bar):
${SALARY_BOOK_EXEMPLARS.map((f) => `- ${f}`).join("\n")}

Primary convergence surfaces (entity indexes):
${ENTITY_INDEX_SURFACES.map((f) => `- ${f}`).join("\n")}

Parallel tool-evolution surfaces:
${TOOL_SURFACES.map((f) => `- ${f}`).join("\n")}

Audit these areas:
${NON_SALARY_TARGETS.map((t) => `- ${t}`).join("\n")}
Approved Salary Book exception (only):
${SALARY_BOOK_TANKATHON_ALLOWED.map((f) => `- ${f}`).join("\n")}

Rubric to use:
${RUBRIC}

BACKLOG RULES:
1) Tasks must be user-flow based, not class-audit based.
2) Each task must target exactly one surface + one primary flow.
3) Include concrete files likely to change.
4) Include acceptance criteria that can be verified.
5) Include before/target rubric scores.
6) Guardrails per task block:
   - Default: Do not modify Salary Book files.
   - Tankathon-only exception: allow edits only to approved Tankathon file; forbid all other Salary Book files/controllers/helpers/tests.
7) Prioritize highest-leverage UX wins first.
8) Prioritization order:
   - P1: Entity index convergence to explorer-workbench behavior
   - P2: Tool evolution (Team Summary, System Values, Two-Way Utility, and Salary Book Tankathon-only)
   - P3: Lower-leverage polish/supporting tasks
9) Do not starve tool evolution: top 10 tasks should include at least 3 tool tasks.
10) Keep ${TASK_FILE} active-only: output unchecked tasks only, and do not include completed ([x]) blocks.

TASK BLOCK FORMAT (required):
- [ ] [P1|P2|P3] [INDEX|TOOL] <surface> — <flow outcome>
  - Problem: <what user cannot do efficiently today>
  - Hypothesis: <why this intervention should help>
  - Scope (files):
    - <path>
    - <path>
  - Acceptance criteria:
    - <criterion>
    - <criterion>
  - Rubric (before → target):
    - Scan speed: X → Y
    - Information hierarchy: X → Y
    - Interaction predictability: X → Y
    - Density/readability: X → Y
    - Navigation/pivots: X → Y
  - Guardrails:
    - <default Salary Book prohibition OR Tankathon-only exception>

For INDEX tasks, prefer acceptance criteria that validate:
- filters/knobs are useful and discoverable
- rows are dense and interactive
- sidebar drill-ins preserve context
- pivots to canonical entity pages are obvious

For TOOL tasks, prefer acceptance criteria that validate:
- fast comparison/scanning workflows
- clear state transitions and patch behavior
- better wayfinding without reducing density

Do not create chores like “add class X across N files” unless directly required
for the flow outcome.

After generating/updating ${TASK_FILE}:
- git add -A && git commit -m "${GENERATE_COMMIT_TITLE}"
      `,
      {
        provider: "openai-codex",
        model: "gpt-5.3-codex",
        thinking: "high",
        timeout: "15m",
      }
    );
  },
});
