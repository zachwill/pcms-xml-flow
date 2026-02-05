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

- [ ] Add Agent overlay endpoint (v1 scaffold + wire click)
  - Route: `GET /tools/salary-book/sidebar/agent/:id` → patches `#rightpanel-overlay`
  - Data source (mirror prototype route):
    - Agent: `pcms.agents` (agent_id, full_name, agency_name)
    - Clients: `pcms.salary_book_warehouse` rows where `agent_id = :id`
      - include `player_id`, `player_name`, `team_code`, `age`, `cap_2025..cap_2030`, `is_two_way`
      - optional: `LEFT JOIN pcms.people` for display names + `years_of_service`
  - View: new partial `_sidebar_agent.html.erb`
    - Must render a single stable root: `<div id="rightpanel-overlay">…</div>`
    - Back button should `@get('/tools/salary-book/sidebar/clear')`
    - Client rows should be clickable → `@get('/tools/salary-book/sidebar/player/:id')` (replaces overlay)
  - Wiring:
    - Replace the placeholder agent click in `tools/salary_book/_player_row.html.erb`
    - Wire the Agent button inside `tools/salary_book/_sidebar_player.html.erb`

- [ ] Add Pick overlay endpoint (v1 scaffold + wire click)
  - Route: `GET /tools/salary-book/sidebar/pick?team=:code&year=:year&round=:round` → patches `#rightpanel-overlay`
  - Data source (start simple; expand later):
    - `pcms.draft_pick_summary_assets` rows for (team_code, draft_year, draft_round)
    - optional v1+: join `pcms.teams` for names/logos, and `pcms.endnotes` for protections text when present
  - View: new partial `_sidebar_pick.html.erb`
    - Header (year/round + destination team)
    - Origin/destination + flags (swap/conditional) if available
    - Raw description (from summary assets) + basic protections section (if any)
  - Wiring:
    - Replace the `console.log` placeholder in `tools/salary_book/_draft_assets_section.html.erb`

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

- [ ] Add team entity pages (`/teams/:slug`) and link from Salary Book headers
- [ ] Add agent entity pages and link from overlays
- [ ] Fragment caching for team sections keyed by `warehouse.refreshed_at`
- [ ] SSE - only if streaming/progress adds real product value
- [ ] Remove/guard debug-only panels (signals + SSE demo) before shipping

---

## Done

- [x] Unify displayed year horizon across table + sub-sections + totals footer
  - Canonical horizon is now **2025–2030** everywhere (table, sub-sections, totals footer).
  - Removed the old subsection-year split; all views use `SALARY_YEARS`.
  - Updated controller SQL pivots (cap_holds, exceptions, dead_money) to include 2030.

- [x] Team section parity: Team Header KPIs + Totals Footer
  - Bulk fetch `pcms.team_salary_warehouse` across the displayed years (don’t recompute totals in Ruby).
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
