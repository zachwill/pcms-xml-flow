# Design Evolution Queue (`web/`)

This file is for **design evolution**, not design hygiene.

## Mission

Raise the overall design quality of non-Salary-Book surfaces in `web/` by improving:
- scan speed
- information hierarchy
- interaction predictability
- density/readability balance
- navigation/pivot clarity

Strategic split:
- **Primary convergence:** entity index pages should behave like explorer workbenches (Salary Book interaction grammar: knobs/filters + dense rows + sidebar drill-ins).
- **Parallel evolution:** tools (`team_summary`, `system_values`, `two_way_utility`) should be substantially improved as planning workbenches.

Salary Book is the reference quality bar and is **read-only** for this loop.

## Hard guardrail

Do not modify Salary Book files while running `agents/design.ts`.

## Focus surfaces

Entity index convergence targets:
- `web/app/views/entities/players/index.html.erb`
- `web/app/views/entities/teams/index.html.erb`
- `web/app/views/entities/agents/index.html.erb`
- `web/app/views/entities/agencies/index.html.erb`
- `web/app/views/entities/drafts/index.html.erb`
- `web/app/views/entities/transactions/index.html.erb`
- `web/app/views/entities/trades/index.html.erb`
- `web/app/views/entities/draft_selections/index.html.erb`

Parallel tool evolution targets:
- `web/app/views/tools/team_summary/show.html.erb`
- `web/app/views/tools/system_values/show.html.erb`
- `web/app/views/tools/two_way_utility/show.html.erb`

## What counts as a good task

A good task is one surface + one user flow, with a clear hypothesis and measurable acceptance criteria.

A bad task is broad cosmetic churn (for example, repo-wide class sweeps) with no flow outcome.

## Rubric (score 1-5 before and after)

1. Scan speed
2. Information hierarchy
3. Interaction predictability
4. Density/readability balance
5. Navigation/pivots

## Backlog

- [x] [P1] [INDEX] /players (`web/app/views/entities/players/index.html.erb`) — find and triage players in-list without losing context
  - Problem: Search/filters are not discoverable in the workspace shell, and there is no sidebar drill-in for quick context; users bounce between full pages to inspect details.
  - Hypothesis: Converting Players index to a true explorer workbench (knobs + dense interactive rows + sidebar drill-ins) will materially reduce navigation churn.
  - Scope (files):
    - `web/app/views/entities/players/index.html.erb`
    - `web/app/views/entities/players/_workspace_main.html.erb`
    - `web/app/views/entities/players/_rightpanel_base.html.erb`
    - `web/app/views/entities/players/_rightpanel_overlay_player.html.erb`
    - `web/app/views/entities/players/_rightpanel_clear.html.erb`
    - `web/app/controllers/entities/players_controller.rb`
    - `web/app/controllers/entities/players_sse_controller.rb`
    - `web/config/routes.rb`
    - `web/test/integration/entities_players_index_test.rb`
  - Acceptance criteria:
    - Commandbar exposes discoverable player-specific knobs (at minimum: search query + team/status lens) with visible active-state feedback.
    - Rows remain dense and fully interactive; row click opens `#rightpanel-overlay` with player snapshot and canonical pivots (player/team/agent).
    - Filter/sort interactions that update both `#maincanvas` and sidebar targets use one ordered SSE response.
    - Closing overlay preserves list scroll/context and does not force full-page navigation.
  - Completion notes:
    - What changed:
      - Reworked `/players` into a full workbench shell (`commandbar + maincanvas + rightpanel base/overlay`) with explicit search/team/status/sort knobs and URL-synced Datastar signals.
      - Implemented dense, interactive row rendering in `entities/players/_workspace_main.html.erb`; row selection now opens sidebar overlay instead of forcing full-page navigation.
      - Added sidebar summary/home context in `entities/players/_rightpanel_base.html.erb` and a dedicated player snapshot overlay with canonical pivots in `entities/players/_rightpanel_overlay_player.html.erb`.
      - Implemented ordered multi-region SSE refresh (`/players/sse/refresh`) in `PlayersSseController`, patching `#maincanvas`, `#rightpanel-base`, and clearing `#rightpanel-overlay` in one response.
      - Implemented sidebar endpoints (`/players/sidebar/:id`, `/players/sidebar/clear`) and added focused integration coverage in `entities_players_index_test.rb`.
    - Why this improves the flow:
      - Users can now tune player discovery directly in the commandbar and triage details in-panel, preserving list position and reducing navigation churn.
      - Sidebar drill-ins provide immediate player/team/agent pivots without losing context.
      - Filter/sort refresh behavior is predictable (single SSE transaction across all relevant regions).
    - Rubric (before → after):
      - Scan speed: 2 → 4
      - Information hierarchy: 2 → 4
      - Interaction predictability: 3 → 4
      - Density/readability: 3 → 4
      - Navigation/pivots: 3 → 4
    - Follow-up tasks discovered:
      - Add commandbar patching on refresh if we want filter-summary chips rendered in-header from server state (currently control states themselves are the active feedback).
      - Preserve selected overlay across refresh when selected player remains in result set (current behavior intentionally clears overlay on lens change).
      - Expand status lenses (e.g., min-contract, expiring window) once warehouse-backed definitions are finalized.
  - Guardrails:
    - Do not modify Salary Book files.

