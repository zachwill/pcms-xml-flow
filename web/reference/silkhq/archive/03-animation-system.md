# 03 — Animation system (travel + stacking + WAAPI)

Silk exposes declarative animation props on multiple subcomponents:

- `travelAnimation` — driven by a Sheet's travel progress (0 → 1)
- `stackingAnimation` — driven by the number/progress of sheets stacked above

These animation props are not CSS keyframes in your stylesheet.
They are runtime-driven and typically end up as:
- inline style changes, and/or
- WAAPI animations, and/or
- computed transforms applied during rAF loops.

## The animation declaration format

From `types.d.ts`:

- Values can be:
  1. `[start, end]` (keyframes array) — **only supported for transform subproperties + opacity**
  2. `(params) => value` — function template
  3. `"some string"` — constant assignment
  4. `null/undefined` — no animation

### Keyframes array limitation

The `[start, end]` syntax is explicitly restricted to:
- `opacity`
- Individual transform properties: `translate`, `translateX`, `translateY`, `translateZ`, `scale`, `scaleX`, `scaleY`, `scaleZ`, `rotate`, `rotateX`, `rotateY`, `rotateZ`, `skew`, `skewX`, `skewY`

For any other CSS property, you **must** use the function syntax.

### Function template signature

```ts
interface CssValueTemplateParams {
  progress: TravelProgress;  // number in [0, 1] for travel; 0..n for stacking
  tween: TweenFunction;      // (start, end) => calc() string
}

type CssValueTemplate = (params: CssValueTemplateParams) => string | number;
```

Where:
- `progress` — current travel or stacking progress (number)
- `tween(start, end)` — returns a CSS `calc()` interpolation string

### The `tween()` function output

From `module.mjs`:

```ts
tween = (start, end) => `calc(${start} + (${end} - ${start}) * ${progress})`
```

Example usage:

```ts
travelAnimation={{
  borderRadius: ({ tween }) => tween("0px", "12px"),
  opacity: ({ progress }) => progress < 0.5 ? 0 : (progress - 0.5) * 2
}}
```

## How progress is defined

### Sheet travel progress

- progress is a float in `[0, 1]`
- 0 = fully out / dismissed
- 1 = fully in at the last detent

Note: "overshoot" can temporarily move past the last detent visually, but progress reporting may clamp/segment depending on settings.

### Stacking progress

- stacking progress is effectively `0..n` where `n = number of sheets above`
- this is why examples sometimes implement:

```ts
({ progress }) =>
  progress <= 1 ? ... : `calc(...)`
```

## Animation registration and lifecycle

### Outlet registration

When a `Sheet.Outlet` mounts:
1. It registers itself with the global registry (`eG`) tied to its parent sheet.
2. It registers its `travelAnimation` and `stackingAnimation` declarations.

When props change:
- The outlet re-registers its animations.

When unmounting:
- The outlet removes itself from the registry.

### Style application timing

Inline styles are applied:
- During travel (continuously, via rAF or scroll events)
- When staging state changes

The `data-silk~="0aj"` token is added to outlets when staging !== "none", signaling that animation-related inline styles may be present.

### Style persistence

After travel completes:
- Certain computed styles are "persisted" as inline styles.
- When `sheetsCount` in a stack becomes 0, runtime calls `removeAllOutletPersistedStylesFromStack(stackId)` to clean up.

## Where animations apply

Any subcomponent using `Sheet.Outlet` or wrapping `Outlet` behavior can be animated.

In runtime (`module.mjs`):
- `Sheet.Outlet` registers its `travelAnimation` and/or `stackingAnimation` with the global registry.
- Those animations can apply to *any* CSS property (with varying support).

Practical rule:
- If you want a Sheet subcomponent to participate in travel/stacking animations, it must be implemented as (or wrap) an `Outlet`.

This is why:
- `Sheet.Title` / `Sheet.Description` are implemented by rendering an `Outlet` around a semantic tag.

