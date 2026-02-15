# web/AGENTS.md — Rails + Datastar

> Read the hard rules. Follow the decision trees. Read the design guide. Check the checklist before coding.
>
> **New here?** Read in this order: hard rules → `web/docs/design_guide.md` (30-second startup + shell patterns) → checklist below.

---

## Hard rules (non-negotiable)

1. **Server HTML, not JSON.** Datastar patches elements by `id`. Don't return JSON and render client-side.
2. **Multi-region = one response.** Updating 2+ regions? Use a single request/response: either `text/html` morph-by-id patch set (multiple top-level `id` roots) or `text/event-stream` when ordering/signals/streaming are required. Never multiple fetches or client stitching.
3. **No Turbo/Hotwire/Stimulus.** Datastar is the only UI runtime. Don't add Turbo Frames, Turbo Streams, or Stimulus controllers.
4. **Scroll = state.** In tools (Salary Book, etc.), scroll position determines active context. Don't override with click-driven state machines.
5. **Sidebar: base + one overlay.** No modal stacks, no nested overlays. `#rightpanel-base` + `#rightpanel-overlay`, that's it.
6. **Density is the design.** Rows, links, data. Not cards, not whitespace, not "premium aesthetics." Scannable tables are the product.
7. **SQL does the math.** Cap/trade/CBA logic lives in Postgres (`pcms.fn_*`, warehouses). Don't reimplement in Ruby or JS.

---

## Decision trees

### How do I return a response?

```
UPDATING UI?
│
├─ 1 region
│  → return text/html
│  → Datastar morphs content into element by id
│
├─ 2+ regions (commandbar + sidebar, main + flash, etc.)
│  → one response only (never multiple fetches)
│  → if elements-only + top-level id roots available: return text/html patch set
│  → if ordering/signals/streaming needed: return text/event-stream
│  → see: web/docs/datastar_sse_playbook.md
│
└─ signals only, no HTML change
   → return application/json
```

### How do I use the sidebar?

```
SIDEBAR CONTENT?
│
├─ "home" context (team summary, tool state)
│  → patch #rightpanel-base
│
├─ drill-in detail (player, contract, pick)
│  → patch #rightpanel-overlay
│  → set signal: overlaytype = "player" (or relevant type)
│
└─ closing the overlay?
   → clear #rightpanel-overlay innerHTML
   → set signal: overlaytype = ""
```

### How do I add filtering/toggling?

```
FILTER OR TOGGLE?
│
├─ changes what data shows (cap vs cash, include options, etc.)
│  → lens toggle: same URL, signal changes, server re-renders
│
└─ changes which entity/page
   → navigation: URL changes, full page or major section swap
```

### Where does logic live?

```
BUSINESS LOGIC?
│
├─ cap math, trade rules, CBA calculations
│  → SQL: add/extend pcms.fn_* functions or warehouses
│  → run migrations, then call from Rails
│
├─ UI state (which panel is open, scroll position, active filters)
│  → Datastar signals (ephemeral, client-side)
│
└─ rendering decisions (what HTML to show)
   → Rails controllers + ERB partials
```

---

## Datastar request-cancellation gotcha (important)

Datastar backend actions (`@get`, `@post`, etc.) default to `requestCancellation: auto`.

- Cancellation is **per element**.
- If one element fires multiple requests quickly, a newer request can cancel an older in-flight request.

Salary Book guardrail:
- The sidebar-loader element (`#salarybook-sidebar-loader`) fires cap-year updates via `data-effect`. It is a **separate element** from the root `#salarybook` shell, so sidebar refreshes don't cancel team-switch requests (or vice versa).
- If adding new `@get`/`@post` triggers, keep heavy fetches on dedicated elements to avoid cross-cancellation.

## Before you code (checklist)

Answer these before writing code:

- [ ] **Design baseline:** Which shell pattern am I using (A full-viewport, B scrolling page, C entity workspace)?
- [ ] **Patch targets:** Which `id`(s) am I patching? (`#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#flash`)
- [ ] **Response type:** Is this 1 region (HTML), 2+ regions via HTML patch set, or 2+ regions via SSE?
- [ ] **Row treatment:** Am I using dense row patterns (identity double-row grid / `entity-cell-two-line`) instead of card layouts?
- [ ] **Visual invariants:** Row hover uses yellow class, and financial/numeric cells use `font-mono tabular-nums`.
- [ ] **Client JS:** Am I keeping JS to scroll/measure/sync/transition only? No business logic?
- [ ] **Data source:** Is the data I need already in a warehouse or `fn_*` function? If not, extend SQL first.
- [ ] **Existing patterns:** Have I checked similar implementations in `web/app/views/` before inventing something new?

