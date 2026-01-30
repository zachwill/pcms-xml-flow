# web/TODO.md

Focused follow-ups for the **Salary Book** UI (informed by `web/reference/silkhq/` patterns).

---

## Immediate: Cleanup

### 0) Remove duplicate ScrollSpy code ✅

~~We have two implementations; only one should exist. Do this first to avoid confusion.~~

- [x] **Deleted** `web/src/features/SalaryBook/hooks/useScrollSpy.ts` (dead; Shell uses the canonical one)
- [x] Canonical hook: `web/src/features/SalaryBook/shell/useScrollSpy.ts`
- [x] Verified no lingering imports

---

## High Priority: Core Animation Infrastructure

### 1) WAAPI helper that persists end styles ✅

~~**Problem:** vanilla WAAPI often "snaps back" at the end unless we persist styles.~~

~~**Silk pattern:** `el.animate(..., { fill: "forwards" })` → `onfinish: commitStyles(); cancel();`~~

- [x] Added `web/src/lib/animate.ts`:
  - `animate()` — async, returns Promise for sequencing
  - `animateSync()` — sync, returns Animation directly
  - `tween()` — CSS calc() interpolation helper
  - `applyProgressStyles()` — progress-driven style application
  - `easings` / `durations` — common presets

### 2) Sidebar transitions (safeToUnmount pattern) ✅

~~**Goal:** avoid "content disappears before animation completes" when pushing/popping entities.~~

~~**Silk pattern:** Separate `open` from `safeToUnmount`. Mount if `open || !safeToUnmount`. On close, set `open=false` immediately but delay unmount until exit animation finishes.~~

- [x] Added `web/src/features/SalaryBook/shell/useSidebarTransition.ts`:
  - `stagedEntity` — the entity to render (lags behind during exit)
  - `transitionState` — `idle | entering | present | exiting | replacing`
  - `safeToUnmount` — false while animation running
  - `containerRef` — attach to element for WAAPI animations
- [x] Updated `RightPanel.tsx` to use the hook
- [x] Entity now animates out before unmounting (slide + fade)

---

## Medium Priority: State Clarity

### 3) Transition state enum (if animations get complex) ✅

~~Current `useSidebarStack` uses a simple stack array. If we find ourselves with multiple `isAnimating` booleans, consider explicit states.~~

**Resolution:** Not needed. `useSidebarTransition` already provides a 5-state machine (`idle | entering | present | exiting | replacing`) which covers the animation lifecycle. `useSidebarStack` remains a simple array since the transition complexity lives in the animation layer, not the data layer.

---

## Low Priority: Nice-to-Have Utilities

### 4) Progress-driven styles utility ✅

~~**Silk pattern:** `tween(start, end)` returns CSS calc() for interpolation.~~

- [x] Added to `web/src/lib/animate.ts`:
  - `tween(start, end, progress)` — CSS calc() interpolation
  - `applyProgressStyles(el, progress, declarations)` — apply progress-driven styles to element

### 5) Scroll progress exposure ✅

~~Current `useScrollSpy` tracks active team but doesn't expose per-section progress (0-1).~~

- [x] Rewrote `useScrollSpy` with Silk-inspired patterns:
  - `sectionProgress` (0→1) — how far through current section
  - `scrollState` (`idle | scrolling | settling`) — scroll lifecycle
  - Cleaner architecture: sorted sections, proper progress calculation
  - Programmatic scroll locking to prevent flicker during `scrollToTeam`
- [x] Updated `SalaryBookShellProvider` and `ShellContextValue` to expose new values
- [x] Exported `ScrollState` and `ScrollSpyResult` types

**Use cases unlocked:**
- Scroll-linked header effects (fade/scale as section scrolls)
- Scroll state awareness (suppress updates during fast scroll, trigger on settle)
- Per-section progress for parallax or sticky transitions

### 5b) Back button team crossfade ✅

When the user scrolls the main canvas while viewing an entity, the "back" destination changes silently. Now the back button's team logo crossfades to communicate this.

- [x] Added `web/src/features/SalaryBook/components/RightPanel/BackButtonTeamBadge.tsx`:
  - Tracks previous/current team with safeToUnmount pattern
  - Crossfades logo when `activeTeam` changes while in entity mode
  - Uses WAAPI `animate()` for scale+opacity transitions
- [x] Updated `RightPanel.tsx` to use the new component
- [x] Removed inline logo loading/error state (now encapsulated in badge)

---

## Deferred: Mobile Hardening

### 6) Scroll/gesture trapping subsystem

We have nested scroll contexts (MainCanvas, Sidebar, per-team horizontal tables). If we see iOS/Android propagation/overscroll bugs:

- [ ] Implement a small dedicated util (not ad-hoc patches)
- [ ] Optional edge/overscroll trapping
- [ ] Platform-gated (iOS Safari vs Android non-standalone)

**Silk insight:** Android non-standalone disables Y-axis trapping to allow browser UI reveal. iOS needs explicit 28px edge-swipe blocking.

### 7) Fixed/sticky + transform compensation

If we animate layout wrappers (translate/scale), sticky elements inside transformed subtrees will break.

- [ ] Avoid transforms on ancestors of sticky elements
- [ ] If unavoidable, implement "transform compensation" (Silk's `Fixed` pattern)

---

## Future: When Trade Machine / Modals Land

### 8) Overlay manager subsystem

Salary Book sidebar is intentionally **non-modal**. Future overlays (trade confirmation, filter popovers) will need:

- [ ] Click-outside routing
- [ ] Escape key routing  
- [ ] Focus restore on dismiss
- [ ] `inertOutside` (optional)
- [ ] Interactive carve-outs (Silk's "Island" pattern)

**Key insight:** Treat this as a single-owner subsystem, not logic scattered across components.
