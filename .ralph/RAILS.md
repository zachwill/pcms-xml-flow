# Rails - Entity Explorer Roadmap (web/)

This is the **single source of truth** for Rails work in this repo.

Scope:
- `web/` Rails + Datastar app
- Bricklink-style **entity explorer** (players/teams/agents/agencies/drafts/picks…)
- Keep the Salary Book tool healthy, but treat it as *maintenance* unless explicitly expanding it.

Non-goals:
- Re-implementing cap/trade/CBA logic in Ruby/JS (it belongs in Postgres: `pcms.*` warehouses + `pcms.fn_*`).
- Turning entity pages into prose/documentation pages.

---

## Reading order (before coding)

1) `web/AGENTS.md` - conventions + URL rules + Datastar posture
2) `web/specs/00-ui-philosophy.md` - scroll position as state, shallow navigation
3) `reference/sites/bricklink.txt` - link-rich, data-dense entity hub model
4) `reference/sites/puckpedia.txt` - team workspace model (tabs, vitals, drill-ins)
5) `reference/sites/builtwith.txt` - search-first index + slices + pivots
6) Prototype reference (read-only): `prototypes/salary-book-react/`

---

## Mental model (keep this consistent)

### Tools vs Entities (two representations of the same object)

We intentionally maintain **two surfaces** for the same underlying entities:

**Tools (ex: Salary Book)**
- job: "answer the next question without losing your place"
- interaction: scroll-driven; sidebar overlays; shallow stack (Back pops)
- data: optimized slices, not exhaustive
- URLs: under `/tools/*` (not canonical)

**Entities (catalog / hubs)**
- job: "this is the object; explore its neighborhood"
- interaction: link graph; dense modules; multiple views/tabs later
- data: can be deep and multi-section (Spotrac/PuckPedia-like)
- URLs: clean, top-level, shareable and canonical

Rule: **Tools should link outward to entity pages**, and entity pages should offer "open in tool" backlinks.

### Why Bricklink works (and what we're copying)

Bricklink doesn't "render everything." It:
- anchors identity in a compact hero
- exposes a few high-leverage slices (inventory/market/history)
- makes nearly every datum a **pivot**

We want the same for PCMS/NBA data.

---

## URL rules (hard constraints)

- Canonical entity routes are **slug-only**.
- Keep **numeric fallbacks** that 301 → canonical slug.
- Slugs live in `web.slugs` (`Slug` model): aliases allowed; one canonical slug per `(entity_type, entity_id)`.
- Progressive enhancement: plain `<a href>` navigation first.

### Special-case: Teams

Teams have a stable natural identifier: `team_code`.

We treat `teams/:slug` where `slug == team_code.downcase` as the canonical intent.
If the slug registry doesn't have the record yet, we **bootstrap it from `pcms.teams`** on first request.

### Special-case: Draft pick "groups"

Future pick assets are naturally keyed today by `(team_code, draft_year, draft_round)`.
We expose them as:

- `/draft-picks/:team_code/:year/:round`

No slug registry for these yet; we can add one later if we need short/pretty pick URLs.

---

## Entity types & keys (current)

| Entity | Canonical URL | Key | Primary sources |
|---|---|---:|---|
| Player | `/players/:slug` | `pcms.people.person_id` | `pcms.people`, `pcms.salary_book_warehouse`, `pcms.draft_selections` |
| Team | `/teams/:slug` | `pcms.teams.team_id` | `pcms.teams`, `pcms.salary_book_warehouse`, `pcms.draft_pick_summary_assets` |
| Agent | `/agents/:slug` | `pcms.agents.agent_id` | `pcms.agents`, `pcms.salary_book_warehouse`, `pcms.agencies` |
| Agency | `/agencies/:slug` | `pcms.agencies.agency_id` | `pcms.agencies`, `pcms.agents` |
| Draft selection | `/draft-selections/:slug` | `pcms.draft_selections.transaction_id` | `pcms.draft_selections`, `pcms.people`, `pcms.teams` |
| Draft pick group | `/draft-picks/:team_code/:year/:round` | natural key | `pcms.draft_pick_summary_assets`, `pcms.teams` |

