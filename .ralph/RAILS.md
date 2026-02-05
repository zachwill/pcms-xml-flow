# Rails + Datastar Salary Book — Backlog

Goal: port the Bun + React prototype (`prototypes/salary-book-react/`) to Rails + Datastar (`web/`).

Tool URL: `/tools/salary-book`

---

## Context for the coding agent

**Mindset**: Internal tool for ~50 users. Ship fast, refactor later.

**Reference docs** (read before coding):
- `web/AGENTS.md` — Rails app conventions
- `web/specs/01-salary-book.md` — interaction + layout spec
- `reference/datastar/` — Datastar conventions (start with `AGENTS.md`)
- `prototypes/salary-book-react/` — markup/UX reference

**Datastar conventions**:
- Signals are flatcase: `activeteam`, `overlaytype`, `displaycapholds`
- DOM refs are underscore-prefixed: `data-ref="_dialog"`
- Patch stable regions by ID: `#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#teamsection-<TEAM>`
- Response types: `text/html` (default), `application/json` (signal-only), `text/event-stream` (SSE)

**Hard rules**:
- Do NOT re-implement cap/trade/CBA math in Ruby — use `pcms.*` warehouses + `fn_*`
- Keep tool endpoints under `/tools/salary-book/*`
- Custom JS only when Datastar + CSS can't do it

---

## Backlog

- [ ] Relax CSP for Tailwind CDN + Datastar
    - Edit `web/config/initializers/content_security_policy.rb`
    - Allow `unsafe-inline` for scripts/styles, or disable CSP entirely
    - This is an internal tool — don't overthink it

- [ ] Port the real Salary Book table layout
    - Replace the toy per-team table with the full layout from the prototype
    - Years 2025–2030 as columns, sticky left name column, dense rows
    - Double-row PlayerRow: primary row (name, salaries) + metadata row (position, age, badges)
    - Both rows highlight on hover as a single unit
    - See `prototypes/salary-book-react/src/features/SalaryBook/` for markup reference
    - See `web/specs/01-salary-book.md` section 2.4 for the double-row spec

- [ ] Implement iOS Contacts sticky headers (CSS)
    - Team header + table header stick together as one unit
    - Next team's header pushes the previous one off
    - This is pure CSS (`position: sticky` with proper `top` values)
    - See prototype's sticky header implementation

- [ ] Port the Team Selector Grid to the command bar
    - East/West conference blocks, teams in a grid
    - Active team highlighted (driven by `$activeteam` signal)
    - Click scrolls to that team section
    - See `prototypes/salary-book-react/src/features/SalaryBook/commandbar/`

- [ ] Implement scroll spy
    - Detect which team section is in the sticky position
    - Update `$activeteam` signal
    - This is the one place we likely need custom JS
    - Emit a CustomEvent, let Datastar handle the signal update
    - See `prototypes/salary-book-react/src/features/SalaryBook/shell/useScrollSpy.ts`

- [ ] Wire scroll spy to sidebar updates
    - When `$activeteam` changes, fetch new team context for `#rightpanel-base`
    - Use `data-on:activeteam__changed` or similar Datastar pattern
    - Endpoint: `GET /tools/salary-book/sidebar/team?team=<CODE>`

- [ ] Implement filter toggles as client-only lenses
    - Cap Holds, Exceptions, Draft Picks, Dead Money toggles
    - Use signals + `data-show` to hide/show sections
    - Do NOT round-trip to server — this avoids scroll-jump issues
    - See `web/specs/01-salary-book.md` section 1.2 for filter groups

- [ ] Expand team sidebar context (`#rightpanel-base`)
    - Cap outlook KPIs: room under tax, first apron, second apron
    - Salary projections (5-year horizon)
    - Roster count, two-way capacity
    - See `web/specs/01-salary-book.md` section 4.1

- [ ] Add Player overlay endpoint
    - `GET /tools/salary-book/sidebar/player/:id` → patches `#rightpanel-overlay`
    - Contract breakdown by year, guarantee structure, options, trade kicker info
    - Back button returns to team context (current viewport team, not origin)
    - Already partially exists — expand to match spec

- [ ] Add Agent overlay endpoint
    - `GET /tools/salary-book/sidebar/agent/:id` → patches `#rightpanel-overlay`
    - Agency info, client list grouped by team with salary totals
    - Link from agent names in player rows

- [ ] Add Pick overlay endpoint
    - `GET /tools/salary-book/sidebar/pick?...` → patches `#rightpanel-overlay`
    - Pick metadata, protections, origin/destination teams
    - Link from draft pick pills in the table

---

## Later (after parity)

- [ ] Add team entity pages (`/teams/:slug`) and link from Salary Book headers
- [ ] Add agent entity pages and link from overlays
- [ ] Fragment caching for team sections keyed by `warehouse.refreshed_at`
- [ ] SSE — only if streaming/progress adds real product value

---

## Done

- [x] Tailwind CDN + config in layout
- [x] CSS variables + design tokens in `application.css`
- [x] Tool route: `GET /tools/salary-book`
- [x] Fragment endpoints exist (team section, team sidebar, player overlay)
- [x] Basic scroll spy → `$activeteam` → sidebar patch loop
- [x] Player rows are real links enhanced to patch overlay
