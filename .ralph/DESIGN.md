# Design Evolution Backlog (`web/`)

Design-evolution only (no hygiene churn).

North star:
- Entity index pages behave like explorer workbenches (commandbar + maincanvas + rightpanel-base + rightpanel-overlay).
- Fast scan, meaningful knobs, dense interactive rows, and contextual drill-ins.
- Salary Book is the read-only interaction quality bar.
- Team Summary, System Values, and Two-Way Utility continue converging toward stronger workbench UX.

Rubric (1-5):
1) Scan speed
2) Information hierarchy
3) Interaction predictability
4) Density/readability balance
5) Navigation/pivots

## Supervisor review — 2026-02-13

Scope reviewed:
- `git log --oneline -8`
- `git diff --name-only HEAD~4 -- web/`
- `web/AGENTS.md`
- `web/docs/design_guide.md`
- `web/docs/datastar_sse_playbook.md`
- `reference/sites/INTERACTION_MODELS.md`

Findings:
- Last four commits stay in one clear track: **INDEX convergence** (`/agencies`, `/draft-selections`, `/agents`, `/players`).
- Each commit is tied to an explicit explorer flow (lookup/filter scan + rightpanel drill-in continuity), not broad style churn.
- Datastar response rules remain aligned: multi-region knob refreshes use one SSE response and patch canonical boundaries (`#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`) with explicit overlay preserve/clear semantics.
- No forbidden Salary Book files were touched.
- `.ralph/DESIGN.md` has before/after rubric scoring evidence for each completed item.

Next-loop guardrails (tightened):
- Keep the next task to **one surface + one user flow** (recommended: `/teams` overlay-preservation flow already in backlog).
- Avoid shared partial rewrites unless directly required by that flow; prefer page-local changes.
- Preserve the canonical workbench shell (`commandbar + maincanvas + rightpanel-base + rightpanel-overlay`) and one-request SSE updates for multi-region interactions.

## Backlog

- [x] [P1] [INDEX] /agencies (`web/app/views/entities/agencies/index.html.erb`) — open agencies as a first-class explorer workbench (not a redirect detour)
  - Problem: `/agencies` currently routes users through `/agents?kind=agencies`, which weakens orientation and hides agency-specific scanning context.
  - Hypothesis: A dedicated agencies workbench shell with agency-native knobs + overlay drill-ins will reduce navigation friction and improve agency workflow adoption.
  - What changed (files):
    - `web/app/controllers/entities/agencies_controller.rb`
    - `web/app/controllers/entities/agencies_sse_controller.rb`
    - `web/app/views/entities/agencies/index.html.erb`
    - `web/app/views/entities/agencies/_workspace_main.html.erb`
    - `web/app/views/entities/agencies/_rightpanel_base.html.erb`
    - `web/app/views/entities/agencies/_rightpanel_overlay_agency.html.erb`
    - `web/app/views/entities/agencies/_rightpanel_clear.html.erb`
    - `web/config/routes.rb`
    - `web/test/integration/entities_agencies_index_test.rb`
    - Removed: `web/test/integration/entities_agencies_entrypoint_test.rb` (redirect-era coverage)
  - Why this improves the flow:
    - `/agencies` is now a direct workbench shell (`#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`) instead of a detour redirect.
    - Commandbar now exposes agency-native knobs: name search, activity lens, year lens, sort key, and sort direction.
    - Dense agency rows open an in-place overlay with clear canonical pivots (`/agencies/:slug|:id`, `/agents/:slug|:id`, `/players/:slug|:id`).
    - Multi-region knob refreshes are shipped in one ordered SSE response (main + sidebar base + overlay state/signals).
  - Rubric (before → after):
    - Scan speed: 2 → 4
    - Information hierarchy: 2 → 4
    - Interaction predictability: 3 → 4
    - Density/readability: 3 → 4
    - Navigation/pivots: 2 → 4
  - Follow-up tasks discovered:
    - Add explicit “with clients / with restrictions / with expirings” checkbox lenses if agency triage needs tighter pre-filtering.
    - Consider inline quick actions in agency rows (e.g., open top agent overlay) for even faster shortlist workflows.

