# web/AGENTS.md — Rails + Datastar (primary UI)

> Notes for AI coding agents working in **web/**.
> This is the *canonical* human-facing app going forward.

## What `web/` is

`web/` is the home for a **Rails + Datastar** application that turns our Postgres warehouses into:

1) **Entity navigation** (Bricklink-style link graph)
   - players ↔ contracts ↔ teams ↔ seasons ↔ agents/agencies ↔ transactions ↔ picks
   - everything should be linkable and pivotable

2) **Tools** (dense instruments)
   - `/tools/salary-book` (scroll-driven sheet + right-panel intelligence)
   - later: trade machine, buyout calculator, scenario builders, etc.

Core stance:
- **Postgres is the product.** Warehouses + `fn_*` functions are the API.
- Rails renders **HTML-first**.
- Datastar morphs/patches HTML and uses signals for *ephemeral UI state*.

### React prototype

The previous Bun + React Salary Book prototype lives here:
- `prototypes/salary-book-react/`

Use it as a markup/interaction reference (scroll spy, scroll sync, overlay transitions), but treat it as **read-only prototype code**.

## Ruby version (important)

This Rails app is pinned via `web/.ruby-version` (Ruby 3.4.x).

In some environments (including agent shells), `ruby` may resolve to macOS system Ruby (`/usr/bin/ruby`, often 2.6). That will break Bundler/Rails and can cause `bin/dev` to try installing gems into the system Ruby.

Before running Rails commands, ensure Ruby 3.4 is first in `PATH`:

```bash
cd web
# Homebrew Ruby 3.4 (include gem bin dir so `foreman`/`bin/dev` works)
export PATH="/opt/homebrew/opt/ruby@3.4/bin:/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"

ruby -v  # should be 3.4.x
```

---

## Start here (reading order)

1) **UI invariants**
   - `web/specs/00-ui-philosophy.md`
   - `web/specs/01-salary-book.md`

2) **Rails rewrite mental model**
   - `web/MIGRATION_MEMO.md` (rewrite memo / interaction mapping)

3) **Datastar**
   - `reference/datastar/insights.md` (hard rules + gotchas)
   - `reference/datastar/rails.md` (Rails SSE + framing)
   - `reference/datastar/basecamp.md` (Basecamp-ish patterns translated to Datastar)

4) **Bricklink navigation inspiration**
   - `reference/sites/bricklink.txt`

---

## Information architecture (URLs)

### Entities: clean, top-level, slug-first

Goal: URLs that feel like a catalog, without looking like one.

Examples (canonical):
- `/players/lebron`
- `/players/damian-lillard`
- `/teams/bos`
- `/agents/rich-paul`

Rules:
- **Canonical routes are slug-only.**
- Keep an **ID fallback** for migration/debug (ex: `/players/2544` → 301 → `/players/lebron`).
- Slugs are not auto-magical; maintain a **slug registry** (with aliases) so we can manually promote “short slugs” over time.
  - Non-canonical slugs should 301 → the canonical slug.

### Tools: everything dense/instrument-like goes under `/tools/*`

Examples:
- `/tools/salary-book`
- `/tools/trade-machine`

Tool fragment endpoints (Datastar patch targets) should live *under the tool*:
- `/tools/salary-book/sidebar/player/:id`
- `/tools/salary-book/teams/:teamcode/section`

This keeps:
- entity pages canonical + shareable
- tools free to be “weird” without polluting the global URL space

---

## Datastar conventions (treat as hard rules)

From `reference/datastar/insights.md`:

- **Signals are flatcase**: `activeteam`, `overlaytype`, `displaycapholds`
- Signals starting with `_` are **local-only** (not serialized to backend)
- **DOM refs must be underscore-prefixed**:
  - `data-ref="_dialog"` → use as `$_dialog`
- Prefer **stable `id` patch boundaries** and patch whole sections.
- Avoid mixing literal attributes with bindings (`value="..."` + `data-bind`, etc.).

Default response type preference:
1) `text/html` (stable IDs + morph)
2) `application/json` (signal-only patches)
3) `text/event-stream` (only when streaming/progress/live feeds are required)

---

## Tailwind conventions (utility-first in ERB)

We use **`tailwindcss-rails`** (compiled CSS), not the CDN.

**Strong preference**: Write utility classes directly in `.html.erb` partials. Avoid custom CSS classes unless there's a good reason (e.g., Datastar `data-class` toggling, complex animations, or truly reusable components).

### Standard column widths (Salary Book table)

| Element | Width | Class |
|---------|-------|-------|
| Sticky label column | 208px | `w-52` |
| Year cells | 96px | `w-24` |
| Total column | 96px | `w-24` |
| Agent column | 160px | `w-40` |

### Patterns

- **Sticky columns**: `sticky left-0 z-[N]` + `after:` pseudo-element for right border
  ```erb
  class="w-52 shrink-0 pl-4 sticky left-0 z-[2] bg-background relative
         after:absolute after:right-0 after:top-0 after:bottom-0 after:w-px after:bg-border/30"
  ```

- **Row hover**: Use `group` on parent + `group-hover:` on children
  ```erb
  <div class="group hover:bg-yellow-50/70 dark:hover:bg-yellow-900/10">
    <div class="group-hover:text-primary">...</div>
  </div>
  ```

- **Dark mode**: Always include `dark:` variants for backgrounds, text, borders

- **Monospace numbers**: `font-mono tabular-nums`

### Row heights

| Row type | Height | Notes |
|----------|--------|-------|
| Player row | 40px | Two sub-rows: 24px (name/salary) + 16px (metadata) |
| Subsection row | 32px | `h-8` |
| Header row | 32px | `h-8` |

### Font sizes

| Element | Size |
|---------|------|
| Player names | `text-[14px]` |
| Subsection titles | `text-[12px]` |
| Metadata/badges | `text-[10px]` |
| General small text | `text-xs` |

### What stays in CSS

Keep in `app/assets/tailwind/application.css` (Tailwind entrypoint):
- CSS custom properties (design tokens): `--background`, `--foreground`, `--border`, etc.
- Truly global resets or base styles
- ID/selector-driven rules required for Datastar patching (ex: `#rightpanel-overlay`, `:has()` fades)
- Complex animations that can't be expressed in utilities

Avoid `app/assets/stylesheets/application.css` (legacy). The layout does not load it anymore.

---

## The irreducible client-side JS (keep it tiny)

Even with Datastar, Salary Book needs a small JS runtime for:

1) **Scroll spy** (active team + section progress)
2) **Sticky + horizontal scroll sync** (header/body scrollers)
3) **Overlay transitions** (safe-to-unmount exit animations)

Integration pattern:
- JS updates the DOM directly where appropriate (fades, scroll sync)
- JS emits bubbling `CustomEvent`s
- Datastar listens and patches signals (then the server patches HTML)

This keeps the mental model clean:
- *UI state* → signals
- *authoritative data* → server-rendered HTML

---

## Data + DB conventions

- Connection string: `POSTGRES_URL` (repo convention)
  - Rails usually expects `DATABASE_URL`; we should support `POSTGRES_URL` as the primary env var.

- Read-side data:
  - `pcms.*` warehouses + primitives (`pcms.salary_book_warehouse`, `pcms.fn_tpe_trade_math()`, etc.)
  - optional: `public.nba_players` (position metadata)

- Write-side app data (Rails-owned):
  - keep it in a dedicated Rails schema (default: `web`, configurable via `RAILS_APP_SCHEMA`):
    - slug registry
    - user accounts/sessions (if needed)
    - annotations/notes
    - saved views/scenarios

Guardrail:
- **Do not re-implement cap/trade/CBA math in Ruby.**
  - If the UI needs a derived field, add/extend a warehouse or SQL function in `migrations/`.

---

## Where things should live (once Rails is scaffolded)

High-level intended layout:

- Rails code
  - `web/app/controllers/entities/*` → entity pages (routes are top-level)
  - `web/app/controllers/tools/*` → Salary Book + other instruments (`/tools/*`)
  - `web/app/views/...` → partials with stable IDs
  - `web/app/javascript/...` → the tiny Salary Book runtime (no React)

- Product specs + references (already present)
  - `web/specs/*`
  - `web/reference/*`

---

## If you’re about to make changes

Before implementing:
- Identify the **patch boundary** you want (stable `id`).
- Prefer returning HTML that patches that region.
- Ensure URLs remain canonical and shareable (progressive enhancement).
- If you need new data, add it to Postgres warehouses/functions first.
