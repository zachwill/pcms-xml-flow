# CSS tokens + styling contract (`data-silk`)

Silk’s styling contract is **token-driven**, not class-driven.

- Runtime generates `data-silk` tokens.
- Default styles (`main.css` / `main-unlayered.css`) target those tokens.
- Apps *can* target tokens too, but Silk’s own examples usually add normal classes on top of primitives.

This file describes the token system and the parts of it that are safe to treat as contract.

---

## Token generation

Source: `dist/module.mjs` (mapping + generator).

### 1) Component name

Each primitive has a compact `componentName` (often single-letter).

Examples (observed):

- Sheet → `"a"`
- ScrollTrap → `"b"`
- Scroll → `"c"`
- Fixed → `"g"`
- SheetStack → `"h"`

### 2) Element tokens: `${componentName}${elementIndex}`

Each subcomponent/element maps to an integer index.

Example (Sheet):

- `view: 1` → token `a1`
- `backdrop: 2` → token `a2`
- `content: 11` → token `a11`

Default CSS targets these tokens directly:

```css
:where([data-silk~="a1"]) { /* Sheet.View defaults */ }
:where([data-silk~="a2"]) { /* Sheet.Backdrop defaults */ }
```

### 3) Variation tokens: `${componentName}${variationSetCode}${variationValueCode}`

Silk uses “variation sets” (stateful modifiers) and variation values.

Token shape:

- `a` (Sheet) + `A` (some set) + `a` (some value) → `aAa`

The exact codes are intentionally compact and can change across versions.

### 4) Extra ad-hoc tokens (`0a*`)

Not all tokens are derivable from mapping. Runtime sometimes appends literal tokens:

- `0aj`, `0al`, etc.

These act as global flags and appear in default CSS.

Example (conceptual):

- `[data-silk~="0aj"] ... { ... }`

Practical point: **some behaviors are toggled by runtime-only flags**, not by component/element tokens.

---

## The token builder (`D(...)` in runtime)

Runtime builds tokens through a memoized builder:

- `D(componentName, variationConfig?) -> (elementName, variations, { className?, dataSilk? })`

Example call:
- `t("content", ["openness"], { className: "my-content" })`

Behavior:

- **Propagates `className`**: Allows your app classes to coexist with Silk tokens.
- **Generates `data-silk`**: Based on the component mapping.
- **Concatenates**: Merges user-provided `dataSilk` tokens into the final list.

Net effect: every element gets a deterministic token list without losing user classes.

---

## CSS import requirement / runtime check

`Sheet.Root` checks a CSS custom property:

- reads `--silk-aY`
- if it is not `"1"`, it warns that Silk’s styles aren’t imported

So importing one of these is effectively required for default behavior:

- `@silk-hq/components/layered-styles`
- `@silk-hq/components/unlayered-styles`

---

## Layered vs unlayered styles

- `layered-styles`: wraps defaults in `@layer silk-defaults { ... }`
- `unlayered-styles`: emits plain CSS (no layers)

Use layered if you want predictable override ordering via CSS layers.

---

## What you can rely on

Stable-enough contract:

- every Silk element receives `data-silk`
- element token shape `${componentName}${elementIndex}`
- runtime may add additional literal tokens (`0a*`) as flags

Not stable:

- the specific short codes (component letters, variation set/value codes)

Practical recommendation:

- rely on your own classes for styling
- use token selectors primarily for debugging/inspection or last-resort overrides

---

## Developer tip: inspecting mapping

`types.d.ts` exports a `mapping` namespace.

```ts
import { mapping } from "@silk-hq/components";

mapping.Sheet.componentName;             // "a"
mapping.Sheet.elementNames.content;      // 11
mapping.Sheet.variationSetsNames.openness; // e.g. "G" (version-specific)
```

---

## Reference tables (observed)

### Component tokens (with intent)

| Token | Component | Purpose / Interaction |
|------:|-----------|:----------------------|
| `a` | Sheet | Main overlay primitive (travel + stacking). |
| `b` | ScrollTrap | Internal gesture absorber; used by Sheet and Fixed. |
| `c` | Scroll | Advanced scroll container (gesture trapping, visual viewport aware). |
| `d` | SlideShow | (Reserved/Future) |
| `e` | VisuallyHidden | Accessibility utility. |
| `f` | SpecialWrapper | Absorbs scroll gestures inside Sheets to prevent travel triggers. |
| `g` | Fixed | `position: fixed` with transform compensation and gesture trapping. |
| `h` | SheetStack | Orchestrates multiple Sheets. |
| `i` | AutoFocusTarget | Target for focus management during present/dismiss. |

### Sheet element indices

| Token | Element |
|------:|---------|
| `a0` | root |
| `a1` | view |
| `a2` | backdrop |
| `a3` | backdropTrap (internal) |
| `a4` | primaryScrollTrapRoot (internal) |
| `a5` | secondaryScrollTrapRoot (internal) |
| `a6` | scrollContainer (internal) |
| `a7` | frontSpacer (internal) |
| `a8` | backSpacer (internal) |
| `a9` | detentMarker (internal) |
| `a10` | contentWrapper (internal) |
| `a11` | content |
| `a12` | bleedingBackground |
| `a13` | stickyContainer (internal) |
| `a14` | sticky (internal) |
| `a15` | leftEdge (internal; native edge swipe prevention) |
| `a16` | trigger |
| `a17` | handle |
| `a18` | outlet |

### Global tokens (not exhaustive)

| Token | Meaning |
|------:|---------|
| `0aj` | staging != none marker; used when runtime-driven inline styles/animations are active |
| `0al` | Fixed marker |
