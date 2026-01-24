#!/usr/bin/env bun
import { loop, work, generate, supervisor } from "./core";

/**
 * Salary Book Agent
 *
 * Builds the NBA Salary Book feature from specs/01-salary-book.md.
 * This is a complex, scroll-driven interface demonstrating how Base UI
 * components can map to sophisticated, in-depth specifications.
 *
 * Usage:
 *   bun agents/salary-book.ts
 *   bun agents/salary-book.ts --once
 *   bun agents/salary-book.ts --dry-run
 */

loop({
  name: "salary-book",
  taskFile: ".ralph/SALARY_BOOK.md",
  timeout: "8m",
  pushEvery: 4,
  maxIterations: 100,
  continuous: false,

  supervisor: supervisor(
    `
    You are the supervisor for the Salary Book feature build.

    Every 4 commits, review progress and adjust the backlog.

    CONTEXT:
    1. Read web/specs/01-salary-book.md — the full specification
    2. Read .ralph/SALARY_BOOK.md — current task backlog
    3. Check web/src/features/SalaryBook/ — what's been built

    REVIEW CHECKLIST:

    **Structure**
    - Is the barrel pattern being followed? (index.ts exports at each level)
    - Are components properly organized? (TopCommandBar/, MainCanvas/, Sidebar/)
    - Are API routes correctly fetching from pcms schema?
    - Is data typing consistent between API responses and frontend types?

    **Scroll-Spy System**
    - Does useScrollSpy correctly detect active team from sticky header position?
    - Does the Team Selector Grid highlight update during scroll?
    - Is there flicker during scroll? (bad)

    **Sticky Headers**
    - Do team headers + table headers stick as ONE unit?
    - Does the next team header push the previous one off (iOS Contacts style)?
    - Are backgrounds opaque? (no content visible through headers)

    **Double-Row Players**
    - Do both rows highlight as one unit on hover?
    - Is the metadata row lower contrast?
    - Do agent/agency clicks work (stop propagation)?

    **Sidebar State Machine**
    - Default mode: shows active team from scroll-spy
    - Entity mode: pushed detail views with Back button
    - Does Back return to CURRENT viewport team, not origin?

    **Visual Polish**
    - Does it look like a professional front-office tool?
    - Are monospace fonts used for salary figures?
    - Are colors/badges consistent with our design system?

    ACTIONS:
    - Add tasks if backlog is thin
    - Reorder if dependencies are wrong
    - Add polish tasks if interactions feel off
    - Add fix tasks if bugs are spotted

    If you make changes:
    - git add -A && git commit -m "salary-book: supervisor review"
    `,
    {
      every: 4,
      model: "claude-opus-4-5-thinking",
      thinking: "medium",
    }
  ),

  run(state) {
    if (state.hasTodos) {
      return work(
        `
        You are building the NBA Salary Book feature.

        Your task: ${state.nextTodo}

        REQUIRED READING (before any code):
        1. web/specs/01-salary-book.md — The full specification
        2. web/docs/bun-postgres.md — How to use Bun's SQL client
        3. web/src/components/ui/index.ts — Available UI primitives
        4. web/src/lib/utils.ts — Utilities (cx, focusRing, formatters)

        DATA SOURCE — PostgreSQL (pcms schema):
        - pcms.salary_book_warehouse: player salaries (cap_2025..cap_2030, option_*, agent_name, is_two_way, etc.)
        - pcms.team_salary_warehouse: team totals, cap space, tax status (cap_total, tax_total, room_under_tax, etc.)
        - pcms.draft_pick_summaries: draft picks (first_round, second_round text per year)
        - pcms.agents / pcms.agencies: agent/agency details

        Use Bun.sql or SQL from "bun" to query. Environment has $POSTGRES_URL.
        Create API routes in web/src/api/routes/salary-book.ts, then fetch from React components.

        IMPORTANT: All code lives in the web/ directory. Paths like src/features/SalaryBook/ mean web/src/features/SalaryBook/.

        ARCHITECTURE — Follow the barrel pattern (all paths relative to web/):

        web/src/features/SalaryBook/
          index.tsx                    # exports { SalaryBook }
          SalaryBook.tsx               # main orchestrator
          data/
            index.ts                   # exports all data + types
            teams.ts                   # NBA teams with metadata
            players.ts                 # player contracts (mock)
            picks.ts                   # draft picks (mock)
          hooks/
            index.ts                   # exports all hooks
            useScrollSpy.ts            # tracks active team
            useSidebarStack.ts         # entity navigation stack
          components/
            index.ts                   # exports all components
            TopCommandBar/
              index.ts
              TeamSelectorGrid.tsx     # 2 conferences, 3x5 grids each
              FilterToggles.tsx        # display/financial/contract filters
            MainCanvas/
              index.ts
              TeamSection.tsx          # wrapper for one team
              TeamHeader.tsx           # sticky header (team name + meta)
              SalaryTable.tsx          # the table with sticky columns
              PlayerRow.tsx            # double-row design
              DraftAssetsRow.tsx       # pick pills per year
              TotalsFooter.tsx         # salary totals
            Sidebar/
              index.ts
              SidebarPanel.tsx         # container with stack logic
              TeamContext.tsx          # default mode content
              PlayerDetail.tsx         # entity: player
              AgentDetail.tsx          # entity: agent
              PickDetail.tsx           # entity: pick

        CRITICAL BEHAVIORS (from spec):

        **Scroll-Spy**
        - Active team = team whose header is currently sticky
        - Update Team Selector Grid highlight smoothly (no flicker)
        - Sidebar default mode follows scroll-spy

        **Sticky Headers (iOS Contacts style)**
        - Team header + table header = ONE sticky group
        - Next team pushes previous off (smooth transition)
        - Opaque backgrounds, no content bleed-through
        - Use position: sticky with proper z-index layering

        **Double-Row Players**
        - Row A: name, salary figures (monospace), agent
        - Row B: position chip, experience, age, guarantee structure, options
        - Hover highlights BOTH rows as one unit
        - Click row → push Player to sidebar
        - Click agent name → push Agent (stopPropagation)

        **Sidebar State Machine**
        - Default: shows current team from scroll-spy
        - Entity: pushed detail view with Back button
        - Back → returns to CURRENT viewport team (not origin!)

        STYLING:
        - Use our design tokens (bg-background, text-foreground, border-border, etc.)
        - Use cx() for className merging
        - Use focusRing() for interactive elements
        - Monospace for salary figures: font-mono tabular-nums
        - Compact, dense, spreadsheet-like aesthetic

        EXECUTION:
        1. Read relevant existing files first
        2. Create/modify ONE component or hook per task
        3. Ensure TypeScript compiles (no errors)
        4. Check off ONLY your task in .ralph/SALARY_BOOK.md
        5. Add follow-up tasks if you discover gaps

        When done:
        - git add -A && git commit -m "salary-book: <short summary>"
        - Exit immediately
        `,
        { model: "gemini-3-flash", thinking: "medium" }
      );
    }

    // No todos — generate initial backlog or signal completion
    const contextBlock = state.context
      ? `\nFocus area: ${state.context}\n`
      : "";

    return generate(
      `
      .ralph/SALARY_BOOK.md has no unchecked tasks.
      ${contextBlock}

      Read web/specs/01-salary-book.md and generate the next batch of tasks.

      Check web/src/features/SalaryBook/ to see what exists.

      Generate concrete, ordered tasks following the build sequence:
      1. Foundation (data types, mock data, hooks)
      2. Layout skeleton (SalaryBook.tsx with 3-column layout)
      3. TopCommandBar (TeamSelectorGrid, FilterToggles)
      4. MainCanvas (TeamSection, sticky headers, PlayerRow)
      5. Sidebar (state machine, entity details)
      6. Integration (scroll-spy wiring, entity clicks)
      7. Polish (transitions, visual refinement)

      Task format:
      - [ ] Create src/features/SalaryBook/data/types.ts with Player, Team, Pick, Agent interfaces
      - [ ] Create useScrollSpy hook that tracks which team header is sticky
      - [ ] Build PlayerRow with double-row design (primary + metadata)

      After writing tasks:
      - git add -A && git commit -m "salary-book: generate backlog"
      `,
      { model: "claude-opus-4-5-thinking", thinking: "medium" }
    );
  },
});
