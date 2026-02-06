# Entity Command Bar — Interface Specification

> Feb 2026 — Design spec for entity index pages (`/players`, `/teams`, `/agents`, etc.)

## Problem Statement

The current entity pages (`/agents`, `/agencies`, `/players`, `/teams`) are:

1. **Separate routes for related entity types** — `/agents` and `/agencies` are two pages when they should be one workspace with a radio toggle
2. **Arbitrary LIMIT queries** — "Showing a small sample" is a cop-out, not a design
3. **Wrong header pattern** — Uses a search bar + scope buttons, not the proven Salary Book command bar pattern
4. **No filter knobs** — No checkboxes/radios to control what's displayed via Datastar

The Salary Book command bar is the **proven pattern** for this app. Entity index pages should mirror it.

---

## Core Thesis

**Entity index pages are workspaces, not search results.**

The Salary Book command bar has two components:

1. **Entity buttons** — Grid of team codes (ATL, BOS, etc.) for quick navigation
2. **Filter knobs** — Grouped checkboxes/radios that control display via Datastar signals

Entity pages should follow the same pattern:

1. **Entity buttons** — Quick-access buttons for the entity type (or sub-type toggles)
2. **Filter knobs** — Checkboxes/radios that filter/modify the displayed data

---

## Command Bar Anatomy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ COMMAND BAR (sticky, ~100-130px)                                            │
│                                                                             │
│  ┌─────────────────────────┐  │  ┌─────────────────────────────────────┐   │
│  │ ENTITY SELECTOR         │  │  │ FILTER KNOBS                        │   │
│  │ (buttons or radios)     │  │  │ (checkboxes/radios by group)        │   │
│  │                         │  │  │                                     │   │
│  │ Examples:               │  │  │ Examples:                           │   │
│  │ • Team grid (30 buttons)│  │  │ • [x] Active only                   │   │
│  │ • [x] Agents / Agencies │  │  │ • [x] With clients                  │   │
│  │ • A-Z letter buttons    │  │  │ • [ ] Show IDs                      │   │
│  └─────────────────────────┘  │  └─────────────────────────────────────┘   │
│                               │                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key rules:**

- Command bar is **sticky** at top
- Divider separates entity selector from filter knobs
- All knobs use **Datastar signals** to control the view (no page reload)
- Clicking a knob triggers `@get` to refresh the content area (or client-side filtering if data is already loaded)

---

## Entity Workspaces

### `/agents` — Agents & Agencies Workspace

**Route:** `/agents` (single route, replaces `/agencies`)

**Command bar:**

| Component | Type | Options |
|-----------|------|---------|
| Entity type | Radio | `[x] Agents` / `[ ] Agencies` |
| Status | Checkbox | `[x] Active only` |
| Has clients | Checkbox | `[ ] With active clients` |

**Signals:**

```javascript
{
  entitytype: 'agents',      // 'agents' | 'agencies'
  activeonly: true,
  withclients: false
}
```

**Behavior:**

- Toggling `Agents` ↔ `Agencies` swaps the table via Datastar `@get`
- Checkboxes filter the current list
- No LIMIT — show all (agents/agencies are ~100-200 rows max)

**URL structure:**

- `/agents` — defaults to agents view
- `/agents?view=agencies` — agencies view (bookmarkable)
- Individual show pages: `/agents/:slug`, `/agencies/:slug` (still separate)

---

### `/teams` — Teams Workspace

**Route:** `/teams`

**Command bar:**

| Component | Type | Options |
|-----------|------|---------|
| Conference | Radio | `[x] All` / `[ ] Eastern` / `[ ] Western` |
| Quick nav | Buttons | Grid of 30 team codes (like Salary Book) |

**Signals:**

```javascript
{
  conference: 'all',  // 'all' | 'eastern' | 'western'
  activeteam: ''      // for highlighting, optional
}
```

**Behavior:**

- Team buttons link directly to `/teams/:code` (no Datastar needed)
- Conference radio filters the button grid and table
- This is essentially a "team picker" page