- [x] [P1] [INDEX] /teams (`web/app/views/entities/teams/index.html.erb`) — scan cap-pressure teams and pivot fast
  - Problem: Team index is mostly identity metadata; cap/tax pressure signals are missing, so users cannot prioritize what matters without opening each team page.
  - Hypothesis: Adding high-signal financial columns + pressure knobs + sidebar drill-in will make Teams index behave like a decision surface instead of a directory.
  - Scope (files):
    - `web/app/views/entities/teams/index.html.erb`
    - `web/app/views/entities/teams/_workspace_main.html.erb`
    - `web/app/views/entities/teams/_rightpanel_base.html.erb`
    - `web/app/views/entities/teams/_rightpanel_overlay_team.html.erb`
    - `web/app/views/entities/teams/_rightpanel_clear.html.erb`
    - `web/app/controllers/entities/teams_controller.rb`
    - `web/app/controllers/entities/teams_sse_controller.rb`
    - `web/config/routes.rb`
    - `web/test/integration/entities_teams_index_test.rb`
  - Acceptance criteria:
    - Commandbar provides discoverable conference/pressure knobs (cap/tax/apron lenses) with URL-reflected state.
    - Rows include dense financial cells (mono/tabular values) and retain fast scanning ergonomics.
    - Clicking a row opens sidebar drill-in while preserving main list context; drill-in includes obvious pivots to canonical team page and Team Summary tool.
    - Multi-region updates (main + sidebar) are delivered via single SSE patch sequence.
  - Completion notes:
    - What changed:
      - Rebuilt `/teams` as a full workbench shell (`commandbar + maincanvas + rightpanel base/overlay`) with search + conference + pressure + sort controls bound to URL-synced Datastar signals.
      - Added dense cap-pressure rows in `entities/teams/_workspace_main.html.erb` with mono/tabular financial cells for cap space, tax room, apron room, tax owed, and roster context.
      - Implemented sidebar home context in `entities/teams/_rightpanel_base.html.erb` (snapshot KPIs + pressure board) plus a team drill-in overlay in `entities/teams/_rightpanel_overlay_team.html.erb` with pivots to canonical team page and Team Summary.
      - Implemented team sidebar endpoints (`/teams/sidebar/:id`, `/teams/sidebar/clear`) and one-request SSE refresh (`/teams/sse/refresh`) in `TeamsSseController`, patching `#maincanvas`, `#rightpanel-base`, and clearing `#rightpanel-overlay` in-order.
      - Added focused integration coverage in `entities_teams_index_test.rb` for commandbar presence, SSE multi-region response shape, and sidebar open/clear behavior.
    - Why this improves the flow:
      - Users can immediately isolate pressure cohorts (conference + cap/tax/apron lens), scan the critical financial posture inline, and open team detail without losing list position.
      - Sidebar drill-ins now provide fast in-context pivots to deeper team analysis tools instead of forcing full-page hops for every row.
      - Refresh behavior is predictable and atomic across main list + sidebar context because updates ship in one SSE sequence.
    - Rubric (before → after):
      - Scan speed: 2 → 4
      - Information hierarchy: 2 → 4
      - Interaction predictability: 3 → 4
      - Density/readability: 3 → 4
      - Navigation/pivots: 3 → 4
    - Follow-up tasks discovered:
      - Preserve an open team overlay across refresh when the selected team remains visible in the filtered result set.
      - Add a season selector to the Teams index once multi-year index scanning is prioritized (currently fixed to 2025 for pressure triage).
      - Tighten Team Summary deep-link contract further by supporting explicit `team=` selection state in that tool.
  - Guardrails:
    - Do not modify Salary Book files.

