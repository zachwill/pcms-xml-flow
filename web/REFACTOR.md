# REFACTOR.md — App Shell vs SalaryBook Boundary Cleanup

> Purpose: a thorough refactor plan (no feature changes) to **cleanly separate** the invariant “application frame” from what is intrinsically part of the **Salary Book** view.
>
> This document is written to be executable as a handoff: you should be able to open a fresh context window and implement step-by-step.

---

## 0) Executive Summary

Today, `web/src/components/app/*` and `web/src/state/shell/*` look like generic “app shell” infrastructure, but they encode **Salary Book semantics**:

- `TopNav` is actually the Salary Book command bar (teams grid + filters).
- `ShellProvider` is a Salary Book runtime (scroll-spy, loaded teams, entity sidebar stack).
- `AppShell` hard-codes Salary Book’s fixed header height + margin offset.

**Goal:** invert the dependency direction so:

- **App frame** is dumb, slot-based, and feature-agnostic.
- **Salary Book** owns its command bar + runtime state machine (scrollspy + sidebar entity stack).

This enables new views (Free Agents, Tankathon, Trade Machine, etc.) to either reuse the frame or ship their own “view shell” without inheriting SalaryBook assumptions.

---

## 1) Current State (Audit)

### 1.1 Current composition path

- `src/features/SalaryBook/SalaryBook.tsx`
  - renders: `<AppShell main={<MainCanvas />} sidebar={<SidebarPanel />} />`

- `src/components/app/AppShell/AppShell.tsx`
  - hard-codes `<TopNav />`
  - wraps everything in `<ShellProvider topOffset={0}>`
  - hard-codes SalaryBook’s header offset (`style={{ marginTop: "130px" }}`)

- `src/components/app/TopNav/*`
  - `TeamSelectorGrid` depends on SalaryBook data: `useTeams` from `@/features/SalaryBook/hooks`
  - depends on global filters state: `@/state/filters`
  - includes placeholder “ViewSelector” UI

- `src/state/shell/*`
  - `ShellProvider`: scrollspy + entity stack + “loaded teams” model + filter-change scroll preservation + NBA team ordering.

### 1.2 Boundary smells

1) **Inverted dependency direction**
   - “app” layer imports “feature” layer (`TopNav/TeamSelectorGrid → useTeams`).

2) **Misleading naming**
   - `AppShell`, `TopNav`, `ShellProvider` imply app-global invariants, but they are SalaryBook-specific.

3) **Conceptual naming collision**
   - `components/ui/Sidebar.tsx` (generic UI primitive)
   - `features/SalaryBook/components/Sidebar/*` (SalaryBook right-hand intelligence panel)

4) **Dead/duplicate code**
   - `features/SalaryBook/hooks/useSidebarStack.ts` duplicates logic that is actually used from `state/shell/useSidebarStack.ts`.

---

## 2) Refactor Goals / Non-Goals

### 2.1 Goals

- Establish a clear layering model:
  - **App frame** (layout only)
  - **View shell** (SalaryBook runtime + chrome)
  - **Feature internals** (rows/table/sidebar modules)

- Make dependencies flow one way:
  - `features/*` may import from `components/ui/*`, `lib/*`, and app-level primitives.
  - app frame must not import from `features/*`.

- Make naming self-describing:
  - “TopNav” becomes a SalaryBook command bar.
  - “ShellProvider” becomes SalaryBook runtime provider.

- Keep behavior identical:
  - fixed header height
  - scrollspy active team
  - filter-change scroll restoration
  - sidebar entity shallow navigation + transitions

### 2.2 Non-goals

- No visual redesign.
- No data/model changes.
- No new routing logic for multiple views (we may scaffold, but not implement).
- Do not prematurely extract the SalaryTable sticky-header/horizontal-sync system into generic table infrastructure.

---

## 3) Target Architecture (End State)

### 3.1 Terminology