- [x] [P1] [INDEX] /draft-selections (`web/app/views/entities/draft_selections/index.html.erb`) — find and trace draft selections without leaving the index flow
  - Problem: Draft selections discovery is legacy search-only and not workbench-oriented; provenance inspection requires context switching.
  - Hypothesis: Converging draft selections into a true index workbench (filters + dense rows + sidebar provenance) will speed historical pick investigation.
  - What changed (files):
    - `web/app/controllers/entities/draft_selections_controller.rb`
    - `web/app/controllers/entities/draft_selections_sse_controller.rb`
    - `web/app/views/entities/draft_selections/index.html.erb`
    - `web/app/views/entities/draft_selections/_workspace_main.html.erb`
    - `web/app/views/entities/draft_selections/_rightpanel_base.html.erb`
    - `web/app/views/entities/draft_selections/_rightpanel_overlay_selection.html.erb`
    - `web/app/views/entities/draft_selections/_rightpanel_clear.html.erb`
    - `web/config/routes.rb`
    - `web/test/integration/entities_draft_selections_index_test.rb`
  - Why this improves the flow:
    - `/draft-selections` is now a dedicated workbench shell (`#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`) with URL-backed query/year/round/team knobs.
    - The main table is always scanable (not query-gated) and rows are dense, click-first pivots into an in-place provenance overlay.
    - Sidebar overlays include full provenance rows plus canonical pivots (`/draft-selections/:slug|:id`, `/draft-picks/:team/:year/:round`, `/transactions/:id`, `/trades/:id`, `/players/:slug|:id`, `/teams/:slug|:id`).
    - Filter changes now refresh main + sidebar base + overlay state in one ordered SSE response, preserving the selected overlay when that row remains visible.
  - Rubric (before → after):
    - Scan speed: 1 → 4
    - Information hierarchy: 2 → 4
    - Interaction predictability: 2 → 4
    - Density/readability: 3 → 4
    - Navigation/pivots: 3 → 5
  - Follow-up tasks discovered:
    - Add a sortable lens (e.g., pick order vs most provenance events) for faster anomaly hunting within busy draft years.
    - Consider an optional “include adjacent years” mode to trace late/early draft-window chains without changing pages.

- [x] [P1] [INDEX] /agents (`web/app/views/entities/agents/index.html.erb`) — jump directly to target agents/agencies while keeping current lens state
  - What changed (files):
    - `web/app/controllers/entities/agents_controller.rb`
    - `web/app/controllers/entities/agents_sse_controller.rb`
    - `web/app/views/entities/agents/index.html.erb`
    - `web/app/views/entities/agents/_workspace_main.html.erb`
    - `web/app/views/entities/agents/_rightpanel_base.html.erb`
    - `web/app/views/entities/shared/_commandbar.html.erb`
    - `web/test/integration/entities_agents_index_test.rb`
  - Why this improves the flow:
    - Agents commandbar now has a first-class search input (`q`) so known-agent and known-agency lookups are direct, not sort/filter-only.
    - Query state is URL-backed and carried through all knob changes (`kind`, filters, year, sort/dir), so users can pivot lenses without losing lookup context.
    - One SSE refresh still patches `#agents-maincanvas`, `#rightpanel-base`, and `#rightpanel-overlay` together, with overlay preserve/clear behavior unchanged and predictable.
    - Search matching is usable in both modes: `kind=agents` matches agent + agency names; `kind=agencies` matches agency names plus member-agent names.
  - Rubric (before → after):
    - Scan speed: 3 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 4 → 4
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Follow-up tasks discovered:
    - Add optional debounced “search-as-you-type” mode to reduce Apply/Clear clicks while preserving request-cancellation safety.
    - Consider row-level match highlighting to improve quick visual confirmation during high-volume scans.