- [x] [P1] [INDEX] /agents (`web/app/views/entities/agents/index.html.erb`) — keep drill-in context stable while filtering/sorting
  - Problem: Refresh interactions can clear overlay context aggressively, causing users to lose selected entity focus during iterative filter/sort work.
  - Hypothesis: Preserving selected overlay when possible (and explicit fallback behavior when not) will improve predictability and comparison workflows.
  - Scope (files):
    - `web/app/views/entities/agents/index.html.erb`
    - `web/app/views/entities/agents/_workspace_main.html.erb`
    - `web/app/controllers/entities/agents_controller.rb`
    - `web/app/controllers/entities/agents_sse_controller.rb`
    - `web/test/integration/entities_agents_index_test.rb`
  - Acceptance criteria:
    - If selected agent/agency remains in filtered results, overlay stays open and refreshes with current lens values.
    - If selected entity is filtered out, overlay closes with explicit, predictable state reset.
    - Selected row is visually identifiable after refresh to preserve user orientation.
    - URL state, Datastar signals, and rendered knob states remain synchronized.
  - Completion notes:
    - What changed:
      - Extended the Agents refresh request contract to send current overlay selection (`selected_type` + `selected_id`) while keeping URL filter state clean/same as before.
      - Added selected-row visual treatment in `entities/agents/_workspace_main.html.erb` for both agent and agency modes using overlay-aware row state (`$overlaytype` + `$overlayid`).
      - Refactored `AgentsController` sidebar data queries into reusable payload loaders (`load_sidebar_agent_payload`, `load_sidebar_agency_payload`) and added `selected_overlay_visible?` to validate selection against current filtered rows.
      - Updated `AgentsSseController#refresh` to preserve overlay when selected row remains visible, otherwise clear overlay explicitly; refresh now also patches canonical Datastar signals (filters/sort/year + overlay state) in the same SSE response.
      - Added focused integration coverage in `entities_agents_index_test.rb` for commandbar/row-state render, overlay-preserving refresh, and explicit reset when selection is filtered out.
    - Why this improves the flow:
      - Users can keep an open drill-in while iterating filters/sorts, so comparison loops stay in-context.
      - When a selected entity disappears from the result set, reset behavior is explicit and deterministic rather than feeling random.
      - Row-level selected-state styling keeps orientation anchored after refresh and reduces "where am I" scanning.
      - Signal patching keeps server-normalized filter/sort state synchronized with Datastar client state.
    - Rubric (before → after):
      - Scan speed: 4 → 5
      - Information hierarchy: 4 → 5
      - Interaction predictability: 2 → 4
      - Density/readability: 4 → 5
      - Navigation/pivots: 4 → 5
    - Follow-up tasks discovered:
      - Add explicit selected-state styling to rightpanel "Top rows" buttons so sidebar list + main table share the same active marker.
      - Add agency-mode overlay-preservation integration coverage (agent mode is covered now; agency mode relies on the same path).
  - Guardrails:
    - Do not modify Salary Book files.

