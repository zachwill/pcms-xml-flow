# Excel Cap Workbook - Backlog

Build a new, self-contained Sean-style Excel cap workbook **generated from code** (Python + XlsxWriter) and powered by Postgres (`pcms.*`).

This backlog reflects the post-v2 audit. Core sheets exist; remaining work focuses on feature-complete scenario tooling, subsystem wiring, and UI polish.

**Canon:** `reference/blueprints/README.md`

---

## Rules (non-negotiable)

- The workbook is a **build artifact**. Prefer deterministic code-gen over manual Excel editing.
- Single-file workbook output (portable/offline). **No external workbook links.**
- Prefer **warehouse-backed** extracts (`pcms.*_warehouse`, `pcms.salary_book_yearly`).
- Use `shared/` for generated artifacts (gitignored).
- All money amounts are **dollars (int)** unless explicitly documented.
- Record `META` fields so every workbook snapshot is reproducible.
- When adding/changing datasets, update:
  - `reference/blueprints/excel-workbook-data-contract.md`
  - `DATA_CONTRACT_VERSION` in `excel/capbook/build.py`
- Reuse UI formatting conventions from `web/src/features/SalaryBook/`.
- **One task per iteration.** Each checkbox below is one iteration; sub-bullets are required deliverables.

---

## Backlog (feature complete)

### 1) Docs alignment (blueprints + agents + comments)
- [x] Update docs to reflect current workbook semantics
  - Remove two-way toggles from the blueprint command bar section
  - Add GENERATED section to ROSTER_GRID lists (blueprint + excel/AGENTS.md)
  - Update command_bar.py comment about fill rows being "not implemented yet"
  - Note policy decisions (two-way counting, fill rows) in blueprint if missing

### 2) HOME sheet: implement full landing page
- [x] Replace HOME stub with a full landing page
  - Show Active Team/Year/Mode/As-of/ActivePlan/Compare Plans using named ranges
  - Show validation + reconcile status from META
  - Add navigation hyperlinks to all major sheets
  - Include top-line readouts (cap/tax/apron room, roster count) from warehouse totals

### 3) PLAN_JOURNAL: add salary_year context + update plan delta filters
- [x] Add salary_year to tbl_plan_journal and filter deltas by SelectedYear
  - Update PLAN_JOURNAL table columns + instructions
  - Default salary_year to SelectedYear via formula (blank = SelectedYear)
  - Update BUDGET_LEDGER plan delta SUMIFS to filter salary_year=SelectedYear
  - Adjusted module docstrings and notes to reflect year-aware filtering

### 4) PLAN_JOURNAL: ActivePlan summary + running totals panel
- [x] Add a running-state panel for ActivePlan + SelectedYear
  - Summary box: total deltas (cap/tax/apron) + action count
  - Cumulative running totals by step for ActivePlan
  - Conditional formatting to gray out rows not in ActivePlan/SelectedYear

### 5) AUDIT_AND_RECONCILE: implement plan diff section
- [x] Replace plan diff placeholder with real Plan Diff outputs
  - Baseline vs ActivePlan delta totals (cap/tax/apron) for SelectedYear
  - Journal action counts + enabled counts
  - Link note back to PLAN_JOURNAL for drilldown

### 6) TEAM_COCKPIT: add plan comparison panel
- [x] Surface ComparePlan A/B/C/D deltas
  - For each compare plan, show delta vs Baseline (cap/tax/apron)
  - Warn if ComparePlan is blank or equals Baseline
  - Link to PLAN_JOURNAL for details

### 7) Exporter/build: deep reconciliation (warehouse totals vs drilldowns)
- [x] Add build-time reconcile v2 (team totals vs drilldown sums)
  - For each `(team_code, salary_year)`: sum drilldowns and compare to `tbl_team_salary_warehouse` totals
    - Cap: `tbl_salary_book_yearly[cap_amount] + tbl_cap_holds_warehouse[cap_amount] + tbl_dead_money_warehouse[cap_value]`
    - Tax: `tbl_salary_book_yearly[tax_amount] + tbl_cap_holds_warehouse[tax_amount] + tbl_dead_money_warehouse[tax_value]`
    - Apron: `tbl_salary_book_yearly[apron_amount] + tbl_cap_holds_warehouse[apron_amount] + tbl_dead_money_warehouse[apron_value]`
  - Record summary fields in `META` (e.g., `reconcile_v2_passed`, counts, first N failures)
  - Mark `validation_status=FAILED` when any mismatch (still emit workbook artifact)

