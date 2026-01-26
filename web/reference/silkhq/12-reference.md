# 12 - Reference (tokens, platforms, animation settings)

Consolidated reference for implementation details that span multiple components.

---

## CSS Token System (`data-silk`)

Silk uses a compact token system for CSS selectors. All styling is driven by `data-silk` attributes containing space-separated tokens.

### Token structure

```
data-silk="<componentToken><elementIndex> [<variationSetToken><variationValueToken>] ..."
```

- **Component token**: single letter identifying the component (e.g., `a` = Sheet, `b` = ScrollTrap)
- **Element index**: numeric index of the element within the component
- **Variation tokens**: state/variation markers (set token + value token)

### Component tokens (observed)

| Token | Component |
|-------|-----------|
| `a` | Sheet |
| `b` | ScrollTrap |
| `c` | Scroll |
| `d` | SlideShow (reserved) |
| `e` | VisuallyHidden |
| `f` | SpecialWrapper |
| `g` | Fixed |
| `h` | SheetStack |
| `i` | AutoFocusTarget |

### Sheet element indices

| Index | Element |
|-------|---------|
| `0` | root |
| `1` | view |
| `2` | backdrop |
| `3` | backdropTrap |
| `4` | primaryScrollTrapRoot |
| `5` | secondaryScrollTrapRoot |
| `6` | scrollContainer |
| `7` | frontSpacer |
| `8` | backSpacer |
| `9` | detentMarker |
| `10` | contentWrapper |
| `11` | content |
| `12` | bleedingBackground |
| `13` | stickyContainer |
| `14` | sticky |
| `15` | leftEdge |
| `16` | trigger |
| `17` | handle |
| `18` | outlet |

### Sheet variation sets

| Set token | Variation set | Values |
|-----------|---------------|--------|
| `G` | openness | `a`=open, `b`=opening, `c`=closed, `d`=closing, ... |
| `H` | staging | `a`=none, `b`=pending, ... |
| `I` | position | `a`=front, `b`=covered, `c`=out |
| `J` | placement | `a`=top, `b`=bottom, `c`=left, `d`=right, `e`=center |
| `K` | track | `a`=top, `b`=bottom, `c`=left, `d`=right |

### Example token parsing

```css
[data-silk~="a1"]           /* Sheet view element */
[data-silk~="a1"][data-silk~="aGa"]  /* Sheet view, openness=open */
[data-silk~="a11"]          /* Sheet content element */
[data-silk~="b0"]           /* ScrollTrap root element */
```

### Global tokens

Some tokens are applied at higher levels:

| Token | Meaning |
|-------|---------|
| `0aj` | Any sheet in stack is staging != none |
| `0af` | Sheet-related global state marker |
| `0al` | Fixed component marker |

---

## Platform Detection

Silk detects platform at runtime for behavior adaptation.

### Detection methods

```js
// Primary: userAgentData API (modern browsers)
if (navigator.userAgentData) {
  if (navigator.userAgentData.platform === "Android") {
    platform = "android";
  }
}

// Fallback: userAgent string
if (navigator.userAgent?.match(/Safari|iPhone/i)) {
  engine = "webkit";
}

// Standalone mode detection
const standalone = 
  window.matchMedia("(display-mode: standalone)").matches || 
  window.navigator.standalone;
```

### Platform-specific behaviors

#### iOS / Safari (WebKit)

| Behavior | Description |
|----------|-------------|
| Native edge swipe prevention | 28px left-edge element blocks browser back gesture |
| Focus scroll prevention | Special handling to prevent Safari scrolling inputs into weird positions |
| Overscroll bounce | `overscroll-behavior` not fully supported; uses overflow toggling fallback |
| Status bar tap | Not available when `nativePageScrollReplacement=true` |

#### Android (non-standalone)

| Behavior | Description |
|----------|-------------|
| Y-axis swipe trap disabled | Allows browser UI (address bar) to reveal/hide |
| Pull-to-refresh | Swipe trap on Y disabled to allow native refresh |

#### Standalone mode (PWA)

| Behavior | Description |
|----------|-------------|
| Full swipe trapping | All gesture trapping enabled (no browser UI to conflict) |
| `nativePageScrollReplacement` | Defaults to `true` on desktop, `false` on mobile browsers |

### Document attributes

Silk sets attributes on `document.documentElement`:

```html
<html 
  data-standalone="true|false"
  data-silk-native-page-scroll-replaced="true|false"
>
```

---

## Animation Settings

Silk supports two animation timing models: **spring physics** and **CSS easing**.

### Spring presets

Use a preset name for quick configuration:

| Preset | Feel |
|--------|------|
| `"gentle"` | Slow, soft |
| `"smooth"` | Default, balanced (used by enteringAnimationSettings default) |
| `"snappy"` | Quick, responsive |
| `"brisk"` | Fast, crisp |
| `"bouncy"` | Overshoots, playful |
| `"elastic"` | Strong overshoot, springy |

```tsx
<Sheet.View enteringAnimationSettings="bouncy" />
```

### Spring config (custom)

For precise control, provide spring physics parameters:

```ts
type SpringConfig = {
  easing: "spring";
  stiffness: number;    // Spring stiffness (higher = faster)
  damping: number;      // Friction (higher = less oscillation)
  mass: number;         // Mass (higher = slower, more momentum)
  initialVelocity?: number;  // Starting velocity
  precision?: number;   // When to consider animation complete
  delay?: number;       // Delay before starting (ms)
};
```

Example from `Card.tsx`:
```tsx
enteringAnimationSettings={{
  easing: "spring",
  stiffness: 180,
  damping: 22,
  mass: 1,
}}
```

### CSS easing config

For traditional CSS timing functions:

```ts
type CSSEasingConfig = {
  easing: "ease" | "ease-in" | "ease-out" | "ease-in-out" | "linear" | `cubic-bezier(${string})`;
  duration: number;     // Duration in ms
  delay?: number;       // Delay before starting (ms)
};
```

Example:
```tsx
enteringAnimationSettings={{
  easing: "cubic-bezier(0.22, 1, 0.36, 1)",
  duration: 400,
}}
```

### Animation settings structure

Full settings object for `enteringAnimationSettings` / `exitingAnimationSettings`:

```ts
type EnteringAnimationSettings = SpringPreset | {
  // Timing (one of):
  easing?: "spring";
  stiffness?: number;
  damping?: number;
  mass?: number;
  // OR:
  easing?: CSSEasingFunction;
  duration?: number;
  
  // Options:
  preset?: SpringPreset;      // Base preset to modify
  skip?: boolean;             // Skip animation entirely
  contentMove?: boolean;      // Animate content position (default: true)
  track?: Track;              // Override travel direction for dual-track
  delay?: number;
};
```

### Defaults

```tsx
// Sheet.View defaults
enteringAnimationSettings={{ preset: "smooth", contentMove: true, skip: prefersReducedMotion }}
exitingAnimationSettings={{ preset: "smooth", contentMove: true, skip: prefersReducedMotion }}
steppingAnimationSettings={{ preset: "smooth", skip: prefersReducedMotion }}
```

### Travel/stacking animation syntax

For `travelAnimation` and `stackingAnimation` props:

```ts
type AnimationDeclarations = {
  [cssProperty: string]: 
    | [from: string | number, to: string | number]  // Keyframes
    | ((context: { progress: number; tween: TweenFn }) => string | number)  // Function
    | string  // Static value
    | null;   // No animation
};
```

Examples:
```tsx
// Keyframe syntax (linear interpolation 0→1)
travelAnimation={{ opacity: [0, 1], scale: [0.95, 1] }}

// Function syntax (custom curve, works for progress > 1)
stackingAnimation={{
  translateY: ({ progress }) => 
    progress <= 1 
      ? progress * -10 + "px" 
      : `calc(-12.5px + 2.5px * ${progress})`,
}}

// Using tween helper
travelAnimation={{
  opacity: ({ progress, tween }) => tween(0, 0.4),  // Same as [0, 0.4]
}}
```

---

## CSS Custom Properties

### Sheet content sizing

| Property | Description |
|----------|-------------|
| `--silk-aA` | Previous detent value (or `0px`) |
| `--silk-aB` | Current detent value |
| `--silk-aC` | Detent index |
| `--silk-aF` | "Fully expanded" sentinel value |

### Fixed component

| Property | Description |
|----------|-------------|
| `--x-collapsed-scrollbar-thickness` | Horizontal scrollbar width when page scroll disabled |
| `--y-collapsed-scrollbar-thickness` | Vertical scrollbar width when page scroll disabled |
| `--silk-fixed-side` | Which side the fixed element is positioned from |

### Scroll

| Property | Description |
|----------|-------------|
| `--ua-scrollbar-thickness` | Measured native scrollbar thickness |

---

## Reduced Motion

Silk respects `prefers-reduced-motion`:

```tsx
// Default behavior
enteringAnimationSettings={{ 
  preset: "smooth", 
  skip: prefersReducedMotion  // Auto-detected
}}

// Force animation regardless
enteringAnimationSettings={{ 
  preset: "smooth", 
  skip: false 
}}

// Force skip
enteringAnimationSettings={{ 
  skip: true 
}}
```

When `skip: true`:
- Sheet appears/disappears instantly
- No travel animation occurs
- Focus management still happens