- [x] [P1] [INDEX] /players (`web/app/views/entities/players/index.html.erb`) — preserve selected player drill-in during iterative filter/sort changes
  - What changed (files):
    - `web/app/controllers/entities/players_controller.rb`
    - `web/app/controllers/entities/players_sse_controller.rb`
    - `web/app/views/entities/players/index.html.erb`
    - `web/app/views/entities/players/_rightpanel_base.html.erb`
    - `web/test/integration/entities_players_index_test.rb`
  - Why this improves the flow:
    - Players refresh now carries selected overlay context (`selected_id`) and preserves `#rightpanel-overlay` when that player is still in the filtered result set.
    - When the selected player is filtered out, refresh explicitly clears overlay HTML and resets signals (`overlaytype`, `selectedplayerid`) in the same SSE transaction.
    - Selected-state highlighting is now synchronized between main table row and sidebar quick-list row; sidebar summary also guarantees the selected visible player appears in the quick list.
    - Commandbar knob changes still ship one ordered SSE response for main canvas + sidebar base + overlay/signals.
  - Rubric (before → after):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Follow-up tasks discovered:
    - Add a lightweight "selected" chip/marker in the sidebar quick list to make preserved context even more obvious during long scan sessions.
    - Consider adding keyboard next/previous row stepping while retaining overlay preservation semantics.

- [x] [P1] [INDEX] /teams (`web/app/views/entities/teams/index.html.erb`) — keep team pressure drill-ins stable while tuning conference/pressure knobs
  - What changed (files):
    - `web/app/controllers/entities/teams_controller.rb`
    - `web/app/controllers/entities/teams_sse_controller.rb`
    - `web/app/views/entities/teams/index.html.erb`
    - `web/app/views/entities/teams/_rightpanel_base.html.erb`
    - `web/test/integration/entities_teams_index_test.rb`
  - Why this improves the flow:
    - Teams refresh now carries `selected_id` and preserves `#rightpanel-overlay` when the selected team is still present in the filtered/sorted result set.
    - When the selected team is no longer visible, refresh explicitly clears overlay HTML and resets `overlaytype`/`selectedteamid` in the same SSE transaction.
    - Sidebar pressure-board quick list now mirrors selected-state highlighting, and summary construction guarantees the selected visible team appears in that quick list.
    - Commandbar knob changes still ship as one ordered SSE response patching `#maincanvas`, `#rightpanel-base`, and `#rightpanel-overlay` together.
  - Rubric (before → after):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Follow-up tasks discovered:
    - Add an explicit “selected” marker chip in pressure-board rows to make preserved context even more legible during rapid filter cycling.
    - Consider keyboard next/previous team stepping that keeps the same preserve/clear overlay contract.

- [x] [P1] [INDEX] /drafts (`web/app/views/entities/drafts/index.html.erb`) — preserve pick/selection context while adjusting year/team/round knobs
  - What changed (files):
    - `web/app/controllers/entities/drafts_controller.rb`
    - `web/app/controllers/entities/drafts_sse_controller.rb`
    - `web/app/views/entities/drafts/index.html.erb`
    - `web/app/views/entities/drafts/_results.html.erb`
    - `web/app/views/entities/drafts/_rightpanel_base.html.erb`
    - `web/test/integration/entities_pane_endpoints_test.rb`
  - Why this improves the flow:
    - Drafts knob refresh now sends selected overlay context (`selected_type` + `selected_key`) and preserves `#rightpanel-overlay` when the selected pick/selection is still visible in the refreshed result set.
    - Incompatible mode switches are now deterministic: e.g., a pick overlay is explicitly cleared when changing into `selections` view.
    - Preserved pick overlays now normalize selection keys per mode (`pick-*` in picks, `grid-*` in grid), so selected styling remains synchronized with the currently visible row/cell grammar.
    - Grid cells and sidebar quick rows now mirror selected-state highlighting, keeping wayfinding stable while iterating year/team/round filters.
    - Multi-region updates remain a single ordered SSE transaction patching results + sidebar base + overlay + signals.
  - Rubric (before → after):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Follow-up tasks discovered:
    - Add a lightweight selected marker glyph in grid cells to further improve preserved-context legibility during rapid year changes.
    - Consider optional keyboard next/previous pick stepping that reuses the same overlay preserve/clear contract.

