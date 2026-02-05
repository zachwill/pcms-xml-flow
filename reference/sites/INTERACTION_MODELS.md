# Web interaction models — synthesis (from `reference/sites/*`)

This document captures *interaction* patterns (not visual style) distilled from the site notes in `reference/sites/` and ongoing `web/` product thinking.

It exists to answer:
- “What kinds of screens are we building in `web/`?”
- “What is the *default* interaction grammar across tools + entity pages + browsing?”

## TL;DR — three top-level surfaces

### 1) Tools / workbenches (scroll-driven, dense, stateful)
A “tool” is a *continuous planning surface* where **scroll position is primary state** and a sidebar provides drill-in context.

- Canonical example in this repo: **Salary Book** (`web/specs/01-salary-book.md`).
- Common traits:
  - One primary scroll container (“rows are the product”).
  - Sticky command bar with fast toggles/filters.
  - Dense, link-rich rows.
  - Sidebar uses a **base + overlay** model (team context underneath; entity detail on top).
  - Not canonical: lives under `/tools/*`; always provide “open entity page” escape hatches.

### 2) Entity workspaces (single entity, still scroll-first)
An “entity page” (player/team/agent/agency/draft/pick/…) is a *mini-workbench*: one entity identity + many modules stacked vertically.

- Default should be **scroll + sections + scrollspy** (not “everything hidden behind tabs”).
- Tabs (if any) are best used as **lens toggles** (e.g., Cap Hit vs Cash), not as content hiding.
- Canonical + shareable: slug-first URLs, with numeric fallbacks that 301 → canonical.

### 3) Catalog / inbox (many entities + many types)
A “catalog/inbox” surface answers two distinct intents:

- **Identity-first (directory):** “I know what I’m looking for.”
  - e.g., Players index with strong filters/sorts.
- **Time-first (digest):** “What changed / what matters right now?”
  - e.g., last night’s games, transactions, injuries, alerts, saved reports.

This is *not* a Netflix-style thumbnail grid. It’s a front-office terminal: rows, events, saved views, pivots.

---

## The marriage: scroll-first + Bricklink/PuckPedia-tier wayfinding

Bricklink/BuiltWith/PuckPedia frequently use tabs, but the transferable ideas are:

1. **Segmentation:** clear module boundaries for distinct jobs-to-be-done.
2. **Orientation:** breadcrumbs + strong H1 + sticky local nav.
3. **Pivots:** almost every datum is a link to a related entity or filtered view.
4. **State:** deep-linkable URLs (shareable “you should look at *this view*”).

A scroll-first implementation can steal the *functional value of tabs* via:
- section anchors (`#contract`, `#transactions`, …)
- scrollspy-highlighted local nav
- a sticky “entity command bar” for KPI strip + lens toggles

---

## Pattern library (how each reference maps)

### Bricklink (`bricklink.txt`)
What to steal:
- **Scoped search** (“what kind of thing are you searching for?”) before typing.
- **Link-rich density**: every attribute is a pivot into the catalog graph.
- **Inventory/manifest module** as a first-class section on entity pages.

### BuiltWith (`builtwith.txt`)
What to steal:
- **Dual-track layout**: main story (chart/primary content) + **dense numeric sidebar**.
- **Pre-sliced segments**: curated breakdowns that feel like expert filters.
- “Insight → action” proximity (CTA becomes “open report”, “save view”, “compare”, etc.).

### PuckPedia (`puckpedia.txt`)
What to steal:
- **Multi-layer navigation**: global nav + sticky entity/team context sub-nav.
- **Inline definitions** (tooltips) to keep dense screens teachable.
- **Asset drill-down** patterns (overview counts → specific items with provenance).

### Spotrac (`spotrac.txt`)
What to steal:
- **Module ordering** that matches user intent:
  - KPI answers → visual shape/timeline → year-by-year table → audit logs (transactions/injuries).
- Strong use of “explain then prove” (summary first, authoritative table next).

### PCMS (`pcms.txt`)
What to steal:
- One-stop consolidated team sheet.
- Legend/symbol encoding to make wide, dense grids scannable.
- Multi-year horizon columns (front-office planning mental model).

### CapFriendly / SalarySwish (`capfriendly.txt`, `salaryswish.txt`)
What to steal:
- **Answer-first dashboard** (cap/tax/aprons up top).
- **Metric lens toggles** applied to a shared table schema.
- Roster segmentation by status to match accounting rules.

---

## Interaction primitives to standardize in `web/`

Across tools, entity pages, and catalog surfaces:

- **Scrollspy = state** (active section/entity context follows scroll).
- **Sticky command bars** for navigation + filters/lenses.
- **Shared entity header chrome** for wayfinding:
  - breadcrumbs
  - scoped search (Players/Teams/Agents/Agencies)
  - “open in tool” links (ex: Salary Book)
- **Lens toggles** that reframe the same rows (cap vs cash, etc.).
- **Rows are pivots**:
  - in tools: click row → open entity overlay (sidebar)
  - in entity/catalog pages: click row → navigate to canonical entity page
  - click related field → pivot to a related entity (overlay in tools; navigation in entities)
- **Base + overlay sidebar state machine** (don’t nest infinitely).
- **Deep-linkable state**: URL should capture entity + section anchor + (when relevant) lens.
- **Provenance + definitions**: tooltips, “last refreshed”, and source notes for derived fields.
- **Saved reports** as first-class objects (named queries / pinned views).

---

## Catalog/inbox: a practical structure

A coherent “home” can be a scroll stack of dense modules with strong pivots:

- Last night: games / boxscores
- Transactions
- Injuries
- Performance slices (last 5/10 games, etc.)
- Cap alerts / deadlines
- Saved reports (pinned)

And then separate directories for systematic browsing:
- `/players`, `/teams`, `/agents`, `/agencies`, `/draft-selections`
- draft pick groups: `/draft-picks/:team_code/:year/:round` (no global index yet)
- `/transactions` (time-first feed)

The key rule: every module row/event must pivot cleanly into:
1) an entity workspace, and/or
2) a tool/workbench context, and/or
3) a filtered report view.
