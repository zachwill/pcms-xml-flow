# Handoff: Salary Book UI Work

You're picking up UI work on the **Salary Book** — a scroll-driven NBA front-office tool.

---

## What is this?

A Bun + React prototype app (`prototypes/salary-book-react/`) that displays NBA salary cap data. Main interaction model:

- **Scroll-driven**: Main canvas is a vertical scroll of 30 NBA teams
- **Scroll-spy with progress**: Active team determined by scroll position + per-section progress (0→1)
- **2-level sidebar**: Base state (team context) + optional entity overlay (player/agent/pick)
- **Shallow navigation**: Click entity → pushes detail; click another → replaces (no deep stack)

---

## The Mentality

We're building a **front-office instrument**, not a documentation UI. Key principles:

1. **Steal from Silk** — We've reverse-engineered patterns from `@silk-hq/components` (see `reference/silkhq/`). We don't use the library, but we steal their ideas: progress-driven animations, safeToUnmount lifecycle, scroll position as state.

2. **Scroll position IS state** — The scroll container's position drives everything. `sectionProgress` (0→1) tells you how far through the current section. `scrollState` tells you the lifecycle (`idle → scrolling → settling`).

3. **Animations use WAAPI** — Not CSS transitions. Our `animate.ts` helper persists final styles via `commitStyles() + cancel()`. This avoids the "snap back" problem.

4. **Postgres is the product** — The UI is a thin consumer of `pcms.*_warehouse` tables. Don't reimplement CBA math in React.

---

## Where to find things

### Start here

| File | Purpose |
|------|---------|
| **`TODO.md`** | Prototype work items, what's done, what's next |
| **`web/specs/00-ui-philosophy.md`** | Core invariants + the scroll-driven model |
| **`web/specs/01-salary-book.md`** | Full interaction spec |

### Core infrastructure

| File | Purpose |
|------|---------|
| `src/features/SalaryBook/shell/useScrollSpy.ts` | **Scroll-spy with progress** — tracks `activeTeam`, `sectionProgress`, `scrollState` |
| `src/features/SalaryBook/shell/useSidebarTransition.ts` | **Sidebar animations** — safeToUnmount pattern for entity transitions |
| `src/features/SalaryBook/shell/SalaryBookShellProvider.tsx` | **Shell context** — provides scroll-spy + sidebar state to the app |
| `src/lib/animate.ts` | **WAAPI helpers** — `animate()`, `tween()`, `applyProgressStyles()` |

### Reference material

| File | Purpose |
|------|---------|
| `reference/silkhq/AGENTS.md` | Patterns we steal from Silk (what to read + why) |
| `reference/silkhq/03-scroll-and-gesture-trapping.md` | Scroll + gesture trapping patterns (inspiration for our scroll-spy) |
| `reference/silkhq/02-sheet-system-architecture.md` | Sheet runtime model: travel/detents/state machines + safe-to-unmount |
| `reference/silkhq/05-animations-and-recipes.md` | Progress-driven animations + WAAPI persistence (`commitStyles()+cancel()`) |

---

## What's been completed

### Scroll System (Silk-inspired rewrite)

The scroll-spy now exposes:

```tsx
const {
  activeTeam,       // string | null — which team's header is sticky
  sectionProgress,  // number 0→1 — how far through current section
  scrollState,      // "idle" | "scrolling" | "settling"
  registerSection,  // register a team section element
  scrollToTeam,     // programmatic navigation
} = useShellContext();
```

**Use `sectionProgress` for:**
- Scroll-linked header effects (fade/scale as section scrolls)
- Parallax or sticky transitions
- Progress-driven animations via `applyProgressStyles()`

**Use `scrollState` for:**
- Suppressing updates during fast scrolling
- Triggering animations on scroll settle
- Knowing when to commit "final" state

### Animation Infrastructure

```tsx
// WAAPI with persistent final styles
await animate(el, [
  { opacity: 0, transform: "translateX(8px)" },
  { opacity: 1, transform: "translateX(0)" },
], { duration: 200, easing: easings.easeOut });

// Progress-driven styles (for scroll-linked effects)
applyProgressStyles(el, sectionProgress, {
  opacity: [0, 1],  // interpolated
  transform: (p) => `translateY(${(1 - p) * 20}px)`,  // function
});

// CSS calc() interpolation
const value = tween("0px", "20px", progress);
// → "calc(0px + (20px - 0px) * 0.5)"
```

### Sidebar Transitions

```tsx
const {
  stagedEntity,      // Entity to render (lags behind during exit)
  transitionState,   // "idle" | "entering" | "present" | "exiting" | "replacing"
  containerRef,      // Attach to element for animations
  safeToUnmount,     // False while animation running
} = useSidebarTransition(currentEntity);

// Render if staged OR animation still running
const showEntity = stagedEntity !== null || !safeToUnmount;
```

---

## What's next

Check `TODO.md` for the current list. The deferred items are:

| Item | Notes |
|------|-------|
| **#6 Scroll/gesture trapping** | Mobile hardening — wait until we see iOS/Android bugs |
| **#7 Transform compensation** | Needed if we animate ancestors of sticky elements |
| **#8 Overlay manager** | For future modals/popovers — click-outside, escape, focus |

Likely next: **Build a scroll-linked header effect** using `sectionProgress` to fade/scale the team header as it's pushed off.

---

## Running the app

```bash
cd prototypes/salary-book-react
bun run dev        # Start dev server (port 3002)
bun run typecheck  # Verify types
```

---

## Gotchas

1. **Animations use WAAPI, not CSS transitions** — See `animate.ts`. We call `commitStyles()` + `cancel()` on finish to persist end styles.

2. **`stagedEntity` vs `currentEntity`** — `useSidebarTransition` returns `stagedEntity`, which lags behind during exit animations. This is intentional.

3. **`sectionProgress` is 0→1** — 0 when section just became active, 1 when next section is about to take over. For the last section, it's based on scroll distance to bottom.

4. **`scrollState: "settling"`** — There's a brief period after scroll stops but before we return to "idle". Use this for snap/momentum completion.

5. **Programmatic scroll locks scroll-spy** — When you call `scrollToTeam()`, scroll-spy updates are suppressed until the scroll completes. This prevents flicker.

6. **Silk docs are reverse-engineered** — The files in `reference/silkhq/` are our notes from reading their minified code. We steal patterns, not the library.

7. **Data comes from Postgres** — API routes in `src/api/` map nearly 1:1 to `pcms.*_warehouse` tables. The real logic lives in SQL.

---

## Quick architecture diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                 SalaryBookShellProvider                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  useScrollSpy                                             │   │
│  │  ├── activeTeam: string | null                           │   │
│  │  ├── sectionProgress: number (0→1)                       │   │
│  │  ├── scrollState: "idle" | "scrolling" | "settling"      │   │
│  │  └── scrollToTeam(code, behavior)                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  useSidebarStack                                          │   │
│  │  ├── currentEntity: SidebarEntity | null                 │   │
│  │  ├── pushEntity / popEntity / clearStack                 │   │
│  │  └── canGoBack: boolean                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         RightPanel                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  useSidebarTransition(currentEntity)                      │   │
│  │  ├── stagedEntity (lags during exit)                     │   │
│  │  ├── transitionState: idle|entering|present|exiting      │   │
│  │  └── safeToUnmount: boolean                              │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```
