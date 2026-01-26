# 07 - Scroll + ScrollTrap (advanced scrolling + gesture trapping)

## `<Scroll>`

Scroll is a primitive for building scroll containers that play well with:
- Sheets
- nested swipe gestures
- page scroll replacement

It is **not** just `overflow: auto`.

### Root responsibilities

`<Scroll.Root>`:
- provides context
- supports `componentId` association
- supports `componentRef` for imperative control:
  - `getProgress()`
  - `getDistance()`
  - `getAvailableDistance()`
  - `scrollTo({ progress|distance, animationSettings })`
  - `scrollBy({ progress|distance, animationSettings })`

### View responsibilities

`<Scroll.View>`:
- defines the scroll port
- supports:
  - axis selection (`axis`: `"x"` | `"y"` | `"both"`)
  - scroll gesture trap/overshoot
  - scroll snap type
  - scroll anchoring
  - scroll padding
  - scroll timeline name
  - native scrollbar enable/disable
- emits:
  - `onScroll`
  - `onScrollStart` (with ability to dismiss keyboard)
  - `onScrollEnd`
  - `onFocusInside` (optionally scrollIntoView)

#### Key props in detail

**`scrollGesture`**:
- Controls whether scroll gestures are enabled
- Values: `"auto"` | `false`
- Use case: disable scrolling until a condition is met (e.g., sheet expanded to last detent)

**`scrollGestureTrap`**:
- Traps scroll gestures at edges to prevent propagation to parent scroll containers or Sheets
- Values: `boolean` or granular `{ x?, y? }` or `{ xStart?, xEnd?, yStart?, yEnd? }`
- Example: `scrollGestureTrap={{ yEnd: true }}` prevents pull-to-refresh and swipe-to-go-back at edges
- Note: if `scrollGestureOvershoot={false}`, trap is always true

**`scrollGestureOvershoot`**:
- Controls elastic bounce at scroll boundaries
- Values: `boolean`
- When `false`, enables trapping automatically

**`safeArea`**:
- Defines the viewport area considered safe for content travel
- Values: `"none"` | `"layout-viewport"` | `"visual-viewport"` (default)
- `"visual-viewport"` accounts for on-screen keyboard

**`pageScroll` + `nativePageScrollReplacement`**:
- `pageScroll={true}` marks this Scroll as controlling page-level scrolling
- `nativePageScrollReplacement`: `true` | `false` | `"auto"`
  - `"auto"` → `false` on mobile browsers (preserves browser UI expand/collapse), `true` elsewhere
- Benefits of replacement: enables `nativeFocusScrollPrevention`, better animation perf
- Limitations: no native anchor scroll, no iOS status bar tap-to-scroll, no pull-to-refresh

**`onScrollStart`**:
- Can be an object: `{ dismissKeyboard: true }` to auto-dismiss on-screen keyboard

Implementation hints (from runtime snippets):
- uses a "UA scrollbar measurer" element to compute scrollbar thickness and store it in `--ua-scrollbar-thickness`.
- has logic to compute visual viewport bounds (`window.visualViewport`) and adjust scroll-into-view behavior.

### Content

`<Scroll.Content>`:
- The element that moves as scroll occurs
- Required descendant of `<Scroll.View>`
- Supports `asChild`

Anatomy:
```tsx
<Scroll.Root>
  <Scroll.View>
    <Scroll.Content>
      ...
    </Scroll.Content>
  </Scroll.View>
</Scroll.Root>
```

### Trigger

`<Scroll.Trigger>`:
- runs scroll actions on press

**Props:**
- `forComponent?: ScrollId` — associates with specific Scroll instance
- `action?: "scroll-to" | "scroll-by"` — action to run on press
- `progress?: number` — target progress (0–1) for scroll-to/scroll-by
- `distance?: number` — target distance in pixels
- `animationSettings?: {...}` — animation options for the scroll action
- `onPress?: { forceFocus?: boolean, runAction?: boolean }` — press behavior
- `asChild?: boolean`

Example:
```tsx
<Scroll.Trigger action="scroll-to" progress={0}>
  Back to Top
</Scroll.Trigger>
```

## ScrollTrap

ScrollTrap is an internal primitive used by:
- Sheet internals (primary/secondary scroll traps)
- Fixed
- Sheet.SpecialWrapper

What it does:
- creates an element that absorbs scroll gestures
- uses an internal "stabiliser" element

Runtime details:
- on scroll, it resets scroll position to a fixed offset (e.g. `scrollTo(300, 300)`), effectively preventing the page from scrolling.
- on iOS where `overscroll-behavior` is not supported, it temporarily toggles overflow to avoid bounce issues.

Tokens in default CSS:
- ScrollTrap root element token is `b0` (since ScrollTrap componentName is `b` and root index is 0).

In CSS you'll see:
- `[data-silk~="b0"] { scrollbar-width: none; }`
- `::-webkit-scrollbar { display:none }`

## Relationship to Sheet swipe trapping

Sheet's swipe trapping is not purely pointer-event based.

It is implemented via a combination of:
- scroll containers + overscroll behavior
- ScrollTrap elements
- platform detection (iOS vs Android vs desktop)

If you're rewriting:
- treat "trap swipe to prevent back navigation" as a dedicated subsystem, not an incidental side effect.