### 8) ASSETS: wire exceptions inventory to DATA_exceptions_warehouse
- [x] Replace placeholder notes with live formulas
  - `FILTER/IFERROR` for `tbl_exceptions_warehouse` (SelectedTeam; include salary_year column in display)
  - Apply money/date formats + explicit "None" empty-state

### 9) ASSETS: wire draft picks to DATA_draft_picks_warehouse
- [x] Replace placeholder notes with live formulas
  - `FILTER/IFERROR` for `tbl_draft_picks_warehouse` (SelectedTeam)
  - Sort by `draft_year`, `draft_round`, `asset_slot` + show `needs_review` indicator clearly

### 10) SIGNINGS_AND_EXCEPTIONS: wire exception inventory
- [x] Drive exception inventory from DATA_exceptions_warehouse
  - Add live exception table filtered by SelectedTeam
  - Align formats with RULES_REFERENCE (money/date)

### 11) SIGNINGS_AND_EXCEPTIONS: compute deltas + journal output
- [x] Add formula-driven SelectedYear deltas for signings
  - Per-row SelectedYear delta (cap/tax/apron) based on year columns
  - Add a "Journal Output" block with aggregated deltas + source label
  - Document manual publish workflow (copy into PLAN_JOURNAL)

### 12) Exporter: surface reconciliation v2 (drilldowns vs totals)
- [x] Show reconcile_v2 status and failures in META + HOME
  - META: add a v2 reconciliation section (drilldowns vs warehouse totals)
  - HOME: Data Health banner considers reconcile_v1 AND reconcile_v2

