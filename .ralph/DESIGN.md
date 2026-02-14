# Design Evolution Backlog (`web/`)

North star:
- Entity index pages are explorer workbenches (fast scan, dense rows, low-friction pivots).
- Entity detail pages are decision dossiers (what changed, why it matters, what to do next).
- Canonical Datastar patch boundaries remain stable: `#commandbar`, `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`.
- Salary Book is read-only reference quality except explicit Tankathon allow-list work.

Guardrails:
- Default: do **not** modify Salary Book files.
- Allowed exception only: `web/app/views/tools/salary_book/_maincanvas_tankathon_frame.html.erb`.
- Do not modify Salary Book controllers/helpers/tests.

Execution mode:
- Current priority is **entity detail page elevation**.
- INDEX and TOOL work continues in parallel where high leverage.
- ENTITY work is explicitly approved in this queue.

Supervisor override: ENTITY
[ENTITY-OVERRIDE]

Backlog hygiene policy (active-only):
- Keep only active unchecked tasks (`- [ ] ...`) in this file.
- Archive completed-task detail to git history (commit diffs/messages), not long in-file history.

---

Audit note (2026-02-14) — completed [P1] [INDEX] Entity navigation pivots (Draft Selections first-class nav)
- What changed (files):
  - `web/app/views/entities/shared/_commandbar.html.erb`
  - `web/app/views/shared/_commandbar_navigation.html.erb`
  - `web/app/views/entities/draft_selections/index.html.erb`
  - `web/app/views/entities/draft_selections/show.html.erb`
  - `web/test/integration/entities_draft_selections_index_test.rb`
  - `web/test/integration/entities_draft_selections_show_test.rb`
- Why this improves flow:
  - Draft Selections is now a first-class destination in both shared entity commandbar and global navigation, reducing indirect pivots through Drafts.
  - Draft Selections index + detail now carry consistent active-nav context (`Selections` active) while keeping direct `Draft` links available.
- Rubric (before → after):
  - Scan speed: 3 → 4
  - Information hierarchy: 4 → 4
  - Interaction predictability: 3 → 4
  - Density/readability: 5 → 5
  - Navigation/pivots: 2 → 4
- Follow-up discovered:
  - Consider migrating `entities/draft_selections/index` commandbar entity grid to the shared entity commandbar partial to remove duplicated nav markup.


Audit note (2026-02-14) — completed [P2] [TOOL] Team Summary commandbar team-find/jump
- What changed (files):
  - `web/app/views/tools/team_summary/show.html.erb`
  - `web/app/views/tools/team_summary/_workspace_main.html.erb`
  - `web/app/controllers/tools/team_summary_controller.rb`
  - `web/test/integration/tools_team_summary_test.rb`
- Why this improves flow:
  - Added commandbar Team Finder (code/name intent + Cmd/Ctrl+K focus + Enter/Jump) so users can target/open a team sidebar directly without table scan/scroll.
  - Team jump keeps compare slot state intact and writes through canonical `selectedteam` semantics.
  - URL/query sync now carries `team_finder_query`, and refresh/sort/compare/sidebar flows preserve this state while keeping existing Datastar patch boundaries.
- Rubric (before → after):
  - Scan speed: 3 → 5
  - Information hierarchy: 4 → 4
  - Interaction predictability: 3 → 4
  - Density/readability: 4 → 4
  - Navigation/pivots: 3 → 4
- Follow-up discovered:
  - Consider upgrading Team Finder from datalist matching to ranked shortlist chips (+ arrow-key cursor) if team filters/lenses expand further.

Audit note (2026-02-14) — completed [P2] [TOOL] Tool overlay behavior parity (Escape close semantics)
- What changed (files):
  - `web/app/views/tools/system_values/show.html.erb`
  - `web/app/views/tools/two_way_utility/show.html.erb`
  - `web/app/views/tools/system_values/_rightpanel_overlay_metric.html.erb`
  - `web/app/views/tools/two_way_utility/_rightpanel_overlay_player.html.erb`
  - `web/app/javascript/tools/team_summary.js`
  - `web/test/integration/tools_system_values_test.rb`
  - `web/test/integration/tools_two_way_utility_test.rb`
- Why this improves flow:
  - System Values and Two-Way Utility now support Escape-to-close overlays with the same non-editable-focus guard used in Team Summary semantics.
  - Close behavior routes through each tool’s canonical sidebar-clear control, keeping `#rightpanel-overlay` patch/clear behavior consistent with existing Datastar boundaries.
  - Cmd/Ctrl+K finder shortcuts remain intact on both tools while Escape now behaves predictably across tool overlays.
