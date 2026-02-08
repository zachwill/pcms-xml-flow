# UI invariants (web)

These are **non-negotiables**. If current behavior and your implementation differ, align to these.

## Product shape

- Rows are the product.
- Scroll position is primary state.
- Sidebar is a 2-level state machine: base + single overlay.
- Filters are lenses, not navigation.

## Surface model

- Tools/workbenches (`/tools/*`): dense, scroll-driven, stateful.
- Entity workspaces: scroll-first module stacks + pivots.
- Catalog/inbox: row/event-driven browsing, not thumbnail grids.

Reference: `reference/sites/INTERACTION_MODELS.md`

## Page layout pattern (mandatory)

This is the default three-layer structure for new pages. If an existing page differs, follow its local pattern unless you are intentionally migrating it.

1. **Command Bar** — `sticky top-0 z-40 h-[130px]` with `border-b border-border bg-background`. Houses navigation, filters, and the global nav dropdown.
2. **Sticky Header(s)** (if applicable) — `sticky top-[130px] z-30` for column headers on data-dense pages (e.g., Team Summary column header, Salary Book table header).
3. **Edge-to-edge flex layout** — Content fills the full viewport width. No `max-w-*` constraints or `mx-auto` centering on `<main>`. Use `px-4 pb-8` for padding.

Canonical examples:
- **Salary Book** (`tools/salary_book/show.html.erb`) — `h-screen flex flex-col`, command bar as `shrink-0`, viewport with `flex-1`
- **Two-Way Utility** (`tools/two_way_utility/show.html.erb`) — `min-h-screen bg-background`, `<main class="pb-8">`
- **Team Summary** (`tools/team_summary/show.html.erb`) — `min-h-screen bg-background`, sticky column header + `<main class="pb-8">`
- Full visual templates: `web/docs/design_guide.md`

### Layout anti-patterns (do not)

- Do not use `max-w-5xl mx-auto` or any max-width centering on `<main>` content areas.
- Do not wrap content in a centered container that prevents edge-to-edge flow.
- Do not use `<table>` elements for primary data layouts that need sticky headers (tables inside `overflow-x-auto` break `position: sticky`).

## Datastar posture

- Server renders HTML; Datastar patches stable IDs.
- Signals are ephemeral UI state, not business authority.
- Keep client JS minimal (scroll/measure/sync/transition glue).

## Design vocabulary (quick reference)

For copy-paste ERB and full class recipes, see `web/docs/design_guide.md`.

- **Shell choice first**: pick A/B/C before writing markup.
- **Row density**: identity rows use double-row grids; numeric rows use `entity-cell-two-line`.
- **Universal row hover**: `hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10`.
- **Financial numbers**: always `font-mono tabular-nums`.

## Anti-patterns (do not)

- Do not use Turbo/Hotwire/Stimulus (Turbo Frames/Streams, Stimulus controllers, etc.). Datastar is the UI runtime.
- Do not orchestrate multi-region updates in custom client JS.
- Do not switch to JSON + client rendering to avoid server HTML.
- Do not avoid SSE just because the response is short-lived.
- Do not re-implement cap/trade/CBA math in Ruby/JS.