- [x] [P1] [INDEX] /transactions (`web/app/views/entities/transactions/index.html.erb`) — keep transaction detail open while refining feed filters
  - What changed (files):
    - `web/app/controllers/entities/transactions_controller.rb`
    - `web/app/controllers/entities/transactions_sse_controller.rb`
    - `web/app/views/entities/transactions/index.html.erb`
    - `web/test/integration/entities_pane_endpoints_test.rb`
  - Why this improves the flow:
    - Transactions commandbar refresh now carries selected overlay context (`selected_type` + `selected_id`) so filter/knob changes can preserve the open transaction detail when that row is still visible.
    - SSE refresh now uses deterministic preserve/clear behavior: it re-renders `#rightpanel-overlay` for visible selected rows and explicitly clears overlay HTML + resets `overlaytype`/`overlayid` when the selected row no longer matches filters.
    - Sidebar quick-feed summary now guarantees the selected visible transaction appears in top rows, so active-state highlighting stays synchronized between main feed row and quick-feed button.
    - Multi-region updates remain one ordered SSE transaction patching `#transactions-results`, `#rightpanel-base`, and `#rightpanel-overlay` together.
  - Rubric (before → after):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Follow-up tasks discovered:
    - Add an explicit selected-marker chip/glyph in quick-feed rows to make preserved context even more legible during rapid filter cycling.
    - Consider optional keyboard next/previous transaction stepping that reuses the same overlay preserve/clear contract.
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/team-summary (`web/app/views/tools/team_summary/show.html.erb`) — make commandbar knob changes patch-driven and state-preserving
  - Problem: Team Summary commandbar currently submits full-page GETs, causing avoidable context resets and uneven state transitions.
  - Hypothesis: A dedicated SSE refresh flow for knobs will keep main table, compare strip, and sidebar synchronized with predictable behavior.
  - Scope (files):
    - `web/app/controllers/tools/team_summary_controller.rb`
    - `web/app/views/tools/team_summary/show.html.erb`
    - `web/app/views/tools/team_summary/_workspace_main.html.erb`
    - `web/app/views/tools/team_summary/_compare_strip.html.erb`
    - `web/app/views/tools/team_summary/_rightpanel_base.html.erb`
    - `web/app/views/tools/team_summary/_rightpanel_overlay_team.html.erb`
    - `web/config/routes.rb`
    - `web/test/integration/tools_team_summary_test.rb`
  - Acceptance criteria:
    - Year/conference/pressure/sort changes trigger one SSE refresh (no full-page reload).
    - SSE refresh patches `#maincanvas`, compare strip, and rightpanel regions in one ordered response.
    - Selected team + compare slots are preserved when still resolvable; otherwise clear deterministically.
    - URL remains shareable and synchronized with current knob state.
  - Rubric (before → target):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 5
    - Interaction predictability: 3 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/two-way-utility (`web/app/views/tools/two_way_utility/show.html.erb`) — preserve selected player context while cycling risk/team/conference lenses
  - Problem: Refresh currently clears the player overlay unconditionally, interrupting risk-triage workflows.
  - Hypothesis: Preserve selected player overlay when still in result set to improve rapid compare/triage loops.
  - Scope (files):
    - `web/app/controllers/tools/two_way_utility_controller.rb`
    - `web/app/views/tools/two_way_utility/_player_row.html.erb`
    - `web/app/views/tools/two_way_utility/_rightpanel_base.html.erb`
    - `web/app/views/tools/two_way_utility/_workspace_main.html.erb`
    - `web/test/integration/tools_two_way_utility_test.rb`
  - Acceptance criteria:
    - On refresh, selected player overlay remains open if player still matches current lenses.
    - If no longer visible, overlay is cleared with explicit signal reset.
    - Active selection is visibly synchronized between table row and quick risk queue.
    - Refresh remains one ordered SSE response for all affected regions.
  - Rubric (before → target):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/system-values (`web/app/views/tools/system_values/show.html.erb`) — extend baseline-delta grammar into Minimum Salary and Rookie Scale sections
  - Problem: Baseline delta treatment is strongest in System/Tax tables; Minimum/Rookie sections still require manual comparison.
  - Hypothesis: Applying consistent delta rows and baseline markers in all sections will improve cross-section scan speed and interpretability.
  - Scope (files):
    - `web/app/controllers/tools/system_values_controller.rb`
    - `web/app/views/tools/system_values/_league_salary_scales_table.html.erb`
    - `web/app/views/tools/system_values/_rookie_scale_amounts_table.html.erb`
    - `web/app/views/tools/system_values/show.html.erb`
    - `web/test/integration/tools_system_values_test.rb`
  - Acceptance criteria:
    - Minimum Salary rows show numeric delta vs selected baseline with consistent color semantics.
    - Rookie Scale rows show numeric delta vs selected baseline with consistent color semantics.
    - Baseline row/selected row labeling remains explicit across all four sections.
    - Integration tests validate minimum + rookie delta rendering.
  - Rubric (before → target):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 4
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/team-summary (`web/app/views/tools/team_summary/_workspace_main.html.erb`) — build compare board directly from dense rows (without sidebar detour)
  - Problem: Pinning compare slots is sidebar-first, adding extra clicks during fast side-by-side setup.
  - Hypothesis: Inline row-level pin actions (A/B) will reduce interaction cost and make compare workflows faster.
  - Scope (files):
    - `web/app/views/tools/team_summary/_workspace_main.html.erb`
    - `web/app/views/tools/team_summary/_compare_strip.html.erb`
    - `web/app/controllers/tools/team_summary_controller.rb`
    - `web/test/integration/tools_team_summary_test.rb`
  - Acceptance criteria:
    - Each row exposes keyboard-accessible `Pin A` / `Pin B` actions.
    - Pin actions update compare strip + sidebar state via one existing compare SSE flow.
    - Row badges and compare strip stay synchronized after pin/replace/clear actions.
    - Dense row layout is preserved (no card conversion).
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 4 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P3] [INDEX] /trades (`web/app/views/entities/trades/index.html.erb`) — prioritize high-complexity deals faster with explicit sort/lens controls
  - Problem: Trades feed is date-first only; users cannot quickly surface multi-asset/multi-team complexity patterns.
  - Hypothesis: Adding complexity-oriented sort/lenses will improve first-pass triage speed for trade analysis.
  - Scope (files):
    - `web/app/controllers/entities/trades_controller.rb`
    - `web/app/controllers/entities/trades_sse_controller.rb`
    - `web/app/views/entities/trades/index.html.erb`
    - `web/app/views/entities/trades/_results.html.erb`
    - `web/app/views/entities/trades/_rightpanel_base.html.erb`
    - `web/test/integration/entities_pane_endpoints_test.rb`
  - Acceptance criteria:
    - Commandbar includes a discoverable sort/lens control for complexity (e.g., newest, most teams, most assets).
    - Selecting a lens reorders list and quick-deals sidebar consistently via one SSE refresh.
    - Selected overlay preserve/clear behavior remains deterministic under new sort/lens changes.
    - URL state captures the active sort/lens.
  - Rubric (before → target):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.
