# Design guide — practical visual patterns for `web/`

Use this when you need to design or redesign a page and want the same visual language as Salary Book + entity workspaces.

This doc is intentionally concrete: it tells you **which shell pattern to choose**, **which row/cell pattern to use**, and **which classes are expected**.

---

## 30-second startup (for coding agents)

Before writing ERB:

1. **Choose shell pattern**: A (full-viewport tool), B (document-scroll page), or C (entity workspace).
2. **Pick one scroll owner** for dense surfaces (usually `<main class="flex-1 min-h-0 overflow-auto">`).
3. **Choose row pattern**: identity cell (double-row grid) or data cell (`entity-cell-two-line`).
4. **Enforce visual invariants**: row hover = yellow class, numbers = `font-mono tabular-nums`.
5. **Keep content edge-to-edge**: avoid `max-w-*` and `mx-auto` on primary content.
6. **If deviating**, cite an existing page that already does it.

---

## Canonical examples by pattern

Use these as source-of-truth templates.

| Pattern | Primary examples |
|---|---|
| **A. Full-viewport tool** | `web/app/views/tools/salary_book/show.html.erb`, `web/app/views/tools/team_summary/show.html.erb`, `web/app/views/tools/two_way_utility/show.html.erb`, `web/app/views/tools/system_values/show.html.erb`, `web/app/views/entities/players/index.html.erb` |
| **B. Document-scroll page** | `web/app/views/ripcity/noah/show.html.erb` |
| **C. Entity workspace** | `web/app/views/entities/players/show.html.erb`, `web/app/views/entities/teams/show.html.erb` |

Additional workspace variants (legacy but valid when editing existing pages):
- `web/app/views/entities/agents/show.html.erb`
- `web/app/views/entities/agencies/show.html.erb`
- `web/app/views/entities/trades/show.html.erb`

---

## Shell patterns

### Pattern A — Full-viewport tool

Use for scroll-driven tools/catalogs where the page owns the viewport.

```erb
<div id="tool-root" class="h-screen w-screen flex flex-col overflow-hidden bg-background">
  <div id="flash"></div>

  <header id="commandbar"
          class="shrink-0 h-[130px] border-b border-border bg-background flex items-start px-4 pt-3 gap-4">
    <%# selectors, filters, global nav %>
  </header>

  <div id="viewport" class="flex flex-1 overflow-hidden relative">
    <main id="maincanvas" class="flex-1 min-h-0 min-w-0 overflow-auto">
      <%# primary content %>
    </main>

    <aside id="rightpanel" class="w-[30%] min-w-[320px] max-w-[480px] border-l border-border bg-background overflow-hidden relative">
      <div id="rightpanel-base-layer" class="absolute inset-0 overflow-y-auto">
        <div id="rightpanel-base"></div>
      </div>
      <div id="rightpanel-overlay"></div>
    </aside>
  </div>
</div>
```

Rules:
- Root must be `h-screen flex flex-col overflow-hidden`.
- Command bar is fixed-height `h-[130px]` (`shrink-0`).
- Pick one primary scroll owner for the dense surface (usually `#maincanvas` / `<main>` with `overflow-auto`).
- Sticky headers inside that scroll owner should use `top-0`.
- Main canvas and sidebar may scroll independently, but avoid nested accidental scroll owners inside the main surface.

#### Right panel layering contract (Pattern A)

For tool sidebars (Salary Book is the reference):
- `#rightpanel-base-layer` is the scrolling underlay wrapper. Do not patch this directly.
- `#rightpanel-base` is the base context patch target (team/system home context).
- `#rightpanel-overlay` is the drill-in patch target (player/agent/pick detail).
- Closing overlay means returning an empty `#rightpanel-overlay` shell; base remains mounted underneath.

### Pattern B — Document-scroll page

Use when the page is lightweight and document scroll is intentional.

```erb
<div class="min-h-screen bg-background">
  <header id="commandbar"
          class="sticky top-0 z-40 border-b border-border bg-background h-[130px] px-4 pt-3 flex items-start gap-4">
    <%# controls %>
  </header>

  <main class="pb-8">
    <%# edge-to-edge content %>
  </main>
</div>
```

Rules:
- Keep `min-h-screen bg-background`.
- Keep command bar sticky with `h-[130px]`.
- Sticky children in document scroll context should use `top-[130px]`.
- Do **not** use this pattern for dense two-axis tools (use Pattern A).

### Pattern C — Entity workspace

Use for single-entity pages with section stacks and optional deferred bootstrap.

