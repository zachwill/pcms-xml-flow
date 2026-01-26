# Silk (@silk-hq/components) — Reverse-engineered specs

Scope: this directory turns `node_modules/@silk-hq/components` and this repo’s `src/` examples into a set of implementation-level specs.

Everything here is grounded in:
- `node_modules/@silk-hq/components/dist/module.mjs` (runtime implementation)
- `node_modules/@silk-hq/components/dist/types.d.ts` (public API + docblocks)
- `node_modules/@silk-hq/components/dist/main.css` + `main-unlayered.css` (default styles)
- `src/components/**` (how the authors intend you to compose primitives)

## Reading order

1. `01-codebase-map.md` — where everything lives, what to read first.
2. `02-data-silk-and-css-contract.md` — the styling/selector contract (critical).
3. `03-animation-system.md` — travel/stacking animation model + WAAPI helper.
4. `04-sheet-runtime-model.md` — Sheet state machines + travel model.
5. `05-sheet-subcomponents.md` — each Sheet sub-component and exact responsibilities.
6. `06-sheetstack.md` — stacking model + outlet animations.
7. `07-scroll-and-scrolltrap.md` — scroll primitive + scroll traps.
8. `08-other-primitives.md` — Fixed, AutoFocusTarget, Island, ExternalOverlay, VisuallyHidden.
9. `09-hooks-and-utilities.md` — exported hooks/utilities and what they actually do.
10. `10-examples-in-this-repo.md` — patterns extracted from `src/components/*`.
11. `11-layer-island-focus-system.md` — Island focus management + layer stacking.
12. `12-reference.md` — CSS tokens, platform quirks, animation settings.

## What these specs are for

- Understand the actual runtime behavior (not marketing).
- Provide a precise contract for a potential rewrite.
- Make it easy to diff: “spec says X; code does Y”.
