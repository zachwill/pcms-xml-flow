# 06 - SheetStack (stacking orchestration)

SheetStack coordinates multiple Sheets so they behave like a native stack (push/pop), rather than independent overlays.

Primary sources:
- `dist/types.d.ts` for public API
- `dist/module.mjs` for runtime behavior

## Public API

### `<SheetStack.Root>` props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `componentId` | `SheetStackId` | `undefined` | Optional id for explicit association |
| `asChild` | `boolean` | `false` | Merge props onto child element |

### `<SheetStack.Outlet>` props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `forComponent` | `SheetStackId \| "closest"` | closest ancestor | Associate with specific SheetStack |
| `stackingAnimation` | `StackingAnimationPropValue` | `undefined` | Animation driven by stacking progress |
| `asChild` | `boolean` | `false` | Merge props onto child element |

## What SheetStack stores

`<SheetStack.Root>` maintains internal state arrays:

- sheet "data" records (by `sheetId`)
  - includes ability to find the previous sheet in the stack

- sheet "staging data" records
  - used to determine if *any* sheet is not in staging `none`

- `sheetsCount`
  - a numeric count of active sheets
  - used for stacking animation progress computations

It publishes a context value containing:

- `stackId`
- `sheetsCount` + setter
- update/remove sheet data
- update/remove staging data
- `sheetsInStackMergedStaging` (computed: `none` vs `not-none`)

## Association model

A Sheet becomes part of a stack when:

- `<Sheet.Root forComponent={sheetStackId} />`, or
- `<Sheet.Root forComponent="closest" />` and there is an ancestor `<SheetStack.Root>`.

## `<SheetStack.Outlet>`

Purpose:
- lets you animate *something outside the sheets* based on the stack's aggregated stacking progress.

Behavior:
- attaches a `stackingAnimation` to the outlet's element.
- exposes `data-silk~="0aj"` when any sheet in the stack is staging != none.

Important runtime detail:
- When `sheetsCount` becomes 0, runtime calls `removeAllOutletPersistedStylesFromStack(stackId)`.
  - i.e. it cleans up leftover inline styles that were persisted during previous animations.

### Stacking animation progress calculation

For `stackingAnimation` on outlets and Sheet.Content:

- Progress value goes from `0` to `n`, where `n` = number of sheets stacked above
- When 1 sheet is stacked above: progress = 1
- When 2 sheets are stacked above: progress = 2
- etc.

This allows for progressive visual effects:
```tsx
stackingAnimation={{
  translateY: ({ progress }) =>
    progress <= 1
      ? progress * -10 + "px"
      : "calc(-12.5px + 2.5px * " + progress + ")",
  scale: [1, 0.933],
  transformOrigin: "50% 0",
}}
```

The `[1, 0.933]` keyframe syntax interpolates linearly from 0→1 progress only.
For progress > 1, use the function syntax to define custom behavior.

## Registration and data flow

When a Sheet associates with a SheetStack:

1. **Registration**: `Sheet.Root` calls `updateSheetData({ sheetId, ... })` on the stack context
2. **Staging sync**: Sheet updates staging via `updateStagingData({ sheetId, staging })` on state changes
3. **Stacking index**: Sheet receives/updates its stacking index via context
4. **Previous sheet lookup**: `getPreviousSheetDataInStack(sheetId)` returns the sheet below in the stack
5. **Deregistration**: On unmount, Sheet calls `removeSheetData(sheetId)` and `removeStagingData(sheetId)`

### Persisted styles mechanism

During stacking animations, styles are applied inline and "persisted" via:
1. Animation runs via WAAPI
2. On animation finish: `commitStyles()` → `cancel()`
3. This leaves computed values as inline styles
4. On stack clear (`sheetsCount === 0`): `removeAllOutletPersistedStylesFromStack()` cleans them up

## The hard part (stack choreography)

Stacking is not only "z-index ordering".

Each Sheet has:
- a stacking index
- a position state: front/covered/out

The machines coordinate who is allowed to come front, who must be covered, and when to decrement indices.

If you rewrite:
- model this as a stack automaton:
  - push transitions: previous front becomes covered
  - pop transitions: covered sheet returns front
  - while traveling, intermediate statuses exist (opening/closing/going-up/going-down)
