# 08 - Other primitives (Fixed, AutoFocusTarget, Island, ExternalOverlay, VisuallyHidden)

## `Fixed`

Purpose (from types):
- a better `position: fixed` wrapper that:
  - traps scroll gestures when scrolling over it
  - preserves visual position if ancestor outlets are being transformed (travel/stacking)
  - exposes CSS vars for collapsed scrollbar thickness when page scrolling is disabled

Runtime (from `module.mjs`):
- `Fixed.Root` wraps a `ScrollTrap.Root` and adds data-silk token `0al`.
- It registers the underlying element as a "fixed component" in the global registry (`eG.addFixedComponent`).
- During outlet transforms, registry can apply "transform compensation" to keep fixed elements visually fixed.

Composition:

```tsx
<Fixed.Root>
  <Fixed.Content>...</Fixed.Content>
</Fixed.Root>
```

## `VisuallyHidden`

Simple accessibility primitive.

Purpose:
- visually hide content while keeping it in the accessibility tree.

Examples use it to:
- include a `<Sheet.Title>` and a close trigger for a `dialog` sidebar without showing them visually.

## `AutoFocusTarget`

Purpose:
- defines an element to focus when a Sheet presents/dismisses.

Association:
- can target all sheets or a specific `SheetId` via `forComponent`.

It works with Sheet's focus management (which also stores "last focused element before showing").

## `Island`

Purpose (from types):
- carve out a region that stays interactive even when one or more Sheets have `inertOutside=true`.

### `<Island.Root>` props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `forComponent` | `SheetId \| "any"` | `undefined` | Associate with specific Sheet(s). `"any"` = all Sheets. |
| `contentGetter` | `string \| (() => HTMLElement)` | `undefined` | CSS selector or function to find content element (alternative to Island.Content) |
| `asChild` | `boolean` | `false` | Merge props onto child element |

### `<Island.Content>` props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `asChild` | `boolean` | `false` | Merge props onto child element |

### API

```tsx
<Island.Root forComponent={sheetId}>
  <Island.Content>
    <nav>This stays clickable when sheet is open</nav>
  </Island.Content>
</Island.Root>

// Or with contentGetter (for third-party elements):
<Island.Root 
  forComponent="any" 
  contentGetter=".my-persistent-nav"
/>
```

Use cases:
- keep a global nav / media controls clickable while a modal sheet is open
- preserve interactivity for chat widgets, floating action buttons, etc.

## `ExternalOverlay`

Purpose:
- tell Silk that a non-Silk overlay is present (e.g. chat widget, third-party modal).

Why it exists:
- inert-outside mechanisms can conflict.
- ExternalOverlay can either:
  1) be included in Sheets' inert-outside, OR
  2) cause Sheets to disable inert-outside (if the external overlay manages its own).

### `<ExternalOverlay.Root>` props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `disabled` | `boolean` | `false` | When true, ExternalOverlay is inactive |
| `selfManagedInertOutside` | `boolean` | `true` | If true, Sheets disable their inert-outside to avoid double-inert |
| `contentGetter` | `string \| (() => HTMLElement)` | `undefined` | CSS selector or function to find the overlay element |
| `asChild` | `boolean` | `false` | Merge props onto child element |

### Modes of operation

**Mode 1: `selfManagedInertOutside={true}` (default)**
- The external overlay manages its own inert-outside.
- Silk Sheets will disable their inert-outside when this ExternalOverlay is active.
- Use for: third-party modals, chat widgets with their own overlay mechanics.

**Mode 2: `selfManagedInertOutside={false}`**
- Silk will include this overlay in its inert-outside calculations.
- The external content will stay interactive when Sheets are open.
- Use for: simple floating elements that need to remain interactive.

### API examples

```tsx
// Wrap a third-party chat widget
<ExternalOverlay.Root 
  selfManagedInertOutside={true}
  contentGetter="#intercom-container"
/>

// Or wrap children directly
<ExternalOverlay.Root selfManagedInertOutside={false}>
  <ThirdPartyWidget />
</ExternalOverlay.Root>

// Conditionally active based on widget state
<ExternalOverlay.Root disabled={!chatWidgetOpen}>
  ...
</ExternalOverlay.Root>
```

## Design takeaway

These primitives are "escape hatches" around the inert-outside + focus + gesture model.

If you're rewriting Silk:
- do not treat these as optional add-ons.
- they are required to make the inert-outside system composable with real-world apps.

## `SpecialWrapper`

Purpose:
- wraps interactive content to avoid scroll/gesture conflicts with Sheet mechanics.
- absorbs scroll gestures that would otherwise trigger sheet travel.

API:

```tsx
<Sheet.SpecialWrapper.Root>
  <Sheet.SpecialWrapper.Content>
    ...interactive content...
  </Sheet.SpecialWrapper.Content>
</Sheet.SpecialWrapper.Root>
```

Also available standalone (internal primitive):

```tsx
<SpecialWrapper.Root>
  <SpecialWrapper.Content>...</SpecialWrapper.Content>
</SpecialWrapper.Root>
```

In mapping:
- `componentName`: internal token
- elements: `root` (0), `content` (1)

Use cases:
- Toast component wraps content in SpecialWrapper to keep pointer interactions sane
- Any interactive content inside a Sheet that shouldn't trigger sheet swipe

Implementation:
- Built on top of `ScrollTrap` internally
- Creates an isolated gesture context

## `SlideShow` (stub)

Present in the mapping namespace but appears to be a placeholder/future primitive:

```ts
namespace SlideShow {
  componentName: string;
  elementNames: {};
  variationSetsNames: {};
  variationValuesNames: {};
}
```

No elements, variations, or runtime code observed. Likely reserved for future carousel/slideshow functionality.

If you're rewriting: ignore for now, but reserve the namespace.