- Rubric (before → after):
  - Scan speed: 4 → 4
  - Information hierarchy: 4 → 4
  - Interaction predictability: 3 → 5
  - Density/readability: 4 → 4
  - Navigation/pivots: 3 → 3
- Follow-up discovered:
  - Consider extracting a small shared keyboard utility for overlay-close + finder-shortcut guards to reduce duplicated inline keydown expressions across tool shells.

Audit note (2026-02-14) — completed [P1] [ENTITY] teams/show roster + cap horizon dossier lanes
- What changed (files):
  - `web/app/views/entities/teams/_roster_breakdown.html.erb`
  - `web/app/views/entities/teams/_section_roster.html.erb`
  - `web/app/views/entities/teams/_cap_horizon_table.html.erb`
  - `web/test/integration/entities_teams_show_test.rb`
- Why this improves flow:
  - Replaced roster/cap horizon table islands with lane-native row treatment (`entity-cell-two-line`, dense identity rows, chip-based status) so scan and pivots are consistent with other upgraded dossier sections.
  - Standard + two-way + accounting buckets now stay numerically complete while keeping canonical player/agent/team pivots visible in-row.
  - Cap horizon now foregrounds current-year pressure posture and keeps full multi-year fidelity in compact lanes, with direct jump links to constraints/activity context.
  - Added bootstrap integration assertions to lock the no-table lane rendering and section-id morph stability for roster + cap horizon.
- Rubric (before → after):
  - Scan speed: 2 → 4
  - Information hierarchy: 3 → 5
  - Interaction predictability: 3 → 4
  - Density/readability: 2 → 4
  - Navigation/pivots: 4 → 4
- Follow-up discovered:
  - Consider adding lightweight sort/lens toggles within roster accounting buckets (amount/type/expiry) once query-param restoration patterns are defined for entity detail sections.

- [ ] [P1] [INDEX] drafts/index — make rightpanel provenance drill-ins lane-native + URL-restorable
  - Problem: Draft pick/selection overlays still present provenance in table islands and index boot does not restore overlay-open state from query params, reducing continuity in contested-pick review.
  - Hypothesis: Lane-native provenance rendering plus first-load URL hydration will make ownership-chain triage faster and predictable across refresh/share workflows.
  - Scope (files):
    - `web/app/views/entities/drafts/_rightpanel_overlay_pick.html.erb`
    - `web/app/views/entities/drafts/_rightpanel_overlay_selection.html.erb`
    - `web/app/views/entities/drafts/index.html.erb`
    - `web/app/controllers/entities/drafts_controller.rb`
    - `web/app/controllers/entities/drafts_sse_controller.rb`
  - Acceptance criteria:
    - Provenance chains in both draft overlays render as lane/list rows with concise severity/flag cues.
    - `/drafts?selected_type=...&selected_key=...` restores overlay-open context on initial page load when target row/cell is in-scope.
    - SSE refresh preserves overlay when still visible and clears it when filtered out (no stale overlay payload/signals).
    - Canonical pivots (trade/transaction/team/player/draft-pick/draft-selection) remain one-click and keyboard reachable.
  - Rubric (before → target):
    - Scan speed: 3 → 4
    - Information hierarchy: 3 → 4
    - Interaction predictability: 2 → 4
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - No Salary Book edits outside the Tankathon allow-list.

- [ ] [P2] [INDEX] draft_selections/index — remove provenance table island + support selected overlay deep-link bootstrap
  - Problem: Draft Selections overlay still uses provenance table presentation and index boot cannot restore `selected_id` overlay context, creating mismatch with other index workbench continuity patterns.
  - Hypothesis: Lane-native provenance rendering and initial selected-id hydration will improve provenance-first workflows and shared-link reliability.
  - Scope (files):
    - `web/app/views/entities/draft_selections/_rightpanel_overlay_selection.html.erb`
    - `web/app/views/entities/draft_selections/index.html.erb`
    - `web/app/controllers/entities/draft_selections_controller.rb`
    - `web/app/controllers/entities/draft_selections_sse_controller.rb`
  - Acceptance criteria:
    - Overlay provenance chain renders as lane/list rows with compact swap/future/conditional flags.
    - `/draft-selections?selected_id=<txn_id>` opens matching overlay on initial load when row is in-scope.
    - Refresh/filter changes preserve or clear overlay strictly by row visibility; no dangling selected signal.
    - Pivots to draft selection, draft pick, transaction, trade, team, and player remain clear and low-friction.
  - Rubric (before → target):
    - Scan speed: 3 → 4
    - Information hierarchy: 3 → 4
    - Interaction predictability: 2 → 4
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - No Salary Book edits outside the Tankathon allow-list.
