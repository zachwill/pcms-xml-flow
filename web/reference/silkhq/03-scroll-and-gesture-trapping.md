# Scroll + ScrollTrap (advanced scrolling + gesture trapping)

Silk’s Scroll primitives are built to coexist with:

- Sheets (travel is scroll-driven)
- nested scroll containers
- platform back-swipe / pull-to-refresh quirks
- focus/keyboard behavior on mobile

---

## `<Scroll>`

Scroll is not “just overflow: auto”. It has explicit policies and an imperative API.

### Structure

```tsx
<Scroll.Root>
  <Scroll.View>
    <Scroll.Content>
      ...
    </Scroll.Content>
  </Scroll.View>
</Scroll.Root>
```

### `<Scroll.Root>` responsibilities

- provides context
- supports `componentId` association
- supports `componentRef` with an imperative API:
  - `getProgress()`
  - `getDistance()`
  - `getAvailableDistance()`
  - `scrollTo({ progress|distance, animationSettings })`
  - `scrollBy({ progress|distance, animationSettings })`

### `<Scroll.View>` responsibilities

- defines scroll port
- supports:
  - `axis`: `x | y | both`
  - `asChild`: boolean
  - `nativeFocusScrollPrevention`: boolean (default `true`)
  - scroll gesture trap/overshoot
  - scroll snap type
  - scroll anchoring
  - scroll padding
  - scroll timeline name
  - native scrollbar enable/disable
- emits:
  - `onScroll`
  - `onScrollStart` (supports keyboard dismissal)
  - `onScrollEnd`
  - `onFocusInside` (optionally scrollIntoView)

### Key props (practical)

**`scrollGesture`**

- `"auto" | false`
- use case: disable scrolling until a condition is met
  - e.g. inside a detented sheet, disable inner scroll until fully expanded

**`scrollGestureTrap`**

- traps scroll gestures at edges to prevent propagation to parent scroll containers or Sheets
- supports:
  - boolean
  - directional objects: `{ x?, y? }` or `{ xStart?, xEnd?, yStart?, yEnd? }`

Example:

```tsx
// Prevents pull-to-refresh and swipe-to-go-back at the bottom edge
<Scroll.View scrollGestureTrap={{ yEnd: true }} />
```

**`scrollGestureOvershoot`**

- boolean
- if `false`, trap is effectively forced true

**`safeArea`**

- `none | layout-viewport | visual-viewport` (default visual)
- `visual-viewport` accounts for on-screen keyboard

**`pageScroll` + `nativePageScrollReplacement`**

- `pageScroll={true}` marks this Scroll as the page scroll controller
- `nativePageScrollReplacement: true | false | 'auto'`
  - `auto` tends to be false on mobile browsers (preserve browser UI expand/collapse), true elsewhere

Benefits of replacement:

- enables `nativeFocusScrollPrevention`
- better animation performance

Limitations:

- no native anchor scroll
- no iOS status bar tap-to-top
- no pull-to-refresh

**`onScrollStart`**

- can be an object: `{ dismissKeyboard: true }`

Implementation hints:

- runtime measures scrollbar thickness and stores it in `--ua-scrollbar-thickness`
- runtime uses `window.visualViewport` where available to compute safe bounds

### `<Scroll.Content>`

- the moving content element inside View
- supports `asChild`

### `<Scroll.Trigger>`

Runs scroll actions on press.

Props:

- `forComponent?: ScrollId`
- `action?: 'scroll-to' | 'scroll-by'`
- `progress?: number` (0–1)
- `distance?: number` (pixels)
- `animationSettings?: ...`
- `onPress?: { forceFocus?: boolean, runAction?: boolean }`
- `asChild?: boolean`

Example:

```tsx
<Scroll.Trigger action="scroll-to" progress={0}>
  Back to Top
</Scroll.Trigger>
```

---

## ScrollTrap (internal primitive)

ScrollTrap is used by:

- Sheet internals (primary/secondary scroll traps)
- Fixed
- Sheet.SpecialWrapper

What it does:

- creates an element that absorbs scroll gestures
- uses an internal stabiliser element

Runtime behavior (observed):

- on scroll, it resets scroll position back to a fixed offset (e.g. `scrollTo(300, 300)`), effectively preventing the page from scrolling
- on iOS where `overscroll-behavior` is not supported, it temporarily toggles overflow to avoid bounce

Token note:

- ScrollTrap root token is `b0`

Default CSS hides scrollbars for traps.

---

## Relationship to Sheet swipe trapping

Sheet swipe trapping is not purely pointer-event based.

It is implemented via a combination of:

- scroll containers + overscroll behavior
- ScrollTrap elements
- platform detection (iOS vs Android vs desktop)

If rewriting: treat “trap swipe to prevent back navigation” as a dedicated subsystem, not an incidental CSS tweak.

---

## Recipes (from examples)

### Detent + embedded scroll

A common pattern:

- disable inner scroll until sheet is at last detent
- trap end-of-scroll to prevent sheet travel from stealing the gesture

Conceptually:

```tsx
<Scroll.View
  scrollGesture={!reachedLastDetent ? false : 'auto'}
  scrollGestureTrap={{ yEnd: true }}
  safeArea="layout-viewport"
  onScrollStart={{ dismissKeyboard: true }}
/>
```