---

## Canonical patch boundaries

These are the stable `id`s Datastar targets:

| ID | What it holds | Owner |
|----|---------------|-------|
| `#commandbar` | navigation + filters + search | shared |
| `#maincanvas` | primary content (table, entity modules) | page-specific |
| `#rightpanel-base` | sidebar "home" context | page-specific |
| `#rightpanel-overlay` | drill-in detail layer | page-specific |
| `#flash` | toast/alerts | shared |

### Salary Book boundaries

| ID | What it holds |
|----|---------------|
| `#salarybook-team-frame` | Patchable frame inside `#maincanvas`. Team switch response morphs this element. |
| `#rightpanel-base` | Team/system context underlay (sidebar team summary + tabs). |
| `#rightpanel-overlay` | Entity overlay layer (player, agent, pick detail). |

Ownership map:
- Shell: `web/app/views/tools/salary_book/show.html.erb`
- Team section partials: `web/app/views/tools/salary_book/_team_section.html.erb`
- Sidebar partials: `web/app/views/tools/salary_book/_sidebar_*.html.erb`
- Team switch controller: `web/app/controllers/tools/salary_book_switch_controller.rb`

### Patch guidance

- Prefer section-level patches, not tiny leaf patches.
- Keep IDs stable across refactors.
- If interaction patches multiple boundaries, use one response (HTML patch set or one-off SSE).
- Protect third-party-managed DOM with `data-ignore-morph`.

---

## Deep dives (read when needed)

| Doc | What it covers |
|-----|----------------|
| `web/RAILS_RESTRUCTURING_ROADMAP.md` | High-level sequencing and structural refactor priorities for Rails controllers/views/helpers/tests |
| `web/docs/design_guide.md` | Concrete visual patterns (shells, row/cell anatomy, table conventions, checklist) |
| `web/docs/datastar_sse_playbook.md` | SSE response templates, Rails `ActionController::Live` patterns |
| `reference/sites/INTERACTION_MODELS.md` | Scroll-driven tools, entity workspaces, catalog surfaces |
| `reference/datastar/insights.md` | Signal naming, DOM refs, Datastar conventions |
| `reference/datastar/rails.md` | Rails + Datastar integration patterns |

Historical/reference:
| Doc | What it covers |
|-----|----------------|
| `prototypes/salary-book-react/` | React prototype (interaction reference, not implementation) |

---

## Quick reference

### Ruby version

Pinned to Ruby 3.4.x via `web/.ruby-version`. Before running Rails commands:

```bash
export PATH="/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"
ruby -v  # should be 3.4.x
```

### Datastar signal conventions

- Signals are **flatcase**: `activeteam`, `overlaytype`, `displaycapholds`
- Underscore prefix = **local-only** (not sent to server): `_scrollpos`
- DOM refs must be underscore-prefixed: `data-ref="_dialog"` → `$_dialog`

### File locations

| What | Where |
|------|-------|
| Entity pages | `web/app/controllers/entities/*`, `web/app/views/entities/*` |
| Tools | `web/app/controllers/tools/*`, `web/app/views/tools/*` |
| Shared partials | `web/app/views/shared/*`, `web/app/views/entities/shared/*` |
| Client JS (minimal) | `web/app/javascript/` |
| Styles | `web/app/assets/tailwind/application.css` |

### URL structure

- Entities: `/players/lebron`, `/teams/bos`, `/agents/rich-paul` (slug-first, canonical)
- Tools: `/tools/salary-book`, `/tools/trade-machine`
- Tool fragments: `/tools/salary-book/sidebar/player/:id` (nested under tool)

### Page layout pattern (mandatory — three layers)

This is the default structure for new pages. If an existing page differs, follow its local pattern unless you are intentionally migrating it.

1. **Command Bar** — `sticky top-0 z-40 h-[130px]`, `border-b border-border bg-background`
2. **Sticky Header(s)** (if applicable) — `sticky top-0 z-30` for column headers inside a viewport-shell scroll owner (Pattern A). Use `sticky top-[130px] z-30` only in document-scroll shells (Pattern B) where the command bar is `sticky top-0`.
3. **Edge-to-edge flex layout** — No `max-w-*` or `mx-auto` on `<main>`. Use `px-4 pb-8`.

Best examples: Salary Book → Two-Way Utility → Team Summary.

Concrete templates: `web/docs/design_guide.md`

### Tailwind patterns

- Utility classes in ERB directly (not custom CSS classes)
- Sticky columns: `sticky left-0 z-[N]`
- Row hover: parent `group` + child `group-hover:`
- Monospace numbers: `font-mono tabular-nums`
- Always include `dark:` variants
