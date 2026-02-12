#!/usr/bin/env bun
import { loop, work, generate, supervisor } from "./core";

/**
 * design.ts — Design evolution loop (NOT hygiene sweeps)
 *
 * Goal:
 * - Raise the UX/design quality of non-Salary-Book surfaces in web/
 * - Work at the user-flow level (hierarchy, navigation, scan speed, interaction clarity)
 * - Keep Salary Book untouched as the golden reference
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
- Salary Book remains read-only and is used as the quality bar for interaction grammar.
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

loop({
  name: "design",
  taskFile: TASK_FILE,
  timeout: "15m",
  pushEvery: 4,
  maxIterations: 240,
  continuous: true,

  supervisor: supervisor(
    `
You are supervising the design-evolution loop.

PRIMARY OBJECTIVE:
Ensure the worker is making meaningful UX/design improvements (flow-level),
not cosmetic lint sweeps.

STRATEGIC INTENT:
${NORTH_STAR}

HARD GUARDRAIL:
Salary Book is read-only reference quality. Do not modify any Salary Book files.
Forbidden edits include (non-exhaustive):
- web/app/views/tools/salary_book/**
- web/app/controllers/tools/salary_book_controller.rb
- web/app/controllers/tools/salary_book_sse_controller.rb
- web/app/helpers/salary_book_helper.rb
- web/test/integration/salary_book*

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
- Did they avoid touching Salary Book files?
- Did ${TASK_FILE} get updated with before/after rubric scoring evidence?

IF DRIFT IS DETECTED:
- Revert low-value cosmetic churn
- Add corrective TODOs emphasizing flow-level outcomes
- Tighten task wording in ${TASK_FILE}

AFTER REVIEW:
- Update ${TASK_FILE} if needed
- git add -A && git commit -m "design: supervisor review"
    `,
    {
      every: 6,
      provider: "openai-codex",
      model: "gpt-5.3-codex",
      thinking: "high",
      timeout: "15m",
    },
  ),

  run(state) {
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

TARGETS (non-Salary-Book only):
${NON_SALARY_TARGETS.map((t) => `- ${t}`).join("\n")}

HARD RULES:
1) Do NOT edit Salary Book files or Salary Book controllers/helpers/tests.
2) Focus on one surface and one user flow for this task.
3) Respect strategic priority: entity index convergence first, while continuing steady tool evolution.
4) Prioritize hierarchy/interaction/wayfinding over cosmetic class parity.
5) You may edit views/controllers/helpers/minimal JS/tests when required.
6) Keep business/CBA math in SQL (do not reimplement in Ruby/JS).
7) Keep changes coherent and shippable (avoid sprawling refactors).

ANTI-PATTERNS (avoid):
- Repo-wide grep/replace for style-only classes
- “Add font-mono/dark variant everywhere” chores with no flow outcome
- Blindly porting Salary Book mechanics where the surface has different goals

REQUIRED TASK COMPLETION STEPS:
1) Implement the flow-level improvement.
2) Run focused verification (tests or targeted checks).
3) Update the task block in ${TASK_FILE} with:
   - What changed (files)
   - Why this improves the flow
   - Before → after rubric scores (all 5 dimensions)
   - Any follow-up tasks discovered
4) Check off the task in ${TASK_FILE}.
5) Commit:
   git add -A && git commit -m "design: <surface> <flow improvement>"
        `,
        {
          provider: "openai-codex",
          model: "gpt-5.3-codex",
          thinking: "high",
          timeout: "12m",
        },
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

Rubric to use:
${RUBRIC}

BACKLOG RULES:
1) Tasks must be user-flow based, not class-audit based.
2) Each task must target exactly one surface + one primary flow.
3) Include concrete files likely to change.
4) Include acceptance criteria that can be verified.
5) Include before/target rubric scores.
6) Explicitly forbid Salary Book edits in each task block.
7) Prioritize highest-leverage UX wins first.
8) Prioritization order:
   - P1: Entity index convergence to explorer-workbench behavior
   - P2: Tool evolution (Team Summary, System Values, Two-Way Utility)
   - P3: Lower-leverage polish/supporting tasks
9) Do not starve tool evolution: top 10 tasks should include at least 3 tool tasks.

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
    - Do not modify Salary Book files.

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
- git add -A && git commit -m "design: generate evolution backlog"
      `,
      {
        provider: "openai-codex",
        model: "gpt-5.3-codex",
        thinking: "high",
        timeout: "15m",
      },
    );
  },
});
