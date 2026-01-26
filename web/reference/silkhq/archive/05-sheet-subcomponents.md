# 05 — Sheet subcomponents (responsibilities + gotchas)

This file describes what each subcomponent does in runtime.

Primary sources:
- `dist/types.d.ts` for the *declared API*
- `dist/module.mjs` for the *actual behavior*

## `<Sheet.Root>`

Responsibilities:
- Validates that Silk CSS is loaded (warns if `--silk-aY !== "1"`).
- Provides context for subcomponents (including nested sheets).
- Owns open/presented state:
  - uncontrolled: `defaultPresented`
  - controlled: `presented` + `onPresentedChange`
- Owns detent state:
  - uncontrolled: `defaultActiveDetent`
  - controlled: `activeDetent` + `onActiveDetentChange`
- Owns `safeToUnmount` lifecycle (via internal staging machine).

Notable runtime details:
- `forComponent="closest"` on Root means "associate with closest SheetStack".
- Root renders an `Outlet` internally for its own underlying element.

## `<Sheet.Portal>`

Implementation:
- client-only portal wrapper (uses local state set in `useEffect` to avoid SSR mismatch).

Default container:
- `document.body`.

## `<Sheet.View>`

Responsibilities:
- The "viewport" in which Content travels.
- Holds the `role` (dialog/alertdialog/etc).
- Handles:
  - inert-outside
  - click-outside, escape
  - focus management
  - swipe travel logic
  - stacking choreography

Mounting behavior (runtime):
- only rendered when:
  - sheet is open, OR
  - sheet is not safe to unmount (exit animation running)

### Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `role` | `"dialog" \| "alertdialog" \| ...` | `"dialog"` | ARIA role |
| `contentPlacement` | `"top" \| "bottom" \| "left" \| "right" \| "center"` | `"bottom"` | Where content appears |
| `tracks` | `Track \| [Track, Track]` | derived | Travel direction(s) |
| `swipe` | `boolean \| "auto"` | `"auto"` | Enable/disable swipe |
| `swipeTrap` | `boolean \| "auto"` | `"auto"` | Prevent scroll propagation |
| `swipeOvershoot` | `boolean` | `true` | Allow overscroll bounce |
| `swipeDismissal` | `boolean` | `true` | Allow swipe to dismiss |
| `inertOutside` | `boolean` | `true` | Prevent interaction outside |
| `nativeEdgeSwipePrevention` | `boolean` | `false` | Block iOS edge swipe (left ~28px) |
| `enteringAnimationSettings` | `EnteringAnimationSettings` | `"gentle"` | Enter animation config |
| `exitingAnimationSettings` | `ExitingAnimationSettings` | `"gentle"` | Exit animation config |
| `steppingAnimationSettings` | `SteppingAnimationSettings` | `"gentle"` | Detent stepping config |

### Event handlers

| Handler | Signature | Description |
|---------|-----------|-------------|
| `onTravelStatusChange` | `(status: TravelStatus) => void` | Fires when travel status changes |
| `onTravelRangeChange` | `(range: { start: number, end: number }) => void` | Fires when detent range changes |
| `onTravel` | `({ progress, range, progressAtDetents }) => void \| (() => void)` | Fires continuously during travel; can return cleanup |
| `onTravelStart` | `() => void` | Fires before first `onTravel` |
| `onTravelEnd` | `() => void` | Fires before last `onTravel` |
| `onClickOutside` | handler or `{ dismiss?, stopOverlayPropagation? }` | Click outside behavior |
| `onEscapeKeyDown` | handler or `{ dismiss?, stopOverlayPropagation?, nativePreventDefault? }` | Escape key behavior |

### TravelStatus values

```ts
type TravelStatus = "entering" | "idleInside" | "stepping" | "exiting" | "idleOutside";
```

## `<Sheet.Content>`

This is the most structurally constrained component.

It **does not** just render a div.

### Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `detents` | `string \| string[]` | `["var(--silk-aF)"]` | Snap points (CSS values) |
| `stackingAnimation` | `StackingAnimationPropValue` | - | Animation when covered by sheets |

Note: `nativeEdgeSwipePrevention` is on `Sheet.View`, not Content.

Runtime renders a fixed internal skeleton:

```
scrollContainer
├── frontSpacer
├── contentWrapper
│   ├── content (your actual panel)
│   └── leftEdge (only when nativeEdgeSwipePrevention=true)
└── backSpacer
    └── detentMarker[] (one per detent)
```

### Detent markers

Each marker gets inline style CSS vars:
- `--silk-aA` previous detent
- `--silk-aB` current detent
- `--silk-aC` index

### Implications for a rewrite

- This DOM is part of the library's internal mechanics.
- CSS and runtime both assume it exists.
- The scroll container handles travel via scroll position.

## `<Sheet.Backdrop>`

Responsibilities:
- blocks interaction with content behind
- optionally swipeable
- can participate in travel/stacking animations

### Props

| Prop | Default | Description |
|------|---------|-------------|
| `swipeable` | `false` | Whether backdrop responds to swipe |
| `themeColorDimming` | `"none"` | `"auto"` enables theme-color integration |
| `travelAnimation` | - | Animation driven by sheet travel |
| `stackingAnimation` | - | Animation driven by stacking |

