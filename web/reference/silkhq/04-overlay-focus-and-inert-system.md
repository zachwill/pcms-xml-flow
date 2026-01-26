# Layer / Island / focus system (inertOutside + click-outside + escape)

Silk has a global overlay manager (a registry in `module.mjs`, named `eG` internally) that coordinates:

- inertOutside application
- click-outside routing
- escape key routing
- focus targeting + focus restoration
- carve-outs via Islands
- coordination with non-Silk overlays (ExternalOverlay)

This system is what makes multiple overlays behave coherently.

---

## Core concepts

### Layer

A layer is an active overlay surface (typically a presented `Sheet.View`).

Observed layer fields:

- identifiers: `layerId` (sheet id), plus context ids (nesting/stacking)
- DOM nodes: `viewElement`, `backdropElement`, `scrollContainerElement`
- overlay policy:
  - `inertOutside`
  - dismissal policy (dialog vs alertdialog)
  - `onClickOutside`
  - `onEscapeKeyDown`
- auto-focus policy:
  - `onPresentAutoFocus`
  - `onDismissAutoFocus`
- focus bookkeeping:
  - `elementFocusedLastBeforeShowing`
  - `focusWasInside` (computed on removal)
- `external` flag (ExternalOverlay)

Layers are added/updated via `updateLayer(...)` and removed via `removeLayer(layerId)`.

### Layer ordering and z-index

Layers are logically ordered by **insertion time** (stack order), not by CSS z-index.

- **Topmost**: The most recently added/updated layer.
- **Covered**: Any layer below the topmost in the registry.

CSS z-index is expected to be handled by the consuming application’s styles or by Silk’s internal stacking logic (see `02-sheet-system-architecture.md`), but the registry’s logic for focus and routing always respects the logical insertion order.

### Island

An Island is a region that should remain interactive even when layers inert everything outside.

- created by the `Island` component
- registry assigns it an incremental numeric id
- can be associated with specific sheets or "any" sheet (see `06-utilities-and-other-primitives.md`)

### AutoFocusTarget

A focus target used by the focus routines.

Conceptually stored as:

- `{ layerId: 'any' | sheetId, element, timing }`

---

## Change processing strategy (batching)

Registry tracks deltas to avoid redundant DOM thrashing:

- `layersJustAdded`
- `layersJustRemoved`
- `layersJustWentToInertOutsideTrue`
- `islandsJustRemoved`

It processes changes via a `processLayersAndIslandsChanges()` routine.

Scheduling detail:

- if the most recently added layer is marked `external`, it processes immediately
- otherwise it batches after ~16ms (post-frame stabilization)

---

## InertOutside implementation (conceptual)

When `inertOutside` is active for the topmost layer, Silk effectively "locks" the rest of the page.

Implementation routine:

1. **Traverse**: Walk the DOM from `document.body`.
2. **Exclusion**: Skip the topmost layer's DOM nodes (`viewElement`, etc.) and any currently registered Islands.
3. **Apply**: Apply the `inert` attribute to all other top-level siblings and ancestors.
4. **Cleanup**: On removal, the registry removes the `inert` attributes from the elements it previously marked.

Fallback considerations:

- older browsers without native `inert` support may require `aria-hidden="true"` plus manual disabling of focusable elements
- current Silk appears to rely primarily on native `inert` support

---

## Escape key routing

On Escape keydown:

1. identify **topmost** eligible layer.
2. apply its `onEscapeKeyDown` policy:
   - `stopOverlayPropagation`: if `true`, lower layers will not receive the event.
   - `dismiss`: if `true` (and the role is not `alertdialog`), trigger the sheet's dismissal.
   - `nativePreventDefault`: if `true`, call `event.preventDefault()` to stop browser defaults.

Default policies:

- `dialog`: `{ dismiss: true, stopOverlayPropagation: true }`
- `alertdialog`: `{ dismiss: false, stopOverlayPropagation: true }`

---

## Click-outside routing

On global click:

1. determine whether click is inside any layer’s relevant elements:
   - `viewElement`, `backdropElement`, or `scrollContainerElement` (depending on configuration).
2. if the click is "outside" the topmost layer's content, walk layers from top → down applying `onClickOutside`:
   - `stopOverlayPropagation`: controls whether the click "falls through" to lower layers.
   - `dismiss`: whether to trigger dismissal for this layer.
3. **Island check**: clicks inside registered Islands are explicitly excluded from "outside" calculations.

Click detection must account for:

- **Portals**: content rendered outside the main DOM tree.
- **Backdrops**: clicking a layer's backdrop is effectively an "outside content" click for that specific layer.
- **Fixed components**: transform compensation can shift elements, requiring bounding box checks.

---

## Focus management flow

### On present

1. store currently-focused element as `elementFocusedLastBeforeShowing`.
2. select focus target:
   - registered `AutoFocusTarget` for this specific layer.
   - else first focusable element inside the layer.
   - else the `View` element itself.
3. apply `onPresentAutoFocus` policy:
   - `{ focus: true }` (default): focus the target.
   - `{ focus: false }`: skip auto-focus.

### On dismiss

1. determine `focusWasInside`: was focus within the layer before dismissal started?
2. restore focus to `elementFocusedLastBeforeShowing` if appropriate.
3. apply `onDismissAutoFocus` policy:
   - `{ focus: true }` (default): restore focus.
   - `{ focus: false }`: skip restoration.
4. `AutoFocusTarget` can override behavior if its timing is set to `"onDismiss"`.

---

## ExternalOverlay interaction

ExternalOverlay registers “external layers” (`external=true`) to coordinate with non-Silk UI (e.g., chat widgets).

Why it matters:

- **Bypass batching**: Silk processes changes immediately (no 16ms delay) for external layers to reduce race conditions with third-party scripts.
- **Self-managed inert**:
  - `selfManagedInertOutside: true` (default): The external overlay manages its own "inert outside" behavior. Silk disables its own `inertOutside` to avoid double-inert conflicts.
  - `selfManagedInertOutside: false`: Silk includes the external overlay in its own inert calculations (keeping the external overlay interactive).

---

## Native focus scroll prevention (iOS)

Registry maintains `nativeFocusScrollPreventers[]`.

When non-empty (and on iOS/iPadOS + in browser):

- installs a special focus scroll prevention handler.
- goal: prevent Safari from scrolling focused inputs into broken/offset positions during overlay animations (which use transforms).

Used by:

- `Sheet.View nativeFocusScrollPrevention={true}` (default)
- `Scroll.View nativeFocusScrollPrevention={true}` (default)

---

## Rewrite implication

If you’re rewriting Silk-like overlays, isolate this subsystem as a first-class service:

- **Authoritative ordering**: Maintain a single source of truth for "topmost".
- **Inert application**: Centralize DOM traversal and `inert` attribute management with Island carve-outs.
- **Event routing**: Route Escape and Click-outside events through the registry rather than individual components.
- **Focus bookkeeping**: Handle target selection and restoration as a lifecycle service.
