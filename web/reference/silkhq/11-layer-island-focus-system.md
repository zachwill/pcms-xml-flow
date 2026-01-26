# 11 - Layer/Island/Focus system (inert-outside + click-outside + escape)

This is the hidden subsystem that makes Sheets behave like real overlays.

Primary source: `node_modules/@silk-hq/components/dist/module.mjs` (global registry object, exported as `eG` internally).

## Core concepts

### Layer

A "layer" is an active overlay surface (typically a presented Sheet.View).

A layer record stores (observed fields):
- `layerId` (sheet id)
- `layerContextId` (custom Sheet context id)
- `layerStackContextId` (stack context id)
- `viewElement`, `backdropElement`, `scrollContainerElement`
- `inertOutside` flag
- focus management:
  - `elementFocusedLastBeforeShowing`
  - `focusWasInside` (computed on removal)
- dismissal policy:
  - `dismissOverlayIfNotAlertDialog`
  - `onClickOutside`
  - `onEscapeKeyDown`
- auto-focus policy:
  - `onPresentAutoFocus`
  - `onDismissAutoFocus`
- `external` flag (used to change scheduling; see below)

Layers are added/updated via `updateLayer(layerLike)` and removed via `removeLayer(layerId)`.

### Island

An "island" is a region that should stay interactive even when layers set `inertOutside=true`.

- created by the `Island` component
- registry assigns an incremental numeric `id`

### AutoFocusTarget

A focus target that can be used by the focus management routines during present/dismiss.

Stored as `{ layerId: "any" | sheetId, element, timing }`.

## Change processing strategy

Registry tracks deltas:

- `layersJustAdded`
- `layersJustRemoved`
- `layersJustWentToInertOutsideTrue`
- `islandsJustRemoved`

On each change, it calls `processLayersAndIslandsChanges()`.

Scheduling detail:
- If the most recently added layer is marked `external`, it processes immediately.
- Otherwise it batches via `setTimeout(..., 16)`.

This is a deliberate "post-frame" stabilization step.

## What `processLayersAndIslandsChanges()` does (conceptually)

Although the function body is large, the intent is clear from call sites and stored cleanup handles:

- Establish or update global event listeners:
  - Escape key down listener
  - Click-outside listener

- Apply / remove inertness outside the top layer(s):
  - likely uses the `inert` attribute where available, plus fallbacks.

- Restore focus appropriately when layers are removed:
  - uses `elementFocusedLastBeforeShowing`
  - uses `focusWasInside` to decide whether to restore

- Coordinate with Islands:
  - islands should be excluded from "make everything inert" sweeps.

## Interaction with ExternalOverlay

External overlays are represented as "layers" with `external=true`.

Why it matters:
- External overlays are not controlled by Silk's own state machines.
- So Silk processes layer changes immediately (no 16ms delay) to reduce conflicts.

ExternalOverlay's `selfManagedInertOutside=true` is intended to disable Silk's inert-outside to avoid double-inert.

## Native focus scroll prevention (iOS)

The registry maintains:
- `nativeFocusScrollPreventers[]`

When non-empty (and on iOS/iPadOS + in browser):
- it installs a special focus scroll prevention cleanup (`e$()` internally).

When empty:
- it removes that prevention.

This is used by:
- `Sheet.View nativeFocusScrollPrevention={true}` (default)
- `Scroll.View nativeFocusScrollPrevention={true}` (default)

The intent:
- prevent Safari from scrolling focused inputs into weird positions during overlay animations.

## Rewrite implications

If you rewrite Silk, isolate this subsystem.

You need a single authoritative manager for:
- which overlay is "topmost"
- how outside interaction is blocked
- how escape/click-outside routing works across nested overlays
- focus restoration and focus targets
- carve-outs (islands)

Treat it as an independent package-level service, not logic embedded in each component.

## Inert implementation details

The inert-outside mechanism works by:

1. **DOM traversal**: On layer change, walk the DOM from `document.body`
2. **Exclusion**: Skip the topmost layer's elements and any registered Islands
3. **Apply inert**: Set `inert` attribute on siblings/ancestors outside the layer
4. **Cleanup on removal**: Remove `inert` when layer is dismissed

Fallback considerations:
- Older browsers without `inert` support may need `aria-hidden="true"` + `tabindex="-1"` on focusable elements
- Current Silk appears to rely on native `inert` support

## Escape key routing

When Escape is pressed:

1. Registry's global `keydown` listener fires
2. Find topmost layer with `onEscapeKeyDown` policy
3. Check `stopOverlayPropagation`:
   - If `true`: only this layer handles it
   - If `false`: event bubbles to layers below
4. Check `dismiss`:
   - If `true` (and not alertdialog): trigger dismiss
5. Check `nativePreventDefault`:
   - If `true`: call `event.preventDefault()`

Default policies:
- `dialog`: `{ dismiss: true, stopOverlayPropagation: true }`
- `alertdialog`: `{ dismiss: false, stopOverlayPropagation: true }`

## Click-outside routing

When a click occurs outside all layer content:

1. Registry's global `click` listener fires
2. Determine if click is inside any layer's `viewElement`, `backdropElement`, or `scrollContainerElement`
3. If outside all, check each layer top-to-bottom:
   - Apply `onClickOutside` policy
   - `stopOverlayPropagation` determines whether to continue to lower layers
4. Islands are excluded from "outside" calculation — clicks inside Islands don't trigger click-outside

The click detection must account for:
- Portal elements
- Backdrop (clicking backdrop = click outside for that layer's content)
- Fixed components with transform compensation

## Focus management flow

### On present:
1. Store `elementFocusedLastBeforeShowing` (the currently focused element)
2. Find focus target:
   - Check registered `AutoFocusTarget` for this layer
   - Fallback to first focusable element in the layer
   - Fallback to the View element itself
3. Apply `onPresentAutoFocus` policy:
   - `{ focus: true }` (default): focus the target
   - `{ focus: false }`: skip auto-focus

### On dismiss:
1. Check `focusWasInside` — was focus inside the layer before dismissal started?
2. Apply `onDismissAutoFocus` policy:
   - `{ focus: true }` (default): restore focus to `elementFocusedLastBeforeShowing`
   - `{ focus: false }`: skip focus restoration
3. Check registered `AutoFocusTarget` for timing `"onDismiss"`

## Layer ordering and z-index

Layers are logically ordered by insertion time (stack order), not by z-index.

The registry maintains insertion order, and:
- "Topmost" = most recently added
- "Covered" = any layer below the topmost

CSS z-index is expected to be handled by the consuming application's styles, but Silk's internal stacking logic (front/covered/out states) coordinates the visual order during stacking animations.
