# TODO_UI — Salary Book-native dense UI roadmap

## Why
We want the **care and interaction rigor** seen in the Ferrari references, but mapped to our actual product:
- NBA salary-cap/trade workflows
- SQL-backed warehouse primitives
- Datastar server-rendered patch architecture

This doc reframes UI work around Salary Book truth and `web/` runtime constraints.

---

## Source-of-truth order (use in this sequence)

1. `web/AGENTS.md` (runtime rules, patch/SSE boundaries, Datastar constraints)
2. `SALARY_BOOK.md` (domain primitives + warehouse contracts)
3. `SALARY_BOOK_STATE_MODEL.md` (Official/Live/Scenario state lens)
4. `web/docs/design_guide.md` (shell + row/cell density patterns)
5. `reference/ui.md` (interaction rigor heuristics)
6. `reference/ferrari.md` (discipline inspiration only, not product semantics)

---

## Product posture

**Ferrari-grade interaction discipline, Salary Book-native semantics.**

That means:
- No automotive metaphors in product behavior.
- No client-side business logic.
- SQL remains the source for cap/trade/CBA math.
- UI must be dense, coherent, and state-explicit.

---

## Core implementation principles

1. **State/lens first**
   - Every complex page declares explicit state: `loading | ready | empty | error`.
   - Every major tool declares lens state (examples):
     - `official | live | scenario`
     - `cap | tax | apron`
     - risk filters (`all | warning | critical`)

2. **One coherent data contract per region**
   - `#maincanvas`, `#rightpanel-base`, `#rightpanel-overlay`, `#flash` each get data from explicit SQL sources.
   - No silent fallback to ad-hoc Ruby math.

3. **Coupling is intentional**
   - When focus/lens changes, dependent regions update together via one SSE response (ordered patches).

4. **Rows over cards**
   - Prefer dense row strips and table/flex row patterns.
   - Use cards only for rare narrative context.

5. **Feedback hierarchy**
   - Ambient (row tint/chip)
   - Glanceable (badges, indicators)
   - Focused (tabular numbers + deltas + provenance)

6. **Deliberate absence**
   - Suppress irrelevant modules in focused states.
   - Don’t render “all boxes always on.”

---

## Required page contract (new standard)

For each major page/tool, add a contract doc in `web/docs/contracts/` with these sections:

### 1) Data contract
- Primary warehouse/function sources (example: `pcms.team_salary_warehouse`, `pcms.salary_book_warehouse`, `pcms.fn_trade_*`).
- “What counts” logic (contract totals vs holds vs dead money) explicitly stated.
- Prohibited logic duplication in Rails.

### 2) State/lens contract
- Page states: loading/ready/empty/error.
- Lens states and defaults.
- Valid transitions + invalid input behavior.

### 3) Patch contract
- Patch targets by id.
- Single-region HTML vs multi-region SSE behavior.
- Ordered patch list for each interaction.

### 4) Coupling map
- `When X changes → Y and Z update` rules.
- Must include commandbar filters, table focus, sidebar context.

### 5) Snapshot fixtures
- At least 4: populated, empty, edge/high-risk, error.
- Include expected visible modules + hidden modules.

---

## Priority targets

### P1 (high impact)
1. `web/app/views/tools/team_summary/show.html.erb`
   - Add explicit active-row + keyboard state.
   - Add base sidebar context (`#rightpanel-base`) with team totals + quick pivots.
   - Contract doc: `web/docs/contracts/team_summary.md`.

2. `web/app/views/tools/two_way_utility/show.html.erb`
   - Add risk lens (`all | warning | critical`) tied to SQL-backed thresholds.
   - Couple lens → sort → highlight in one coherent response path.
   - Optional player overlay in `#rightpanel-overlay`.

3. `web/app/views/entities/agents/show.html.erb`
4. `web/app/views/entities/agencies/show.html.erb`
   - Replace card-heavy modules with dense row strips.
   - Preserve drill-in detail via collapsible rows/overlay.

### P2 (higher complexity)
5. `web/app/views/entities/trades/show.html.erb`
6. `web/app/views/entities/transactions/show.html.erb`
   - Add shared `focus_team` state that filters all dependent modules.
   - Tighten coupling across breakdown/ledger/artifacts.
   - Contract docs for both pages.

7. `web/app/views/tools/system_values/show.html.erb`
   - Lens: `absolute | yoy_delta | pct_delta`.
   - Transition markers for cap/tax/apron threshold crossings.

### P3 (consistency)
8. `entities/draft_selections/show`
9. `entities/draft_picks/show`
10. Complete contract + snapshot coverage for all high-traffic pages.

---

## Definition of done (per page)

- Uses shell pattern A/B/C from `web/docs/design_guide.md`.
- Explicit state/lens model documented.
- Data contract points to SQL source(s) and “what counts” behavior.
- Multi-region interactions delivered via one SSE stream.
- Dense row-first treatment; no unnecessary card chrome.
- Numeric/financial cells use `font-mono tabular-nums`.
- Shared yellow row hover pattern present.
- Couplings are visible and testable.
- URL/deep-link captures key context where appropriate.
- Snapshot fixtures exist and are reviewable.

---

## Immediate next steps

1. Create contract template file: `web/docs/contracts/_template.md`.
2. Implement first two contracts:
   - `web/docs/contracts/team_summary.md`
   - `web/docs/contracts/two_way_utility.md`
3. Execute P1 on Team Summary with explicit patch/coupling map.
4. Add snapshot fixtures for Team Summary (`normal`, `empty`, `edge`, `error`).

This keeps us aligned to Salary Book truth while preserving the high-discipline interaction quality we liked from Ferrari.