# Utilities + other primitives

This file covers non-Sheet primitives (`Fixed`, `VisuallyHidden`, `AutoFocusTarget`, `Island`, `ExternalOverlay`, `SpecialWrapper`), exported hooks, and utility functions. These components often serve as "escape hatches" that allow Silk's inert-outside, focus, and gesture systems to compose with the rest of your application.

---

## Fixed

Purpose:

- A robust `position: fixed` wrapper that solves two common problems:
  1. **Scroll Trapping**: Automatically traps scroll gestures when scrolling over it, preventing them from propagating to sheets or the page.
  2. **Transform Compensation**: Preserves visual position if ancestor elements (like a `Sheet.Outlet`) are being transformed during travel or stacking.

Runtime behavior:

- `Fixed.Root` wraps a `ScrollTrap.Root` and adds global token `0al`.
- Registers itself as a “fixed component” in the global registry (`eG.addFixedComponent`).
- The registry applies inverse transforms so the element stays visually fixed even when its parents are moving.

Composition:

```tsx
<Fixed.Root>
  <Fixed.Content>
    {/* Content here stays fixed relative to the viewport */}
  </Fixed.Content>
</Fixed.Root>
```

Related CSS variables (exposes browser-measured values):

- `--x-collapsed-scrollbar-thickness`: Width of horizontal scrollbar when page scrolling is disabled.
- `--y-collapsed-scrollbar-thickness`: Width of vertical scrollbar when page scrolling is disabled.

---

## VisuallyHidden

Accessibility primitive:

- Visually hides content while keeping it in the accessibility tree (DOM).
- Essential for providing `dialog` semantics (titles/descriptions) without rendering visible UI.

Example (Sidebar pattern):

```tsx
<Sheet.View role="dialog">
  <VisuallyHidden.Root>
    <Sheet.Title>Navigation Menu</Sheet.Title>
    <Sheet.Trigger action="dismiss">Close Menu</Sheet.Trigger>
  </VisuallyHidden.Root>
  <nav>...</nav>
</Sheet.View>
```

---

## AutoFocusTarget

Purpose:

- Explicitly defines an element to receive focus when a Sheet presents or dismisses.
- Bypasses default "auto-focus first interactive element" logic.

Association:

- Can target all sheets or a specific `SheetId` via `forComponent`.
- Works with the global layer manager’s focus routines, which also tracks the "last focused element" before a sheet appears to restore focus on dismissal.

---

## Island

Purpose:

- Carves out a region that stays interactive even when one or more sheets have `inertOutside={true}`.
- **Critical Use Case**: Global navigation, media controls, or status bars that must remain clickable while a modal sheet is open.

### Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `forComponent` | `SheetId \| "any"` | `undefined` | Associate with specific Sheet(s). `"any"` = all Sheets. |
| `contentGetter` | `string \| (() => HTMLElement)` | `undefined` | CSS selector or function to find content element (alternative to Island.Content) |
| `asChild` | `boolean` | `false` | Merge props onto child element |

### API Examples

```tsx
<Island.Root forComponent={sheetId}>
  <Island.Content>
    <nav>Stays clickable when sheet is open</nav>
  </Island.Content>
</Island.Root>

// target all sheets via selector (e.g. for a global nav outside the React tree)
<Island.Root forComponent="any" contentGetter=".global-persistent-nav" />
```

---

## ExternalOverlay

Purpose:

- Notifies Silk that a non-Silk overlay exists (e.g., third-party modal, Intercom/Zendesk chat widget).
- Coordinates "inert-outside" policies to prevent "double-inerting" or focus locks between different overlay systems.

### Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `disabled` | `boolean` | `false` | When true, ExternalOverlay is inactive. |
| `selfManagedInertOutside` | `boolean` | `true` | See modes below. |
| `contentGetter` | `string \| (() => HTMLElement)` | `undefined` | CSS selector or function to find the overlay element. |
| `asChild` | `boolean` | `false` | Merge props onto child element. |

### Modes

- **`selfManagedInertOutside={true}` (Default)**:
  - Use when the external overlay manages its own backdrop/inertness.
  - Silk will **disable** its own `inertOutside` system while this overlay is active to ensure the external overlay remains interactive.
- **`selfManagedInertOutside={false}`**:
  - Silk will include the external overlay in its own inert calculations.
  - The external overlay stays interactive while the rest of the page (outside the current Silk sheet) becomes inert.

---

## SpecialWrapper

A gesture-isolation wrapper built on `ScrollTrap`.

Purpose:

- Wraps interactive content inside a Sheet to avoid scroll/gesture conflicts.
- Absorbs scroll gestures that would otherwise trigger sheet travel (swipe-to-dismiss).

Example (Toast pattern):

```tsx
<Sheet.View>
  <Sheet.SpecialWrapper.Root>
    <Sheet.SpecialWrapper.Content>
      {/* Interactive toast content that shouldn't dismiss the sheet on swipe */}
      <button onClick={...}>Undo</button>
    </Sheet.SpecialWrapper.Content>
  </Sheet.SpecialWrapper.Root>
</Sheet.View>
```

Implementation Notes:
- Used internally by `Toast` and components with complex internal interactions (like maps).
- Creates an isolated gesture context that prevents propagation to the Sheet's travel scroller.

---

## Exported hooks/utilities

### `createComponentId()`

Returns an opaque component instance id (a Context reference, not a string). Used for disambiguation when nested roots exist or when associating triggers/targets outside the component tree.

```tsx
const loginSheetId = createComponentId();
// Used in <Sheet.Root componentId={loginSheetId}> and <Sheet.Trigger forComponent={loginSheetId}>
```

### `useClientMediaQuery(query)`

Client-only media query hook that returns `false` during SSR/hydration and updates reactively on the client.

```tsx
const isDesktop = useClientMediaQuery("(min-width: 768px)");
<Sheet.View contentPlacement={isDesktop ? "center" : "bottom"} />
```

### `updateThemeColor(color)`

Sets the underlying theme color used by the theme-color dimming system.
- Validates color (hex, rgb, rgba).
- Updates the global registry and recomputes the `<meta name='theme-color'>` tag factoring in active backdrops.

### `useThemeColorDimmingOverlay({ elementRef?, dimmingColor })`

Registers a custom dimming overlay in the registry. Used for custom overlays that should affect the browser's theme-color.

**Returns:**
- `setDimmingOverlayOpacity(alpha: number)`: Immediately set opacity (0–1).
- `animateDimmingOverlayOpacity({ keyframes, duration?, easing? })`: Animate between two opacities.

### `usePageScrollData()`

Returns page scroll state after hydration.
- `pageScrollContainer`: The Scroll element replacing body scroll if active, otherwise `document.body`.
- `nativePageScrollReplaced`: Boolean indicating if the body scroll was replaced by Silk.

### `animate(element, keyframes, options?)`

WAAPI helper that **persists final styles** after completion (via `commitStyles()`).
- Use for one-shot animations where you want the end state (e.g. `opacity: 1`) to remain as an inline style.

---

## SlideShow (stub)

Present in the mapping namespace (token `d`) but currently reserved for future functionality. No runtime code or elements are implemented in the current version.
