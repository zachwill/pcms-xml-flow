# Design Evolution Backlog (`web/`)

North star:
- Entity **index pages** are explorer workbenches (fast scan, tight pivots, dense rows).
- Entity **detail pages** are decision dossiers (what changed, why it matters, what to do next).
- Canonical pattern remains `#commandbar` + `#maincanvas` + sidebar layers where applicable.
- Salary Book remains read-only reference quality, except approved Tankathon partial work.
- Tool surfaces continue evolving in parallel (System Values / Two-Way / Team Summary).

Rubric (1-5):
1) Scan speed
2) Information hierarchy
3) Interaction predictability
4) Density/readability balance
5) Navigation/pivots

## Audit snapshot (2026-02-13)

- Index convergence wave succeeded: `/agents`, `/players`, `/teams`, `/agencies`, `/drafts`, `/draft-selections`, `/transactions`, `/trades` now largely operate in flex-row workbench grammar.
- Tankathon exception succeeded in approved Salary Book frame file.
- Biggest remaining UX gap is now **entity detail pages** (`/players/:slug`, `/agents/:slug`, `/teams/:slug`, etc.), which still contain many table-heavy sections and weaker “next action” flow.

## Focus reset — entity detail phase

- Prioritize substantial upgrades to individual entity pages.
- Target outcomes:
  - faster comprehension in first 10 seconds,
  - clearer causal flow (event → cap impact → constraints),
  - obvious next pivots (team/agent/trade/transaction) without backtracking.
- Keep index/tool momentum, but detail-page elevation is now primary.

---

