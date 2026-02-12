#!/usr/bin/env bun
import { loop, work, generate, supervisor } from "./core";

/**
 * design-audit.ts — Design consistency agent
 *
 * Propagates Salary Book's polish level to every other page in web/.
 *
 * The idea: Salary Book has had 100+ commits of iterative refinement —
 * hover treatments, dark mode, nil handling, conditional badges, sticky
 * column shadows, font-mono on numbers, etc. The other tools and entity
 * pages haven't had that attention. This agent reads the Salary Book as
 * the gold standard and systematically audits + fixes discrepancies in
 * every other view.
 *
 * Two-phase loop:
 *   1. If .ralph/DESIGN_AUDIT.md has unchecked todos → fix the next one.
 *   2. If no todos remain → audit all non-Salary-Book views and generate
 *      a new checklist of specific discrepancies.
 *
 * Usage:
 *   bun agents/design-audit.ts
 *   bun agents/design-audit.ts --once
 *   bun agents/design-audit.ts --dry-run
 *   bun agents/design-audit.ts -c "focus on entities/trades"
 */

const TASK_FILE = ".ralph/DESIGN_AUDIT.md";

const EXEMPLAR_FILES = [
  "web/app/views/tools/salary_book/_player_row.html.erb",
  "web/app/views/tools/salary_book/_team_section.html.erb",
  "web/app/views/tools/salary_book/_sidebar_player.html.erb",
  "web/app/views/tools/salary_book/_sidebar_agent.html.erb",
  "web/app/views/tools/salary_book/_sidebar_pick.html.erb",
  "web/app/views/tools/salary_book/_table_header.html.erb",
  "web/app/views/tools/salary_book/_kpi_cell.html.erb",
  "web/app/views/tools/salary_book/_totals_footer.html.erb",
  "web/app/views/tools/salary_book/_cap_holds_section.html.erb",
  "web/app/views/tools/salary_book/_dead_money_section.html.erb",
  "web/app/views/tools/salary_book/_draft_assets_section.html.erb",
  "web/app/views/tools/salary_book/show.html.erb",
];

const AUDIT_TARGETS = [
  "web/app/views/tools/two_way_utility/",
  "web/app/views/tools/team_summary/",
  "web/app/views/tools/system_values/",
  "web/app/views/entities/trades/",
  "web/app/views/entities/transactions/",
  "web/app/views/entities/drafts/",
  "web/app/views/entities/players/",
  "web/app/views/entities/teams/",
  "web/app/views/entities/agents/",
  "web/app/views/entities/agencies/",
  "web/app/views/entities/draft_picks/",
  "web/app/views/entities/draft_selections/",
];

const DESIGN_REFS = [
  "web/docs/design_guide.md",
  "web/AGENTS.md",
];

const CHECKLIST = `
DESIGN CONSISTENCY CHECKLIST — check every item for every file:

1. ROW HOVER: rows use \`hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10\`
   (or \`dark:hover:bg-yellow-900/25\` for dense tool surfaces).
   Sticky-left columns carry matching \`group-hover:\` background.
   Transition: \`transition-colors duration-75\`.

2. NUMBERS: all numeric/financial values use \`font-mono tabular-nums\`.
   Currency uses a format helper (\`format_salary\`, \`format_compact_currency\`).
   Right-aligned in table cells.

3. NIL/EMPTY STATES: nil values render as \`—\` (em dash), never blank, never "N/A",
   never raw nil. The dash uses \`text-muted-foreground/50\` styling.

4. IDENTITY CELLS: player/team/agent identity columns use the double-row grid
   pattern (24px primary + 16px secondary) where space allows.
   Primary: \`text-[14px] font-medium\`. Secondary: \`text-[10px] text-muted-foreground/80\`.

5. DARK MODE: every custom color class has a \`dark:\` variant.
   Backgrounds, text colors, borders, badges — all need counterparts.
   Check: red, green, blue, amber, orange, yellow, purple tints.

6. TEXT SIZES: primary row text \`text-[14px]\`, secondary/meta \`text-[10px]\`,
   table headers \`text-[10px] uppercase tracking-wide font-medium\`.
   Header backgrounds: \`bg-muted/40\`.

7. CONDITIONAL BADGES: edge-case states should be visually surfaced
   (two-way, trade restricted, poison pill, no-trade, option year, etc.)
   using appropriate color-coded chips/badges — not hidden or ignored.

8. STICKY COLUMNS: shadow treatment uses the Salary Book pattern:
   \`before:absolute before:right-0 before:top-0 before:bottom-0 before:w-[6px]
    before:bg-gradient-to-r before:from-[rgba(0,0,0,0.08)] before:to-transparent\`
   Plus \`after:...\` for the 1px border.

9. CHIP CLASSES: use \`entity-chip entity-chip--{muted|warning|danger|success|accent}\`
   tokens, not bespoke per-page badge classes.

10. TABLE HEADERS: use \`bg-muted/40 text-[10px] uppercase tracking-wide
    text-muted-foreground/90\`. Inner/nested table headers should at minimum
    use \`text-muted-foreground\` — not bare unstyled \`<th>\`.

11. HOVER-TO-PRIMARY: interactive identity links should transition to
    \`text-primary\` or \`hover:text-foreground\` on row hover, matching
    Salary Book's \`group-hover:text-primary\` pattern.

12. LINK AFFORDANCES: clickable entity names use \`hover:underline\`.
    Agent/agency names in secondary positions use
    \`text-muted-foreground hover:text-foreground hover:underline\`.

13. IMAGE FALLBACKS: headshot/logo images have \`onerror\` fallback handlers
    matching the Salary Book pattern. Use \`loading="lazy" decoding="async"\`.
`.trim();

