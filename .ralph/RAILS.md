# Rails — What to do next (canonical backlog)

This is the **single source of truth** for Rails work in this repo.

Scope:
- `web/` Rails + Datastar app
- Bricklink-style **entity explorer** (players/teams/agents/picks…)
- Keep the Salary Book tool healthy, but treat it as *maintenance* unless explicitly expanding it.

Non-goals:
- Re-implementing cap/trade/CBA logic in Ruby/JS (it belongs in Postgres: `pcms.*` warehouses + `pcms.fn_*`).
- Turning entity pages into prose/documentation pages.

## Reading order (before coding)

1) `web/AGENTS.md` — conventions + URL rules + Datastar posture
2) `reference/sites/bricklink.txt` — information architecture inspiration
3) `reference/datastar/basecamp.md` + `reference/datastar/insights.md` — patterns + gotchas (only if enhancing)
4) Prototype reference (read-only): `prototypes/salary-book-react/`
5) PCMS mental models (reference implementation): `reference/pcms/MENTAL_MODELS.md`

## Current direction

We are moving from “tool parity work” to “**entity navigation** work”.

**Primary goal:** link-rich, slug-first entity pages that make Postgres warehouses explorable.

## Hard rules (treat as constraints)

- Canonical entity routes are **slug-only**.
- Keep numeric fallbacks that 301 → canonical slug.
- Slugs live in the `Slug` table (aliases allowed; one canonical slug per `(entity_type, entity_id)`).
- HTML-first; progressive enhancement (Datastar optional).
- Don’t duplicate cap/trade math in Ruby.

---

## Backlog (ordered)

### A) Entity explorer (main workstream)

(Imported from the previous `.ralph/ENTITIES.md` backlog; that file should be considered deprecated.)

#### Teams
- [ ] Add Teams entity routes + controller (canonical + numeric fallback)
  - Routes:
    - `GET /teams/:slug` → `Entities::TeamsController#show`
    - `GET /teams/:id` (numeric) → `#redirect` (301 → canonical; create default slug on-demand)
  - Slug registry:
    - `Slug.entity_type = 'team'`
    - `Slug.entity_id = pcms.teams.team_id`
    - Default slug: `team_code.downcase` (e.g. `BOS` → `bos`)
  - Data source: `pcms.teams` (NBA only)
  - View: `web/app/views/entities/teams/show.html.erb`
    - Hero: team name, team code, conference/division
    - Action link: `/tools/salary-book?team=BOS`
    - “Known slugs” list

- [ ] Add `/teams` index page (conference-grouped)
  - Route: `GET /teams` → `Entities::TeamsController#index`
  - Query `pcms.teams`, group Eastern/Western
  - Links can use numeric fallback until canonical slugs exist

#### Agents
- [ ] Add Agents entity routes + controller (canonical + numeric fallback)
  - Routes:
    - `GET /agents/:slug` → `Entities::AgentsController#show`
    - `GET /agents/:id` (numeric) → `#redirect` (301 → canonical; create default slug on-demand)
  - Slug registry:
    - `Slug.entity_type = 'agent'`
    - `Slug.entity_id = pcms.agents.agent_id`
    - Default slug: parameterized agent name; fallback `agent-<id>`
  - Data sources:
    - `pcms.agents` (identity)
    - `pcms.salary_book_warehouse` (client list via `agent_id`)
  - View: `web/app/views/entities/agents/show.html.erb`
    - Hero: agent name, agency
    - Client list: group by current team, show counts + cap totals (2025)
    - Cross-links: players + teams

- [ ] Add `/agents` index page with simple search
  - Route: `GET /agents` → `Entities::AgentsController#index`
  - Query param: `?q=` (case-insensitive match)

#### Link helpers
- [ ] Add helper(s) to generate canonical entity hrefs when available
  - New helper: `web/app/helpers/entity_links_helper.rb`
  - For each entity type: if canonical slug exists → use it; else numeric fallback

#### Upgrade Player page
- [ ] Expand Player entity page (v1) to be link-rich (not just slug debug)
  - Pull minimal snapshot from `pcms.salary_book_warehouse`:
    - current `team_code`, `agent_id`, `agent_name`, `cap_2025..cap_2030`
  - Add cross-links to team + agent pages

### B) Salary Book (maintenance)

- [ ] Visual QA pass vs prototype
  - Scroll spy correctness
  - Overlay layering/back behavior
  - Horizontal scroll sync

---

## Done

(keep this section short; delete items instead of letting it become a graveyard)
