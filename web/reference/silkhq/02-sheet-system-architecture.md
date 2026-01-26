# Sheet system architecture (travel + state machines + subcomponents + stacking)

This document is the “how Sheets actually work” spec, synthesized from runtime (`module.mjs`) + types + default CSS.

---

## High-level architecture

- `Sheet.Root` provides context and controls:
  - presented/open state (controlled or uncontrolled)
  - active detent (controlled or uncontrolled)
  - `safeToUnmount` lifecycle (exit animations keep View mounted)
  - optional SheetStack association

- `Sheet.View` is conditionally rendered:
  - rendered when `open === true` **OR** `safeToUnmount === false`
  - meaning: exit animations can run while the sheet is logically closed

- `Sheet.Content` renders a fixed internal DOM skeleton that enables scroll-driven travel:
  - scroll container
  - spacer elements
  - content wrapper
  - detent markers
  - optional left-edge element for iOS back-swipe prevention

- A global runtime registry (internally named `eG`) stores:
  - active layers (for inertOutside/focus)
  - stacking indices and sheet ordering
  - outlet animations + persisted inline styles
  - fixed component registrations (transform compensation)
  - theme-color dimming overlays
  - iOS focus scroll prevention handles

---

## Core idea: travel is scroll

Silk implements presentation/dismissal (“travel”) using:

- a scroll container inside `Sheet.Content`
- spacers to create scroll range
- scroll snapping to detents

So: **scroll position is the source of truth** for the Sheet’s progress.

---

## State machines

Runtime uses custom state machine helpers.

Observed machines:

| Machine | States (observed) | Purpose |
|---------|-------------------|---------|
| `openness` | `open`, `opening`, `closed`, `closing`, `stepping` | presented/open state and transitions |
| `staging` | `none`, `pending`, `flushing-to-preparing-open`, `flushing-to-preparing-opening`, `preparing-open`, `preparing-opening`, `safe-to-unmount` | mount/unmount coordination (drives `safeToUnmount`) |
| `position` | `front`, `covered`, `out` | stacking position in a `SheetStack` |
| `positionCoveredStatus` | `idle`, `going-down`, `going-up`, `indeterminate`, `come-back` | sub-status while covered |
| `opennessClosedStatus` | `pending`, … | sub-status while closed |

Key messages/events (observed):

- Openness: `OPEN`, `OPEN_PREPARED`, `CLOSE`/`ACTUALLY_CLOSE`, `STEP`/`ACTUALLY_STEP`, `READY_TO_OPEN`, `READY_TO_CLOSE`
- Position: `READY_TO_GO_FRONT`, `READY_TO_GO_DOWN`, `READY_TO_GO_UP`, `READY_TO_GO_OUT`, `GO_OUT`, `GO_UP`, `GO_DOWN`

---

## Tracks + placement

User-facing props:

- `contentPlacement`: `top | bottom | left | right | center`
- `tracks`: a single track or a tuple `[trackA, trackB]`

Runtime computes:

- `actualPlacement` (layout)
- `actualTrack` (travel direction)

Resolution rules (practical):

| `contentPlacement` | `tracks` | Result |
|--------------------|----------|--------|
| absent | absent | placement=bottom, track=bottom |
| `top|bottom|left|right` | absent | track = placement |
| `center` | absent | track = bottom |
| absent | single track | placement = track |
| absent | dual track tuple | placement = center, track becomes axis-only |
| both provided | both provided | validated; conflicts throw |

### Dual-track behavior

When `tracks` is a tuple like `['top','bottom']` or `['left','right']`:

- sheet can travel from either edge
- placement becomes `center`
- entering/exiting settings can override which edge is used via `{ track }`

Internally, track can become axis-only (`horizontal`/`vertical`) for some computations.

---

## Detents

Prop:

- `detents?: string | string[]`

Normalization:

- string → `[detents, 'var(--silk-aF)']`
- array → `[...detents, 'var(--silk-aF)']`
- absent → `['var(--silk-aF)']`

Meaning:

- `--silk-aF` is a “fit content / fully expanded” sentinel and is always appended.

### Detent markers + CSS vars

`Sheet.Content` creates marker elements for each detent with inline vars:

- `--silk-aA`: previous detent (or `0px`)
- `--silk-aB`: current detent
- `--silk-aC`: detent index

These act as measurement anchors for the scroll-snap/travel model.

---

## Travel model (DOM + mapping)

### Internal DOM skeleton (important)

`Sheet.Content` does **not** render a single wrapper; it renders a constrained skeleton:

```
scrollContainer
├── frontSpacer
├── contentWrapper
│   ├── content (your panel)
│   └── leftEdge (only when nativeEdgeSwipePrevention=true)
└── backSpacer
    └── detentMarker[]
```

### Scroll-to-progress mapping

- scroll position within `scrollContainer` maps to travel progress
- spacers determine scroll range
- scroll-snap snaps to detent marker positions

### Keyboard navigation guard

Runtime disables `overflow` and `scroll-snap-type` during certain keyboard navigation operations to avoid scroll-snap glitches.

---

## Presented state vs `safeToUnmount`

Silk separates:

- “presented/open” state
- “safe to remove from DOM” state

`Sheet.View` is mounted when:

- `open === true` OR `safeToUnmount === false`

`safeToUnmount` is controlled by the **staging** machine:

- when staging reaches `safe-to-unmount` → `safeToUnmount = true`

This is the core “don’t unmount until exit animation completes” behavior.

Implementation detail:

- `defaultPresented: true` doesn’t show immediately on SSR; it presents after hydration.

---

## Swipe configuration

Key props:

| Prop | Type | Meaning |
|------|------|---------|
| `swipe` | `boolean | 'auto'` | enable/disable swipe travel |
| `swipeTrap` | `boolean | 'auto'` | prevent propagation during swipe |
| `swipeOvershoot` | `boolean` | allow edge bounce |
| `swipeDismissal` | `boolean` | allow swipe-to-dismiss |

Computed behavior (high-signal):

- **Android (non-standalone)**: `swipeTrap='auto'` tends to disable Y-axis trapping (avoid fighting address bar reveal / pull-to-refresh)
- **iOS/desktop/standalone**: `swipeTrap='auto'` usually traps based on overflow rules
- if `inertOutside=true`, swipeTrap effectively computes true (you can’t both inert-outside and allow propagation)
- if `swipeOvershoot=false`, trapping on the travel axis is forced true (no bounce → don’t propagate)

---

## Overlay dismissal policy (dialog vs alertdialog)

Defaults differ by role:

| Role | Click outside dismisses | Escape dismisses |
|------|-------------------------|-----------------|
| `dialog` | yes | yes |
| `alertdialog` | no | no |

Customization props (shape):

- `onClickOutside`: handler or `{ dismiss?, stopOverlayPropagation? }`
- `onEscapeKeyDown`: handler or `{ dismiss?, stopOverlayPropagation?, nativePreventDefault? }`

Implementation detail:

- these behaviors are coordinated by the global layer manager described in `04-overlay-focus-and-inert-system.md`.

---

## Platform detection (behavior branches)

Runtime detects platform via `navigator.userAgentData` when available, else `navigator.userAgent`.

Standalone mode detection:

- `matchMedia('(display-mode: standalone)').matches` or `navigator.standalone`

iOS-specific note:

- iOS Safari requires additional focus scroll prevention and has overscroll quirks.

---

## Native edge swipe prevention (iOS)

When `nativeEdgeSwipePrevention=true`:

- `Sheet.Content` includes a left-edge element (~28px) to block iOS back-swipe gesture

Gotcha:

- this element can intercept click-outside, affecting dismissal unless you account for it in structure/z-index.

---

## Keyboard dismissal trick (from examples)

Common technique:

- during travel, if progress drops below ~1, focus the View element to blur inputs
- this dismisses mobile on-screen keyboards

---

## Subcomponents: responsibilities (public surface)

### `<Sheet.Root>`

Responsibilities:

- context provider
- controlled/uncontrolled presented state (`defaultPresented` vs `presented` + callback)
- controlled/uncontrolled detent state
- staging machine + `safeToUnmount`
- dev CSS presence check (`--silk-aY === '1'`)

Notable:

- `forComponent='closest'` associates with nearest `SheetStack`

### `<Sheet.Portal>`

- client-only portal wrapper (avoids SSR mismatch)
- default container: `document.body`

### `<Sheet.View>`

The main overlay viewport.

Key props (declared defaults):

| Prop | Default |
|------|---------|
| `role` | `dialog` |
| `contentPlacement` | `bottom` |
| `swipe` | `auto` |
| `swipeTrap` | `auto` |
| `swipeOvershoot` | `true` |
| `swipeDismissal` | `true` |
| `inertOutside` | `true` |
| `nativeEdgeSwipePrevention` | `false` |
| entering/exiting/stepping settings | `gentle` (or preset-based) |

Travel events:

- `onTravelStatusChange(status)`
- `onTravelRangeChange({ start, end })`
- `onTravel(...)` (can return cleanup)
- `onTravelStart()` / `onTravelEnd()`

`TravelStatus` values:

```ts
type TravelStatus = 'entering' | 'idleInside' | 'stepping' | 'exiting' | 'idleOutside';
```

### `<Sheet.Content>`

Props:

- `detents?: string | string[]`
- `stackingAnimation?: StackingAnimationPropValue`

Most important contract: renders internal skeleton used by travel.

### `<Sheet.Backdrop>`

Props:

- `swipeable?: boolean` (default false)
- `themeColorDimming?: 'none' | 'auto'`
- `travelAnimation?`, `stackingAnimation?`

Theme-color dimming integration is described in `05-animations-and-recipes.md` and `06-utilities-and-other-primitives.md`.

### `<Sheet.Trigger>`

- pressable that can `present`, `dismiss`, or `step`
- tracks “last focused element” for restoration on dismiss
- sets ARIA attributes (`aria-controls`, `aria-expanded`, `aria-haspopup`)
- uses custom `onPress` to force focus (Safari compatibility) and optionally prevent default behavior

### `<Sheet.Handle>`

- built on Trigger; defaults to stepping
- stepping cycles detents; at last detent it dismisses (does not wrap)
- if only one detent exists and action is not `dismiss`, the handle is disabled

### `<Sheet.Outlet>`

- registers travel/stacking animation declarations in the runtime registry
- receives inline styles as progress changes
- used to implement semantic animated elements (Title/Description/etc.)

### `<Sheet.BleedingBackground>`

- provides a background that can “bleed” under rounded corners
- disabled when track resolves to axis-only (common for dual-track center placement)

### `<Sheet.SpecialWrapper>`

- built on ScrollTrap
- isolates interactive content to avoid gesture conflicts

### `<Sheet.Title>` / `<Sheet.Description>`

- semantic tags (default `h2`, `p`)
- wrapped in an Outlet so they can animate
- register IDs for aria labeling

---

## SheetStack integration (overview)

SheetStack turns independent sheets into a coordinated push/pop stack.

- sheets register into a stack via `Sheet.Root forComponent={id}` or `forComponent='closest'`
- each sheet receives a stacking index and a `position` state (`front/covered/out`)
- stacking animations use **stacking progress** `0..n`
- the stack cleans up persisted styles when it becomes empty

More on stacking progress and animation rules: `05-animations-and-recipes.md`.
