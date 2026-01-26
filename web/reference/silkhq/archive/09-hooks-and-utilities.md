# 09 — Hooks and utilities (exported)

Exports confirmed in `dist/module.mjs` and `dist/types.d.ts`:

- `createComponentId`
- `useClientMediaQuery`
- `updateThemeColor`
- `useThemeColorDimmingOverlay`
- `usePageScrollData`
- `animate`

---

## `createComponentId()`

```ts
const createComponentId: () => ComponentId;
```

Returns a React context object used as an opaque component instance id.

Used for disambiguation when you have nested roots of the same primitive, or when you need to associate triggers/targets outside the component tree.

Example:
```tsx
const loginSheetId = createComponentId();

// In render:
<Sheet.Root componentId={loginSheetId}>
  ...
</Sheet.Root>

// Elsewhere in the tree:
<Sheet.Trigger forComponent={loginSheetId} action="present">
  Open Login
</Sheet.Trigger>
```

This is not a string id; it's a Context reference.

---

## `useClientMediaQuery(query)`

```ts
const useClientMediaQuery: (value: string) => boolean;
```

Client-only media query hook.

Contract:
- returns `false` on the server and during SSR
- on client, returns whether `window.matchMedia(query).matches`
- updates reactively when the media query result changes

Example:
```tsx
const isDesktop = useClientMediaQuery("(min-width: 768px)");

// Use for responsive placement/tracks
<Sheet.View
  contentPlacement={isDesktop ? "center" : "bottom"}
  tracks={isDesktop ? ["top", "bottom"] : undefined}
/>
```

---

## `updateThemeColor(color)`

```ts
const updateThemeColor: (color: string) => void;
```

Writes a new "underlying theme color" used by the theme-color dimming system.

Runtime behavior:
- validates that color parses as rgb/rgba/hex
- updates the global registry's `underlyingThemeColor`
- recomputes the actual `<meta name="theme-color">` content factoring in active dimming overlays

Example:
```tsx
// Set the base theme color
updateThemeColor("#1a1a2e");

// When Sheet.Backdrop has themeColorDimming="auto",
// it will blend its dimming color with this base
```

---

## `useThemeColorDimmingOverlay({ elementRef?, dimmingColor })`

```ts
const useThemeColorDimmingOverlay: (options: {
  elementRef?: React.RefObject<HTMLElement | null>;
  dimmingColor: string;
}) => {
  setDimmingOverlayOpacity: (alpha: number) => void;
  animateDimmingOverlayOpacity: (options: {
    keyframes: [number, number];
    duration?: number;
    easing?: string;
  }) => void;
};
```

Registers a dimming overlay entry in the global registry. Use this for custom overlays that should affect the browser's theme-color.

**Parameters:**
- `elementRef` — optional ref to associate with this overlay (for z-ordering)
- `dimmingColor` — the color to blend with the underlying theme color (e.g., `"black"`)

**Returns:**
- `setDimmingOverlayOpacity(alpha)` — immediately set opacity (0–1)
- `animateDimmingOverlayOpacity({ keyframes, duration?, easing? })` — animate opacity between two values

Example:
```tsx
const overlayRef = useRef<HTMLDivElement>(null);

const { setDimmingOverlayOpacity, animateDimmingOverlayOpacity } = 
  useThemeColorDimmingOverlay({
    elementRef: overlayRef,
    dimmingColor: "black"
  });

// Animate the theme-color dim when overlay appears
animateDimmingOverlayOpacity({ 
  keyframes: [0, 0.5], 
  duration: 300, 
  easing: "ease-out" 
});
```

Note: Sheet.Backdrop uses a specialized internal pathway when `themeColorDimming="auto"` — this hook is for custom overlays.

---

## `usePageScrollData()`

```ts
const usePageScrollData: () => {
  pageScrollContainer: HTMLElement | undefined;
  nativePageScrollReplaced: boolean | undefined;
};
```

Returns page scroll state after hydration.

**Return values:**
- Before hydration: both values are `undefined`
- If `<Scroll.View nativePageScrollReplacement={true}>` is active:
  - `nativePageScrollReplaced: true`
  - `pageScrollContainer`: the Scroll element replacing body scroll
- Otherwise:
  - `nativePageScrollReplaced: false`
  - `pageScrollContainer`: `document.body`

Use case:
```tsx
const { pageScrollContainer, nativePageScrollReplaced } = usePageScrollData();

// Adapt scroll-linked animations based on container
useEffect(() => {
  if (!pageScrollContainer) return;
  
  const target = nativePageScrollReplaced 
    ? pageScrollContainer 
    : document.documentElement;
  
  // Set up scroll listener
}, [pageScrollContainer, nativePageScrollReplaced]);
```

---

## `animate(element, keyframes, options?)`

```ts
const animate: (
  element: HTMLElement | null,
  keyframes: { [key: string]: [string | number, string | number] },
  options?: {
    duration?: number;
    easing?: string;
  }
) => void;
```

WAAPI wrapper that **persists final styles** after animation completes.

**Behavior:**
1. Calls `element.animate(keyframes, { duration, easing, fill: "forwards" })`
2. On animation finish: calls `commitStyles()` then `cancel()`
3. Result: the final keyframe values become inline styles on the element

This is deliberately different from normal WAAPI usage where styles revert after animation ends.

**Parameters:**
- `element` — the target element (no-op if null)
- `keyframes` — object where each key is a CSS property and value is `[from, to]`
- `options.duration` — animation duration in ms (default varies)
- `options.easing` — CSS easing function (default: `"ease"`)

Example:
```tsx
import { animate } from "@silk-hq/components";

// Fade and scale an element, persisting final state
animate(elementRef.current, {
  opacity: [0, 1],
  scale: [0.9, 1],
}, {
  duration: 300,
  easing: "ease-out"
});
// After 300ms, element has inline styles: opacity: 1; scale: 1;
```

Use cases:
- One-shot animations where you want the end state to stick
- Animations that must survive component state changes
- Coordinating with Silk's persist-after-animate pattern