### Theme-color dimming

When `themeColorDimming="auto"`, runtime may:
- register a dimming overlay that adjusts `<meta name="theme-color">`
- take over backdrop opacity management (inline updates)

## `<Sheet.Trigger>`

Responsibilities:
- a button that can:
  - present
  - dismiss
  - step detents

### Props

| Prop | Default | Description |
|------|---------|-------------|
| `action` | `"present"` | `"present"`, `"dismiss"`, or `"step"` |

### Runtime details

- Has a custom `onPress` abstraction that can:
  - force focus (Safari compatibility)
  - optionally prevent default action execution
- For `action="present"`, it stores the last focused element to restore focus later.
- For `action="step"`, it sends a `STEP` message to the openness machine.

### ARIA

- If `sheetRole` is dialog/alertdialog and action is present:
  - sets `aria-haspopup="dialog"`
- Sets `aria-controls` to the internal sheet id.
- Sets `aria-expanded` for present/dismiss actions.

## `<Sheet.Handle>`

Built on top of `<Sheet.Trigger>`.

Defaults:
- default `action="step"`.

### Stepping behavior

When action is `step`:
- Cycles forward through detents (detent 0 → 1 → 2 → ...)
- At the last detent: **dismisses the sheet** (does not wrap to first detent)
- If only one detent exists and action is not `dismiss`, the handle is disabled (no stepping possible)

Runtime detail:
- Sends `STEP` message to the openness machine
- The openness machine transitions to `stepping` state during the animation

## `<Sheet.Outlet>`

This is the core primitive for "things that animate with travel/stacking".

Responsibilities:
- Registers itself with the global registry as an outlet tied to a sheet.
- Registers travel/stacking animations in the registry.
- Computes and applies inline styles for travel/stacking animations.
- Applies a magic data-silk token (`0aj`) when staging is not none.

### Props

| Prop | Description |
|------|-------------|
| `travelAnimation` | Declarative animation driven by travel progress |
| `stackingAnimation` | Declarative animation driven by stacking progress |

Usage pattern:
- Many Sheet subcomponents are actually implemented as an Outlet around a semantic tag.

## `<Sheet.BleedingBackground>`

Purpose:
- provides a background that can "bleed" under rounded corners / edges.

### Runtime behavior

- sets a context flag `bleedingBackgroundPresent` on mount.
- disables "bleed" when track is axis-only (`horizontal`/`vertical`) via a `bleedDisabled` variation.

### When bleed is disabled

Bleed is disabled when:
- `tracks` is a dual-track tuple (e.g., `["top", "bottom"]`)
- The resolved track is `"horizontal"` or `"vertical"` (axis-only)

Note: Even with bleed enabled, if the content fills the entire sheet area, the bleeding background has no visible effect (there's no gap to bleed into).

## `<Sheet.SpecialWrapper>`

Actually implemented using the internal `ScrollTrap` primitive.

Purpose (from types + examples):
- wrap interactive content in a way that avoids scroll/gesture conflicts with the sheet.

### Structure

```tsx
<Sheet.SpecialWrapper.Root>
  <Sheet.SpecialWrapper.Content>
    {/* Your interactive content */}
  </Sheet.SpecialWrapper.Content>
</Sheet.SpecialWrapper.Root>
```

In examples:
- used in Toast so inner content remains interactive while sheet mechanics run.

## `<Sheet.Title>` and `<Sheet.Description>`

Implementation:
- Render semantic tags (`h2` and `p` by default)
- Wrapped in `Sheet.Outlet` so they can be animated.
- Assign IDs into context for aria labeling.

Props:
- Standard HTML attributes for the underlying element
- `asChild` to use your own element
- `travelAnimation` / `stackingAnimation` inherited from Outlet

## Internal-only subcomponents

The mapping shows these element names which are used internally but not exported:

| Element | Purpose |
|---------|---------|
| `stickyContainer` | Container for sticky elements within sheet |
| `sticky` | Sticky-positioned element |
| `backdropTrap` | Scroll trap for backdrop |
| `primaryScrollTrapRoot` | Primary scroll trap |
| `secondaryScrollTrapRoot` | Secondary scroll trap |

These are implementation details; you cannot use them directly.

## `asChild` behavior (applies to most subcomponents)

Contract:
- if `asChild=true`, Silk renders your child element instead of its default element.

Runtime expectation:
- the child must forward props (and refs in React <19).

This is a "Radix Slot" style pattern.

### Example

```tsx
<Sheet.Trigger asChild>
  <button className="my-custom-button">Open Sheet</button>
</Sheet.Trigger>
```

The `button` receives all props that `Sheet.Trigger` would have applied to its default element.

## Common ref forwarding pattern

When combining refs (e.g., your ref + context ref), use a callback pattern:

```tsx
const setRefs = React.useCallback((node: HTMLElement | null) => {
  // Set context ref
  contextRef.current = node;

  // Forward to user ref
  if (typeof ref === "function") {
    ref(node);
  } else if (ref) {
    ref.current = node;
  }
}, [ref]);

return <Sheet.View ref={setRefs} />;
```

This pattern appears frequently in the example components.

Note: React 19+ allows function components to accept `ref` as a regular prop without `forwardRef`. The examples in this repo still use `forwardRef` for broader compatibility.
