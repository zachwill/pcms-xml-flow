# web/AGENTS.md

> Notes for AI coding agents working in **web/**.
> This file is the fastest way to get oriented before making changes.

## What `web/` is

`web/` is a **Bun + React + TypeScript** app that consumes the repo's Postgres warehouses.

It exists to provide:

- A UI (currently: **Salary Book**) for browsing NBA PCMS-derived `pcms.*_warehouse` tables.
- A small Bun API layer under `/api/*` (currently: `/api/salary-book/*`) that queries Postgres (`pcms` schema).

This directory is intentionally isolated from the repo's Python code.

## Start here

| File | Purpose |
|------|---------|
| **`HANDOFF.md`** | Detailed handoff doc — what's done, what's next, architecture diagrams |
| **`TODO.md`** | Current work items with status |
| **`specs/00-ui-philosophy.md`** | Core invariants + scroll-driven model |
| **`specs/01-salary-book.md`** | Full interaction spec |
| **`RAILS_TODO.md`** | Migration memo: how to turn this React app into **Rails + Datastar** |

## Mental model (read this first)

### The product is Postgres

- Warehouses + SQL functions are the stable API.
- The web app should remain a thin consumer.
- Prefer implementing derived fields / rule logic in SQL migrations & refreshes.

### The UI is not documentation

Do **not** add long prose / "rule cards" / content blocks.

Rules should surface as:
- derived attributes
- constraint flags
- badges / glyphs / cell tints
- short tooltips
- sidebar intel modules (timeline + constraint report)

See: `web/specs/00-ui-philosophy.md`.

### Scroll position IS state

We take inspiration from Silk (`web/reference/silkhq/`). The scroll container's position drives:

- `activeTeam` — which team's header is sticky
- `sectionProgress` — 0→1 progress through that section
- `scrollState` — `idle | scrolling | settling`

Use `sectionProgress` for scroll-linked animations. See `specs/00-ui-philosophy.md` for the full model.

### Interaction invariants

- **Scroll-driven context**: scroll position determines active team + progress.
- **Sticky iOS-contacts headers**: team header + table header push off between teams.
- **Sidebar is 2-level**:
  - base = team context (from scroll)
  - overlay = single entity detail (player/agent/pick/team/…)
  - clicking a new entity replaces overlay (no stacking)
  - Back returns to **current viewport** team
- **Filters are lenses**: they reshape content without changing navigation state.

Authoritative interaction spec: `web/specs/01-salary-book.md`.

---

## Dependencies / prerequisites

- **Bun** installed.
- A reachable Postgres instance with the `pcms` schema populated (run the Python import flow in the repo root).
- `POSTGRES_URL` set in the environment (used by Bun API routes).

## Running locally

```bash
cd web
bun install

# dev server (hot reload)
POSTGRES_URL="$POSTGRES_URL" bun run dev

# optional: override port
PORT=3001 POSTGRES_URL="$POSTGRES_URL" bun run dev

# typecheck
bun run typecheck
```

Notes:

- `src/server.ts` defaults to **port 3002** if `PORT` is not set.
- `web/tests/api.test.ts` expects the server to be running on **http://localhost:3001**.

---

## Project structure

```
src/
  server.ts           # Bun server entry point (Bun.serve)
  client.tsx          # React app entry point
  index.html          # HTML shell
  api/
    routes/           # API route handlers (one file per domain)
  components/
    ui/               # Shared UI components
    app/              # Legacy app wrappers (AppShell)
  layouts/
    ThreePaneFrame/   # Slot-based layout frame (header/main/right)
  features/           # Feature modules (SalaryBook, etc.)
    SalaryBook/
      shell/          # SalaryBook runtime (scroll-spy, sidebar, transitions)
        CommandBar/   # SalaryBook command bar (teams + filters)
      components/
        RightPanel/   # Right-hand intelligence panel
  lib/
    animate.ts        # WAAPI helpers (animate, tween, applyProgressStyles)
    server/
      router.ts       # Route registry + Bun.serve route compilation
      utils.ts        # Error handling helpers
    utils.ts          # Client utilities (cx, focusRing, etc.)
  state/
    filters/          # Filter state
specs/
  00-ui-philosophy.md
  01-salary-book.md
  02-team-header-and-draft-assets.md
  03-trade-machine.md
reference/
  silkhq/             # Reverse-engineered Silk patterns (steal ideas, not the library)
    AGENTS.md         # Quick patterns to steal
    *.md              # Detailed docs on scroll, animation, state machines
tests/
  api.test.ts         # API endpoint tests (expects PORT=3001)
```

---

## Key conventions

- **API routes** are registered via `RouteRegistry` in `src/lib/server/router.ts` and merged in `src/server.ts`.
- Prefer reading tool-facing UI data from `pcms.*_warehouse` tables.
- Keep the app **read-only** unless there's a strong reason to add writes.
- Don't re-implement cap/trade rules in React if they can live in SQL.
- **Animations use WAAPI**, not CSS transitions — see `src/lib/animate.ts`.
- **Scroll-linked effects** should use `sectionProgress` from `useShellContext()`.

---

## Performance notes (Jan 2026 state)

Optimizations applied:

- **Memoization**
  - `PlayerRow`: `React.memo()` + custom comparator (player id + key fields + filter toggles)
  - `SalaryTable`: `filteredPlayers` in `useMemo()`
  - `TeamSection`: click handlers in `useCallback()`

- **SWR**
  - hooks migrated from ad-hoc fetches to SWR
  - global config: `revalidateOnFocus: false`, `dedupingInterval: 5000`

- **Scroll-spy**
  - Uses `requestAnimationFrame` for batched updates
  - Programmatic scroll locks updates to prevent flicker

Future (only if needed): virtualization (`@tanstack/react-virtual`) with care around sticky headers.

---

## When adding new capability (draft assets / trade machine)

Before changing React:

1) Identify missing **derived fields** → implement in SQL/warehouses.
2) Add/extend Bun API endpoints to return structured results.
3) Keep UI changes minimal and aligned with the scroll + sidebar model.

Specs to read in order:
- `web/specs/00-ui-philosophy.md`
- `web/specs/01-salary-book.md`
- `web/specs/02-team-header-and-draft-assets.md`
- `web/specs/03-trade-machine.md`