### 13) SIGNINGS_AND_EXCEPTIONS: exception_used validation helper list
- [x] Add exception_used dropdown sourced from DATA_exceptions_warehouse
  - Add a helper spill range using FILTER for SelectedTeam exceptions (non-expired)
  - Label format: "exception_type_name ($remaining)" or "TPE: player_name ($remaining)"
  - Named range `ExceptionUsedList` references the spill range via spill operator (#)
  - Data validation wired for tbl_signings_input[exception_used] with warning mode

### 14) WAIVE_BUYOUT_STRETCH: formula-driven net owed + dead money
- [x] Compute waive/buyout deltas via formulas
  - net_owed = remaining_gtd - giveback
  - dead_year_* formulas based on stretch toggle (simple distribution)
  - Add SelectedYear delta + journal output block

### 15) TRADE_MACHINE: team selectors + status summary
- [ ] Add team dropdowns and lane status summaries
  - Team validation list from tbl_team_salary_warehouse[team_code]
  - Show each lane’s cap/tax/apron totals + room for SelectedYear
  - Display apron level / taxpayer status from warehouse

### 16) TRADE_MACHINE: matching rules + legality outputs
- [ ] Implement matching math per lane
  - Compute max incoming using rule tiers + outgoing total
  - Output legality flag + notes (aggregation/apron restrictions)
  - Tie to SelectedMode/SelectedYear context

### 17) TRADE_MACHINE: journal output rows
- [ ] Add per-lane Journal Output rows
  - Net delta for SelectedYear (cap/tax/apron)
  - Source label (e.g., "Trade Lane A")
  - Publish instructions (copy into PLAN_JOURNAL)

### 18) PLAN_JOURNAL: subsystem outputs integration
- [ ] Add SUBSYSTEM_OUTPUTS rollup + include in budget ledger
  - Reference Journal Output blocks from Trade/Signings/Waive
  - Update BUDGET_LEDGER plan deltas to include subsystem outputs
  - Document workflow so analysts know what feeds totals

### 19) Incomplete roster charges policy
- [ ] Decide + implement (or explicitly exclude) incomplete roster charges
  - If implemented: GENERATED rows + policy delta + audit note
  - If excluded: explicit note in AUDIT_AND_RECONCILE policy assumptions

---

## Completed (v2 backlog)

### 1) ROSTER_GRID: implement EXISTS_ONLY rows + wire `ShowExistsOnlyRows`
- [x] Add an `EXISTS_ONLY` section (non-counting rows) for analyst reference
  - Implemented: shows players with `team_code=SelectedTeam` who have $0 in SelectedYear (all modes: cap/tax/apron = 0) but non-zero in a future year column
  - When `ShowExistsOnlyRows="No"` (default), section displays a collapsed message; when `"Yes"`, full listing shown
  - Labeled as "EXISTS" bucket with Ct$="N", CtR="N" (never counts)
  - Purple styling to visually distinguish from counting sections
  - Updated TEAM_COCKPIT + BUDGET_LEDGER to show info message instead of "NOT YET IMPLEMENTED" warning

### 2) Two-way toggles: decide + implement real semantics without breaking reconciliation trust
- [x] Decide what `CountTwoWayInTotals` / `CountTwoWayInRoster` mean, and implement accordingly
  - **Decision:** Remove the toggles entirely. Two-way counting is a CBA fact, not a user policy choice.
  - Per CBA: two-way contracts COUNT toward cap/tax/apron totals but do NOT count toward 15-player roster.
  - The toggles were misleading because they implied the user could change authoritative totals.
  - **Implementation:**
    - Removed `CountTwoWayInRoster` and `CountTwoWayInTotals` toggles from command bar
    - Removed "NOT YET IMPLEMENTED" warnings from TEAM_COCKPIT and BUDGET_LEDGER
    - Added informational 2-way readouts to TEAM_COCKPIT PRIMARY READOUTS section:
      - "Two-Way Count:" — shows `two_way_row_count` (separate from 15-player roster)
      - "Two-Way Cap Amount:" — shows `cap_2way` (included in Cap Total above)
    - Updated AUDIT_AND_RECONCILE policy assumptions section (removed 2-way toggle rows)
    - Roster Count readout already shows "NBA roster + N two-way" format

### 3) Roster fill (generated rows): implement minimal, explicit, toggleable generation
- [x] Add a `GENERATED` section that creates fill rows when `RosterFillTarget` is 12/14/15
  - Generate `RosterFillTarget - current_roster_count` rows
  - Choose amounts based on `RosterFillType` (`Rookie Min` / `Vet Min` / `Cheapest`) using `tbl_minimum_scale` / `tbl_rookie_scale`
  - Generated rows:
    - Are visibly labeled as "GEN" bucket with gold/amber styling
    - Are toggleable by setting `RosterFillTarget=0`
    - Show Ct$=Y and CtR=Y (count toward totals and roster)
    - Display "Fill Slot #N (type)" in the Name column
    - Appear in ROSTER_GRID between DEAD MONEY and EXISTS_ONLY sections
  - TEAM_COCKPIT and BUDGET_LEDGER show informational amber alert when fill is active
  - AUDIT_AND_RECONCILE shows policy impact breakdown (current roster count, fill rows needed, amount per row, total impact)
  - NOTE: Generated rows are policy assumptions, NOT included in reconciliation checks (warehouse vs drilldowns)

---

## Follow-ups discovered

- [x] Consider adding GENERATED fill amounts to BUDGET_LEDGER as an explicit "Policy Delta" row (currently only shown in AUDIT section)
  - Added a new **POLICY DELTAS** section between Plan Deltas and Derived Totals
  - Shows "Generated Fill Rows (GEN)" with cap/tax/apron impact
  - Uses amber styling to clearly indicate policy assumptions vs authoritative data
  - Dynamic note shows fill count and type when active
  - Updated Derived Totals formula: `Snapshot + Plan + Policy = Derived`
  - Updated sheet subtitle and docstrings to reflect new structure
- [x] Consider mode-aware fill amounts (currently uses cap-based minimum; could vary by Tax/Apron mode)
  - **Decision:** No change needed. Fill amounts are intentionally mode-independent.
  - **Rationale:** Minimum salary contracts (both rookie min and vet min) count identically
    toward cap, tax, and apron thresholds per CBA. There is no separate "tax minimum" or
    "apron minimum" — the same dollar amount applies regardless of which mode is selected.
  - **Implementation:** Added clarifying comments to `roster_grid.py` and `audit.py` explaining
    why mode-aware fill amounts are not needed.

---

## Completed (recent)

- [x] AUDIT_AND_RECONCILE: add apron reconciliation section
  - Add an `APRON AMOUNT RECONCILIATION` block mirroring CAP/TAX
  - Warehouse columns: `apron_rost`, `apron_2way`, `apron_fa`, `apron_term`, `apron_total`
  - Drilldowns:
    - `tbl_salary_book_warehouse[apron_y*]` (SelectedYear via `CHOOSE`)
    - `tbl_cap_holds_warehouse[apron_amount]`
    - `tbl_dead_money_warehouse[apron_value]`
  - Conditional formatting: delta==0 green, else red
  - Total row for `APRON TOTAL`

- [x] AUDIT_AND_RECONCILE: make the summary banner require CAP+TAX+APRON all reconcile
  - PASS iff all three total deltas (cap/tax/apron) are zero (tolerance < 1)
  - FAIL message names which totals are mismatched (Cap/Tax/Apron) and shows deltas

- [x] TEAM_COCKPIT: surface a reconciliation delta alert (mode-aware)
  - Compute delta as: (salary_book for SelectedTeam + holds + dead_money) - warehouse total for SelectedMode/SelectedYear
  - Conditional formatting: non-zero delta shows red and points to `AUDIT_AND_RECONCILE`
  - Keep headline totals authoritative (still sourced from `tbl_team_salary_warehouse`)

- [x] Policy toggles: make "not implemented yet" explicit (no silent defaults) — historical (superseded by later fill + EXISTS_ONLY implementation)
  - When `RosterFillTarget > 0`, show a **loud** "NOT YET IMPLEMENTED" warning in `TEAM_COCKPIT` and `BUDGET_LEDGER`
  - When `ShowExistsOnlyRows = "Yes"`, show a **loud** "NOT YET IMPLEMENTED" warning in `TEAM_COCKPIT` and `BUDGET_LEDGER`

- [x] Two-way toggles: stop misleading implications while keeping reconciliation trust — historical (superseded by later toggle removal + informational readouts)
  - `ROSTER_GRID` Ct$/CtR reflect **authoritative** counting semantics (2-way Ct$=Y, CtR=N)
  - When `CountTwoWayInTotals="Yes"` or `CountTwoWayInRoster="Yes"`, show **NOT YET IMPLEMENTED** warnings

- [x] Unlock input tables on protected sheets
  - Apply unlocked input formats to `tbl_plan_manager`, `tbl_plan_journal`, `tbl_signings_input`, `tbl_waive_input`
  - Confirm sheet protection still prevents formula overwrites but allows user edits
  - Add a quick note in each sheet explaining editable zones

- [x] Budget ledger plan deltas respect `ActivePlan` (via `ActivePlanId`)
  - Add named range `ActivePlanId` (lookup plan_id from `tbl_plan_manager[plan_name]=ActivePlan`)
  - Update plan delta SUMIFS to filter by `plan_id = ActivePlanId`
  - Add fallback behavior if ActivePlanId is blank

- [x] ROSTER_GRID: add explicit `CountsTowardTotal` / `CountsTowardRoster` columns
  - Make bucket logic explicit (ROST / 2WAY / FA / TERM)
  - Ensure % of cap and MINIMUM label use **SelectedYear**

- [x] ROSTER_GRID: mode-aware amounts (Cap / Tax / Apron)
  - Mode-switch uses IF(SelectedMode=...) pattern in all salary column formulas
  - Year headers show mode + year (e.g., "Cap 2025", "Tax 2026")
  - Reconciliation block uses mode-appropriate warehouse columns

- [x] ROSTER_GRID: apply option/guarantee/trade badge conditional formatting

- [x] TEAM_COCKPIT: quick drivers + min totals use SelectedYear
