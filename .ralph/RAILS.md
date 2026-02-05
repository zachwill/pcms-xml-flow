# Rails + Datastar Salary Book - Backlog

Goal: port the Bun + React prototype (`prototypes/salary-book-react/`) to Rails + Datastar (`web/`).

Tool URL: `/tools/salary-book`

---

## Context for the coding agent

**Mindset**: Internal tool for ~50 users. Ship fast, refactor later.

**Reference docs** (read before coding):
- `web/AGENTS.md` - Rails app conventions
- `web/specs/01-salary-book.md` - interaction + layout spec
- `reference/datastar/` - Datastar conventions (start with `AGENTS.md`)
- `prototypes/salary-book-react/` - markup/UX reference

**Datastar conventions**:
- Signals are flatcase: `activeteam`, `overlaytype`, `displaycapholds`
- DOM refs are underscore-prefixed: `data-ref="_dialog"`
- Patch stable regions by ID: `#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#teamsection-<TEAM>`
- Response types: `text/html` (default), `application/json` (signal-only), `text/event-stream` (SSE)

**Hard rules**:
- Do NOT re-implement cap/trade/CBA math in Ruby - use `pcms.*` warehouses + `fn_*`
- Keep tool endpoints under `/tools/salary-book/*`
- Custom JS only when Datastar + CSS can't do it

---

## Backlog

- [ ] Filter Toggles parity (Financials + Contracts) (client-only lenses)
  - Add new flatcase signals + UI checkboxes:
    - Financials: `displaytaxaprons` (default **true**), `displaycashvscap` (false), `displayluxurytax` (false)
    - Contracts: `displayoptions` (true), `displayincentives` (true), `displaytwoway` (true)
  - Preserve context on change (call `window.__salaryBookPreserveContext?.()` like the Display group)
  - Wire v1 behavior (no server calls):
    - `displaytaxaprons`: hide/show Tax Status row in totals footer + tax/apron KPI rows/cards where they exist
    - `displaytwoway`: hide/show two-way players in the main table (client-side)
    - `displayoptions` / `displayincentives`: start by gating badges/tooltips (avoid per-cell `data-class` unless needed)

---

## Later (after parity)

NOTE: BrickLink-style **entity pages** now have their own backlog + agent:
- Backlog: `.ralph/ENTITIES.md`
- Agent loop: `bun agents/entities.ts`

- [ ] Fragment caching for team sections keyed by `warehouse.refreshed_at`
- [ ] SSE - only if streaming/progress adds real product value
- [ ] Remove/guard debug-only panels (signals + SSE demo) before shipping

---

## Done

- [x] Add Pick overlay endpoint (v1 scaffold + wire click)
  - Route: `GET /tools/salary-book/sidebar/pick?team=:code&year=:year&round=:round` → patches `#rightpanel-overlay`
  - New partial: `_sidebar_pick.html.erb` (pick identity badge, status badges, provenance, PCMS description, protections)
  - Wired pick pill clicks in `_draft_assets_section.html.erb`

- [x] Add Agent overlay endpoint (v1 scaffold + wire click)
  - Route: `GET /tools/salary-book/sidebar/agent/:id` → patches `#rightpanel-overlay`
  - New partial: `_sidebar_agent.html.erb` (agent header + client roster)
  - Wired agent clicks in `_player_row.html.erb` and `_sidebar_player.html.erb`

- [x] Unify displayed year horizon across table + sub-sections + totals footer
  - Canonical horizon is now **2025-2030** everywhere (table, sub-sections, totals footer).
  - Removed the old subsection-year split; all views use `SALARY_YEARS`.
  - Updated controller SQL pivots (cap_holds, exceptions, dead_money) to include 2030.

- [x] Team section parity: Team Header KPIs + Totals Footer
  - Bulk fetch `pcms.team_salary_warehouse` across the displayed years (don't recompute totals in Ruby).
  - `GET /tools/salary-book/teams/:teamcode/section` renders the full team section (header + players + sub-sections + totals footer).

- [x] Expand team sidebar context (`#rightpanel-base`) to match spec
  - KPI cards + lightweight tabs (Cap Outlook / Team Stats placeholder)
  - Base panel patchable by stable ID (`#rightpanel-base`)

- [x] Expand Player overlay (`#rightpanel-overlay`) to match spec
  - Contract breakdown by year, guarantee structure, options, trade kicker / restrictions
  - Back behaves correctly (returns to current viewport team)

- [x] Tailwind CDN + config in layout
- [x] Relax CSP for Tailwind CDN + Datastar
- [x] CSS variables + design tokens in `application.css`
- [x] Tool route: `GET /tools/salary-book`
- [x] Port the real Salary Book table layout (double-row players, years 2025-2030)
- [x] Implement iOS Contacts sticky headers (CSS)
- [x] Fragment endpoints exist (team section, team sidebar, player overlay)
- [x] Scroll spy (v1) → `salarybook-activeteam` CustomEvent → Datastar updates `$activeteam` → sidebar patch loop
- [x] Port the Team Selector Grid to the command bar
- [x] Add Filter Toggles UI (Display group; client-only lenses)
- [x] Filter toggle UX: preserve context after layout changes
  - When toggles hide/show sections, rebuild scroll-spy cache and snap back to current `$activeteam` so the user doesn't "jump teams".
  - Exposed `window.__salaryBookRebuildCache()` and `window.__salaryBookPreserveContext()` from scroll-spy script
  - Filter checkboxes call `__salaryBookPreserveContext()` on change
- [x] Player rows patch overlay on click + keyboard
- [x] Render team sub-sections in the main canvas (toggle-controlled)
  - Cap Holds (`pcms.cap_holds_warehouse`)
  - Exceptions (`pcms.exceptions_warehouse`)
  - Dead Money (`pcms.dead_money_warehouse`)
  - Draft Assets row + pick pills (`pcms.draft_pick_summary_assets`)
  - Bulk fetch per warehouse to avoid N+1
