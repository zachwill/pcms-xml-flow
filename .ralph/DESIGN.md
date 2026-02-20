# Design Evolution Backlog

## Context
Salary Book + Noah are the quality bar. These tasks converge other surfaces toward that standard.
Each task is one iteration of focused work (~10 min). Commit when done.

---

## /teams — interaction predictability

- [ ] [P1] [INDEX] /teams — unify row click → overlay drill-in behavior
  Files: web/app/views/teams/index.html.erb, web/app/views/teams/_workspace_main.html.erb, web/app/views/teams/_rightpanel_overlay_team.html.erb, web/app/controllers/teams_controller.rb
  Why: Row click should predictably open the team overlay in #rightpanel-overlay, matching Salary Book's click-row-to-sidebar pattern.

- [ ] [P1] [INDEX] /teams — sync commandbar lane counts with filtered row set
  Files: web/app/views/teams/_commandbar.html.erb, web/app/views/teams/_pressure_section.html.erb, web/app/controllers/teams_controller.rb
  Why: Lane headers and commandbar counts drift from the visible rows after filter changes.

- [ ] [P2] [INDEX] /teams — active-row highlight state when overlay is open
  Files: web/app/views/teams/_workspace_main.html.erb, web/app/javascript/teams_index.js
  Why: When a team overlay is open, the source row should show active state so users know where they are.

## /players — triage flow

- [ ] [P1] [INDEX] /players — reframe commandbar filters around triage sequence
  Files: web/app/views/players/index.html.erb, web/app/views/players/_workspace_main.html.erb, web/app/controllers/players_controller.rb
  Why: Too many controls with no implied ordering; users need scope → urgency → drill-in progression.

- [ ] [P2] [INDEX] /players — align sidebar quick-feed urgency semantics with row badges
  Files: web/app/views/players/_rightpanel_base.html.erb, web/app/views/players/_workspace_main.html.erb
  Why: Sidebar and row sections use different language for the same urgency concepts.

- [ ] [P2] [INDEX] /players — deterministic overlay clear on filter refresh
  Files: web/app/views/players/_rightpanel_overlay_player.html.erb, web/app/controllers/players_sse_controller.rb
  Why: Overlay should clear when its player leaves the filtered result set.

## /agents + /agencies — directory coherence

- [ ] [P1] [INDEX] /agents — make agency scope state visible and persistent
  Files: web/app/views/agents/index.html.erb, web/app/views/agents/_commandbar.html.erb, web/app/controllers/agents_controller.rb
  Why: Mode/scope feels split; users lose track of whether they're scoped to an agency.

- [ ] [P2] [INDEX] /agents — smooth agent↔agency overlay pivots
  Files: web/app/views/agents/_rightpanel_overlay_agent.html.erb, web/app/views/agents/_rightpanel_overlay_agency.html.erb, web/app/controllers/agents_sse_controller.rb
  Why: Overlay pivots between agent and agency detail should preserve context, not feel like a page reset.

- [ ] [P2] [INDEX] /agencies — make posture lanes first-class row actions
  Files: web/app/views/agencies/index.html.erb, web/app/views/agencies/_workspace_main.html.erb, web/app/controllers/agencies_controller.rb
  Why: Posture risk → agent list pivot is too implicit; should be a direct row action.

## /team-summary — stepping loop

- [ ] [P1] [TOOL] /team-summary — connect sort/filter state to overlay stepping context
  Files: web/app/views/team_summary/show.html.erb, web/app/views/team_summary/_rightpanel_overlay_team.html.erb, web/app/controllers/team_summary_controller.rb
  Why: Stepping through teams in the overlay should respect current sort order so next/prev is predictable.

- [ ] [P2] [TOOL] /team-summary — show list position in stepping controls
  Files: web/app/views/team_summary/_rightpanel_overlay_team.html.erb, web/app/javascript/team_summary.js
  Why: Users need "3 of 12" context to know where they are in the filtered set.

## /system-values — metric wayfinding

- [ ] [P1] [TOOL] /system-values — tighten section wayfinding and toggle state
  Files: web/app/views/system_values/show.html.erb, web/app/views/system_values/_commandbar.html.erb, web/app/controllers/system_values_controller.rb
  Why: Section toggles and finder state require too much context switching; which sections are on should be obvious.

- [ ] [P2] [TOOL] /system-values — stable metric context across refreshes
  Files: web/app/views/system_values/_rightpanel_overlay_metric.html.erb, web/app/views/system_values/_rightpanel_base.html.erb
  Why: Metric drill-in should maintain section/baseline/row identity when year or section toggles change.

## /trades — team impact scan

- [ ] [P1] [TOOL] /trades — surface per-team OUT/IN impact in index rows
  Files: web/app/views/trades/index.html.erb, web/app/views/trades/_results.html.erb, web/app/controllers/trades_controller.rb
  Why: Users bounce between row and overlay to understand team impact; enough context should be in the row.

- [ ] [P2] [TOOL] /trades — sync overlay and row state on filter refresh
  Files: web/app/views/trades/_rightpanel_overlay_trade.html.erb, web/app/controllers/trades_sse_controller.rb
  Why: Overlay should stay consistent (or clear) when filters change the visible row set.

## /transactions — severity lanes

- [ ] [P1] [TOOL] /transactions — clarify lane severity and route cues
  Files: web/app/views/transactions/index.html.erb, web/app/views/transactions/_results.html.erb, web/app/controllers/transactions_controller.rb
  Why: Lane labels and severity cues require manual parsing; should communicate "what changed and where" instantly.

- [ ] [P2] [TOOL] /transactions — deterministic overlay lifecycle on filter change
  Files: web/app/views/transactions/_rightpanel_overlay_transaction.html.erb, web/app/controllers/transactions_sse_controller.rb
  Why: Same overlay-clear-on-filter pattern needed here.

## /drafts — cross-view consistency

- [ ] [P1] [TOOL] /drafts — unify risk/ownership legend across picks, selections, and grid views
  Files: web/app/views/drafts/index.html.erb, web/app/views/drafts/_results.html.erb, web/app/controllers/drafts_controller.rb
  Why: Risk cues use different language across the three views; one legend, one meaning.

- [ ] [P2] [TOOL] /drafts — consistent overlay selection across all three views
  Files: web/app/views/drafts/_rightpanel_overlay_pick.html.erb, web/app/views/drafts/_rightpanel_overlay_selection.html.erb, web/app/controllers/drafts_sse_controller.rb
  Why: Click-to-overlay should behave identically whether in picks, selections, or grid view.

## /draft-selections — provenance triage

- [ ] [P1] [INDEX] /draft-selections — severity grouping for contested ownership chains
  Files: web/app/views/draft_selections/index.html.erb, web/app/views/draft_selections/_workspace_main.html.erb, web/app/controllers/draft_selections_controller.rb
  Why: Users need to shortlist contested picks fast; severity lanes should separate clean from contested.

- [ ] [P2] [INDEX] /draft-selections — overlay persistence tied to visible result set
  Files: web/app/views/draft_selections/_rightpanel_overlay_selection.html.erb, web/app/controllers/draft_selections_sse_controller.rb
  Why: Same overlay-clear pattern; overlay for a hidden row should auto-clear.