- **App Frame**: invariant layout structure (header slot, main slot, right slot). No SalaryBook knowledge.
- **View Shell**: a view-level composition layer that wires together runtime providers + chrome + view surfaces.
- **Feature Internals**: SalaryBook’s table + rows + right panel modules.

### 3.2 Proposed folder layout

A concrete target tree:

```
src/
  app/
    App.tsx                 # optional (or keep client.tsx as root)
    providers/              # SWR/Toast/etc if we want to centralize later

  layouts/
    ThreePaneFrame/
      ThreePaneFrame.tsx    # dumb layout: header/main/right slots
      index.ts

  features/
    SalaryBook/
      pages/
        SalaryBookPage.tsx  # route-level view shell

      shell/                # SalaryBook runtime + chrome
        SalaryBookShellProvider.tsx  # renamed ShellProvider
        useScrollSpy.ts
        useSidebarStack.ts
        useSidebarTransition.ts
        teamOrder.ts
        index.ts

        CommandBar/
          SalaryBookCommandBar.tsx   # renamed TopNav
          TeamSelectorGrid.tsx
          FilterToggles.tsx
          ViewSelector.tsx           # can remain placeholder
          index.ts

      components/
        MainCanvas/...
        RightPanel/...

      hooks/...
      data/...
      SalaryBook.tsx         # optional: keep as alias that re-exports SalaryBookPage
      index.tsx
```

Notes:
- The “shell” directory is intentionally separate from “components” to encode that it is **runtime state + chrome**.
- “RightPanel” is a rename of SalaryBook’s sidebar to avoid collisions with the UI primitive `components/ui/Sidebar`.

### 3.3 Dependency rules (explicit)

- `layouts/*` must not import from `features/*`.
- `features/SalaryBook/shell/*` may import from:
  - `features/SalaryBook/*`
  - `state/filters/*` (global provider can stay global)
  - `components/ui/*` and `lib/*`

- `components/app/*` should become very small or disappear; app-level UI is not a goal right now.

---

## 4) Proposed Renames (to reduce confusion)

### 4.1 Component renames

- `components/app/TopNav/TopNav.tsx`
  - → `features/SalaryBook/shell/CommandBar/SalaryBookCommandBar.tsx`

- `components/app/AppShell/AppShell.tsx`
  - → replaced by `layouts/ThreePaneFrame/ThreePaneFrame.tsx` (layout only)

- `features/SalaryBook/components/Sidebar/SidebarPanel.tsx`
  - → `features/SalaryBook/components/RightPanel/RightPanel.tsx` (or `InspectorPanel.tsx`)

### 4.2 Provider renames

- `state/shell/ShellProvider.tsx`
  - → `features/SalaryBook/shell/SalaryBookShellProvider.tsx`

### 4.3 Naming collision policy

- `components/ui/Sidebar.tsx` remains the generic UI primitive.
- SalaryBook’s right surface should not use the name “Sidebar” at the top level.

---

## 5) Migration Plan (Phased, Low-Risk)

Each phase is intended to be a clean commit with a working app + green typecheck.

### Phase 0 — Baseline + guardrails (prep)

1) Confirm usage graph:
   - `rg "components/app" src | head`
   - `rg "state/shell" src | head`

2) Ensure tests/typecheck are green before changes:
   - `bun run typecheck`
   - `bun run test` (optional)

3) Create this refactor doc (done).

**Acceptance:** baseline is known-good.

---

### Phase 1 — Introduce a dumb layout frame (no behavior change)

**Goal:** replace `AppShell` with a truly feature-agnostic layout.

1) Create `src/layouts/ThreePaneFrame/ThreePaneFrame.tsx`:
   - props: `header`, `main`, `right` (or `sidebar`), `headerHeight` (optional)
   - renders the 3-region layout:
     - fixed header slot
     - main/right container underneath
   - does NOT import `ShellProvider` or `TopNav`.

