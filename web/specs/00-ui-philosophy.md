# web/specs/00 — UI Philosophy & Invariants

> This is not a visual design doc. It is the interaction + information-design contract.
> The Salary Book UI is intentionally **not** a "documentation UI" and should not drift into that.

## Core thesis

This app is a front-office instrument:

- **Rows are the product.** The primary surface is a dense, scrollable, multi-team table.
- **Scroll position IS state.** The app always knows which team you're "in" AND how far through that section.
- **The sidebar is an intelligence panel.** It answers the *next question* without losing place.
- **Navigation is shallow.** One overlay at a time; clicking a new entity replaces the overlay.

This is the opposite of "cards + modals + pages."

---

## The Scroll-Driven Model

We take inspiration from [Silk](https://silk-hq.github.io/silk/) — a scroll-driven UI library. Key insight: **scroll position is not just navigation; it's the primary state driver.**

### Scroll Position as State

The scroll container's position maps to:

| Output | Meaning |
|--------|---------|
| `activeTeam` | Which team's header is currently in the sticky position |
| `sectionProgress` | 0→1 progress through that team's section |
| `scrollState` | Lifecycle: `idle → scrolling → settling` |

These aren't derived after the fact — they ARE the state. Components subscribe to them and react.

### Progress-Driven Animations

Instead of triggering animations on discrete events (click, mount), we can drive animations from scroll progress:

```tsx
// As user scrolls through a section, header fades/scales
applyProgressStyles(headerEl, sectionProgress, {
  opacity: (p) => 0.3 + (0.7 * p),
  transform: (p) => `scale(${0.95 + 0.05 * p})`,
});
```

This creates fluid, scroll-linked effects without complex event handling.

### Scroll Lifecycle

The `scrollState` tells you where you are in the scroll lifecycle:

| State | Meaning | Use case |
|-------|---------|----------|
| `idle` | Not scrolling | Safe to commit state, show final UI |
| `scrolling` | Actively scrolling | Suppress expensive updates, show lightweight UI |
| `settling` | Scroll stopped, momentum completing | Wait for snap, prepare final state |

### Why This Matters

Traditional approaches:
- Scroll event → derive state → trigger animation → hope it syncs

Our approach:
- Scroll position → IS the state → components read it directly → animations follow naturally

This eliminates timing bugs, reduces state management complexity, and creates smoother UX.

---

## Non-negotiables

### 1) No documentation UI

- Do not add "rule cards," long prose blocks, or content-first layouts.
- Rules are expressed as **derived fields + constraints + warnings + badges + tooltips**.
- Full clause text can exist, but should be **collapsed** and secondary.

### 2) Compute in Postgres

- Postgres warehouses/functions are the product API.
- The web app should be a thin consumer.
- Prefer: `pcms.*_warehouse` tables, `pcms.fn_*` functions.
- Avoid re-implementing CBA/Ops math in Ruby/JS.

### 3) Two-level sidebar state machine

The sidebar has a base state (team context) and a single overlay (entity detail).

- Team context updates with scroll-spy.
- Overlay does not change during scroll.
- Clicking another entity replaces the overlay (does not stack).
- Back returns to **current** viewport team, not origin.

### 4) Filters are lenses, not navigation

- Filters reshape what's visible/badged.
- Filters must not change selection state.
- Toggling filters should preserve scroll position and not "jump the user."

---

## Animation Patterns

We use WAAPI (Web Animations API) with a specific pattern stolen from Silk:

### Persist Final Styles

```tsx
// Problem: vanilla WAAPI reverts styles after animation ends
// Solution: commitStyles() + cancel() pattern

async function animate(el, keyframes, options) {
  const anim = el.animate(keyframes, { ...options, fill: "forwards" });
  await anim.finished;
  anim.commitStyles();  // Write final values as inline styles
  anim.cancel();        // Release the animation
}
```

### Safe-to-Unmount Lifecycle

When dismissing content with exit animations:

```tsx
// Wrong: content disappears before animation completes
{entity && <EntityDetail />}

// Right: keep mounted until animation finishes
const { stagedEntity, safeToUnmount } = useSidebarTransition(entity);
{(stagedEntity || !safeToUnmount) && <EntityDetail entity={stagedEntity} />}
```

The `stagedEntity` lags behind during exit animations, allowing the outgoing content to animate out before unmounting.

---

## Rule-to-UI translation guidelines

When you discover complicated rules (CBA/Ops Manual), translate them into:

1. **Derived attributes** (DB): booleans, classifications, computed amounts, "earliest/latest year," etc.
2. **Constraint flags** (DB): "blocked because X," "gated by apron," "counts as cash now," etc.
3. **Minimal visual markers** (UI): chips, glyphs, cell tints, hover tooltips.
4. **Sidebar intel modules** (UI): timeline + constraint report + drilldown.

Never translate rules into "read this explanation." Translate into "here is what it means and what blocks you."

---

## Information hierarchy

- The **sticky team header** is for identity + constraint posture (at-a-glance).
- The **table** is for scanning and comparison.
- The **sidebar Tier 0** is for thresholds + restriction state + slots.
- Everything else is drilldown.

---

## Debugging / correctness

- If a UI element is confusing, the fix is usually a **missing derived field** or a **bad precedence decision**, not more text.
- If a UI query is slow, fix it in SQL (warehouse refresh / indexes / fast refresh functions).

---

## Related specs

- `web/specs/01-salary-book.md` — main interaction model.
- `web/specs/02-team-header-and-draft-assets.md` — header KPIs + draft assets UI.
- `web/specs/03-trade-machine.md` — trade planning UI + DB primitives.

---

## Reference: Silk Patterns We Steal

See `web/reference/silkhq/AGENTS.md` for the full knowledge map. Key patterns:

| Pattern | Source | Our Implementation |
|---------|--------|-------------------|
| Progress-driven styles | `travelAnimation` in Silk | `applyProgressStyles()` in `animate.ts` |
| Safe-to-unmount lifecycle | Sheet staging machine | `useSidebarTransition()` |
| Scroll position as state | Sheet travel model | `useScrollSpy()` with `sectionProgress` |
| WAAPI with persistent styles | `animate()` utility | `animate()` in `animate.ts` |
| Scroll lifecycle events | `onScrollStart/End` | `scrollState` in `useScrollSpy()` |