---

## Current implementation status (Feb 2026)

Implemented in `web/`:

- Players
  - `/players` index (search-first)
  - `/players/:id` numeric fallback → slug (creates canonical on demand)
  - `/players/:slug` show

- Teams
  - `/teams` index
  - `/teams/:id` numeric fallback → slug
  - `/teams/:slug` show (bootstraps from `team_code`)

- Agents
  - `/agents` index (search-first)
  - `/agents/:id` numeric fallback → slug
  - `/agents/:slug` show

- Agencies
  - `/agencies` index (search-first)
  - `/agencies/:id` numeric fallback → slug
  - `/agencies/:slug` show

- Draft selections (historical picks)
  - `/draft-selections` index (+ search by player name)
  - `/draft-selections/:id` numeric fallback → slug
  - `/draft-selections/:slug` show

- Draft picks (future pick assets)
  - `/draft-picks/:team_code/:year/:round` show (grouped asset rows)

- Salary Book → Entity linking
  - Sidebar overlays expose "Open team/agent/pick page" links
  - Entity pages expose "Open in Salary Book" backlinks

---

## Backlog (ordered)

### A) Make linking *effortless* (highest leverage)

- [x] Add canonical link helper(s) so we stop hardcoding `/agents/:id` everywhere
  - `web/app/helpers/entity_links_helper.rb` (request-local slug cache + prefetch helper)
  - API: `entity_href(entity_type:, entity_id:)` + convenience helpers (`player_href`, `agent_href`, ...)
  - Behavior: if canonical slug exists → use `/players/:slug`; else use numeric fallback `/players/:id`

- [x] Add a shared "entity header" partial (Bricklink/BuiltWith-style)
  - `web/app/views/entities/shared/_entity_header.html.erb`
  - breadcrumbs
  - scoped search (Players/Teams/Agents/Agencies)
  - quick links back to `/tools/salary-book`

### B) Densify entity pages (v1 modules, still minimal UI)

These should feel more like "hubs" and less like "debug pages," but still stay compact and link-rich.

- [x] Player page modules
  - contract snapshot (salary book horizon) — visual 6-year horizon with option/guarantee badges
  - team history — derived from transactions (SIGN/TRADE/DRAFT/etc.), shows stints with logos
  - stats/percentiles scaffolding — placeholder module for future NBA API ingestion

- [x] Team page modules (PuckPedia-inspired)
  - cap vitals (from `pcms.team_salary_warehouse`) — compact KPI strip at top
  - roster breakdown table (cap hit toggle later) — standard/2W split + accounting buckets
  - draft pick provenance modules — year-by-year grid with pick pills

- [ ] Agent/Agency pages
  - client totals by team
  - agency → top clients

### C) Data primitives (do the work in Postgres)

- [ ] Add/extend warehouses or `pcms.fn_*` functions to support entity pages without Ruby parsing.
  - examples:
    - `pcms.player_team_history_warehouse`
    - `pcms.agent_clients_warehouse`
    - `pcms.draft_pick_timeline_warehouse` (turn `raw_part` into structured timeline JSON)

### D) Salary Book maintenance only

- [ ] Continue UI parity / QA vs prototype as needed (but don't let this block entity work).

---

## Done

- [x] Teams entity routes + controller + index
- [x] Agents entity routes + controller + search index
- [x] Agencies entity routes + controller + search index
- [x] Draft selections entity routes + controller + search index
- [x] Draft pick group entity page (natural key route)
- [x] Upgrade Player entity page to show core connections (team/agent/agency/draft)
- [x] Add Salary Book sidebar "Open entity page" links (team/agent/pick)
- [x] Add canonical entity link helpers (slug-first links w/ numeric fallback) + refactor entity views/tool overlays to use them
- [x] Add shared entity header partial (breadcrumbs + scoped search + Salary Book link) + refactor entity pages to use it
