# web/AGENTS.md

> Notes for AI coding agents working in **web/**.

## What this is

`web/` is a **Bun + React + TypeScript** web app that lives alongside the Python PCMS ingest pipeline.

It exists to provide:

- A UI (currently: **Salary Book**) for browsing NBA PCMS-derived "warehouse" tables.
- A small Bun API layer under `/api/*` (currently: `/api/salary-book/*`) that reads from Postgres (`pcms` schema).

This directory is intentionally isolated from the repo's Python code. Avoid introducing JS/TS build artifacts or Node dependencies outside of `web/`.

## Dependencies / prerequisites

- **Bun** installed.
- A reachable Postgres instance with the `pcms` schema populated (run the Python import flow in the repo root).
- `POSTGRES_URL` set in the environment (used by `src/api/routes/salary-book.ts`).

## Running locally

```bash
cd web
bun install

# dev server (hot reload)
POSTGRES_URL="$POSTGRES_URL" bun run dev

# optional: override port
PORT=3001 POSTGRES_URL="$POSTGRES_URL" bun run dev
```

Notes:

- `src/server.ts` defaults to **port 3002** if `PORT` is not set.
- `web/tests/api.test.ts` expects the server to be running on **http://localhost:3001**.

## Project structure

```
src/
  server.ts       # Bun server entry point (Bun.serve)
  client.tsx      # React app entry point
  index.html      # HTML shell
  api/
    routes/       # API route handlers (one file per domain)
  components/
    ui/           # Shared UI components
  features/       # Feature modules (pages/views)
  lib/
    server/
      router.ts   # Route registry + Bun.serve route compilation
      utils.ts    # Error handling helpers
    utils.ts      # Client utilities
tests/
  api.test.ts     # API endpoint tests (expects PORT=3001)
```

## Key conventions

- **API routes** are registered via `RouteRegistry` in `src/lib/server/router.ts` and merged in `src/server.ts`.
- Prefer pulling tool-facing UI data from `pcms.*_warehouse` tables.
- Keep this app read-only unless there's a strong reason to add writes.

## Common pitfalls

- If `/api/salary-book/*` errors on startup, you likely forgot `POSTGRES_URL`.
- If `bun test` fails with connection refused, start the server first with `PORT=3001`.

---

## Performance optimizations (Jan 2026)

The following optimizations have been applied to address React performance issues:

### 1. **Memoization**

- **`PlayerRow`**: Wrapped in `React.memo()` with custom comparison function (checks player ID + key salary fields + filter toggles). Prevents re-renders when scrolling or toggling unrelated filters.

- **`SalaryTable`**: `filteredPlayers` is now wrapped in `useMemo()` to avoid re-filtering on every render.

- **`CapOutlookTab` → `SalaryProjections`**: Bar chart calculations (max value, height percentages) are memoized. Chart uses CSS transitions instead of re-animating from zero.

- **`TeamSection`**: Click handlers (`handlePlayerClick`, `handleAgentClick`, `handlePickClick`) are wrapped in `useCallback()` to maintain stable references for memoized child components.

### 2. **Data fetching with SWR**

Hooks have been migrated from raw `useState/useEffect` to **SWR**:

- **`usePlayers`**: Global cache by team. When switching teams, cached data shows instantly while revalidating. Agent view can reuse player data without re-fetching.

- **`useTeamSalary`**: Same caching strategy. Deduplicates requests when multiple TeamSections mount.

SWR config:
```ts
{
  revalidateOnFocus: false,
  dedupingInterval: 5000,
  keepPreviousData: true,  // Show previous team while loading new
}
```

### 3. **Future: Virtualization**

The current implementation renders all 30 teams × ~15 players into the DOM at once (~450 rows). For smoother scrolling with large lists, consider adding virtualization:

**Recommended approach:**
1. Install `@tanstack/react-virtual` (preferred) or `react-window`
2. Virtualize the `MainCanvas` scroll container
3. Keep sticky headers working by using a fixed header + virtualized body pattern

**Implementation sketch:**
```tsx
// In MainCanvas.tsx
import { useVirtualizer } from '@tanstack/react-virtual';

function MainCanvas() {
  const parentRef = useRef<HTMLDivElement>(null);
  
  // Flatten all teams into rows with estimated heights
  const rows = useMemo(() => {
    return loadedTeams.flatMap(team => [
      { type: 'header', team },
      ...playersForTeam[team].map(p => ({ type: 'player', player: p })),
      { type: 'footer', team },
    ]);
  }, [loadedTeams, playersForTeam]);

  const virtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: (i) => rows[i].type === 'header' ? 56 : 72,
    overscan: 5,
  });

  // Render only visible rows...
}
```

**Caveats:**
- Sticky team headers require extra work (absolute positioning + scroll listeners)
- Horizontal scroll sync between header/body must be preserved
- Consider deferring until performance profiling shows it's needed

