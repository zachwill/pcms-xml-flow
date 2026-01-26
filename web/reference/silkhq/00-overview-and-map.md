# Silk (@silk-hq/components) — Reverse-engineered reference (consolidated)

This directory is an implementation-level reference for **Silk v0.9.12** (`@silk-hq/components`) grounded in:

- `node_modules/@silk-hq/components/dist/module.mjs` (actual runtime)
- `node_modules/@silk-hq/components/dist/types.d.ts` (declared public API + docblocks)
- `node_modules/@silk-hq/components/dist/main.css` + `main-unlayered.css` (default styles)
- `src/components/**` in this repo (author-intended composition patterns)

Goal: capture what the library *actually does* (scroll-driven travel, state machines, gesture trapping, focus/inert systems) so we can steal patterns or rewrite safely.

---

## Package map (what to read)

Key files:

- `dist/module.mjs`
  - component implementations
  - global runtime registry (internally named `eG`)
  - state machines
  - WAAPI + spring helpers
  - `data-silk` token generator
- `dist/types.d.ts`
  - public API surface and prop docblocks
  - exports a `mapping` namespace (component/element/variation tokens)
- `dist/main.css` / `dist/main-unlayered.css`
  - default styles (token-driven)

Exports (from `dist/module.mjs`):

- Components: `Sheet`, `SheetStack`, `Scroll`, `AutoFocusTarget`, `VisuallyHidden`, `Fixed`, `Island`, `ExternalOverlay`
- Utilities/hooks: `createComponentId`, `useClientMediaQuery`, `updateThemeColor`, `useThemeColorDimmingOverlay`, `usePageScrollData`, `animate`

---

## This repo’s examples (what Silk expects you to compose)

Silk’s `src/components/**` examples are not “separate libraries”; they demonstrate intended composition:

- BottomSheet
- Card
- DetachedSheet
- LongSheet
- Page
- PageFromBottom
- SheetWithDetent
- SheetWithKeyboard
- SheetWithStacking
- Sidebar
- Toast
- TopSheet

These wrappers mostly customize:

- `contentPlacement` / `tracks`
- `nativeEdgeSwipePrevention`
- `themeColorDimming`
- `swipeOvershoot`
- travel/stacking animation props

---

## Reading paths

### If you’re implementing/re-writing Sheet mechanics
1. `01-css-tokens-and-styling-contract.md`
2. `02-sheet-system-architecture.md`
3. `04-overlay-focus-and-inert-system.md`
4. `05-animations-and-recipes.md`
5. `03-scroll-and-gesture-trapping.md` (if you need Scroll primitives)
6. `06-utilities-and-other-primitives.md`

### If you’re stealing patterns for Salary Book / scroll-driven UIs
- `AGENTS.md` (what we steal and where)
- `03-scroll-and-gesture-trapping.md`
- `05-animations-and-recipes.md`
- skim `04-overlay-focus-and-inert-system.md` for Islands/focus restoration

---

## Package anatomy (`@silk-hq/components`)

Key files to reference for implementation details:

- `dist/module.mjs`: Main ESM runtime (logic, state machines, gesture handling).
- `dist/types.d.ts`: Public API with extensive docblocks (the “declared” contract).
- `dist/main.css`: Default styles (layered).
- `dist/main-unlayered.css`: Default styles (plain).

**Primary Exports:**

- **Components**: `Sheet`, `SheetStack`, `Scroll`, `AutoFocusTarget`, `VisuallyHidden`, `Fixed`, `Island`, `ExternalOverlay`
- **Hooks/Utils**: `usePageScrollData`, `useClientMediaQuery`, `updateThemeColor`, `useThemeColorDimmingOverlay`, `animate`

---

## Glossary (Silk terms)

- **Travel**: Sheet presentation/dismissal motion, implemented as a **scroll container** whose scroll position maps to progress.
- **Detents**: scroll-snap points for travel (CSS sizes); a final “fit content” detent is always appended.
- **Progress**:
  - travel progress: `0..1`
  - stacking progress: `0..n` (n = number of sheets above)
- **Outlet**: an element registered to receive progress-driven inline styles (`travelAnimation` / `stackingAnimation`).
- **Staging**: lifecycle state machine that keeps the View mounted until exit animations finish (drives `safeToUnmount`).
- **Layer**: a top-level overlay surface registered globally for inertOutside + click-outside + escape + focus.
- **Island**: a carve-out region that stays interactive even when inertOutside is applied.

---

## File index (consolidated)

- `AGENTS.md` — how we use this reference in *this repo* (patterns we steal)
- `00-overview-and-map.md` — you are here
- `01-css-tokens-and-styling-contract.md` — `data-silk` contract
- `02-sheet-system-architecture.md` — travel model + state machines + subcomponents + stack integration
- `03-scroll-and-gesture-trapping.md` — Scroll + ScrollTrap + page scroll replacement
- `04-overlay-focus-and-inert-system.md` — layers/islands/focus/inertOutside/click-outside/escape
- `05-animations-and-recipes.md` — progress-driven animations, animation settings, recipes from examples
- `06-utilities-and-other-primitives.md` — Fixed/VisuallyHidden/etc + exported hooks

---

## Archive

The original, more granular 00–12 notes (plus the previous knowledge map) are preserved in:

- `web/reference/silkhq/archive/`

Prefer the consolidated docs above unless you’re comparing/porting specific phrasing.
