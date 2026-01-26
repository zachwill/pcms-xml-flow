# Silk (@silk-hq/components) — Reference Knowledge Map

Reverse-engineered specs for the Silk UI primitives library (v0.9.12). These docs contain **tacit knowledge about scroll-driven UIs, state machines, and gesture handling** that's relevant to the Salary Book even if we don't use Silk directly.

---

## How to use this reference

The Salary Book is scroll-driven (`web/specs/01-salary-book.md`). Silk solves similar problems:

- Scroll position → UI state
- Sticky/fixed positioning during transforms
- Two-level navigation (base + overlay)
- Gesture trapping and platform quirks
- Focus management with interactive carve-outs

**Use these docs to steal patterns**, not necessarily the library.

---

## Knowledge map by Salary Book concern

### Scroll-spy / scroll-driven context

**Salary Book need:** Active team determined by scroll position; sidebar reflects viewport.

**Where to look:**

| Doc | What's there |
|-----|--------------|
| `07-scroll-and-scrolltrap.md` | Scroll-to-progress mapping, `scrollGestureTrap` for preventing propagation, `onScroll`/`onScrollStart`/`onScrollEnd` patterns |
| `04-sheet-runtime-model.md` | How Silk maps scroll position → travel progress (0-1); spacer elements create scroll range |
| `09-hooks-and-utilities.md` | `usePageScrollData()` — detecting scroll container + replacement state |

**Key insight:** Silk uses scroll containers + spacers + scroll-snap for its "travel" model. The scroll position *is* the state. This is the same mental model as our scroll-spy.

---

### Sticky headers (iOS Contacts pattern)

**Salary Book need:** Team header + table header stick together, pushed off by next team.

**Where to look:**

| Doc | What's there |
|-----|--------------|
| `08-other-primitives.md` | `Fixed` primitive — preserves visual position even when ancestors are transformed; exposes CSS vars for scrollbar thickness |
| `05-sheet-subcomponents.md` | `stickyContainer` / `sticky` internal elements (not exported, but show the pattern) |
| `12-reference.md` | CSS custom properties for positioning (`--silk-fixed-side`, etc.) |

**Key insight:** Silk's `Fixed` component handles "transform compensation" — keeping elements visually fixed even when parent outlets are being animated. Useful if we ever animate the main canvas.

---

### Two-level sidebar state machine

**Salary Book need:** Base state (team context from scroll) + single overlay (entity detail). Back returns to current viewport team.

**Where to look:**

| Doc | What's there |
|-----|--------------|
| `04-sheet-runtime-model.md` | State machines: `openness` (open/opening/closed/closing), `staging` (coordinates mount/unmount), `position` (front/covered/out) |
| `04-sheet-runtime-model.md` | `safeToUnmount` lifecycle — View stays mounted during exit animation until staging reaches "safe-to-unmount" |
| `06-sheetstack.md` | Stacking as a state machine, not z-index; "front/covered/out" choreography |

**Key insight:** Silk separates "open" from "safe to unmount". When dismissing, `open` becomes false immediately but View stays mounted until exit animation completes. This pattern avoids the "content disappears before animation finishes" bug.

**For Salary Book:** Our 2-level model is simpler (no stacking), but the "base updates silently while overlay is open" pattern is the same. The staging machine concept could inform how we handle entity transitions.

---

### Focus management + interactive carve-outs

**Salary Book need:** Main canvas stays interactive while entity detail is shown; clicking a row should select entity, not "dismiss" anything.

**Where to look:**

| Doc | What's there |
|-----|--------------|
| `11-layer-island-focus-system.md` | The entire layer/island/focus subsystem — how Silk tracks "topmost" overlay, carves out interactive regions, handles escape/click-outside |
| `08-other-primitives.md` | `Island` — regions that stay interactive even with `inertOutside=true`; `ExternalOverlay` — coordinating with non-Silk overlays |
| `05-sheet-subcomponents.md` | `onClickOutside`, `onEscapeKeyDown` — configurable dismiss policies |