loop({
  name: "design-audit",
  taskFile: TASK_FILE,
  timeout: "15m",
  pushEvery: 4,
  maxIterations: 200,
  continuous: true,

  supervisor: supervisor(
    `
You are the supervisor for the design consistency audit loop.

Your job: ensure the worker is making real, correct improvements — not
introducing regressions, not making cosmetic-only changes that break
functionality, and not drifting from the Salary Book reference patterns.

REVIEW INPUTS:
1) ${TASK_FILE} — current audit findings + fix checklist
2) Recent git diff (run: git log --oneline -8 && git diff HEAD~4 -- web/)
3) ${DESIGN_REFS.join("\n3) ")}

SUPERVISOR CHECKLIST:
- Are fixes actually matching Salary Book patterns (not inventing new ones)?
- Are dark mode variants present for every color change?
- Are fixes surgical (not rewriting entire files unnecessarily)?
- Are completed items genuinely complete?
- Is the worker touching the right files (not modifying Salary Book itself)?
- Do tables still render correctly (no broken ERB, no unclosed tags)?
- Are hover transitions consistent (\`duration-75\`, not mixed values)?
- Has the worker avoided adding client-side JS where server HTML suffices?

IF ISSUES FOUND:
- Revert problematic changes if needed
- Add corrective tasks to ${TASK_FILE}
- Clarify the pattern the worker should follow

AFTER REVIEW:
- Update ${TASK_FILE} if needed
- git add -A && git commit -m "design: supervisor review"
    `,
    {
      every: 6,
      provider: "github-copilot",
      model: "claude-opus-4.6",
      thinking: "high",
      timeout: "15m",
    },
  ),

  run(state) {
    if (state.hasTodos) {
      return work(
        `
You are fixing a design consistency issue to match Salary Book's polish level.

CURRENT TASK:
${state.nextTodo}

BEFORE EDITING, read these exemplar files to understand the target pattern:
${EXEMPLAR_FILES.map((f) => `- ${f}`).join("\n")}

DESIGN CONTRACT:
${DESIGN_REFS.map((f) => `- ${f}`).join("\n")}

RULES:
1. Read the specific target file(s) mentioned in the task FIRST.
2. Read the relevant Salary Book exemplar that demonstrates the correct pattern.
3. Make the MINIMAL edit to fix the specific issue. Do not refactor unrelated code.
4. Ensure dark mode variants are present for any color you add/change.
5. Do NOT modify any file under web/app/views/tools/salary_book/ — that's the reference.
6. Do NOT add client-side JavaScript unless the task explicitly requires it.
7. Do NOT change data queries or controller logic — this is presentation-layer only.
8. Test your ERB mentally: ensure no unclosed tags, no syntax errors.

AFTER FIXING:
1. Check off the completed item in ${TASK_FILE}.
2. If the fix reveals adjacent issues in the same file, append them as new
   unchecked tasks in ${TASK_FILE} (be specific: file, line range, what's wrong).
3. Commit:
   git add -A && git commit -m "design: <short description of what you fixed>"
        `,
        {
          provider: "github-copilot",
          model: "claude-opus-4.6",
          thinking: "high",
          timeout: "12m",
        },
      );
    }

    const contextBlock = state.context
      ? `\nFOCUS AREA (from --context flag): ${state.context}\n`
      : "";

    return generate(
      `
${TASK_FILE} has no unchecked tasks. Run a fresh design consistency audit.
${contextBlock}

STEP 1: Read the Salary Book exemplar files completely. These are the gold standard:
${EXEMPLAR_FILES.map((f) => `- ${f}`).join("\n")}

STEP 2: Read the design contract:
${DESIGN_REFS.map((f) => `- ${f}`).join("\n")}

STEP 3: Audit EVERY .html.erb file in these directories:
${AUDIT_TARGETS.map((d) => `- ${d}`).join("\n")}

For each file, check EVERY item in this checklist:

${CHECKLIST}

STEP 4: Write findings to ${TASK_FILE}.

TASK FORMAT REQUIREMENTS:
- Group findings by file path.
- Each task is a checkbox with the EXACT file path, line number(s), and specific violation.
- Include what the current code does AND what it should do instead.
- Prioritize: missing dark mode > missing hover > missing font-mono > header styling > everything else.

GOOD task example:
  - [ ] \`web/app/views/entities/trades/show.html.erb\` L145: trade-group inner \`<tr>\` rows have no hover treatment; add \`hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10 transition-colors duration-75\`

BAD task example:
  - [ ] Fix hover on trades page

After writing tasks:
- Preserve any existing context/notes at the top of ${TASK_FILE}
- git add -A && git commit -m "design: generate audit findings"
      `,
      {
        provider: "github-copilot",
        model: "claude-opus-4.6",
        thinking: "high",
        timeout: "15m",
      },
    );
  },
});
