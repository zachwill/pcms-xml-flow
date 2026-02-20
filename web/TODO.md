# web/TODO.md — Rails Restructuring Roadmap

**Created:** 2026-02-15
**Context:** MVP is working well — entities, tools, Datastar patches, SSE, sidebar overlays all function. This roadmap captures the structural improvements needed to iterate confidently toward v1.

---

## What we got right in the MVP

- **Datastar + server HTML** pattern is correct and should stay
- **Entity / Tool split** (controllers, views, routes) is a good top-level organization
- **SSE controllers** are well-sized (70–130 lines) — good reference pattern
- **Patch boundary IDs** (`#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`) are stable
- **SQL-first business logic** (`pcms.fn_*`, warehouses) keeps CBA math out of Ruby — keep it there
- **Slug model** and entity URL structure (`/players/:slug`, `/teams/:slug`) are clean

---

## What needs restructuring

### 1. Fat controllers → extract query objects + service objects

**Problem:** Most controllers are 600–1,300 lines. They inline SQL query construction, row-level annotation, sorting/filtering logic, and response formatting.

| Controller | Lines | Priority |
|------------|-------|----------|
| `tools/salary_book_controller.rb` | 1,293 | 🔴 Critical |
| `tools/system_values_controller.rb` | 1,070 | 🔴 Critical |
| `entities/players_controller.rb` | 1,056 | 🔴 Critical |
| `entities/drafts_controller.rb` | 900 | 🟡 High |
| `entities/transactions_controller.rb` | 868 | 🟡 High |
| `entities/teams_controller.rb` | 828 | 🟡 High |
| `entities/trades_controller.rb` | 772 | 🟡 High |
| `entities/agents_controller.rb` | 768 | 🟡 High |
| `tools/two_way_utility_controller.rb` | 741 | 🟡 High |

**Target:** Controllers should be ≤200 lines. They call into query/service objects and render.

**Pattern:**

```
app/
  queries/                      # SQL query builders (return result sets)
    salary_book_queries.rb
    player_queries.rb
    ...
  services/                     # Multi-step orchestration
    salary_book/
      team_frame_builder.rb
      sidebar_builder.rb
    ...
```

Each query class encapsulates one SQL concern. Controllers become thin orchestration:

```ruby
# Before (inline in controller)
def show
  rows = ActiveRecord::Base.connection.select_all(<<~SQL)
    SELECT ... FROM pcms.salary_book_warehouse ...
  SQL
  # 80 lines of annotation, sorting, grouping
end

# After
def show
  @frame = SalaryBook::TeamFrameBuilder.call(team: params[:team], year: params[:year])
end
```

---

### 2. Missing model / domain layer

**Problem:** Only `Slug` model exists. All data access is raw SQL in controllers. No place to put shared query logic, computed attributes, or cross-controller reuse.

**Action:** Introduce lightweight read-only models or plain Ruby domain objects for core concepts:

```
app/models/
  salary_entry.rb        # Wraps a salary_book_warehouse row
  team_cap_sheet.rb      # Team-level cap summary
  draft_asset.rb         # Pick ownership record
  trade_record.rb        # Trade with annotations
```

These don't need full ActiveRecord — `Struct`, `Data`, or read-only AR models work fine. The point is a named object with computed methods instead of hash manipulation in controllers.

---

### 3. Helper bloat → presenters or view models

**Problem:** `salary_book_helper.rb` is 641 lines. `entities_helper.rb` is 336 lines. Helpers are grab-bags of formatting, conditional logic, and HTML generation.

**Action:** Move display logic into presenter objects or view-specific helpers:

```
app/presenters/
  player_row_presenter.rb
  salary_book_sidebar_presenter.rb
  cap_hold_presenter.rb
```

Or, at minimum, split the monolithic helpers:

```
app/helpers/
  salary_book/
    formatting_helper.rb
    sidebar_helper.rb
    filter_helper.rb
```

---

### 4. View partial decomposition

**Problem:** Several partials are 250–500 lines:

| Partial | Lines |
|---------|-------|
| `salary_book/_sidebar_player.html.erb` | 494 |
| `salary_book/_sidebar_agent.html.erb` | 368 |
| `players/_workspace_main.html.erb` | 345 |
| `salary_book/show.html.erb` | 332 |
| `players/_rightpanel_base.html.erb` | 270 |
| `salary_book/_player_row.html.erb` | 260 |
| `salary_book/_sidebar_team_tab_cap.html.erb` | 256 |
| `salary_book/_team_section.html.erb` | 249 |

**Target:** Partials should be ≤100 lines. Extract sub-partials for logical sections (contract details, guarantee rows, agent info, etc.).

---

### 5. Test coverage

**Problem:** Only one test exists (`test/models/slug_test.rb`). No controller tests, no integration tests, no system tests.

**Priority tests to add (in order):**

1. **Controller smoke tests** — each action returns 200 (requires DB fixtures or factory setup)
2. **Query object tests** — once extracted, test SQL builders in isolation
3. **Helper / presenter tests** — formatting and display logic
4. **Integration tests** — key user flows (team switch, sidebar drill-in, entity navigation)

Test infrastructure decisions:
- [ ] Decide on fixture strategy (SQL fixtures from warehouse snapshots vs factory_bot)
- [ ] Set up `test/queries/` mirroring `app/queries/`
- [ ] Consider `test/integration/` for Datastar patch flow tests

---

### 6. Route organization

**Current state:** Routes are well-organized but verbose (160+ lines). As entity count grows, consider:

- [ ] Extract entity routes into a shared concern/helper (`draw :entities`)
- [ ] Use `resources` where the pattern fits (sidebar, SSE, pane are consistent across entities)

---

### 7. JavaScript organization

**Current state:** JS is minimal and well-scoped (one file per tool/entity workspace). This is fine for now.

**Future:** If JS grows, consider:
- [ ] Shared utility module for common Datastar signal patterns
- [ ] Extract scroll/measure/sync helpers into a shared module

---

## Sequencing (recommended order)

### Phase 1 — Extract query objects from the biggest controllers

Focus on the three 1,000+ line controllers first:

- [ ] `SalaryBookQueries` — extract from `salary_book_controller.rb`
- [ ] `SystemValuesQueries` — extract from `system_values_controller.rb`
- [ ] `PlayerQueries` — extract from `players_controller.rb`

**Gate:** Each controller drops below 400 lines. Existing behavior unchanged.

### Phase 2 — Introduce presenters for sidebar/overlay views

- [ ] `PlayerSidebarPresenter` — extract from `_sidebar_player.html.erb` + helper
- [ ] `AgentSidebarPresenter` — extract from `_sidebar_agent.html.erb` + helper
- [ ] `SalaryBookHelper` → split into focused modules

**Gate:** `salary_book_helper.rb` < 200 lines. Sidebar partials < 150 lines each.

### Phase 3 — Add controller smoke tests

- [ ] Set up test fixtures / factory approach
- [ ] Smoke tests for all tool controllers
- [ ] Smoke tests for all entity controllers (index + show)

**Gate:** `bin/rails test` passes with coverage of every public action.

### Phase 4 — Decompose remaining entity controllers

- [ ] Extract query objects for drafts, transactions, teams, trades, agents
- [ ] Each controller ≤ 300 lines

### Phase 5 — View partial cleanup

- [ ] Break 250+ line partials into sub-partials
- [ ] Establish shared partial library for common row patterns (identity cells, money cells, date cells)

---

## What NOT to change

- **Datastar as UI runtime** — no Turbo/Hotwire/Stimulus
- **Server HTML responses** — no JSON API layer
- **SQL-first business logic** — CBA math stays in `pcms.fn_*`
- **Patch boundary IDs** — keep `#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay` stable
- **Entity/Tool top-level split** — this organization is correct
- **SSE controller pattern** — these are already well-structured

---

## Related docs

- `web/REFACTOR.md` — Salary Book "apps can take over" refactor (specific feature)
- `web/AGENTS.md` — hard rules, decision trees, Datastar conventions
- `web/docs/design_guide.md` — visual patterns and shell anatomy
- `web/docs/datastar_sse_playbook.md` — SSE response templates
