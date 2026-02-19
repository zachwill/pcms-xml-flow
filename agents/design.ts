#!/usr/bin/env bun
import { readFileSync } from "node:fs";

import { loop, work, generate, halt, runPi } from "./core";

/**
 * design.ts — UX/design evolution loop for web/
 *
 * Intent:
 * - Converge non-Salary-Book surfaces toward the Salary Book + Noah quality bar.
 * - Work in logical UX chunks (flow outcomes), not cosmetic class sweeps.
 * - Keep Salary Book read-only except approved Tankathon surface work.
 */

const TASK_FILE = ".ralph/DESIGN.md";

const DESIGN_DOCS = [
  "web/AGENTS.md",
  "web/docs/AGENTS.md",
  "web/docs/design_guide.md",
  "web/docs/agent_browser_playbook.md",
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

const INDEX_SURFACES = [
  "web/app/views/players/index.html.erb",
  "web/app/views/teams/index.html.erb",
  "web/app/views/agents/index.html.erb",
  "web/app/views/agencies/index.html.erb",
  "web/app/views/drafts/index.html.erb",
  "web/app/views/draft_selections/index.html.erb",
  "web/app/views/trades/index.html.erb",
  "web/app/views/transactions/index.html.erb",
];

const TOOL_SURFACES = [
  "web/app/views/team_summary/show.html.erb",
  "web/app/views/system_values/show.html.erb",
  "web/app/views/two_way_utility/show.html.erb",
];

const QA_ROUTES = [
  "/",
  "/ripcity/noah",
  "/team-summary",
  "/system-values",
  "/two-way-utility",
  "/players",
  "/teams",
  "/agents",
  "/drafts",
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

const COMMIT_TITLE_SCHEMA = "design: [TRACK] /surface flow-outcome";
const SUPERVISOR_COMMIT_TITLE = "design: [PROCESS] /supervisor review";
const GENERATE_COMMIT_TITLE = "design: [PROCESS] /backlog generate evolution backlog";

const STRATEGY = `
North star:
- Salary Book + Noah are the reference taste and interaction grammar.
- Non-Salary surfaces should converge toward explorer workbenches (fast scan, dense rows, low-friction pivots).
- Preserve canonical patch boundaries: #commandbar, #maincanvas, #rightpanel-base, #rightpanel-overlay.
- Ship coherent chunk outcomes (flow bundles), not isolated style edits.
`.trim();

const EVIDENCE_GATE = `
Evidence-first execution (mandatory):
- Before coding, inspect / and /ripcity/noah, then the target route.
- Capture fresh artifacts in /tmp/agent-browser/:
  - snapshot -i -C -c
  - annotated screenshot(s)
- Write a short diagnosis before implementation:
  - what is strong and should remain
  - what is weak/confusing
  - highest-leverage flow problem for this chunk
- For interaction-sensitive redesigns, propose 1-2 chunk options and confirm direction before implementation.
`.trim();

const RUBRIC = `
Rubric (score 1-5):
1) Scan speed
2) Information hierarchy
3) Interaction predictability
4) Density/readability balance
5) Navigation/pivots
`.trim();

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

function pendingChangedPaths(): string[] {
  const unstaged = gitLines(["diff", "--name-only"]);
  const staged = gitLines(["diff", "--cached", "--name-only"]);
  return Array.from(new Set([...unstaged, ...staged]));
}

function forbiddenSalaryBookPaths(paths: string[]): string[] {
  return paths.filter((path) => {
    if (path.startsWith("web/app/views/salary_book/")) {
      return !SALARY_BOOK_ALLOWED.includes(path);
    }

    if (SALARY_BOOK_FORBIDDEN_EXACT.has(path)) return true;
    if (path.startsWith("web/test/integration/salary_book")) return true;
    return false;
  });
}

function evaluateGuards(state: { hasTodos: boolean; nextTodo: string | null }): string[] {
  const errors: string[] = [];
  const taskContent = readTaskFileContent();
  const entityOverrideEnabled = hasEntityOverride(taskContent);

  if (state.hasTodos && /\[ENTITY\]/i.test(state.nextTodo ?? "") && !entityOverrideEnabled) {
    errors.push(
      `Blocked task: ${state.nextTodo}. [ENTITY] requires explicit override marker in ${TASK_FILE} ` +
        `([ENTITY-OVERRIDE] or \"supervisor override: ENTITY\").`
    );
  }

  const pendingForbidden = forbiddenSalaryBookPaths(pendingChangedPaths());
  if (pendingForbidden.length > 0) {
    errors.push(`Working diff touches forbidden Salary Book paths: ${pendingForbidden.join(", ")}`);
  }

  return errors;
}

function logGuardFailure(scope: "loop" | "supervisor", errors: string[]): void {
  const prefix = scope === "supervisor" ? "[Supervisor Guard][FAIL]" : "[Design Guard][FAIL]";
  console.log(prefix);
  for (const error of errors) console.log(`- ${error}`);
}

const SUPERVISOR_PROMPT = `
You are supervising the design-evolution loop.

PRIMARY OBJECTIVE:
Drive meaningful UX/design improvements in coherent flow chunks, not cosmetic sweeps.

${STRATEGY}
${EVIDENCE_GATE}

Reference docs:
${bullets([TASK_FILE, ...DESIGN_DOCS])}

Read-only quality exemplars:
Salary Book:
${bullets(SALARY_BOOK_EXEMPLARS)}
Noah:
${bullets(NOAH_EXEMPLARS)}

Hard guardrail:
- Salary Book is read-only except:
${bullets(SALARY_BOOK_ALLOWED)}
- Do not edit Salary Book controllers/helpers/tests.
- [ENTITY] track requires explicit override marker in ${TASK_FILE}.

Supervisor checklist:
- Is each commit tied to one surface (or explicit family) and one flow outcome?
- Did the worker gather and cite before-state evidence before coding?
- Is the change improving hierarchy, wayfinding, or interaction predictability?
- Are Datastar patch boundaries and response semantics still correct?
- Is this real UX movement, not style-only churn?

If drift is detected:
- Revert low-value churn.
- Tighten task wording in ${TASK_FILE}.
- Add corrective tasks focused on evidence-first chunk outcomes.

After review:
- Update ${TASK_FILE} if needed.
- git add -A && git commit -m "${SUPERVISOR_COMMIT_TITLE}"
`.trim();

function workerPrompt(nextTodo: string | null): string {
  return `
You are executing one design-evolution task.

Current task:
${nextTodo}

${STRATEGY}
${EVIDENCE_GATE}

Read first:
${bullets([TASK_FILE, ...DESIGN_DOCS])}

Reference exemplars:
Salary Book:
${bullets(SALARY_BOOK_EXEMPLARS)}
Noah:
${bullets(NOAH_EXEMPLARS)}

Primary surfaces:
INDEX:
${bullets(INDEX_SURFACES)}
TOOL:
${bullets(TOOL_SURFACES)}

Allowed implementation areas:
${bullets(TARGET_SURFACES)}

Salary Book exception (only):
${bullets(SALARY_BOOK_ALLOWED)}

Hard rules:
1) Do not edit Salary Book files except allowed exception above.
2) Do not edit Salary Book controllers/helpers/tests.
3) [ENTITY] work is blocked unless override marker exists in ${TASK_FILE}.
4) Keep changes to one coherent chunk outcome.
5) Prioritize hierarchy/interaction/wayfinding over class churn.
6) Keep business/CBA math in SQL (not Ruby/JS).
7) Commit title schema: ${COMMIT_TITLE_SCHEMA}

Agent-browser QA loop (when app is runnable):
- Session: pcms-web
- Capture before/after artifacts in /tmp/agent-browser/
- Preferred baseline routes:
${bullets(QA_ROUTES)}
- If blocked, document exact blocker in task notes.

Completion steps:
1) Capture before evidence and write diagnosis.
2) Implement the chunk.
3) Run focused verification.
4) Capture after evidence.
5) Update ${TASK_FILE} with concise notes + follow-ups.
6) Commit:
   git add -A && git commit -m "design: [TRACK] /surface flow-outcome"
  `;
}

function generatePrompt(context: string | null): string {
  const contextBlock = context ? `\nFocus area from --context: ${context}\n` : "";

  return `
${TASK_FILE} has no unchecked tasks.${contextBlock}
Generate a fresh design-evolution backlog (not hygiene chores).

${STRATEGY}
${EVIDENCE_GATE}
${RUBRIC}

Read first:
${bullets([...DESIGN_DOCS, ...SALARY_BOOK_EXEMPLARS, ...NOAH_EXEMPLARS])}

Surfaces to audit:
${bullets(TARGET_SURFACES)}

Preferred baseline routes:
${bullets(QA_ROUTES)}

Backlog rules:
1) Tasks must be user-flow based.
2) Each task = one surface (or explicit PROCESS family) + one primary outcome.
3) Include likely files to change.
4) Require before-state evidence (/, /ripcity/noah, target route).
5) Include acceptance criteria and rubric targets.
6) Default guardrail: do not modify Salary Book files.
7) Tankathon exception allowed only for:
${bullets(SALARY_BOOK_ALLOWED)}
8) Prioritize P1 entity-index convergence and high-impact tool work.
9) Top 10 tasks should include at least 3 TOOL tasks.

Task format:
- [ ] [P1|P2|P3] [INDEX|TOOL|PROCESS|ENTITY] <surface> — <flow outcome>
  - Problem:
  - Hypothesis:
  - Evidence to gather first:
    - Reference routes: / and /ripcity/noah
    - Target route: <route>
    - Artifacts: snapshot -i -C -c + annotated screenshot(s)
  - Scope (files):
    - <path>
  - Acceptance criteria:
    - <criterion>
  - Rubric (before → target):
    - Scan speed: X → Y
    - Information hierarchy: X → Y
    - Interaction predictability: X → Y
    - Density/readability: X → Y
    - Navigation/pivots: X → Y
  - Guardrails:
    - default Salary Book prohibition (or explicit Tankathon exception)

After writing tasks:
- git add -A && git commit -m "${GENERATE_COMMIT_TITLE}"
  `;
}

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
        logGuardFailure("supervisor", errors);
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
    const errors = evaluateGuards(state);
    if (errors.length > 0) {
      logGuardFailure("loop", errors);
      return halt("Design guardrails failed. Resolve violations before continuing the loop.");
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