- [x] [P1] [ENTITY] /players/:slug — replace table-heavy contract sections with dense flex dossier lanes
  - Problem: Contract history, guarantees, incentives, and ledger sections still read like disconnected spreadsheet tables.
  - Hypothesis: Converting to unified flex-row dossier lanes will reduce context switching and improve “what matters now” comprehension.
  - Scope (files):
    - web/app/views/entities/players/_section_contract_history.html.erb
    - web/app/views/entities/players/_section_guarantees.html.erb
    - web/app/views/entities/players/_section_incentives.html.erb
    - web/app/views/entities/players/_section_ledger.html.erb
    - web/test/integration/entities_players_show_test.rb
  - What changed (files):
    - Replaced all table markup in the four target player dossier sections with dense flex-row lane layouts using consistent identity + metric cells (`entity-cell-two-line`).
    - Added explicit high-signal chips/flags across lanes (PO/TO/ETO, FULL/PARTIAL/NON guarantees, No-Trade, Trade Bonus, conditional protections, likely/unlikely incentives).
    - Added focused integration coverage in `entities_players_show_test.rb` to assert lane rendering, absence of `<table>` in targeted sections, and visibility of key flags.
  - Why this improves the flow:
    - Contract reading now follows one scan grammar across chronology → guarantees → incentives → ledger, reducing mode-switching between differently shaped tables.
    - Year/event identity is anchored in left lanes while money/flags stay in predictable right metric cells, making “what matters now” faster to parse.
    - Pivots (team/transaction/trade links) remain inline in the same row context instead of buried in wide table columns.
  - Acceptance criteria:
    - No `<table>` markup remains in the four target player section partials.
    - Section rows use consistent identity + metric cell grammar (year/event/action + money/flags).
    - High-signal flags (option, no-trade, trade bonus, guarantee type) are visible at row glance.
  - Rubric (before → after):
    - Scan speed: 3 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Follow-up tasks discovered:
    - Add a compact “next decisions” rail near constraints/contract horizon so the same lane grammar surfaces upcoming option/expiry triggers first.
    - Consider harmonizing Vitals/Connections/Team History onto the same lane grammar to complete full-page dossier consistency.
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [ENTITY] /players/:slug — add “next decisions” rail (options, expirings, guarantee triggers)
  - Problem: The page surfaces lots of history but does not foreground immediate decision points.
  - Hypothesis: A compact decision rail near header/constraints will improve planning speed and downstream pivots.
  - Scope (files):
    - web/app/views/entities/players/show.html.erb
    - web/app/views/entities/players/_section_constraints.html.erb
    - web/app/views/entities/players/_section_contract.html.erb
    - web/app/views/entities/players/_rightpanel_base.html.erb
    - web/test/integration/entities_players_show_test.rb
  - Acceptance criteria:
    - Decision rail lists upcoming option/expiry/trigger items with season labels and urgency cues.
    - Each decision item has direct pivot links (team, transaction/trade where available).
    - Local nav + decision rail maintain stable anchors for fast jump/read.
  - Rubric (before → target):
    - Scan speed: 3 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [ENTITY] /agents/:slug — convert table/card mix into sectioned flex workbench with client cohorts
  - Problem: Agent page mixes cards and multiple tables, making large client books hard to triage quickly.
  - Hypothesis: Cohort-based flex lanes (max-level, expiring, restricted, two-way) will speed portfolio reading.
  - Scope (files):
    - web/app/views/entities/agents/show.html.erb
    - web/app/views/entities/agents/_sticky_header.html.erb
    - web/test/integration/entities_agents_show_test.rb
  - Acceptance criteria:
    - Key client sections use flex-row lanes instead of table markup.
    - Cohort headers show counts + cap rollups and preserve direct player/team pivots.
    - Header/posture chips remain dense and immediately legible.
  - Rubric (before → target):
    - Scan speed: 3 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [ENTITY] /teams/:slug — de-table activity, two-way, and apron provenance into causal flow lanes
  - Problem: Team detail still has table-heavy operational sections that fragment the cap story.
  - Hypothesis: Converting these sections to dense flow lanes will improve “what changed and why” understanding.
  - Scope (files):
    - web/app/views/entities/teams/_section_activity.html.erb
    - web/app/views/entities/teams/_section_two_way.html.erb
    - web/app/views/entities/teams/_section_apron_provenance.html.erb
    - web/app/views/entities/teams/show.html.erb
    - web/test/integration/entities_teams_show_test.rb
  - Acceptance criteria:
    - No `<table>` markup remains in the three target team section partials.
    - Rows expose event/action → cap/tax/apron consequence in one line of sight.
    - Related pivots (player/transaction/trade) are preserved or improved.
  - Rubric (before → target):
    - Scan speed: 3 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [ENTITY] /transactions/:id — redesign from static record view to causal transaction timeline
  - Problem: Transaction detail is comprehensive but hard to parse causally (parties, ledger effects, artifacts are separated and table-dense).
  - Hypothesis: Timeline-style lanes with explicit cause/effect chips will make transaction interpretation much faster.
  - Scope (files):
    - web/app/views/entities/transactions/show.html.erb
    - web/test/integration/entities_transactions_show_test.rb
  - Acceptance criteria:
    - Page presents chronological/causal lane from transaction facts → parties → ledger deltas → cap artifacts.
    - Core sections avoid large table blocks for primary read path.
    - “Open related trade/player/team” pivots are visible in each lane.
  - Rubric (before → target):
    - Scan speed: 2 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P1] [ENTITY] /trades/:id — reframe trade detail as team-centric OUT/IN impact board
  - Problem: Trade detail contains rich data but requires too much table scanning to understand team-by-team directionality.
  - Hypothesis: Team-centric OUT/IN lanes with net impact cues will reduce drill burden and improve legal/cap interpretation.
  - Scope (files):
    - web/app/views/entities/trades/show.html.erb
    - web/test/integration/entities_trades_show_test.rb
  - Acceptance criteria:
    - Leg breakdown and trade-group sections are readable in team-centric lane grammar.
    - OUT/IN/net cues are visible before reading deep details.
    - Transaction, player, and pick pivots are preserved in each lane.
  - Rubric (before → target):
    - Scan speed: 2 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [ENTITY] /agencies/:slug — de-table roster/distribution/historical sections into flex lanes
  - Problem: Agency detail remains dominated by traditional tables, slowing cross-agent and cross-team pattern detection.
  - Hypothesis: Flex-lane sections with compact posture chips will speed “agency footprint” reads.
  - Scope (files):
    - web/app/views/entities/agencies/show.html.erb
    - web/test/integration/entities_agencies_show_test.rb
  - Acceptance criteria:
    - Agent roster, team distribution, and historical subsections no longer rely on table markup for primary rows.
    - Section headers expose counts/rollups and preserve direct agent/player/team pivots.
    - Local nav anchors remain stable.
  - Rubric (before → target):
    - Scan speed: 3 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [ENTITY] /draft-selections/:slug — convert provenance section to severity-first chain lanes
  - Problem: Draft selection detail still buries provenance complexity in a table.
  - Hypothesis: Severity-first chain lanes (clean / with trade / deep chain) will make ownership risk obvious immediately.
  - Scope (files):
    - web/app/views/entities/draft_selections/show.html.erb
    - web/test/integration/entities_draft_selections_show_test.rb
  - Acceptance criteria:
    - Provenance section renders as dense chain lanes with severity cues.
    - Trade/date/from→to details remain legible and linkable without table scanning.
    - Transaction/trade pivots remain one click.
  - Rubric (before → target):
    - Scan speed: 3 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [ENTITY] /draft-picks/:slug — redesign protections + trade chain into rule lanes and chain map
  - Problem: Draft pick detail is thorough but table-heavy and hard to interpret quickly under conditional complexity.
  - Hypothesis: Rule-oriented lanes plus compact chain map will improve comprehension of protections/swaps.
  - Scope (files):
    - web/app/views/entities/draft_picks/show.html.erb
    - web/test/integration/entities_draft_picks_show_test.rb
  - Acceptance criteria:
    - Protection details and trade chain sections use lane grammar with explicit conditional/swap flags.
    - Counterparty/original-owner context is visible without row-by-row table parsing.
    - Trade/team pivots remain immediate.
  - Rubric (before → target):
    - Scan speed: 3 → 5
    - Information hierarchy: 3 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 3 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/system-values — add keyboard-first metric finder shortlist
  - Problem: Finder works, but still biases pointer-heavy selection for known metrics.
  - Hypothesis: Ranked typeahead + Enter open will complete find-and-open in one flow.
  - Scope (files):
    - web/app/controllers/tools/system_values_controller.rb
    - web/app/views/tools/system_values/_commandbar.html.erb
    - web/app/views/tools/system_values/show.html.erb
    - web/test/integration/tools_system_values_test.rb
  - Acceptance criteria:
    - Finder supports keyboard shortlist + Enter to open selected metric overlay.
    - Finder/overlay/URL state stay synchronized after refresh.
    - No regressions in existing section visibility URL behavior.
  - Rubric (before → target):
    - Scan speed: 4 → 5
    - Information hierarchy: 5 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 5 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P2] [TOOL] /tools/two-way-utility — add intent suggestions with one-keystroke overlay open
  - Problem: Intent filter narrows rows but still requires manual find/open in dense team sections.
  - Hypothesis: Top-match shortlist with keyboard open will materially reduce player lookup friction.
  - Scope (files):
    - web/app/controllers/tools/two_way_utility_controller.rb
    - web/app/views/tools/two_way_utility/_commandbar.html.erb
    - web/app/views/tools/two_way_utility/_workspace_main.html.erb
    - web/app/views/tools/two_way_utility/_rightpanel_overlay_player.html.erb
    - web/test/integration/tools_two_way_utility_test.rb
  - Acceptance criteria:
    - Intent input displays ranked shortlist suggestions.
    - Enter/open selects a suggestion and opens overlay while preserving team-section context.
    - Compare pins and intent state remain stable after quick-open.
  - Rubric (before → target):
    - Scan speed: 4 → 5
    - Information hierarchy: 4 → 5
    - Interaction predictability: 4 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 4 → 5
  - Guardrails:
    - Do not modify Salary Book files.

- [ ] [P3] [PROCESS] design loop hygiene — enforce commit title schema and forbidden Salary Book path guard
  - Problem: Recent history includes inconsistent commit naming and historical risk of forbidden Salary Book path touches.
  - Hypothesis: Hard checks in loop/supervisor step will reduce drift and cleanup churn.
  - Scope (files):
    - agents/design.ts
    - web/app/views/tools/salary_book/_maincanvas_tankathon_frame.html.erb (allow-list reference only)
  - Acceptance criteria:
    - Commit title schema enforced (`design: [TRACK] /surface flow-outcome`) for worker commits.
    - Loop rejects diffs touching Salary Book files outside approved Tankathon file.
    - Failure mode is explicit and logged in supervision output.
  - Rubric (before → target):
    - Scan speed: 3 → 3
    - Information hierarchy: 4 → 4
    - Interaction predictability: 3 → 5
    - Density/readability: 4 → 4
    - Navigation/pivots: 3 → 3
  - Guardrails:
    - Salary Book exception: only edit `web/app/views/tools/salary_book/_maincanvas_tankathon_frame.html.erb`.
    - Do not modify any other Salary Book files/controllers/helpers/tests.
