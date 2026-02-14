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

- [ ] [P2] [TOOL] Tool overlay behavior parity — unify keyboard close semantics across tools
  - Problem: Team Summary has explicit Escape-to-close behavior, while System Values and Two-Way Utility overlays rely on click-only close, creating inconsistent overlay control expectations.
  - Hypothesis: Consistent Escape-to-close behavior (while preserving input focus exceptions) will improve interaction predictability across planning tools.
  - Scope (files):
    - `web/app/views/tools/system_values/show.html.erb`
    - `web/app/views/tools/two_way_utility/show.html.erb`
    - `web/app/views/tools/system_values/_rightpanel_overlay_metric.html.erb`
    - `web/app/views/tools/two_way_utility/_rightpanel_overlay_player.html.erb`
    - `web/app/javascript/tools/team_summary.js`
  - Acceptance criteria:
    - Escape closes active overlay in System Values and Two-Way Utility when focus is not in editable inputs.
    - Cmd/Ctrl+K finder shortcuts continue to work as-is on both tools.
    - Overlay close still uses canonical `#rightpanel-overlay` patch/clear behavior; no modal stacks introduced.
  - Rubric (before → target):
    - Scan speed: 4 → 4
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 3 → 3
  - Guardrails:
    - No Salary Book edits outside the Tankathon allow-list.
