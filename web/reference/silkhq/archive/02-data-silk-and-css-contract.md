# 02 - `data-silk` + CSS contract (how styling works)

Silk does **not** style via class names; it styles via a compact token system stored in `data-silk`.

This is the core contract between:
- runtime (`dist/module.mjs`), and
- default styles (`dist/main.css` / `main-unlayered.css`), and
- your app CSS (you can target `[data-silk~="..."]` too, but examples prefer normal class names on top).

## Token generation

Source: `node_modules/@silk-hq/components/dist/module.mjs` (mapping + generator function).

### 1) Component name

Each primitive has a single-letter `componentName`.

Example mapping (from `module.mjs`):
- Sheet → `componentName: "a"`
- ScrollTrap → `"b"`
- Scroll → `"c"`
- Fixed → `"g"`
- SheetStack → `"h"`

### 2) Element tokens: `${componentName}${elementIndex}`

Each subcomponent corresponds to an element name mapped to an integer.

Example: Sheet element names (from `types.d.ts mapping.Sheet.elementNames`):
- `root: 0` → token `a0`
- `view: 1` → token `a1`
- `backdrop: 2` → token `a2`
- `content: 11` → token `a11`
- `handle: 17` → token `a17`
- `outlet: 18` → token `a18`

You'll see these in CSS:
- `:where([data-silk~="a1"]) { position: fixed; ... }` (Sheet.View defaults)
- `:where([data-silk~="a2"]) { background-color: #000; opacity: 0.5; ... }` (Backdrop defaults)

### 3) Variation tokens: `${componentName}${variationSetCode}${variationValueCode}`

Silk uses "variation sets" (think: stateful modifiers) to generate additional tokens.

In the mapping:
- variation set names are encoded (e.g. Sheet `openness: "A"`, `staging: "B"`, …)
- variation values are encoded (e.g. `open: "a"`, `closed: "c"`, `top: "f"`, …)

So a variation token looks like:

- `a` (Sheet)
- `A` (openness variation set)
- `a` (open value)

→ `aAa` (example shape; exact tokens depend on the set/value).

### 4) Extra ad-hoc tokens (`0ac`, `0aj`, …)

Some tokens are not obviously tied to a component+index. They are passed as raw strings into `dataSilk` (e.g. `"0aj"`).

You can see these in runtime when the code calls `D("Sheet")(..., { dataSilk: ["0ac"] })`.

In default CSS, these are used as global modifiers.

Example:
- `[data-silk~="0aj"] [data-silk~="b0"][data-silk~="bCa"][data-silk] { overflow: clip !important; }`

The practical point: **not all tokens are derivable from mapping**, some are "magic flags" set by runtime.

## The token builder (`D`)

Runtime defines a memoized builder:

- `D(componentName, variationConfig?)` returns a function.
- That function is called with:
  - element name (e.g. `"content"`)
  - list of variation sets to apply
  - and optional `{ className, dataSilk }` to append.

Result:
- `className` passed through
- `data-silk` is auto-generated and concatenated with user tokens

Net effect: every Silk element gets a deterministic `data-silk` token list.

## CSS import requirement / runtime check

`Sheet.Root` mounts a dev warning component that checks a CSS custom property:

- It reads `--silk-aY` from the root element.
- If it's not `"1"`, it warns:
  > "The CSS styles for Silk are not found. Please refer to the documentation on how to import them."

So, importing either:
- `@silk-hq/components/layered-styles` or
- `@silk-hq/components/unlayered-styles`

is not optional if you expect default behavior.

## Layered vs unlayered styles

- `layered-styles` wraps defaults in `@layer silk-defaults { ... }`
- `unlayered-styles` emits normal CSS (no layers)

Use unlayered if:
- you don't want to manage CSS layers ordering, or
- your build chain doesn't preserve them correctly.

Use layered if:
- you want to easily override Silk defaults by ordering layers.

## What you can rely on (stable CSS contract)

- Presence of `data-silk` on every internal element.
- Element token = `${componentName}${elementIndex}`.
- Runtime may add extra "global" tokens (`0a*`) to toggle behaviors.

What you should **not** rely on in your own CSS:
- the *specific short codes* (`"a"`, `"A"`, `"f"`, etc.) are intentionally compact; they can change across versions.
- instead, prefer styling via your own classes applied to subcomponents (as the examples do).

## Developer tip: inspecting the mapping

The `mapping` namespace is exported in `types.d.ts` and provides programmatic access to the token structure:

```typescript
import { mapping } from "@silk-hq/components";

// mapping.Sheet.componentName → "a"
// mapping.Sheet.elementNames.content → 11
// mapping.Sheet.variationSetsNames.openness → "A"
// mapping.Sheet.variationValuesNames.open → "a"
```

This is useful for understanding which tokens exist without reverse-engineering the minified runtime.
