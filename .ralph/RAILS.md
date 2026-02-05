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

- [x] Team section parity: Team Header KPIs + Totals Footer
  - **Do not recompute** totals in Ruby — prefer `pcms.team_salary_warehouse`.
  - Bulk fetch `pcms.team_salary_warehouse` for all teams across the displayed years, grouped by `team_code`.
  - Update `TeamHeader` inside each `#teamsection-<TEAM>` sticky header to match spec:
    - logo (NBA CDN if possible) + team name + conference label
    - KPI cards: room under tax, apron 1, apron 2, roster count
  - Add a Totals Footer at the bottom of each team section:
    - total salary by year
    - cap space by year
    - tax/apron status badges (and luxury tax row later if available)
  - **Important:** `GET /tools/salary-book/teams/:teamcode/section` should render the *full* team section (players + subsections + totals). Right now it only reloads players.

- [x] Expand team sidebar context (`#rightpanel-base`) to match spec
  - KPI cards: room under tax, first apron, second apron, roster count
  - Add lightweight tabs (Cap Outlook / Team Stats) - Team Stats can be placeholder
  - Keep base panel patchable by stable ID (`#rightpanel-base`)

- [ ] Expand Player overlay (`#rightpanel-overlay`) to match spec
  - Contract breakdown by year, guarantee structure, options, trade kicker info
  - Back already behaves correctly (returns to current viewport team)

- [ ] Add Agent overlay endpoint (v1 scaffold + wire click)
  - `GET /tools/salary-book/sidebar/agent/:id` → patches `#rightpanel-overlay`
  - Wire agent name clicks (currently placeholder behavior)

- [ ] Add Pick overlay endpoint (v1 scaffold + wire click)
  - `GET /tools/salary-book/sidebar/pick?...` → patches `#rightpanel-overlay`
  - Wire draft pick pills in the table (replace `console.log` placeholder)

- [ ] Add remaining Filter Toggles (Financials + Contracts) to match spec (client-only lenses)
  - Financials: Tax/Aprons (default ON), Cash vs Cap (OFF), Luxury Tax (OFF)
  - Contracts: Options (ON), Incentives (ON), Two-Way (ON)
  - Use flatcase signals (e.g. `displaytaxaprons`, `displayoptions`, `displaytwoway`)

---

## Later (after parity)

- [ ] Add team entity pages (`/teams/:slug`) and link from Salary Book headers
- [ ] Add agent entity pages and link from overlays
- [ ] Fragment caching for team sections keyed by `warehouse.refreshed_at`
- [ ] SSE - only if streaming/progress adds real product value
- [ ] Remove/guard debug-only panels (signals + SSE demo) before shipping

---

## Done

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
- [x] Player rows are real links enhanced to patch overlay
- [x] Render team sub-sections in the main canvas (toggle-controlled)
  - Cap Holds (`pcms.cap_holds_warehouse`)
  - Exceptions (`pcms.exceptions_warehouse`)
  - Dead Money (`pcms.dead_money_warehouse`)
  - Draft Assets row + pick pills (`pcms.draft_pick_summary_assets`)
  - Bulk fetch per warehouse to avoid N+1
