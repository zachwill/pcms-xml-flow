# Animations (travel/stacking) + settings + recipes

Silk uses two complementary animation approaches:

1. **Progress-driven styles** (travelAnimation / stackingAnimation): runtime continuously applies inline styles based on progress.
2. **WAAPI one-shots** (`animate()`): runs a Web Animations API animation, then persists end styles.

This file consolidates:

- the animation declaration syntax
- how progress is defined
- animation settings (springs vs CSS easing)
- key patterns from examples

---

## Progress values

### Travel progress

- `progress` is a float in `[0, 1]`
- `0` = fully out / dismissed
- `1` = fully in at the last detent

Note:

- overshoot can exist visually, but progress reporting may clamp/segment depending on settings.

### Stacking progress

- stacking progress is effectively `0..n`
- `n` = number of sheets stacked above

Implication:

- the tuple keyframe form `[start, end]` interpolates linearly for `0..1` only
- for progress values > 1, you generally need the function template form

---

## Animation declaration format

From `types.d.ts`, `travelAnimation` and `stackingAnimation` accept a “declarations object”:

- keys are **camelCased CSS properties**
- values can be:
  1. `[start, end]` keyframes tuple (**restricted**)
  2. function template `(params) => value`
  3. constant string/number
  4. `null/undefined` (no animation)

### Keyframe tuple restrictions

`[start, end]` is only supported for:

- `opacity`
- individual transform properties:
  - `translate`, `translateX/Y/Z`
  - `scale`, `scaleX/Y/Z`
  - `rotate`, `rotateX/Y/Z`
  - `skew`, `skewX/Y`

For other properties (e.g. `borderRadius`, `backgroundColor`) use the function form.

### Function template signature

```ts
interface CssValueTemplateParams {
  progress: number;
  tween: (start: string | number, end: string | number) => string;
}
```

`tween(start, end)` returns:

- `calc(${start} + (${end} - ${start}) * ${progress})`

Example:

```ts
travelAnimation={{
  borderRadius: ({ tween }) => tween('0px', '12px'),
  opacity: ({ progress }) => (progress < 0.5 ? 0 : (progress - 0.5) * 2),
}}
```

### CSS property naming

- use camelCase: `borderRadius`, `backgroundColor`, `translateX`, etc.
- transform components are treated as separate properties, not a combined `transform` string

---

## Outlet registration + lifecycle

Progress-driven styles attach through Outlets.

When a `Sheet.Outlet` mounts:

1. registers itself with the global registry tied to its parent sheet
2. registers its `travelAnimation` and/or `stackingAnimation` declarations

On prop change:

- re-registers declarations

On unmount:

- deregisters

### When styles are applied

Inline styles are applied:

- continuously during travel (rAF/scroll-driven)
- when staging state changes

The `data-silk~='0aj'` token appears when staging != none, signaling active staging/animation.

### Style persistence + cleanup

Some computed styles are persisted as inline styles after motion completes.

Stack-level cleanup:

- when a SheetStack’s `sheetsCount` becomes 0, runtime calls `removeAllOutletPersistedStylesFromStack(stackId)`.

---

## WAAPI helper: `animate()` (persist end styles)

Silk exports an `animate()` utility:

- calls `element.animate(keyframes, { fill: 'forwards', ... })`
- on finish: `commitStyles()` then `cancel()`

Net: final styles persist as inline styles and the animation object is released.

This is the pattern we copied into `web/src/lib/animate.ts`.

---

## Animation settings (enter/exit/step)

Silk supports two timing models:

- spring physics
- CSS easing

### Spring presets

| Preset | Feel |
|--------|------|
| `gentle` | slow, soft |
| `smooth` | balanced default |
| `snappy` | quick |
| `brisk` | fast |
| `bouncy` | overshoot |
| `elastic` | strong overshoot |

### Spring config (custom)

```ts
type SpringConfig = {
  easing: 'spring';
  stiffness: number;
  damping: number;
  mass: number;
  initialVelocity?: number;
  precision?: number;
  delay?: number;
};
```

### CSS easing config