**Alternative:** Could redirect `/teams` to `/tools/salary-book` since that's the primary team workspace. The `/teams` index might be unnecessary.

---

### `/players` — Players Workspace

**Route:** `/players`

**Command bar:**

| Component | Type | Options |
|-----------|------|---------|
| Team filter | Buttons | Grid of 30 team codes (click to filter) |
| Contract status | Checkbox | `[x] Under contract` / `[ ] Free agents` / `[ ] Two-way` |
| Alphabet | Buttons | A-Z quick nav (optional) |

**Signals:**

```javascript
{
  team: '',              // empty = all, or team code
  undercontract: true,
  freeagents: false,
  twoway: true
}
```

**Behavior:**

- Clicking a team button filters to that team's players via `@get`
- Checkboxes toggle player categories
- No LIMIT — but may need pagination for 500+ players (Datastar infinite scroll or "Load more")

---

### `/draft-picks` — Draft Picks Workspace

**Route:** `/draft-picks`

**Command bar:**

| Component | Type | Options |
|-----------|------|---------|
| Year | Buttons | `2025` `2026` `2027` `2028` `2029` `2030` `2031` |
| Round | Radio | `[x] All` / `[ ] 1st` / `[ ] 2nd` |
| Owner | Buttons | Grid of 30 team codes (filter by current owner) |

**Signals:**

```javascript
{
  year: '2025',
  round: 'all',
  owner: ''
}
```

---

### `/transactions` — Transactions Workspace

**Route:** `/transactions`

**Command bar:**

| Component | Type | Options |
|-----------|------|---------|
| Date range | Buttons | `Today` `This week` `This month` `This season` `All` |
| Type | Checkboxes | `[x] Trades` `[x] Signings` `[x] Waivers` `[ ] Other` |
| Team | Buttons | Grid of 30 team codes (filter by team involved) |

---

## Shared Header Partial (Revised)

Replace `_entity_header.html.erb` with a new `_command_bar.html.erb`:

```erb
<%#
  Command bar for entity workspaces.

  locals:
  - title: (String) workspace title (e.g., "Agents")
  - signals: (Hash) Datastar signal defaults
  - entity_selector: (Hash) { type: 'radio'|'buttons', options: [...] }
  - filter_groups: (Array) [{ label: 'Status', knobs: [...] }, ...]
  - salary_book_href: (String) optional link back to Salary Book
%>

<header
  id="commandbar"
  class="sticky top-0 z-10 shrink-0 border-b border-border bg-background px-4 pt-3 pb-3"
  data-signals="<%= signals.to_json %>"
>
  <div class="flex items-start gap-4">
    <%# Entity selector (left side) %>
    <div class="flex gap-4">
      <%= render_entity_selector(entity_selector) %>
    </div>

    <%# Divider %>
    <div class="h-16 w-px bg-border self-center"></div>

    <%# Filter knobs (right side) %>
    <div class="flex items-start gap-4">
      <% filter_groups.each do |group| %>
        <div class="space-y-1">
          <div class="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/70">
            <%= group[:label] %>
          </div>
          <div class="space-y-1">
            <% group[:knobs].each do |knob| %>
              <%= render_knob(knob) %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>

    <%# Spacer + Salary Book link %>
    <div class="ml-auto shrink-0">
      <a href="<%= salary_book_href || '/tools/salary-book' %>" 
         class="text-xs text-muted-foreground hover:text-foreground hover:underline">
        Salary Book
      </a>
    </div>
  </div>
</header>
```

---

## Knob Rendering

### Checkbox Knob

```erb
<div class="flex items-center gap-1.5">
  <input
    type="checkbox"
    id="filter-<%= knob[:signal] %>"
    class="size-3.5 accent-primary"
    data-bind="<%= knob[:signal] %>"
  />
  <label for="filter-<%= knob[:signal] %>" 
         class="text-[11px] leading-none cursor-pointer select-none text-foreground/80 hover:text-foreground transition-colors">
    <%= knob[:label] %>
  </label>
</div>
```

### Radio Knob Group

