# web/TODO.md — Rails + Datastar build (active backlog)

This is the **active** backlog for the new Rails app in `web/`.

React prototype (reference only): `prototypes/salary-book-react/`

If you need deep context:
- `web/RAILS_TODO.md` (migration memo)
- `web/specs/00-ui-philosophy.md` + `web/specs/01-salary-book.md` (UX invariants)
- `web/FEATURE_AUDIT.md` (parity checklist)
- `reference/datastar/*` (Datastar conventions + Rails SSE)

---

## Phase 0 — Repo structure (done)

- [x] Move Bun + React prototype from `web/` → `prototypes/salary-book-react/`
- [x] Promote canonical Salary Book specs/docs back into `web/`
- [x] Write `web/AGENTS.md`

---

## Phase 1 — Rails scaffold (make it run)

Goal: a bootable Rails app that can render a Datastar-enabled page.

- [x] Decide Ruby + Rails versions (Ruby **3.4.8**, Rails **8.1.2**).
- [x] Scaffold Rails in-place (Rails app root is `web/`).
- [x] Make Rails accept repo convention `POSTGRES_URL` (wired in `config/database.yml`).
- [x] Keep Rails-owned tables isolated in the `web` schema (default via `RAILS_APP_SCHEMA`; see `config/database.yml`).
- [x] Add Datastar to the default layout (CDN script).
- [x] Fix CSP for Datastar expressions (`'unsafe-eval'`).
- [x] Boot proof: `/tools/salary-book` renders and Datastar loads.

---

## Phase 2 — Routing + slug registry (Bricklink-style navigation)

Goal: clean, top-level entity pages with canonical slugs.

- [x] Add slug table migration (supports aliases + one canonical slug per entity):
  - `entity_type` (player/team/agent/contract/…)
  - `entity_id` (initially NBA/PCMS shared id)
  - `slug` (unique per entity_type)
  - `canonical` boolean (one true per entity_id)
  - timestamps
- [x] Implement `/players/:slug` (canonical).
- [x] Implement `/players/:id` numeric fallback → 301 → canonical slug (creates default slug on-demand).
- [x] Add an admin-only rake task to promote short slugs (make alias canonical):
  - `bin/rails slugs:promote[player,2544,lebron]`

---

## Phase 3 — Tools skeleton: Salary Book layout

Goal: a working `/tools/salary-book` shell with stable patch boundaries.

- [x] Add `/tools/salary-book` route.
- [x] Render the 3-pane frame with stable IDs (minimum):
  - `#flash`
  - `#commandbar`
  - `#maincanvas`
  - `#rightpanel-base`
  - `#rightpanel-overlay`
- [ ] Port the CSS variables / dense styling primitives from the prototype.

---

## Phase 4 — The tiny JS runtime (non-React)

Goal: preserve the 3 irreducible client problems, but in plain JS.

- [ ] Implement scroll spy + progress (prototype reference: `prototypes/salary-book-react/src/features/SalaryBook/shell/useScrollSpy.ts`).
- [ ] Implement horizontal scroll sync for sticky header/body.
- [ ] Implement overlay transition manager (safe-to-unmount).
- [ ] JS → Datastar glue via bubbling `CustomEvent`:
  - event: `salarybook-activeteam` → detail `{ team: 'BOS' }`
  - Datastar listens and sets `$activeteam`, then patches sidebar base.

---

## Phase 5 — Data wiring (HTML-first)

Goal: render real data from Postgres warehouses with HTML patches.

- [ ] Team index source: `pcms.teams` (NBA, active).
- [ ] Render one team section server-side from:
  - `pcms.salary_book_warehouse`
  - `pcms.team_salary_warehouse`
  - `pcms.exceptions_warehouse`, `pcms.cap_holds_warehouse`, `pcms.dead_money_warehouse`, `pcms.draft_pick_summary_assets`
- [ ] Sidebar base endpoint (team context): `/tools/salary-book/sidebar/team?team=BOS` → patches `#rightpanel-base`.
- [ ] Overlay endpoints:
  - player: `/tools/salary-book/sidebar/player/:id`
  - agent: `/tools/salary-book/sidebar/agent/:id`
  - pick: `/tools/salary-book/sidebar/pick?...`

Filters:
- [ ] Implement as **client-only lenses first** (signals + `data-show`) to avoid scroll jumps.

---

## Phase 6 — Parity + performance

- [ ] Work through gaps listed in `web/FEATURE_AUDIT.md`.
- [ ] Add fragment caching for:
  - per-team sections
  - sidebar base modules
  - overlays (player/agent/pick)
- [ ] Key caches by warehouse `refreshed_at` timestamps (don’t invent app-level invalidation).

---

## Done criteria (v1)

- Salary Book tool works end-to-end:
  - scroll-driven active team
  - filter lenses
  - right panel base + entity overlay
  - URLs are canonical and shareable

- Entity navigation exists and feels Bricklink-like:
  - player/team/agent pages are link-rich
  - tools link to entities (and entities can link back to tools)