```erb
<div id="entity-show" class="min-h-screen w-full bg-background">
  <%= render partial: "entities/shared/commandbar", locals: { active_entity_scope: "players" } %>

  <%# optional deferred bootstrap %>
  <div id="entity-bootstrap" class="hidden" aria-hidden="true" data-init="@get('/players/<%= @slug %>/sse/bootstrap')"></div>

  <main id="maincanvas" class="px-4 pb-8" data-entity-workspace>
    <%= render partial: "entities/shared/entity_header", locals: { ... } %>

    <div class="lg:flex lg:gap-8">
      <%= render partial: "entities/shared/local_nav", locals: { sections: [...] } %>
      <div class="min-w-0 flex-1 space-y-8">
        <%# section modules %>
      </div>
    </div>

    <%# keep overlay target when page supports detail overlays %>
    <div id="rightpanel-overlay"></div>
  </main>
</div>
```

Rules:
- Prefer `entities/shared/entity_header` for new workspaces.
- Section blocks use `scroll-mt-24 space-y-3` + uppercase `h2`.
- If page already uses `workspace_header`, follow local precedent unless migrating intentionally.

---

## Row and cell patterns (core density)

### 1) Identity cell: double-row grid

Used for player/team/agent identity columns.

```erb
<div class="grid grid-cols-[36px_1fr] grid-rows-[24px_16px]">
  <div class="row-span-2 flex items-center justify-start">
    <div class="w-8 h-8 rounded border border-border bg-background overflow-hidden"></div>
  </div>

  <div class="h-[24px] flex items-end min-w-0 pl-2">
    <span class="truncate font-medium text-[14px]">Name</span>
  </div>

  <div class="h-[16px] -mt-px flex items-start gap-2 min-w-0 pl-2 leading-none text-[10px] text-muted-foreground/80 tabular-nums">
    <span>meta</span>
  </div>
</div>
```

Acceptable width variants exist (`grid-cols-[34px_1fr]`, `grid-cols-[40px_1fr]`) depending on the column.

### 2) Data cell: `entity-cell-two-line`

Defined in `web/app/assets/tailwind/application.css`.

```erb
<div class="entity-cell-two-line">
  <div class="entity-cell-primary justify-end font-mono tabular-nums">
    <%= format_compact_currency(value) %>
  </div>
  <div class="entity-cell-secondary justify-end font-mono tabular-nums">
    under cap
  </div>
</div>
```

Use this for numeric/financial columns.

### 3) Row container + hover (universal)

Default shared hover:

```erb
<div class="group cursor-pointer transition-colors duration-75 hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10">
```

Dense Salary Book surfaces may use a stronger dark hover:

```erb
<div class="group cursor-pointer transition-colors duration-75 hover:bg-yellow-50/70 dark:hover:bg-yellow-900/25">
```

For `<tr>` rows:

```erb
<tr class="hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10 transition-colors duration-75">
```

If a column is sticky-left, it must carry matching `group-hover:` background classes. Keep hover intensity consistent across the same surface.

---

## Table conventions

Base wrapper and table classes:

```erb
<div class="overflow-x-auto rounded-lg border border-border">
  <table class="entity-table min-w-full text-xs">
```

Header convention:
- `bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground/90`

Body convention:
- `divide-y divide-border`
- row hover class above

Use `<table>` for ordinary tabular sections.
Use flex/sticky column layouts when you need complex frozen-column behavior like Team Summary.

---

## Number, chip, and typography conventions

- **Numeric/financial values**: `font-mono tabular-nums`.
- **Positive room**: `text-emerald-600 dark:text-emerald-400`.
- **Negative/over**: `text-red-500`.
- **Nil values**: `—`.
- **Chips**: `entity-chip entity-chip--{muted|warning|danger|success|accent}`.

Common text sizes:
- Row primary: `text-[14px] font-medium`
- Row secondary/meta: `text-[10px] text-muted-foreground/80`
- Table header: `text-[10px] font-medium uppercase tracking-wide`

---

## New page checklist (design)

- [ ] Chosen shell pattern A/B/C.
- [ ] Command bar matches `h-[130px]` structure.
- [ ] Main content is edge-to-edge (no max-width centering).
- [ ] Identity rows use double-row grid pattern.
- [ ] Numeric/data cells use `entity-cell-two-line` where appropriate.
- [ ] Row hover uses yellow hover class (and consistent dark hover intensity for that surface).
- [ ] Financial numbers use `font-mono tabular-nums`.
- [ ] Sticky headers use `top-0` inside scrolling `<main>`; use `top-[130px]` only in document-scroll shells.
- [ ] Dark mode variants are present for custom color overrides.
- [ ] Any intentional deviation references an existing page pattern.

---

## Anti-patterns

- Card-heavy layouts with excessive whitespace for row-first data.
- Custom hover palettes instead of the shared yellow hover class.
- `max-w-* mx-auto` wrapping primary tool/entity content.
- Mixed scroll ownership on dense surfaces (document scroll + nested `overflow-x-auto` islands).
- Recreating component CSS when existing utilities/classes already cover it.
- Switching to client-rendered JSON for server-rendered surfaces.

---

## Maintenance rule

When changing a canonical class pattern in ERB/CSS, update this file and `web/AGENTS.md` in the same PR.
