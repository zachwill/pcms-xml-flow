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

- [ ] [P1] [INDEX] Entity navigation pivots — make Draft Selections first-class in global/entity nav
  - Problem: `draft-selections` is a standalone entity surface, but shared entity navigation omits it, forcing indirect pivots through Drafts and reducing wayfinding speed.
  - Hypothesis: Adding a first-class Selections destination in shared nav patterns will reduce pivot friction between picks/trades/transactions and historical selection provenance.
  - Scope (files):
    - `web/app/views/entities/shared/_commandbar.html.erb`
    - `web/app/views/shared/_commandbar_navigation.html.erb`
    - `web/app/views/entities/draft_selections/index.html.erb`
    - `web/app/views/entities/draft_selections/show.html.erb`
  - Acceptance criteria:
    - Entity commandbar grid exposes a direct Selections destination with stable active-state behavior.
    - Global commandbar navigation includes Draft Selections as a direct option.
    - Draft selections index/detail surfaces show predictable active nav context without regressing existing Draft workspace links.
  - Rubric (before → target):
    - Scan speed: 3 → 4
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 4
    - Density/readability: 5 → 5
    - Navigation/pivots: 2 → 4
  - Guardrails:
    - No Salary Book edits outside the Tankathon allow-list.

- [ ] [P2] [TOOL] Team Summary — add rapid team-find/jump flow in commandbar
  - Problem: Team Summary currently relies on manual table scanning + scroll for team targeting, with no direct team intent input unlike other tool surfaces with quick-jump affordances.
  - Hypothesis: A lightweight team-find/jump control (code/name intent) will speed compare setup and sidebar drill-in without reducing table density.
  - Scope (files):
    - `web/app/views/tools/team_summary/show.html.erb`
    - `web/app/views/tools/team_summary/_workspace_main.html.erb`
    - `web/app/controllers/tools/team_summary_controller.rb`
    - `web/app/javascript/tools/team_summary.js`
  - Acceptance criteria:
    - Users can target a specific team from commandbar intent input and jump/open sidebar with minimal interaction.
    - Jump behavior preserves existing compare pins and selected-team signal semantics.
    - URL/state sync remains canonical and refresh/step/compare SSE flows keep patch boundaries intact.
  - Rubric (before → target):
    - Scan speed: 3 → 5
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 4
    - Density/readability: 4 → 4
    - Navigation/pivots: 3 → 4
  - Guardrails:
    - No Salary Book edits outside the Tankathon allow-list.

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
