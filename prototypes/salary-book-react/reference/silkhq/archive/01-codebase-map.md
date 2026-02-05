# 01 - Codebase map (package + examples)

## Package under analysis

Package: `node_modules/@silk-hq/components` (v0.9.12 in this repo)

Key files:

- `node_modules/@silk-hq/components/dist/module.mjs`
  - Main ESM runtime.
  - Contains: component implementations, the global runtime registry (`eG`), state machines, WAAPI + spring helpers, data-silk mapping.

- `node_modules/@silk-hq/components/dist/main.cjs`
  - CJS build; same logic.

- `node_modules/@silk-hq/components/dist/types.d.ts`
  - Public API types.
  - Also contains unusually detailed documentation blocks for each prop.
  - Use this as the "declared contract"; use `module.mjs` as the "actual contract".

- `node_modules/@silk-hq/components/dist/main.css`
  - Default styles, wrapped in `@layer silk-defaults { ... }`.

- `node_modules/@silk-hq/components/dist/main-unlayered.css`
  - Same styles without CSS layers.

Exports (from `dist/module.mjs`, near end):

- Components: `Sheet`, `SheetStack`, `Scroll`, `AutoFocusTarget`, `VisuallyHidden`, `Fixed`, `Island`, `ExternalOverlay`
- Utilities/hooks: `createComponentId`, `useClientMediaQuery`, `updateThemeColor`, `useThemeColorDimmingOverlay`, `usePageScrollData`, `animate`

Additionally, `types.d.ts` exports a `mapping` namespace which is useful for understanding the `data-silk` token system:

- `mapping.Sheet.componentName`, `mapping.Sheet.elementNames`, `mapping.Sheet.variationSetsNames`, `mapping.Sheet.variationValuesNames`
- Similar structure for `ScrollTrap`, `Scroll`, `Fixed`, `Island`, `SheetStack`, etc.

## This repo (examples/css)

This project is a Next.js app using the primitives as building blocks.

Where to look:

- `src/app/globals.css`
  - Imports Silk default styles via:
    - `@import "@silk-hq/components/unlayered-styles";`

- `src/components/*/*.{ts,tsx}`
  - Each folder is a pattern: "BottomSheet", "Sidebar", "Toast", "Page", "SheetWithStacking", etc.
  - Full list: BottomSheet, Card, DetachedSheet, LongSheet, Page, PageFromBottom, SheetWithDetent, SheetWithKeyboard, SheetWithStacking, Sidebar, Toast, TopSheet
  - These are not independent libraries; they are composition examples demonstrating:
    - which subcomponents to use
    - which props matter for certain UX
    - what CSS you're expected to provide

## Practical reading workflow

1. Start with `types.d.ts` to understand the public surface area.
2. Cross-check the behavior in `module.mjs`:
   - how a prop is defaulted
   - when effects run (`useEffect` vs `useLayoutEffect`)
   - what's computed vs what's user-controlled
3. Use CSS to understand the DOM structure contract:
   - `Sheet.Content` renders multiple internal wrapper elements; CSS relies on them.
4. Use the examples to learn "intended composition":
   - wrappers mostly customize: `contentPlacement`, `tracks`, `nativeEdgeSwipePrevention`, `themeColorDimming`, and animation props.
