# 04 — Sheet runtime model (state machines + travel)

This is the "actual" implementation contract as observed in `dist/module.mjs`, cross-checked against `types.d.ts`.

## High-level architecture

- `Sheet.Root` provides context and controls:
  - "presented/open" state (controlled or uncontrolled)
  - "safeToUnmount" state (keeps View mounted during exit)
  - detent control (controlled or uncontrolled)
  - stacking context integration (`SheetStack`)

- `Sheet.View` is conditionally rendered:
  - rendered when `open === true` OR `safeToUnmount === false`
  - meaning: if an exit animation is running, View stays mounted.

- `Sheet.Content` renders a fixed internal DOM skeleton:
  - scroll container
  - front/back spacers
  - wrapper around moving content
  - "detent markers" used as physical measurement anchors
  - optional left-edge "native edge swipe prevention" element

- A global runtime registry (`eG`) stores:
  - active sheets and layers
  - stacking indices
  - outlet registered animations + persisted styles
  - fixed components (for transform compensation)
  - theme-color overlays
  - focus scroll prevention hooks, etc.

## State machines

The code uses explicit state machine helpers (not Redux; it's a custom mini-state-machine system).

### Machine namespaces

Observed machine "namespaces" (from mapping + runtime):

| Machine | States | Purpose |
|---------|--------|---------|
| `openness` | `open`, `opening`, `closed`, `closing`, `stepping` | Controls presented state |
| `staging` | `none`, `pending`, `flushing-to-preparing-open`, `flushing-to-preparing-opening`, `preparing-open`, `preparing-opening`, `safe-to-unmount` | Coordinates mount/unmount timing |
| `position` | `front`, `covered`, `out` | Stacking position in SheetStack |
| `positionCoveredStatus` | `idle`, `going-down`, `going-up`, `indeterminate`, `come-back` | Sub-status when covered |
| `opennessClosedStatus` | `pending`, ... | Sub-status when closed |

The `stepping` state is entered when navigating between detents via `Sheet.Handle` or programmatic stepping.

### Key state machine events/messages

From `module.mjs`, the following messages are sent to machines:

**Openness machine:**
- `OPEN` — request to open
- `OPEN_PREPARED` — open after preparation complete
- `CLOSE` — request to close (alias: `ACTUALLY_CLOSE`)
- `STEP` — step to next detent (alias: `ACTUALLY_STEP`)
- `READY_TO_OPEN` — internal signal
- `READY_TO_CLOSE` — internal signal

**Position machine (stacking):**
- `READY_TO_GO_FRONT` — sheet should become front
- `READY_TO_GO_DOWN` — sheet is being covered by another
- `READY_TO_GO_UP` — sheet above is leaving
- `READY_TO_GO_OUT` — sheet should exit stack
- `GO_OUT` — execute exit from stack
- `GO_UP` — execute return to front
- `GO_DOWN` — execute being covered

These machines coordinate:
- entering/exiting animations
- stacking interactions
- which sheet is "front" in a stack

## Tracks + placement

User-facing props:

- `contentPlacement`: `top|bottom|left|right|center`
- `tracks`: a single track or two-track tuple

Runtime computes:

- `actualPlacement` (used for layout)
- `actualTrack` (used for travel axis)

### Resolution rules

| `contentPlacement` | `tracks` | Result |
|--------------------|----------|--------|
| absent | absent | `placement=bottom`, `track=bottom` |
| `top\|bottom\|left\|right` | absent | `track = placement` |
| `center` | absent | `track = bottom` |
| absent | single track (`top\|bottom\|left\|right`) | `placement = track` |
| absent | dual track (`["top","bottom"]` etc) | `placement = center`, track is axis-aligned |
| both provided | both provided | validated for compatibility; conflicts throw |

### Dual-track behavior

When `tracks` is a tuple like `["top", "bottom"]` or `["left", "right"]`:
- The sheet can travel from either edge.
- `contentPlacement` becomes `center`.
- The actual travel direction is determined by:
  - The `track` option in `enteringAnimation`/`exitingAnimation` settings.
  - Which edge the user swipes from.

This is an "axis-only" track: `"horizontal"` or `"vertical"` internally.

## Detents

User prop:
- `detents?: string | string[]`

Runtime normalizes to an array:
- if string: `[detents, "var(--silk-aF)"]`
- if array: `[...detents, "var(--silk-aF)"]`
- if absent: `["var(--silk-aF)"]`

The `--silk-aF` variable represents "fit content" — the sheet expands to fit its content (up to viewport limits). This is always the final detent.

`Sheet.Content` builds "detent marker" elements and assigns CSS vars per marker:

- `--silk-aA`: previous detent value (or `0px`)
- `--silk-aB`: this detent value
- `--silk-aC`: detent index

These markers are used to measure and drive scroll-snap/travel.

## Travel model (core mechanics)

Sheet travel is implemented using a scroll container + spacers + scroll snapping.

### DOM structure

`Sheet.Content` renders:
- `scrollContainer` — captures scroll/touch events
  - `frontSpacer` — spacer before content
  - `contentWrapper` — moving content container
    - `content` — your actual panel
    - `leftEdge` — only when `nativeEdgeSwipePrevention=true`
  - `backSpacer` — contains detent markers

### Scroll-to-progress mapping

- Scroll position within the scroll container maps to travel progress.
- Spacer heights/widths create the scroll range.
- Scroll snapping (`scroll-snap-type`) snaps to detent positions.

### During keyboard navigation

Explicit logic disables `overflow` and `scroll-snap-type` during keyboard navigation keys to avoid glitches.

### Pointer/touch handling

- Pointer capture is used during drag operations.
- Touch events are intercepted and processed for velocity/direction.
- Platform-specific behavior applies (see below).

## Platform detection

Runtime detects platform using `navigator.userAgentData` or `navigator.userAgent`:

```js
// From module.mjs
T = "undefined" != typeof window ? window.navigator.userAgent : null;

// userAgentData check
if (navigator.userAgentData) {
  "Android" === navigator.userAgentData.platform && (A = "android");
}
```

Standalone mode detection:
```js
window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone
```

### Android-specific behavior

On Android in non-standalone mode:
- Swipe trapping on the Y axis tends to be disabled to allow browser UI reveal.
- This prevents conflicting with the browser's pull-to-refresh or address bar reveal.

## Presented/unpresented state

From `Sheet.Root`:

- `defaultPresented` initializes open state.
- `presented` + `onPresentedChange` makes it controlled.

Important implementation detail:
- `defaultPresented: true` does **not** show immediately on SSR; it becomes presented after hydration.

## `safeToUnmount` lifecycle

`Sheet.Root` stores:
- `safeToUnmount` boolean

`Sheet.View` mount condition:
- mount if open OR not safeToUnmount

The staging machine controls this:
- When staging reaches `"safe-to-unmount"` state → `safeToUnmount = true`
- This is the mechanism that lets exit animations complete without you manually delaying unmount

Meaning:
- when dismissing, `open` becomes false early
- but View stays mounted until the internal staging machine reaches "safe-to-unmount"

Note: The types also expose `open` + `onOpenChange` as aliases for `presented` + `onPresentedChange`.

## Swipe configuration

### Key props

| Prop | Type | Description |
|------|------|-------------|
| `swipe` | `boolean \| "auto"` | Enable/disable swipe gestures |
| `swipeTrap` | `boolean \| "auto"` | Prevent scroll propagation during swipe |
| `swipeOvershoot` | `boolean` | Allow overscroll bounce at edges |
| `swipeDismissal` | `boolean` | Allow swipe to dismiss |

### Computed behavior

Runtime has platform-specific behavior:

**Android (non-standalone mode):**
- When `swipeTrap="auto"`, Y-axis trapping is disabled
- This prevents conflicting with browser pull-to-refresh and address bar reveal
- X-axis swipe trapping follows normal rules

**iOS / Desktop / Standalone:**
- `swipeTrap="auto"` generally enables trapping based on content overflow

Other computed rules:
- When `inertOutside=true`, `swipeTrap` effectively computes to true (you can't both inert-outside and allow swipe propagation).
- When `swipeOvershoot=false`, swipe trapping on travel axis is forced true (no overscroll bounce => prevent propagation).

## Inert-outside and overlay dismissal

- `inertOutside` defaults true.
- When true, Silk prevents interaction with content outside the sheet.

### Click outside and Escape handling

Default behavior varies by role:

| Role | Click outside dismisses | Escape dismisses |
|------|------------------------|------------------|
| `dialog` | yes | yes |
| `alertdialog` | no | no |

Props to customize:
- `onClickOutside`: handler or options object `{ dismiss?, stopOverlayPropagation? }`
- `onEscapeKeyDown`: handler or options object `{ nativePreventDefault?, dismiss?, stopOverlayPropagation? }`

There is explicit infrastructure for:
- "ExternalOverlay" integration (see `08-other-primitives.md`)
- "Island" regions that remain interactive even when inertOutside is on

## "Native edge swipe prevention" (iOS)

When `nativeEdgeSwipePrevention=true`, `Sheet.Content` includes a left-edge element.

Doc note (from types):
- it blocks interaction in a ~28px strip unless you lift your own elements above it.

Runtime note:
- it also intercepts click-outside, which can affect dismissal.

## Keyboard handling

The examples demonstrate keyboard dismissal patterns:

```tsx
const travelHandler = useMemo(() => {
  if (!reachedLastDetent) return onTravel;

  return ({ progress, ...rest }) => {
    if (progress < 0.999) {
      viewRef.current.focus();  // Blur inputs, dismiss on-screen keyboard
    }
    onTravel?.({ progress, ...rest });
  };
}, [reachedLastDetent, onTravel, viewRef]);
```

Focusing the View element causes input blur, which dismisses mobile keyboards.

## Stacking integration

When `Sheet.Root forComponent="closest"`:
- the sheet registers itself with the nearest `SheetStack`.

Runtime coordinates "front/covered/out" states and stacking index changes via:
- `updateSheetStackingIndex`
- `getPreviousSheetDataInStack`
- position machine transitions like `READY_TO_GO_FRONT`, `GO_OUT`, `GO_UP`, etc.

Practical implication:
- stacking is not a simple z-index: it's a stateful multi-sheet choreography.
