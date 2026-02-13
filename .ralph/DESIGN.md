# Design Evolution Backlog (`web/`)

North star:
- Entity index pages should behave like explorer workbenches (Salary Book-like interaction grammar, not clones).
- Fast scan, meaningful filters/knobs, dense interactive rows, and sidebar drill-ins.
- Canonical shell: `#commandbar` + `#maincanvas` + `#rightpanel-base` + `#rightpanel-overlay`.
- Salary Book is read-only and remains the interaction quality bar.
- Team Summary, System Values, and Two-Way Utility should continue converging toward stronger workbench UX.

Rubric (1-5):
1) Scan speed
2) Information hierarchy
3) Interaction predictability
4) Density/readability balance
5) Navigation/pivots

Audit reset — 2026-02-13:
- Completed tasks were reviewed and remain shipped.
- No new regressions found in Datastar patch-boundary/SSE contract on audited surfaces.
- Remaining work is flow-level parity/trust polish (not class-only churn).
- This file is reset to only actionable unchecked design tasks.

- [ ] [P1] [TOOL] /tools/system-values — make Rookie Scale drill-ins metric-cell specific
  - Problem: Rookie row drill-ins always default overlay metric to Year 1, so users cannot directly open Option Y3/Y4 or option-% context from the exact cell they’re scanning.
  - Hypothesis: Cell-specific drill-in targets will improve predictability and reduce extra clicks during rookie baseline analysis.
  - Scope (files):
    - web/app/views/tools/system_values/_rookie_scale_amounts_table.html.erb
    - web/app/views/tools/system_values/_rightpanel_overlay_metric.html.erb
    - web/test/integration/tools_system_values_test.rb
  - Acceptance criteria:
    - Clicking any Rookie metric cell opens overlay with matching `overlay_metric` (Year 1, Year 2, Option Y3, Option Y4, Y3 %, Y4 %).
    - Active row/cell state remains legible after open (no ambiguity about what was clicked).
    - Existing `/tools/system-values/sse/refresh` preserve/clear semantics continue working for rookie overlays.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [INDEX] /agencies — define restriction composition where posture controls are used
  - Problem: `live risk` lens now exposes threshold text, but “restrictions” is still undefined, forcing users to infer components.
  - Hypothesis: Explicit restrictions composition copy (no-trade + trade kicker + trade-restricted) will improve trust in posture filters.
  - Scope (files):
    - web/app/views/entities/agencies/index.html.erb
    - web/app/views/entities/agencies/_rightpanel_base.html.erb
    - web/test/integration/entities_agencies_index_test.rb
  - Acceptance criteria:
    - Commandbar posture helper includes a compact definition of `restrictions`.
    - Sidebar snapshot mirrors the same definition text (single posture grammar in both regions).
    - Copy remains year-aware where needed and does not alter existing filter behavior.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [INDEX] /teams — add compare pin/unpin controls in overlay header for parity
  - Problem: Teams compare controls exist in rows/base modules but not in the overlay, creating mode-switch friction during drill-in triage.
  - Hypothesis: Overlay-level Pin A / Pin B / Clear slot controls will keep compare workflows continuous while preserving overlay focus.
  - Scope (files):
    - web/app/views/entities/teams/_rightpanel_overlay_team.html.erb
    - web/test/integration/entities_teams_index_test.rb
  - Acceptance criteria:
    - Overlay header/body exposes Pin A / Pin B controls with active-slot visual state.
    - Clear A / Clear B affordances appear when relevant and use the same compare action path as rows.
    - Compare actions preserve selected overlay context and keep URL sync behavior intact.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [INDEX] /agents — improve agency-overlay tie-back in agent directory rows
  - Problem: Opening an agency overlay from the agents directory does not strongly tie back to all affected agent rows, weakening scan context.
  - Hypothesis: Agency-context tie-back cues in the row list will reduce disorientation during agent⇄agency pivot loops.
  - Scope (files):
    - web/app/views/entities/agents/_workspace_main.html.erb
    - web/test/integration/entities_agents_index_test.rb
  - Acceptance criteria:
    - When an agency overlay is active, agent rows represented by that agency show a clear but lightweight tie-back cue.
    - Existing agent-row selected highlighting behavior remains intact.
    - No extra requests are introduced; behavior remains in current `/agents/sse/refresh` interaction model.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [INDEX] /players — surface “why matched” emphasis for active constraint lens
  - Problem: Constraint chips are present, but active lens reason is not visually prioritized, making filtered states less self-explanatory.
  - Hypothesis: Lens-matched chip emphasis will improve trust and reduce second-guessing when scanning filtered player lists.
  - Scope (files):
    - web/app/views/entities/players/_workspace_main.html.erb
    - web/app/views/entities/players/_rightpanel_base.html.erb
    - web/test/integration/entities_players_index_test.rb
  - Acceptance criteria:
    - Active constraint lens has a clear in-row match emphasis without increasing row height.
    - Sidebar quick/snapshot modules use the same lens explanation language.
    - No business logic is moved to JS; emphasis is rendered from existing server state.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [INDEX] /transactions — show intent-search match provenance in rows
  - Problem: Intent search filters rows, but users can’t quickly tell whether the match came from player name, team, transaction type, or description.
  - Hypothesis: Match-provenance cues in row secondary lines will improve trust and reduce re-scanning.
  - Scope (files):
    - web/app/controllers/entities/transactions_controller.rb
    - web/app/views/entities/transactions/_results.html.erb
    - web/test/integration/entities_pane_endpoints_test.rb
  - Acceptance criteria:
    - Intent-filtered rows display a concise match provenance cue.
    - Cue is compact and compatible with existing dense row layout.
    - Overlay preserve/clear behavior under query changes remains unchanged.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 4 → 5
    - Interaction predictability: 5 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/two-way-utility — strengthen compare-card risk explanations
  - Problem: Compare board shows deltas, but “why risky” context (hard limit vs estimated limit, threshold posture) is still implicit.
  - Hypothesis: Compact risk-source annotations in compare cards will improve decision confidence without extra drill-ins.
  - Scope (files):
    - web/app/views/tools/two_way_utility/_rightpanel_base.html.erb
    - web/test/integration/tools_two_way_utility_test.rb
  - Acceptance criteria:
    - Compare cards surface concise risk-source context for each pinned player.
    - Delta module language reflects whether signals are estimate-based or hard-limit based.
    - Existing compare actions (`pin`, `clear_slot`, `clear_all`) and overlay preserve behavior remain unchanged.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 5 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P3] [TOOL] /tools/system-values — add tax-bracket step interpretation notes in overlay
  - Problem: Tax bracket overlays show values/deltas but not a quick reminder of incremental step interpretation for first-pass readers.
  - Hypothesis: A compact overlay note for tax-step interpretation will improve readability/trust without changing data density.
  - Scope (files):
    - web/app/views/tools/system_values/_rightpanel_overlay_metric.html.erb
    - web/test/integration/tools_system_values_test.rb
  - Acceptance criteria:
    - Tax-section overlays include concise, non-intrusive interpretation copy specific to bracketed tax rates.
    - Note appears only for tax overlays (not system/minimum/rookie).
    - Existing selected-vs-baseline and focused-row context remains unchanged.
  - Rubric (before → target):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 5 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.