- [x] [P1] [INDEX] /drafts (`web/app/views/entities/drafts/index.html.erb`) — trace pick ownership/provenance with fewer context switches
  - Problem: Team filtering is hidden in params, and ownership/protection details require jumping away from the index; provenance flow is fragmented.
  - Hypothesis: Exposing team knob + row/cell sidebar drill-in will turn Drafts into a true ownership explorer.
  - Scope (files):
    - `web/app/views/entities/drafts/index.html.erb`
    - `web/app/views/entities/drafts/_results.html.erb`
    - `web/app/controllers/entities/drafts_controller.rb`
    - `web/app/controllers/entities/drafts_sse_controller.rb`
    - `web/app/views/entities/drafts/_rightpanel_base.html.erb`
    - `web/app/views/entities/drafts/_rightpanel_overlay_pick.html.erb`
    - `web/app/views/entities/drafts/_rightpanel_overlay_selection.html.erb`
    - `web/app/views/entities/drafts/_rightpanel_clear.html.erb`
    - `web/config/routes.rb`
    - `web/test/integration/entities_pane_endpoints_test.rb`
  - Acceptance criteria:
    - Commandbar exposes discoverable team/year/round controls across picks/selections/grid views.
    - Clicking a grid/list row opens `#rightpanel-overlay` with protections/provenance summary and pivots to canonical trade/team/draft-pick pages.
    - Switching view mode preserves relevant filter state in URL and clears/retains overlay predictably.
    - Dense table/grid layout is retained (no card conversion).
  - Completion notes:
    - What changed:
      - Rebuilt `/drafts` as a workbench shell (`commandbar + maincanvas + rightpanel base/overlay`) with explicit view/year/round/team controls bound to Datastar signals and URL state.
      - Added ordered SSE refresh endpoint (`/drafts/sse/refresh`) to patch `#drafts-results`, `#rightpanel-base`, and clear `#rightpanel-overlay` in one response when knobs change.
      - Converted draft list/grid rows into interactive drill-ins: picks and selections rows open overlay endpoints, and grid cells now open pick provenance overlays directly.
      - Added dedicated sidebar surfaces for ownership/provenance (`_rightpanel_overlay_pick`) and selection provenance (`_rightpanel_overlay_selection`) plus a summary base panel and clear endpoint.
      - Extended controller query/loading paths to support team-aware filtering, grid year-window control, sidebar payloads, and workspace summary metrics.
      - Expanded `entities_pane_endpoints_test.rb` with focused drafts coverage for commandbar discoverability, SSE multi-region response shape, and pick/selection sidebar endpoints.
    - Why this improves the flow:
      - Team/year/round state is now visible and editable in one place, so users no longer rely on hidden params.
      - Ownership and provenance can be inspected in-panel from either list rows or grid cells, reducing page hops to trace where picks came from.
      - View/filter transitions keep URL and signal state synchronized while clearing overlay state deterministically.
      - Density is preserved (table/grid-first), but with faster pivots to draft-pick, draft-selection, trade, team, transaction, and player pages.
    - Rubric (before → after):
      - Scan speed: 3 → 4
      - Information hierarchy: 2 → 4
      - Interaction predictability: 3 → 4
      - Density/readability: 3 → 4
      - Navigation/pivots: 3 → 4
    - Follow-up tasks discovered:
      - Preserve a compatible open overlay across refresh when the selected pick/selection still exists in the filtered set (current behavior intentionally clears).
      - Add richer team filter affordances (e.g., conference/team-set presets) once cross-index commandbar control patterns are standardized.
      - Consider adding commandbar patching on refresh if draft year option sets should be server-normalized per-view instead of globally unioned.
  - Guardrails:
    - Do not modify Salary Book files.