```ts
type CSSEasingConfig = {
  easing: 'ease' | 'ease-in' | 'ease-out' | 'ease-in-out' | 'linear' | `cubic-bezier(${string})`;
  duration: number;
  delay?: number;
};
```

### Settings shape (practical)

Entering/exiting settings can include:

- `{ preset?, skip?, contentMove?, track?, ...timing }`

Stepping settings do not support `track`.

### Spring simulation note

Silk’s spring is sampled into a discrete progress array; duration derives from the sample length (not an analytic spring function).

---

## Theme-color dimming integration (Backdrop)

When `Sheet.Backdrop themeColorDimming='auto'`:

- runtime may register a dimming overlay entry in the global registry
- opacity updates may be driven manually (inline) to keep `<meta name='theme-color'>` in sync

Takeaway:

- backdrop opacity can be controlled via two channels:
  1) animation declarations
  2) theme-color dimming overlay mechanism

---

## Recipes (from examples in this repo)

### BottomSheet

Defaults commonly set:

- View: `nativeEdgeSwipePrevention={true}`
- Backdrop: `themeColorDimming='auto'`
- Content: includes `Sheet.BleedingBackground`
- Handle: use `action='dismiss'` (not step)

### DetachedSheet

- responsive switch: bottom (mobile) vs center+dual tracks (desktop)

### Sidebar

- `sheetRole='dialog'`
- left placement + `swipeOvershoot={false}`
- uses `VisuallyHidden` for accessible title/close without visible UI

### Toast (non-modal animated surface)

Key policies:

- no dialog semantics (`sheetRole=''`)
- `inertOutside={false}`
- disable focus stealing (`onPresentAutoFocus={{ focus:false }}` etc.)
- disable outside dismiss (`onClickOutside.dismiss=false`, `onEscapeKeyDown.dismiss=false`)
- wrap content in `Sheet.SpecialWrapper` for sane interactions

### Detent + embedded scroll

- disable inner scroll until expanded to last detent
- trap end-of-scroll to avoid gesture propagation
- use `onScrollStart={{ dismissKeyboard: true }}`

### Keyboard dismissal during travel

- in `onTravel`, when progress < ~1, focus the View element to blur inputs

### Page (Side travel)

- View: `contentPlacement="right"` (or `"left"`)
- View: `swipeOvershoot={false}`
- Result: A standard slide-in page overlay.

### PageFromBottom (Manual dismissal)

- View: `contentPlacement="bottom"`, `swipe={false}`
- View: `nativeEdgeSwipePrevention={true}`
- Backdrop: `travelAnimation={{ opacity: [0, 0.1] }}`
- Pattern: requires a `Sheet.Trigger action="dismiss"` button in the UI since gesture dismissal is disabled.

### Card (Zoom / Scale animation)

- View: `contentPlacement="center"`, `tracks="top"`
- Content: `travelAnimation={{ scale: [0.8, 1], opacity: [0, 1] }}`
- Backdrop: `travelAnimation={{ opacity: ({ progress }) => Math.min(0.4 * progress, 0.4) }}`
- Result: A classic centered modal that scales up from 80% on entry.

### LongSheet (Dynamic track switching)

- View: initial `tracks="bottom"`
- Content embeds `Scroll.Root`
- Logic: `onScroll` checks scroll progress; if scrolled significantly, switch `tracks` to `"top"`.
- Result: Sheet slides down if you're at the top, but slides up/off the top if you've scrolled deep.

### TopSheet

- View: `contentPlacement="top"`
- View: `nativeEdgeSwipePrevention={true}`
- Content: includes `Sheet.BleedingBackground`

### Stacking animations

- stacking progress is `0..n`; use functions for behavior beyond 1
- tune translate/scale per placement axis

---

## Technical rules for animations

### Outlet requirement

Animations (both `travelAnimation` and `stackingAnimation`) only work on components that are implemented as or wrap a `Sheet.Outlet`.

### Staging token (`0aj`)

The global `data-silk~='0aj'` token is applied to all active Outlets and SheetStack Outlets whenever a sheet in the stack is in a staging state other than `none` (i.e., it is currently animating or preparing to animate).