## WAAPI helper export: `animate()`

Exported utility:

```ts
animate(element, { opacity: [0,1] }, { duration, easing })
```

Runtime behavior (from `module.mjs`):
- calls `element.animate(keyframes, { duration, easing, fill: "forwards" })`
- `onfinish` commits the end styles (`commitStyles()`) then cancels the animation
- net: final styles persist as inline styles.

Use cases:
- small one-off animations outside Silk's travel model
- avoids you having to implement "persist final styles" yourself

## Spring vs CSS easing

For Sheet entering/exiting/stepping, the config accepts:

- preset names: `gentle | smooth | snappy | brisk | bouncy | elastic`
- or explicit config:
  - `easing: "spring"` + physical params (`stiffness`, `damping`, `mass`, `initialVelocity?`, `precision?`, `delay?`)
  - OR `easing: "ease" | "ease-in" | "ease-out" | "ease-in-out" | "linear" | cubic-bezier(...)` + `duration` + `delay?`

### Spring simulation

Runtime (from `module.mjs`) produces:
- a discrete array of progress values simulating a spring
- duration is derived from the length of the generated array

Important implication:
- "spring" is not a continuous analytic function here; it's sampled into an array of progress values.

### Animation settings shape

```ts
type SpringPreset = "gentle" | "smooth" | "snappy" | "brisk" | "bouncy" | "elastic";

type StaticAnimationOptions = {
  preset?: SpringPreset;   // Can combine with explicit config
  skip?: boolean;          // Skip animation entirely
  contentMove?: boolean;   // Whether content moves during animation
};

type SpringConfig = {
  easing: "spring";
  stiffness: number;
  damping: number;
  mass: number;
  initialVelocity?: number;
  precision?: number;
  delay?: number;
};

type CSSEasingConfig = {
  easing: "ease" | "ease-in" | "ease-out" | "ease-in-out" | "linear" | `cubic-bezier(${string})`;
  duration: number;
  delay?: number;
};

type EnteringAnimationSettings = SpringPreset | (
  (SpringConfig & StaticAnimationOptions & { track?: Track }) |
  (CSSEasingConfig & StaticAnimationOptions & { track?: Track }) |
  (StaticAnimationOptions & { track?: Track })
);

type ExitingAnimationSettings = SpringPreset | (
  (SpringConfig & StaticAnimationOptions & { track?: Track }) |
  (CSSEasingConfig & StaticAnimationOptions & { track?: Track }) |
  (StaticAnimationOptions & { track?: Track })
);

// Note: SteppingAnimationSettings does NOT have `track` option
type SteppingAnimationSettings = SpringPreset | (
  (SpringConfig & StaticAnimationOptions) |
  (CSSEasingConfig & StaticAnimationOptions) |
  StaticAnimationOptions
);
```

The `track` option in entering/exiting settings allows overriding the travel direction for dual-track sheets. Stepping animations don't support `track` since they occur within an already-presented sheet.

## Theme-color dimming integration (Backdrop)

`Sheet.Backdrop` can drive:
- backdrop element opacity **and**
- the document `<meta name="theme-color">`

When `themeColorDimming="auto"` and conditions match (browser support, theme-color parseable), runtime:
- registers a "dimming overlay" in a global registry
- updates its alpha in sync with travel progress

This is why Backdrop sometimes replaces its own opacity animation with an "ignore" placeholder and manually sets inline opacity.

Takeaway:
- Backdrop opacity can be controlled by travel progress in two different channels:
  1) animation props
  2) theme-color dimming overlay mechanism

If you build a rewrite, model these as separate concerns.

## CSS property naming

All CSS properties in animation declarations must use camelCase:
- `borderRadius` (not `border-radius`)
- `backgroundColor` (not `background-color`)
- `translateX` (not `translate-x`)

Individual transform components are treated as separate properties, not combined into a single `transform` string.