- [x] [P1] [INDEX] /transactions (`web/app/views/entities/transactions/index.html.erb`) — triage transaction feed in place
  - Problem: Team filter is not visible in UI, and row inspection requires full-page navigation; triage is slower than necessary.
  - Hypothesis: Adding explicit team control and sidebar transaction drill-ins will support rapid feed triage while preserving list position.
  - Scope (files):
    - `web/app/views/entities/transactions/index.html.erb`
    - `web/app/views/entities/transactions/_results.html.erb`
    - `web/app/views/entities/transactions/_rightpanel_base.html.erb`
    - `web/app/views/entities/transactions/_rightpanel_overlay_transaction.html.erb`
    - `web/app/views/entities/transactions/_rightpanel_clear.html.erb`
    - `web/app/controllers/entities/transactions_controller.rb`
    - `web/app/controllers/entities/transactions_sse_controller.rb`
    - `web/config/routes.rb`
    - `web/test/integration/entities_pane_endpoints_test.rb`
  - Acceptance criteria:
    - Commandbar includes discoverable team filter alongside date/type knobs.
    - Clicking a row opens transaction detail overlay (key facts + pivots to transaction/player/team pages) without leaving index.
    - Filter changes that affect both main results and sidebar context are delivered as one SSE response.
    - Interaction model keeps dense rows and predictable hover/selection behavior.
  - Completion notes:
    - What changed:
      - Rebuilt `/transactions` into a full workbench shell (`commandbar + maincanvas + rightpanel base/overlay`) and added an explicit team selector (`#transactions-team-select`) next to date/type controls.
      - Converted transaction feed rows into dense, selectable drill-ins in `entities/transactions/_results.html.erb`; row click now opens sidebar overlay while inline links still pivot canonically with `stopPropagation`.
      - Added sidebar base + overlay surfaces (`_rightpanel_base`, `_rightpanel_overlay_transaction`) with workspace KPIs, quick-feed buttons, transaction key facts, ledger/artifact summaries, and canonical pivots (transaction/player/team/trade).
      - Extended `TransactionsController` with sidebar endpoints and shared state loaders (`sidebar_base`, `sidebar`, `sidebar_clear`, `load_sidebar_transaction_payload`, `build_sidebar_summary!`) plus team option loading.
      - Added `TransactionsSseController#refresh` and route wiring so filter changes patch `#transactions-results`, `#rightpanel-base`, clear `#rightpanel-overlay`, and sync signals in one ordered SSE response.
      - Expanded integration coverage in `entities_pane_endpoints_test.rb` for commandbar team control presence, SSE multi-region response shape, and transaction sidebar open/clear endpoints.
    - Why this improves the flow:
      - Feed triage now stays in one place: users can filter by team/date/type and inspect transaction details in-panel without losing list context.
      - Sidebar quick-feed buttons and row selected-state treatment improve orientation during sequential transaction review.
      - SSE refresh behavior is atomic and predictable across main feed + sidebar context, removing split-refresh uncertainty.
    - Rubric (before → after):
      - Scan speed: 3 → 4
      - Information hierarchy: 3 → 4
      - Interaction predictability: 3 → 4
      - Density/readability: 3 → 4
      - Navigation/pivots: 3 → 4
    - Follow-up tasks discovered:
      - Preserve an open transaction overlay across refresh when the selected transaction remains in the filtered result set (current behavior intentionally clears overlay).
      - Add sort controls (date/type/team route) if transaction triage shifts from “recent first” toward investigation workflows.
      - Reuse the transaction sidebar pattern for `/trades` to keep cross-feed drill-in behavior consistent.
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [INDEX] /trades (`web/app/views/entities/trades/index.html.erb`) — inspect deal anatomy without leaving the list
  - Problem: Team param exists but lacks a visible control; trade rows are scanable but not workbench-interactive for fast package breakdown.
  - Hypothesis: Visible team filter + sidebar trade anatomy preview will improve package comparison speed and reduce page hopping.
  - Scope (files):
    - `web/app/views/entities/trades/index.html.erb`
    - `web/app/views/entities/trades/_results.html.erb`
    - `web/app/controllers/entities/trades_controller.rb`
    - `web/config/routes.rb`
    - `web/test/integration/entities_pane_endpoints_test.rb`
  - Acceptance criteria:
    - Team filter is present and discoverable in commandbar (not only URL param).
    - Row click opens overlay with compact team-in/team-out anatomy, assets summary, and canonical pivots.
    - Multi-target refreshes use ordered SSE patching when main/side panels both change.
    - Rows remain dense, hover-consistent, and link-rich.
  - Rubric (before → target):
    - Scan speed: 3 → 4
    - Information hierarchy: 3 → 4
    - Interaction predictability: 3 → 4
    - Density/readability: 3 → 4
    - Navigation/pivots: 3 → 4
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [INDEX] /agencies entry (`web/app/views/entities/agencies/index.html.erb` + `/agents?kind=agencies`) — make agency exploration first-class
  - Problem: Agency exploration is discoverability-fragile (redirect-only entry, weak wayfinding), so users underuse agency lens workflows.
  - Hypothesis: A first-class Agencies entry flow that lands directly in agency workbench mode will reduce navigation friction and improve adoption.
  - Scope (files):
    - `web/app/controllers/entities/agencies_controller.rb`
    - `web/app/views/entities/shared/_commandbar.html.erb`
    - `web/app/views/entities/agents/index.html.erb`
    - `web/app/views/entities/agents/_workspace_main.html.erb`
    - `web/test/integration/entities_agencies_entrypoint_test.rb`
  - Acceptance criteria:
    - Agencies is an obvious entry path from entity commandbar/navigation and lands in `kind=agencies` mode.
    - Redirects preserve filter/sort query state so shared URLs open identical agency lens state.
    - Agency rows stay dense and interactive with sidebar drill-ins + canonical agency/agent pivots.
    - Active lens (agents vs agencies) is visually explicit and URL-backed.
  - Rubric (before → target):
    - Scan speed: 2 → 4
    - Information hierarchy: 2 → 4
    - Interaction predictability: 2 → 4
    - Density/readability: 3 → 4
    - Navigation/pivots: 2 → 4
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/team-summary (`web/app/views/tools/team_summary/show.html.erb`) — compare teams in-place with sidebar-assisted drill-in
  - Problem: Team Summary is strong for scanning but weak for in-context drill-in and side-by-side reasoning; users must context-switch to team pages.
  - Hypothesis: Adding rightpanel base/overlay behavior and lightweight compare state will make Team Summary a true workbench.
  - Scope (files):
    - `web/app/views/tools/team_summary/show.html.erb`
    - `web/app/controllers/tools/team_summary_controller.rb`
    - `web/config/routes.rb`
    - `web/app/javascript/tools/team_summary.js`
    - `web/test/integration/tools_team_summary_test.rb`
  - Acceptance criteria:
    - Clicking a team row opens sidebar context with KPI breakdown and obvious pivots (team page, related tool context).
    - Users can pin/compare at least two teams without leaving current scroll context.
    - State transitions (select, replace, clear compare) are explicit and predictable.
    - Any multi-region update (main + sidebar + compare strip) uses one ordered SSE response.
  - Rubric (before → target):
    - Scan speed: 4 → 5
    - Information hierarchy: 3 → 4
    - Interaction predictability: 2 → 4
    - Density/readability: 4 → 5
    - Navigation/pivots: 3 → 4
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/system-values (`web/app/views/tools/system_values/show.html.erb`) — compare rule shifts across seasons faster
  - Problem: System Values is dense but serial; users manually scan wide tables to infer year-over-year deltas and section transitions.
  - Hypothesis: Adding a comparison lens + clearer section wayfinding will speed analytical workflows without sacrificing density.
  - Scope (files):
    - `web/app/views/tools/system_values/show.html.erb`
    - `web/app/views/tools/system_values/_league_system_values_table.html.erb`
    - `web/app/views/tools/system_values/_league_tax_rates_table.html.erb`
    - `web/app/controllers/tools/system_values_controller.rb`
    - `web/test/integration/tools_system_values_test.rb`
  - Acceptance criteria:
    - Users can set a baseline season and see explicit delta treatment (visual + numeric) across visible sections.
    - Section wayfinding (System/Tax/Minimum/Rookie) is obvious and keeps orientation while scrolling.
    - Toggle/range changes have predictable patch behavior (single-region HTML or ordered SSE when multiple regions change).
    - Density remains table-first; no cardized replacements.
  - Rubric (before → target):
    - Scan speed: 3 → 4
    - Information hierarchy: 3 → 4
    - Interaction predictability: 3 → 4
    - Density/readability: 4 → 4
    - Navigation/pivots: 2 → 4
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/two-way-utility (`web/app/views/tools/two_way_utility/show.html.erb`) — isolate at-risk two-way situations quickly
  - Problem: Surface is dense and useful, but lacks fast risk filtering and in-panel drill-ins for player-level decision context.
  - Hypothesis: Risk knobs + sidebar drill-ins will improve scan-to-decision speed for two-way management workflows.
  - Scope (files):
    - `web/app/views/tools/two_way_utility/show.html.erb`
    - `web/app/views/tools/two_way_utility/_team_section.html.erb`
    - `web/app/views/tools/two_way_utility/_player_row.html.erb`
    - `web/app/controllers/tools/two_way_utility_controller.rb`
    - `web/test/integration/tools_two_way_utility_test.rb`
  - Acceptance criteria:
    - Commandbar exposes discoverable risk knobs (e.g., low remaining games, estimated limit flags, conference/team narrowing).
    - Row click opens sidebar drill-in with usage trend, contract flags, and canonical pivots to player/team/agent pages.
    - Filter + drill-in behavior preserves main scroll context and keeps state transitions predictable.
    - Layout stays dense and row-first while improving wayfinding cues.
  - Rubric (before → target):
    - Scan speed: 3 → 4
    - Information hierarchy: 3 → 4
    - Interaction predictability: 3 → 4
    - Density/readability: 4 → 5
    - Navigation/pivots: 3 → 4
  - Guardrails:
    - Do not modify Salary Book files.

