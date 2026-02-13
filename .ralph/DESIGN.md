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

Supervisor review — 2026-02-13 (latest design loop audit):
- Scope discipline: each recent commit mapped to one explicit INDEX surface + user flow (`/teams` overlay compare controls, `/agents` agency tie-back cues, `/players` why-matched emphasis, `/transactions` intent-match provenance).
- Flow-level value: diffs changed interaction grammar/wayfinding in-row or in-overlay; no broad cosmetic sweep commits detected.
- Patch contract: Datastar boundaries stayed canonical (`#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`) and multi-region refreshes remained SSE-backed.
- Salary Book guardrail: no forbidden Salary Book files were touched.
- Validation evidence:
  - Known pre-existing env issue remains: full-file index tests can fail when `tailwind.css` is missing from test assets.
  - Flow-focused assertions pass in this env:
    - `entities_agents_index_test` (agency overlay preserved while scanning agents)
    - `entities_players_index_test` (trade-kicker why-matched emphasis)
    - `entities_teams_index_test` (overlay compare controls wiring)
    - `entities_pane_endpoints_test` (transactions team intent provenance)
- Next-loop constraint (tightened): pick exactly one unchecked task, deliver interaction-level outcome + rubric delta evidence, and avoid cross-surface restyling churn.

- [x] [P1] [TOOL] /tools/system-values — make Rookie Scale drill-ins metric-cell specific
  - What changed (files):
    - web/app/views/tools/system_values/_rookie_scale_amounts_table.html.erb
      - Converted Rookie drill-ins from row-level default (`salary_year_1`) to per-metric cell actions for all six rookie metrics.
      - Added metric-specific active-cell styling (while preserving row-level context highlight) so clicked context is unambiguous.
    - web/app/views/tools/system_values/_rightpanel_overlay_metric.html.erb
      - Highlighted the active metric inside “Pick scale detail” to mirror the clicked Rookie cell.
    - web/app/views/tools/system_values/_rightpanel_base.html.erb
      - Updated sidebar helper copy to match new interaction grammar (Rookie now metric-cell drill-in).
    - web/test/integration/tools_system_values_test.rb
      - Expanded wiring assertions to cover multiple rookie metric targets.
      - Updated rookie overlay and SSE preserve assertions to validate non-default rookie metrics are retained.
  - Why this improves the flow:
    - Users can now open the exact rookie metric they are scanning (Option Y3/Y4 and option-% included) in one click.
    - Active state now communicates both the focused row and the exact focused metric cell, reducing ambiguity and backtracking.
    - Overlay metric state persists through `/tools/system-values/sse/refresh` for non-default rookie metrics, preserving context during baseline/range changes.
  - Rubric (before → after):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Follow-up tasks discovered:
    - Consider matching this metric-cell focus cue style on other multi-metric detail tables where row-level drill-ins still mask exact metric origin.

- [x] [P1] [INDEX] /agencies — define restriction composition where posture controls are used
  - What changed (files):
    - web/app/views/entities/agencies/index.html.erb
      - Added explicit posture helper definition text: `Restrictions: no-trade + trade kicker + trade-restricted`.
      - Kept existing year-aware threshold copy for `Inactive + live` and `Live risk` unchanged in behavior.
    - web/app/views/entities/agencies/_rightpanel_base.html.erb
      - Mirrored the same restrictions definition text in the sidebar snapshot helper box.
      - Preserved the same year-aware threshold grammar used in the commandbar.
    - web/test/integration/entities_agencies_index_test.rb
      - Extended the index shell assertion to verify both threshold copy and restrictions-composition copy appear in both regions.
  - Why this improves the flow:
    - Posture controls now define exactly what `restrictions` means at the point of filtering, removing guesswork.
    - Commandbar and sidebar now share one posture grammar, improving trust when users scan and then validate context in the right panel.
    - Year-aware threshold language remains intact, so users still understand the active Book-year condition while gaining composition clarity.
  - Rubric (before → after):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Follow-up tasks discovered:
    - Consider reusing this exact restrictions-definition line in `/agents` and overlay-level agency summaries for posture-language parity.