**Key insight:** Silk's `Island` concept is powerful: mark a region as "stays interactive" regardless of overlay state. If we ever add true overlays, this pattern prevents the "can't click the nav while modal is open" problem.

**For Salary Book:** We don't use `inertOutside` (our sidebar is non-modal), but the `Island` concept could apply if we add modals later.

---

### Platform-specific scroll/gesture behavior

**Salary Book need:** Works well on mobile Safari/Chrome; doesn't fight with browser gestures.

**Where to look:**

| Doc | What's there |
|-----|--------------|
| `12-reference.md` | Platform detection methods, iOS vs Android behavior differences |
| `07-scroll-and-scrolltrap.md` | `scrollGestureTrap` — preventing scroll propagation at edges; iOS `overscroll-behavior` workarounds |
| `04-sheet-runtime-model.md` | `nativeEdgeSwipePrevention` — the 28px left-edge blocker for iOS back gesture |

**Key insight:** Android non-standalone mode disables Y-axis swipe trapping to allow browser UI (address bar) reveal. iOS needs explicit edge-swipe blocking. These are the kinds of platform quirks that bite you in production.

**Relevant quote from `07`:**
> If you're rewriting: treat "trap swipe to prevent back navigation" as a dedicated subsystem, not an incidental side effect.

---

### Animation patterns

**Salary Book need:** Smooth transitions for entity detail push/pop; possibly scroll-linked header effects.

**Where to look:**

| Doc | What's there |
|-----|--------------|
| `03-animation-system.md` | `travelAnimation` / `stackingAnimation` — declarative animations driven by progress value; spring physics; the `tween()` helper |
| `09-hooks-and-utilities.md` | `animate()` — WAAPI wrapper that **persists final styles** (calls `commitStyles()` then `cancel()`) |
| `12-reference.md` | Spring presets (`gentle`, `snappy`, `bouncy`, etc.); CSS easing configs |

**Key insight:** Silk's `animate()` utility solves a common WAAPI annoyance: styles revert after animation ends. Their pattern: `element.animate()` → `onfinish: commitStyles() + cancel()`. Steal this.

**For scroll-linked animations:** The `travelAnimation` syntax (`({ progress, tween }) => ...`) is a clean pattern for progress-driven styles.

---

### Detents and snap points

**Salary Book need:** Probably not directly, but could inform expandable sections or "peek" states.

**Where to look:**

| Doc | What's there |
|-----|--------------|
| `04-sheet-runtime-model.md` | Detent system — snap points defined as CSS values, normalized to array with "fit content" as final detent |
| `10-examples-in-this-repo.md` | `SheetWithDetent` — progressive disclosure pattern; scroll disabled until expanded |

**Key insight:** Detents are implemented as scroll-snap points with marker elements. Each marker gets CSS vars (`--silk-aA`, `--silk-aB`, `--silk-aC`) for previous/current/index. This is a clever way to make snap points measurable.

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
      el.style[prop] = value({ progress });
    }
  }
}
```

---

## Full docs index

| File | Content |
|------|---------|
| `00-index.md` | Overview + reading order |
| `01-codebase-map.md` | Package structure, key files |
| `02-data-silk-and-css-contract.md` | Token system, CSS selectors |
| `03-animation-system.md` | Travel/stacking animations, springs, WAAPI |
| `04-sheet-runtime-model.md` | **State machines, travel mechanics, detents** |
| `05-sheet-subcomponents.md` | All Sheet.* components and props |
| `06-sheetstack.md` | Stacking orchestration |
| `07-scroll-and-scrolltrap.md` | **Scroll primitive, gesture trapping** |
| `08-other-primitives.md` | Fixed, Island, ExternalOverlay |
| `09-hooks-and-utilities.md` | Exported hooks/utilities |
| `10-examples-in-this-repo.md` | Composition patterns |
| `11-layer-island-focus-system.md` | **Inert-outside + focus management** |
| `12-reference.md` | CSS tokens, platform quirks, animation settings |
