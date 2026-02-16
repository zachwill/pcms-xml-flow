# Rails Restructuring Roadmap (Current)

This file tracks what is **actually left** after the namespace flattening work.

_Last updated: 2026-02-11 (controller + helper/presenter extraction pass)_

---

## Current architecture snapshot

The app is now flattened at the top level:

- Controllers live in `app/controllers/*` (no `tools/` or `entities/` controller namespaces)
- Views live in `app/views/<feature>/*` (no `app/views/tools/*` or `app/views/entities/*` roots)
- Shared entity/tool partials are under `app/views/shared/*`
- Routes are top-level (no `scope module: :entities`, no `namespace :tools`)
- Salary Book canonical path is `/` (`salary_book_path`)

Important invariants remain unchanged:

- Datastar runtime + server-rendered HTML
- SQL-first business logic (`pcms.fn_*`, warehouses)
- Stable patch boundary IDs (`#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#flash`)

---

## Completed milestones

### ✅ Namespace flattening

- `tools/*` internals moved up and de-namespaced
- `entities/*` internals moved up and de-namespaced
- JS entry modules moved to top-level (`salary_book`, `system_values`, `team_summary`, `two_way_utility`, `workspace`)
- Route helpers and render partial paths updated to flattened structure

### ✅ URL cleanup

- Salary Book canonical URL is `/`
- `/salary-book` remains available as a direct route
- `/tools/*` prefix removed from active app navigation and internal links

### ✅ Query/service extraction foundation

Query objects/services exist for the key feature areas (`app/queries`, `app/services`) and are actively used by controllers.

### ✅ Agencies controller extraction pass

`agencies_controller.rb` has been slimmed to orchestration-only shape with:

- `AgencyQueries` for SQL access
- `Agencies::IndexWorkspaceState` for index filters/rows/sidebar summary
- `Agencies::ShowWorkspaceData` for show-page hydration

### ✅ Draft selections extraction pass (index + show/sidebar)

`draft_selections_controller.rb` now delegates to focused query/service units:

- `DraftSelections::IndexWorkspaceState` for index filters/rows/sidebar summary
- `DraftSelectionQueries` for SQL access (show/sidebar/redirect seed queries)
- `DraftSelections::ShowWorkspaceData` for show-page hydration
- `DraftSelections::SidebarSelectionPayload` for overlay hydration

This removes duplicated SQL across show/sidebar paths while keeping existing Datastar behavior and patch IDs unchanged.

### ✅ Team Summary controller extraction pass (finalized)

`team_summary_controller.rb` now delegates workspace assembly to:

- `TeamSummaryQueries` for SQL access
- `TeamSummary::WorkspaceState` for filter parsing, compare/step orchestration state, sidebar hydration, state params, and boot-error fallback payloads

Controller cleanup completed:

- Shared state assignment helper
- Overlay partial selection centralized
- Boot error path moved out of controller

### ✅ System Values controller extraction pass (finalized)

`system_values_controller.rb` now delegates to:

- `SystemValues::WorkspaceState` for base workspace loading + boot-error fallback payloads
- `SystemValues::WorkspaceDerivedState` for overlay derivation, metric-finder state, quick cards, and overlay signals

Controller cleanup completed:

- Shared state assignment helper
- Overlay partial selection centralized
- Boot error path moved out of controller

### ✅ Two-Way Utility controller extraction pass

`two_way_utility_controller.rb` now delegates to:

- `TwoWayUtilityQueries` for SQL access
- `TwoWayUtility::WorkspaceState` for filter parsing/base workspace + boot-error fallback payloads
- `TwoWayUtility::OverlayState` for sidebar/overlay hydration and refresh overlay visibility resolution

### ✅ Drafts controller extraction pass

`drafts_controller.rb` now delegates to:

- `Drafts::IndexWorkspaceState` for index filters/results/sidebar summary
- `Drafts::OverlayState` for initial overlay hydration from URL state and visibility checks
- `DraftQueries` for sidebar payload fetches

### ✅ Salary Book controller extraction pass

`salary_book_controller.rb` now delegates major request assembly to focused services under `app/services/salary_book/*`:

- `SalaryBook::WorkspaceState` (show bootstrap + boot-error fallback)
- `SalaryBook::FrameState` (main frame payloads + frame error payloads)
- `SalaryBook::TeamSidebarState` (team/cap/draft/rights sidebar hydration)
- `SalaryBook::ComboboxPlayersState` (combobox request param normalization + payload)
- `SalaryBook::SidebarPickState` (pick overlay hydration)

Additional cleanup:

- `SalaryBookSwitchController` now reuses `FrameState` + `TeamSidebarState` directly (removing duplicated frame/sidebar branch logic).
- Added `app/services/salary_book/README.md` documenting action→service boundaries for future agents.
- Added query delegation from controller to `SalaryBookQueries` so inherited/sibling controllers can safely reuse shared query calls.
- Updated Salary Book integration tests to current URLs (`/salary-book*`) and added switch-team patch-payload coverage.

### ✅ Baseline integration tests exist