- [x] [P1] [INDEX] /teams — add compare pin/unpin controls in overlay header for parity
  - What changed (files):
    - web/app/views/entities/teams/_rightpanel_overlay_team.html.erb
      - Added overlay-level compare actions directly in the team identity header block: Pin A, Pin B, Clear A, and Clear B.
      - Wired overlay controls to the same `/teams/sse/refresh` compare action path used by row controls (`pin` and `clear_slot`).
      - Added active-slot visual states driven by `$comparea` / `$compareb` and conditional Clear A / Clear B affordances.
      - Ensured compare actions keep overlay context by always sending `selected_id` for the currently open overlay team.
    - web/test/integration/entities_teams_index_test.rb
      - Expanded overlay endpoint assertions to verify Pin A / Pin B and Clear slot control wiring in the teams overlay payload.
  - Why this improves the flow:
    - Compare workflows now continue inside drill-in mode without forcing users back to row-level controls.
    - Overlay triage keeps context while pinning/unpinning, reducing mode-switch friction and preserving wayfinding continuity.
    - Active-slot button states and conditional clear affordances make compare slot ownership explicit at the point of decision.
  - Rubric (before → after):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 5 → 5
  - Follow-up tasks discovered:
    - Investigate and stabilize broader teams-index integration suite setup (asset/test-env drift surfaced during full-file test run), while keeping this overlay flow coverage focused and passing.

- [x] [P2] [INDEX] /agents — improve agency-overlay tie-back in agent directory rows
  - What changed (files):
    - web/app/views/entities/agents/_workspace_main.html.erb
      - Added agency-context row tie-back styling for agent rows when an agency overlay is active (`$overlaytype === 'agency'` + matching `$overlayid`).
      - Added a lightweight in-cell `overlay` indicator next to agency names for represented rows so row context remains explicit during agency drill-ins.
      - Kept existing selected-agent row highlighting behavior unchanged (`$overlaytype === 'agent'` path still uses current highlight state).
    - web/test/integration/entities_agents_index_test.rb
      - Extended index wiring assertions to verify the new agency tie-back class and agency-match `data-show` cue are rendered.
      - Extended `/agents/sse/refresh` overlay-preserve coverage to confirm tie-back cues are present while an agency overlay remains active in agents mode.
  - Why this improves the flow:
    - Users now get immediate row-level confirmation of which agent rows are represented by the currently open agency overlay.
    - Agent ⇄ agency pivot loops keep list context anchored, reducing re-scan overhead and “where am I?” drift after opening an agency overlay.
    - The cue remains lightweight (subtle row tint + compact in-cell marker), preserving dense table readability.
  - Rubric (before → after):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Follow-up tasks discovered:
    - Stabilize full-file `entities_agents_index_test.rb` runs in environments missing compiled `tailwind.css` (layout asset-path drift); SSE-focused coverage for this flow passes and remains the current verification guardrail.

- [x] [P2] [INDEX] /players — surface “why matched” emphasis for active constraint lens
  - What changed (files):
    - web/app/controllers/entities/players_controller.rb
      - Added summary-level active-constraint context fields (`constraint_lens_match_key`, `constraint_lens_match_chip_label`, `constraint_lens_match_reason`) derived from existing server lens state.
      - Kept all filtering/business logic in SQL and Ruby controller state wiring (no client business logic added).
    - web/app/views/entities/players/_workspace_main.html.erb
      - Added a shared “Why matched” line in the workspace cap-total header when a non-`all` constraint lens is active.
      - Switched constraint/status chips to keyed token structs, then prioritized and visually emphasized the chip that matches the active constraint lens (ring + stronger weight + match label) without changing row height.
    - web/app/views/entities/players/_rightpanel_base.html.erb
      - Added the same “Why matched” explanation language to sidebar snapshot helper copy and the Top cap hits module header.
      - Added active-lens match emphasis in Top cap hits row metadata via a compact match chip using the same server-provided label.
    - web/test/integration/entities_players_index_test.rb
      - Expanded trade-kicker refresh assertions to verify shared “Why matched” copy appears across refreshed regions and that match-chip emphasis text is rendered.
  - Why this improves the flow:
    - Filtered player lists now state *why* each row qualifies under the active constraint lens, instead of only showing generic posture chips.
    - Main-canvas rows and sidebar modules now use one shared explanation grammar, reducing interpretation drift between scan and validation contexts.
    - Active-lens match emphasis remains compact and dense, preserving existing row height/readability.
  - Rubric (before → after):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 5 → 5
  - Follow-up tasks discovered:
    - Stabilize full-file `entities_players_index_test.rb` runs in environments without compiled `tailwind.css`; SSE-focused coverage for this flow remains passing and is the current verification guardrail.

