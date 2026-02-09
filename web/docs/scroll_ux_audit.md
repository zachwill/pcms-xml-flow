# Scroll UX audit memo (for future me)

## Why this exists

We hit a severe UX failure mode in `Team Summary` (and initially in `System Values`):

- horizontal scroll worked only when mouse was in one narrow sub-region
- sticky headers appeared in the wrong place (looked "mid-page")
- interactions felt random because different parts of the surface had different scroll owners

This memo captures exactly what went wrong and how we fixed it.

---

## The core bug pattern

### Symptom cluster

1. "Sometimes I can scroll sideways, sometimes I can't"
2. Sticky header offset looks wrong (`top-[130px]` appears broken)
3. Sticky row/header appears detached from where user thinks scrolling is happening

### Root cause

**Multiple competing scroll containers** on the same surface.

Typical bad combo:

- page/document scrolling vertically
- nested `overflow-x-auto` wrapper for table body
- sticky header offset tied to commandbar (`top-[130px]`)
- body has global `overflow-x: hidden`, so horizontal scroll only works inside explicit wrappers

Result: users must hover the exact wrapper to horizontal-scroll; sticky can anchor to a different containing block than expected.

---

## What we changed

## 1) `Team Summary` now uses one scroll owner

**File:** `web/app/views/tools/team_summary/show.html.erb`

### Before

- Shell used document-style flow (`min-h-screen`)
- Nested horizontal wrapper in main data surface (`overflow-x-auto overscroll-x-contain`)
- Sticky table header used `top-[130px]`

### After

- Shell is fixed viewport:
  - `h-screen w-screen flex flex-col overflow-hidden`
- Command bar is fixed layer:
  - `header` uses `shrink-0`
- Main is single scroll owner (both axes):
  - `main` = `flex-1 min-h-0 overflow-auto`
- Removed nested horizontal-only wrapper for core table surface
- Sticky table header now anchors to main scroll container:
  - `top-0`

This eliminates pointer-position-dependent scrolling.

---

## 2) `System Values` was moved toward same model

Files:

- `web/app/views/tools/system_values/show.html.erb`
- `web/app/views/tools/system_values/_league_system_values_table.html.erb`
- `web/app/views/tools/system_values/_league_tax_rates_table.html.erb`
- `web/app/views/tools/system_values/_league_salary_scales_table.html.erb`
- `web/app/views/tools/system_values/_rookie_scale_amounts_table.html.erb`

Key adjustments:

- fixed-shell + scrolling main pattern
- section sticky headers set to `top-0` (inside main scroll context)
- retained horizontal wrappers where needed for wide sections
- retained sticky-left Season column

---

## Practical rule set (must follow)

For dense tool surfaces:

1. **Choose one primary scroll owner per surface.**
   - Usually `<main class="flex-1 min-h-0 overflow-auto">` in viewport shells.
2. **If header is sticky inside that scroll owner, use `top-0`.**
3. **Do not force users to discover tiny horizontal-scroll hit areas.**
   - Avoid nested horizontal wrappers unless absolutely necessary.
4. **If nested horizontal scroll is unavoidable, make it explicit and synchronized** (Salary Book does this intentionally with JS refs).
5. **Remember:** global CSS sets `body { overflow-x: hidden; }`.
   - So page-level horizontal scroll does not exist by default.

---

## Audit playbook for `web/`

### Step 1: find likely hotspots

```bash
rg -n "overflow-x-auto|overflow-auto|sticky top-\[130px\]|sticky top-0|h-screen|min-h-screen" web/app/views
```

### Step 2: inspect each tool page for scroll-owner conflicts

Focus first on:

- `web/app/views/tools/*/show.html.erb`
- any tool partial with sticky headers + overflow wrappers

### Step 3: red flags

- A page with document scroll (`min-h-screen`) **plus** inner `overflow-x-auto` data region
- Sticky header using `top-[130px]` while actual scroll happens inside another container
- Horizontal scroll only available in a narrow internal div

### Step 4: migrate if needed

- Convert to viewport shell (`h-screen ... overflow-hidden`)
- Make `main` the scroll owner (`overflow-auto`)
- Move sticky offsets to `top-0` for headers inside that main

---

## Initial suspects to review next

1. `web/app/views/tools/two_way_utility/show.html.erb`
2. `web/app/views/tools/two_way_utility/_team_section.html.erb`

Reason: still using document-scroll style with `top-[130px]` sticky section headers. May be fine, but validate pointer-independent scroll and sticky behavior under narrow viewport + trackpad.

(Other entity pages use table wrappers intentionally; not automatically a bug, but verify only where users report mixed-axis scrolling confusion.)
