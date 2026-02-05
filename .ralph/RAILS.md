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

- [x] Port the Team Selector Grid to the command bar
  - Two blocks: Eastern / Western
  - Teams in a grid (match prototype: 3 rows × 5 teams per conference)
  - Active team highlighted (driven by `$activeteam` signal)
  - Click scrolls `#maincanvas` to `#teamsection-<CODE>` (prefer smooth)
  - Data source: `pcms.teams` has `conference_name` (see `migrations/009_nba_team_metadata.sql`)

- [ ] Upgrade scroll spy (v1)
  - Keep custom JS tiny (this is still the only “real” JS need)
  - Continue emitting a `salarybook-activeteam` CustomEvent → Datastar updates `$activeteam`
  - Make “active team” align with the sticky header threshold (top of `#maincanvas`)
  - Add a small programmatic-scroll lock so clicking a team doesn’t flicker
  - (Optional later) expose `sectionprogress` + `scrollstate` as signals for animations

- [ ] Add Filter Toggles UI (client-only lenses; no server round-trips)
  - Signals (flatcase): `displaycapholds`, `displayexceptions`, `displaydraftpicks`, `displaydeadmoney`
  - Defaults per spec: Cap Holds OFF, Exceptions ON, Draft Picks ON, Dead Money OFF
  - Use `data-bind` on inputs + `data-show` / `data-class` to hide/show sections

- [ ] Render team sub-sections in the main canvas (toggle-controlled)
  - Cap Holds (`pcms.cap_holds_warehouse`)
  - Exceptions (`pcms.exceptions_warehouse`)
  - Dead Money (`pcms.dead_money_warehouse`)
  - Draft Assets row (start with `pcms.draft_assets_warehouse`; fall back to `pcms.draft_pick_summary_assets` if needed)

- [ ] Add per-team Totals Footer
  - Total salary by year
  - Cap space / room under thresholds (as available)
  - Prefer `pcms.team_salary_warehouse` (don’t recompute in Ruby)

- [ ] Expand team sidebar context (`#rightpanel-base`) to match spec
  - KPI cards: room under tax, first apron, second apron, roster count
  - Add lightweight tabs (Cap Outlook / Team Stats) — Team Stats can be placeholder

- [ ] Expand Player overlay (`#rightpanel-overlay`) to match spec
  - Contract breakdown by year, guarantee structure, options, trade kicker info
  - Back already behaves correctly (returns to current viewport team)

- [ ] Add Agent overlay endpoint
  - `GET /tools/salary-book/sidebar/agent/:id` → patches `#rightpanel-overlay`
  - Wire agent name clicks (currently placeholder behavior)

- [ ] Add Pick overlay endpoint
  - `GET /tools/salary-book/sidebar/pick?...` → patches `#rightpanel-overlay`
  - Wire draft pick pills in the table

---

## Later (after parity)

- [ ] Add team entity pages (`/teams/:slug`) and link from Salary Book headers
- [ ] Add agent entity pages and link from overlays
- [ ] Fragment caching for team sections keyed by `warehouse.refreshed_at`
- [ ] SSE — only if streaming/progress adds real product value
- [ ] Remove/guard debug-only panels (signals + SSE demo) before shipping

---

## Done

- [x] Tailwind CDN + config in layout
- [x] Relax CSP for Tailwind CDN + Datastar
- [x] CSS variables + design tokens in `application.css`
- [x] Tool route: `GET /tools/salary-book`
- [x] Port the real Salary Book table layout (double-row players, years 2025–2030)
- [x] Implement iOS Contacts sticky headers (CSS)
- [x] Fragment endpoints exist (team section, team sidebar, player overlay)
- [x] Basic scroll spy → `$activeteam` → sidebar patch loop
- [x] Player rows are real links enhanced to patch overlay