- [x] [P2] [INDEX] /transactions — show intent-search match provenance in rows
  - What changed (files):
    - web/app/controllers/entities/transactions_controller.rb
      - Added `annotate_intent_match_provenance!` during index-state load to tag each intent-filtered row with compact match-source metadata.
      - Added deterministic match-source detection for player, team, type, description, id, and method fields plus compact cue/title strings for rendering.
    - web/app/views/entities/transactions/_results.html.erb
      - Added a compact secondary-line provenance cue in the Method column (`match <source>`) when an intent query is active.
      - Kept dense two-line row layout intact by appending provenance inline with existing contract-type metadata.
    - web/test/integration/entities_pane_endpoints_test.rb
      - Extended transactions SSE refresh assertions to validate player-match provenance rendering.
      - Added coverage for team-text intent queries to verify team provenance cues are emitted.
  - Why this improves the flow:
    - Users can immediately see *why* each transaction row matched the current intent query, reducing ambiguity between player/team/type/description-style hits.
    - Provenance is rendered in-row (not hidden in overlay) so scan/triage loops stay inside the feed.
    - Overlay preserve/clear behavior remains unchanged because only row metadata rendering was added.
  - Rubric (before → after):
    - Scan speed: 5 → 5
    - Information hierarchy: 4 → 5
    - Interaction predictability: 5 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Follow-up tasks discovered:
    - Consider extending provenance grammar to multi-token intent parsing (per-token source breakdown) if query complexity increases.
    - Stabilize full `entities_pane_endpoints_test.rb` runs in environments lacking compiled `tailwind.css`; SSE-focused transactions coverage remains passing.

- [x] [P2] [TOOL] /tools/two-way-utility — strengthen compare-card risk explanations
  - What changed (files):
    - web/app/views/tools/two_way_utility/_rightpanel_base.html.erb
      - Added compare-card risk-source helpers (`limit_basis_label`, `threshold_posture`, `risk_source_summary`) so each pinned slot now states the source of risk explicitly.
      - Added compact per-slot risk-source copy + chips (limit basis + threshold posture) directly inside Slot A/Slot B cards.
      - Updated compare delta module with signal-basis language and a dynamic remaining-games label (`hard-limit` vs `estimate-aware`) plus threshold-posture summary for both players.
    - web/test/integration/tools_two_way_utility_test.rb
      - Added SSE refresh assertions that verify hard-limit risk-source copy in both compare cards.
      - Added SSE refresh coverage for mixed hard-limit/estimated comparisons and estimate-aware delta labeling.
  - Why this improves the flow:
    - Compare decisions now expose “why risky” inline (limit basis + threshold posture) without forcing overlay drill-ins.
    - Delta interpretation now communicates whether comparisons are hard-limit-to-hard-limit or estimate-influenced, improving trust when slots mix signal types.
    - Existing compare mechanics and overlay-preserve wiring remain unchanged; this is a clarity upgrade to the same workflow.
  - Rubric (before → after):
    - Scan speed: 5 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 5 → 5
    - Density/readability: 5 → 5
    - Navigation/pivots: 5 → 5
  - Follow-up tasks discovered:
    - Consider reusing this risk-source sentence grammar in the player overlay compare controls so Slot cards and overlay copy stay perfectly aligned.
    - Full-file `tools_two_way_utility_test.rb` still inherits the known missing `tailwind.css` layout-asset issue in this environment; SSE-focused coverage for this flow passes and is the active guardrail.

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