2) Keep the existing `AppShell` temporarily as an adapter:
   - `AppShell` can become a thin wrapper around `ThreePaneFrame` while we migrate.

**Acceptance:** app still works, no functional changes.

---

### Phase 2 — Create SalaryBook “view shell” (provider + command bar wiring)

**Goal:** SalaryBook owns its shell concerns; app frame stays dumb.

1) Create `features/SalaryBook/pages/SalaryBookPage.tsx` that composes:

- `SalaryBookShellProvider` (or still `ShellProvider` temporarily)
- `SalaryBookCommandBar` (renamed TopNav)
- `ThreePaneFrame` layout:
  - `header={<SalaryBookCommandBar />}`
  - `main={<MainCanvas />}`
  - `right={<RightPanel />}`

2) Update routing:
- `client.tsx` route element becomes `<SalaryBookPage />`.

3) Keep `features/SalaryBook/SalaryBook.tsx` as a compatibility alias:
- `export function SalaryBook() { return <SalaryBookPage /> }`

**Acceptance:** SalaryBook still renders identically, but composition now clearly indicates what’s SalaryBook.

---

### Phase 3 — Move/rename TopNav into SalaryBook shell/CommandBar

**Goal:** eliminate app → feature dependency inversion.

Steps:

1) Move these files:

- `src/components/app/TopNav/TopNav.tsx`
- `src/components/app/TopNav/TeamSelectorGrid.tsx`
- `src/components/app/TopNav/FilterToggles.tsx`
- `src/components/app/TopNav/ViewSelector.tsx`
- `src/components/app/TopNav/index.ts`

→ to `src/features/SalaryBook/shell/CommandBar/*`

2) Rename exports:
- `TopNav` → `SalaryBookCommandBar`

3) Ensure the command bar imports SalaryBook hooks without crossing boundaries:
- `TeamSelectorGrid` using `useTeams` is now feature-local, so it’s fine.

4) Delete or deprecate `components/app/TopNav` barrel exports.

**Acceptance:** there is no longer a generic “app top nav” that imports SalaryBook.

---

### Phase 4 — Move/rename ShellProvider (state/shell → SalaryBook shell)

**Goal:** SalaryBook runtime state lives with the SalaryBook feature.

1) Move `src/state/shell/*` → `src/features/SalaryBook/shell/*` (or `runtime/*`).
   - `ShellProvider.tsx` becomes `SalaryBookShellProvider.tsx`
   - keep the same public API initially (contexts + hooks)

2) Transitional compatibility layer (recommended):
   - keep `src/state/shell/index.ts` as a shim that re-exports from `features/SalaryBook/shell` for one iteration.
   - This reduces churn and makes rollback easier.

3) Update imports gradually:
   - Update SalaryBook internals first to import from `features/SalaryBook/shell`.
   - Then remove the shim once the tree is updated.

4) Decide what truly belongs at app-level state:
   - `FilterProvider` can remain global.
   - Everything else in shell is SalaryBook-specific today.

**Acceptance:** `src/state/shell` is empty or only a transitional re-export shim.

---

### Phase 5 — Disambiguate SalaryBook “Sidebar” naming

**Goal:** remove confusion between UI `Sidebar` primitive and SalaryBook right panel.

1) Rename directory:
- `features/SalaryBook/components/Sidebar/` → `features/SalaryBook/components/RightPanel/`

2) Rename key component:
- `SidebarPanel` → `RightPanel` (or `InspectorPanel`)

3) Update imports inside SalaryBook.

**Acceptance:** it’s impossible to confuse the app’s generic nav sidebar primitive with SalaryBook’s intelligence panel.

---

### Phase 6 — Remove dead/duplicate hook code

**Goal:** ensure there’s exactly one source-of-truth for sidebar stack.

1) Remove `features/SalaryBook/hooks/useSidebarStack.ts` (currently redundant).
2) Ensure `features/SalaryBook/hooks/index.ts` re-exports from the canonical location.