`test/integration/` now has broad coverage across major surfaces (entities + tools), instead of only a single model test.

### ✅ Salary Book helper split + presenter foundation

`salary_book_helper.rb` was decomposed into focused helper modules under `app/helpers/salary_book/*`:

- `SalaryBook::FormattingHelper`
- `SalaryBook::ContractsHelper`
- `SalaryBook::PercentileHelper`
- `SalaryBook::AssetsHelper`

A presenter layer was added for sidebar-heavy rendering paths:

- `SalaryBook::PlayerSidebarPresenter`
- `SalaryBook::AgentSidebarPresenter`
- `SalaryBook::PickSidebarPresenter`

Sidebar partials now use presenter-backed precomputed state for header/contract chips/marker/ownership logic, reducing embedded view logic while preserving current Datastar IDs and routes.

Additional partial decomposition landed for pick sidebar:

- `_sidebar_pick.html.erb` reduced to section orchestration
- extracted `_sidebar_pick_ownership.html.erb`, `_sidebar_pick_source_rows.html.erb`, `_sidebar_pick_text_block.html.erb`

---

## What still needs restructuring

## 1) Finish controller slimming (highest priority)

Controllers still over target size:

| Controller | LOC |
|---|---:|
| `agents_controller.rb` | 217 |
| `teams_controller.rb` | 215 |
| `draft_picks_controller.rb` | 213 |
| `agencies_controller.rb` | 201 |

Target:

- Index/overlay orchestration in controllers
- SQL and derivation moved to queries/services
- Bring controllers toward ≤200 LOC where practical

## 2) Helper bloat → presenters / focused helper modules

Current helper sizes:

- `app/helpers/salary_book_helper.rb` ~16 LOC (entrypoint)
- `app/helpers/salary_book/*.rb` ~775 LOC (split by concern)
- `app/helpers/entities_helper.rb` ~336 LOC

Action:

- Continue moving sidebar-heavy conditional/render-prep logic into presenters/view-models
- Keep helper modules as formatting/primitives, not workflow assembly

## 3) Partial decomposition (large ERB files)

Largest files still need decomposition:

- `salary_book/_sidebar_player.html.erb` (418)
- `players/_workspace_main.html.erb` (381)
- `salary_book/show.html.erb` (362)
- `salary_book/_sidebar_agent.html.erb` (358)
- `teams/_workspace_main.html.erb` (352)

Target:

- Keep most partials ≤100–150 LOC
- Extract repeatable row/cell units into shared partials under `app/views/shared/*`

## 4) Introduce lightweight domain objects

Still heavily hash-based in render paths.

Action:

- Add plain Ruby read models/value objects for repeated concepts (cap sheet rows, draft assets, trade summaries, etc.)
- Keep these lightweight and read-oriented

## 5) Test strategy: deepen from integration-only baseline

Current state is better (integration tests exist), but still missing layered confidence.

Next additions:

1. Controller smoke matrix (all public actions)
2. Query object tests under `test/queries/*`
3. Service tests under `test/services/*`
4. Presenter/helper unit tests for formatting and conditional display logic

## 6) Route file ergonomics

Behavior is correct, but route file is large.

Optional cleanup:

- Extract route groups via `draw`/concerns for readability
- Keep current URL contracts unchanged while reorganizing declarations

---

## Recommended sequencing from here

### Phase A — Controller extraction pass

Remaining focus:

1. `agents_controller.rb`
2. `teams_controller.rb`
3. `draft_picks_controller.rb`
4. `agencies_controller.rb` cleanup pass

(`system_values_controller.rb`, `two_way_utility_controller.rb`, `drafts_controller.rb`, `team_summary_controller.rb`, `salary_book_controller.rb`, and `draft_selections_controller.rb` extraction passes completed.)

Gate: no controller >400 LOC; top controllers materially reduced. ✅ (current max: `agents_controller.rb` at 217 LOC)

### Phase B — Sidebar presenter extraction (in progress)

Completed:

- `PlayerSidebarPresenter`
- `AgentSidebarPresenter`
- helper split for `salary_book_helper` into `app/helpers/salary_book/*`

Remaining:

- push more row-level/section assembly out of ERB into presenters
- continue decomposing `_sidebar_player` and `_sidebar_agent` into section partials

Gate: helper split landed; continue reducing oversized sidebar partials.

### Phase C — Partial decomposition + shared row library

Start with Salary Book sidebar + Teams/Players workspace partials.

Gate: no partial >250 LOC in the targeted surfaces.

### Phase D — Test deepening

Add query/service/controller tests around the newly extracted units.

Gate: integration + unit layers both green in CI/local.

---

## What not to change

- Do not introduce Turbo/Hotwire/Stimulus
- Do not move business logic into JS
- Do not reimplement cap/CBA math in Ruby
- Do not change Datastar patch boundary IDs

---

## Related docs

- `web/AGENTS.md` (hard rules + patch boundaries)
- `web/docs/design_guide.md`
- `web/docs/datastar_sse_playbook.md`
