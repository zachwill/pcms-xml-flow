# Silk patterns (for agents)

We **do not** use `@silk-hq/components` in this repo.

We reverse-engineered it because it encodes a lot of hard-won knowledge about:
- scroll-driven state machines (scroll position as truth)
- gesture trapping and platform quirks
- safe-to-unmount lifecycles
- overlay focus/inert routing

The Salary Book UI steals these patterns.

---

## What to read (consolidated)

- `00-overview-and-map.md` — where everything is + reading paths
- `01-css-tokens-and-styling-contract.md` — `data-silk` tokens (if you need to debug selectors)
- `02-sheet-system-architecture.md` — safeToUnmount, travel/detents, state machines
- `03-scroll-and-gesture-trapping.md` — scroll/gesture patterns (relevant to our scroll-spy)
- `04-overlay-focus-and-inert-system.md` — Islands/external overlay/focus (if/when we add real overlays)
- `05-animations-and-recipes.md` — progress-driven animations + WAAPI persistence
- `06-utilities-and-other-primitives.md` — Fixed/VisuallyHidden/AutoFocusTarget + hook exports

---

## Patterns we actively steal in `web/`

### 1) Scroll position IS state
Silk’s core travel model: scroll position *is* the state.
- In Salary Book: `activeTeam`, `sectionProgress`, `scrollState`.
- Implementation: `web/src/state/shell/useScrollSpy.ts`

### 2) Safe-to-unmount lifecycle
Silk’s staging machine decouples “open” vs “still mounted for exit animation”.
- Implementation: `web/src/state/shell/useSidebarTransition.ts`

### 3) WAAPI animations that persist end styles
Silk pattern: `element.animate(..., { fill: 'forwards' })` -> `onfinish: commitStyles(); cancel();`.
- Avoids “snap back” and releases animation resources.
- Implementation: `web/src/lib/animate.ts`

### 4) Progress-driven styles (`tween()` + declarations)
Declarations object + `tween(start, end)` for CSS `calc(...)` interpolation.
- Implementation: `web/src/lib/animate.ts` (`tween`, `applyProgressStyles`)

---

## Knowledge map by Salary Book concern

| Salary Book concern | What to read | Key insight |
|:---|:---|:---|
| **Scroll-driven context** | `03-scroll-and-gesture-trapping.md` | Scroll-to-progress mapping, gesture trapping for preventing propagation. |
| **Sticky headers** | `06-utilities-and-other-primitives.md` | `Fixed` primitive handles "transform compensation" — keeping elements fixed even when ancestors move. |
| **Two-level state machine** | `02-sheet-system-architecture.md` | `safeToUnmount` lifecycle — keeps View mounted during exit animation until "safe-to-unmount". |
| **Interactive carve-outs** | `04-overlay-focus-and-inert-system.md` | `Island` — regions that stay interactive even when everything else is `inert`. |
| **Platform quirks** | `03-scroll-and-gesture-trapping.md` | Android non-standalone vs iOS Safari scroll/gesture differences. |
| **Animation patterns** | `05-animations-and-recipes.md` | Progress-driven `travelAnimation` syntax; spring presets; persistent WAAPI. |

---

## Quick patterns to steal

### 1. Safe-to-unmount lifecycle
```tsx
// Don't unmount until exit animation completes
const [open, setOpen] = useState(false);
const [safeToUnmount, setSafeToUnmount] = useState(true);

// Render if open OR animation still running
{(open || !safeToUnmount) && <EntityDetail />}
```

### 2. WAAPI with persistent styles
```tsx
function animateAndPersist(el, keyframes, options) {
  const anim = el.animate(keyframes, { ...options, fill: "forwards" });
  anim.onfinish = () => {
    anim.commitStyles();
    anim.cancel();
  };
}
```

### 3. Progress-driven styles
```tsx
function applyProgressStyles(el, progress, declarations) {
  for (const [prop, value] of Object.entries(declarations)) {
    if (Array.isArray(value)) {
      const [start, end] = value;
      el.style[prop] = `calc(${start} + (${end} - ${start}) * ${progress})`;
    } else if (typeof value === 'function') {
      el.style[prop] = value({ progress, tween });
    }
  }
}
```

---

## Archive

The original granular 00–12 file set is preserved in `web/reference/silkhq/archive/`.
Prefer the consolidated docs unless you’re comparing historical phrasing.