**Acceptance:** no duplicate sidebar stack implementations exist.

---

### Phase 7 — Update docs + AGENTS handoff

1) Update `web/HANDOFF.md`:
   - “ShellProvider” renamed / moved
   - “TopNav” renamed / moved

2) Update `web/TODO.md` with “Boundary refactor” completion.

---

## 6) Acceptance Criteria (Regression Checklist)

### Visual/layout invariants

- Fixed header remains fixed.
- Main canvas starts below header with the same effective offset (currently 130px).
- Sidebar remains independent scroll.

### Behavior invariants

- Team selector grid:
  - highlights active team from scrollspy
  - click scrolls to team
  - shift-click toggles loaded teams
  - alt/cmd click isolates

- Filters:
  - toggling does not change selection state
  - scroll position is preserved (restores active team)

- Sidebar:
  - default mode shows scrollspy-driven team context
  - entity mode overlays details
  - back returns to current viewport team (not origin)
  - entity transitions still use safeToUnmount/WAAPI

### Build invariants

- `bun run typecheck` passes.
- `bun run test` passes (at least the existing suite).

---

## 7) Risks / Gotchas

1) **Header height coupling (130px)**
   - Today both `AppShell` and `TopNav` hard-code 130px.
   - During refactor, ensure there is a *single source of truth*:
     - either `ThreePaneFrame` receives `headerHeight={130}`
     - or the header measures itself (later)

2) **Sticky + overflow interactions**
   - SalaryBook has careful constraints where sticky elements must not be inside an overflow container that breaks `position: sticky`.
   - Keep `SalaryTable` layout unchanged.

3) **Path alias churn**
   - The `@/*` alias makes it easy to move files, but barrels (`index.ts`) must be updated carefully.

4) **Transitional shims**
   - Keep shims temporarily to reduce diff size.
   - Remove shims only after everything imports the new canonical path.

---

## 8) Optional Follow-ups (Not required for the boundary refactor)

These are explicitly out-of-scope for the initial refactor, but become easier after separation:

1) **Generalize “command bar slots”**
   - If future views need their own command bars, the app frame can provide a header slot; each view provides its own header component.

2) **Generalize “3-pane layout” variants**
   - Some views may want no right panel or a collapsible right panel.

3) **Extract a generic “StickyHeaderTable” pattern**
   - Only after a second view needs the same mechanics.

---

## 9) Implementation Notes (tactical)

When implementing:

- Prefer *move + re-export* over “move everything and update every import in one shot”.
- Keep commits small and behavior-preserving.
- Use `rg` to find imports and update systematically.

Suggested command sequence per phase:

- `rg "@/components/app" src`
- `rg "@/state/shell" src`
- `bun run typecheck`
- `bun run dev` and click around:
  - team nav
  - filter toggles
  - open player, agent, pick
  - scroll while entity open, then back

---

## 10) Open Questions (decisions to make during implementation)

1) **Where should global filters live long-term?**
   - Today `FilterProvider` is app-global; UI is SalaryBook-specific.
   - This is acceptable if filters are intended to be “global lenses” across future views.

2) **Should `useTeams` become app-global?**
   - Right now it’s in SalaryBook hooks; command bar uses it.
   - If future views need teams, consider moving `useTeams` into a shared “NBA” domain module (but not required now).

3) **What do we call the right panel?**
   - `RightPanel` is neutral.
   - `InspectorPanel`/`IntelPanel` communicates product intent.

---

### Appendix A — Current files implicated (for quick grep)

- Layout / app-ish:
  - `src/components/app/AppShell/AppShell.tsx`
  - `src/components/app/TopNav/*`

- SalaryBook shell state:
  - `src/state/shell/*`

- SalaryBook components:
  - `src/features/SalaryBook/components/MainCanvas/*`
  - `src/features/SalaryBook/components/Sidebar/*`

- Global providers:
  - `src/client.tsx`
  - `src/state/filters/*`