```erb
<div class="flex items-center gap-2">
  <% knob[:options].each do |opt| %>
    <label class="flex items-center gap-1 cursor-pointer">
      <input
        type="radio"
        name="<%= knob[:signal] %>"
        value="<%= opt[:value] %>"
        class="size-3.5 accent-primary"
        data-bind="<%= knob[:signal] %>"
        <%= 'checked' if opt[:default] %>
      />
      <span class="text-[11px] leading-none text-foreground/80 hover:text-foreground transition-colors">
        <%= opt[:label] %>
      </span>
    </label>
  <% end %>
</div>
```

### Button Grid (Team Selector Style)

```erb
<div class="grid grid-cols-5 gap-1">
  <% buttons.each do |btn| %>
    <a
      href="#<%= btn[:value] %>"
      class="relative h-7 px-2 rounded text-xs font-medium transition-all duration-150 border outline-none inline-flex items-center justify-center"
      data-on:click.prevent="$<%= signal %> = '<%= btn[:value] %>'; @get('<%= refresh_path %>')"
      data-class="{
        'bg-primary text-primary-foreground border-primary shadow-sm': $<%= signal %> === '<%= btn[:value] %>',
        'bg-muted/50 text-foreground border-border hover:bg-muted hover:border-foreground/20': $<%= signal %> !== '<%= btn[:value] %>'
      }"
      title="<%= btn[:title] %>"
    ><%= btn[:label] %></a>
  <% end %>
</div>
```

---

## Content Area

Below the command bar, the content area renders based on current signals:

```erb
<main id="entity-content" class="flex-1 overflow-y-auto px-4 py-4">
  <%# This region is patched by Datastar @get calls %>
  <%= render partial: "entities/agents/table", locals: { agents: @agents } %>
</main>
```

**Datastar refresh pattern:**

When a knob changes, trigger:
```javascript
@get('/agents/content?entitytype=' + $entitytype + '&activeonly=' + $activeonly)
```

The controller returns a partial that replaces `#entity-content`.

---

## Migration Plan

### Phase 1: Merge `/agencies` into `/agents`

1. Add `view` param to `Entities::AgentsController#index`
2. Add radio knob: `Agents` / `Agencies`
3. Remove `/agencies` route (or redirect to `/agents?view=agencies`)
4. Remove `Entities::AgenciesController#index`

### Phase 2: Command Bar Partial

1. Create `_command_bar.html.erb` with knob rendering helpers
2. Replace `_entity_header.html.erb` usage on index pages
3. Keep `_entity_header.html.erb` for show pages (different pattern)

### Phase 3: Remove LIMITs

1. Audit all entity index queries
2. Remove arbitrary `LIMIT 50` clauses
3. Add Datastar-powered pagination if needed (unlikely for most entities)

### Phase 4: Datastar Integration

1. Add `data-signals` to command bar
2. Wire up `@get` refresh for knob changes
3. Create `/agents/content` (or similar) endpoints for partial refreshes

---

## Show Pages

Show pages (`/agents/:slug`, `/players/:slug`, etc.) are **different** from index pages:

- They show **one entity** in detail
- They don't need a command bar with entity selectors
- They may have their own knobs (e.g., "Show IDs", "Expand all sections")

For show pages, keep a simpler header with:
- Breadcrumb
- Title + badge
- Back link to index
- Optional filter knobs for the detail view

---

## Summary

| Concept | Index Pages | Show Pages |
|---------|-------------|------------|
| Header | Command bar (entity selector + filter knobs) | Simple header (breadcrumb + title) |
| Pattern | Mirrors Salary Book | Workspace with sections |
| Knobs | Control list filtering | Control detail display |
| Datastar | `@get` to refresh content | Optional (mostly static) |

**Key principles:**

1. ✅ Single workspace with radio toggle for related entities (not separate routes)
2. ✅ Command bar with filter knobs (not search bar + scope buttons)
3. ✅ Show all entities (not arbitrary LIMITs)
4. ✅ Datastar-driven filtering (not page reloads)
