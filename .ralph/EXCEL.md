# Excel Cap Workbook — Backlog

Build a new, self-contained Sean-style Excel cap workbook **generated from code** (Python + XlsxWriter) and powered by Postgres (`pcms.*`).

This backlog reflects the post-v2 audit. Core sheets exist; remaining work focuses on correctness, usability, and explicit policy wiring.

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

## Backlog (ordered)

### 1) AUDIT_AND_RECONCILE: add apron reconciliation section
- [x] Add an `APRON AMOUNT RECONCILIATION` block mirroring CAP/TAX
  - Warehouse columns: `apron_rost`, `apron_2way`, `apron_fa`, `apron_term`, `apron_total`
  - Drilldowns:
    - `tbl_salary_book_warehouse[apron_y*]` (SelectedYear via `CHOOSE`)
    - `tbl_cap_holds_warehouse[apron_amount]`
    - `tbl_dead_money_warehouse[apron_value]`
  - Conditional formatting: delta==0 green, else red
  - Total row for `APRON TOTAL`

### 2) AUDIT_AND_RECONCILE: make the summary banner require CAP+TAX+APRON all reconcile
- [ ] Update the summary banner logic so it cannot show PASS if any section mismatches
  - PASS iff all three total deltas (cap/tax/apron) are zero (tolerance < 1)
  - FAIL message should name which totals are mismatched (Cap/Tax/Apron) and show deltas

### 3) TEAM_COCKPIT: surface a reconciliation delta alert (mode-aware)
- [ ] Add a cockpit alert row: `Unreconciled drilldowns vs warehouse: $X (SelectedMode)`
  - Compute delta as: (salary_book for SelectedTeam + holds + dead_money) − warehouse total for SelectedMode/SelectedYear
  - Conditional formatting: non-zero delta shows red and points to `AUDIT_AND_RECONCILE`
  - Keep headline totals authoritative (still sourced from `tbl_team_salary_warehouse`)

### 4) Policy toggles: make “not implemented yet” explicit (no silent defaults)
- [ ] When `RosterFillTarget > 0`, show a **loud** “NOT YET IMPLEMENTED” warning
  - Display in both `TEAM_COCKPIT` and `BUDGET_LEDGER`
  - Explicitly state that no generated fill rows are currently being applied
- [ ] When `ShowExistsOnlyRows = "Yes"`, show a “NOT YET IMPLEMENTED” warning
  - Until EXISTS_ONLY rows actually exist, don’t imply the toggle does anything

### 5) ROSTER_GRID: implement EXISTS_ONLY rows + wire `ShowExistsOnlyRows`
- [ ] Add an `EXISTS_ONLY` section (non-counting rows) for analyst reference
  - Suggested MVP definition: players with `team_code=SelectedTeam` who have 0 in SelectedYear (all modes) but non-zero in a future year column
  - When `ShowExistsOnlyRows="No"`, hide/suppress this section
  - Label clearly as “exists but does not count”

### 6) Two-way toggles: clarify semantics and avoid breaking reconciliation trust
- [ ] Decide + implement (and label) what `CountTwoWayInTotals` means
  - Either:
    - (A) treat it as **display-only** (Ct$ labels only) and **label it that way**, OR
    - (B) compute a separate “policy-adjusted total (excluding 2-way)” that is explicitly *not* the authoritative total
  - In either case, keep the authoritative reconciliation path intact vs `tbl_team_salary_warehouse`

### 7) Roster fill (generated rows): implement minimal, explicit, toggleable generation
- [ ] Add a `GENERATED` section that creates fill rows when `RosterFillTarget` is 12/14/15
  - Generate `RosterFillTarget - current_roster_count` rows
  - Choose amounts based on `RosterFillType` (`Rookie Min` / `Vet Min` / `Cheapest`) using `tbl_minimum_scale` / `tbl_rookie_scale`
  - Generated rows must:
    - be visibly labeled as generated assumptions
    - be toggleable by setting `RosterFillTarget=0`
    - be auditable/reconcilable in `AUDIT_AND_RECONCILE` (as policy deltas, not silently merged)

---

## Completed (recent)

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
  - Honor `CountTwoWayInRoster` + `CountTwoWayInTotals` in CtR/Ct$ labels
  - Ensure % of cap and MINIMUM label use **SelectedYear**

- [x] ROSTER_GRID: mode-aware amounts (Cap / Tax / Apron)
  - Mode-switch uses IF(SelectedMode=...) pattern in all salary column formulas
  - Year headers show mode + year (e.g., "Cap 2025", "Tax 2026")
  - Reconciliation block uses mode-appropriate warehouse columns

- [x] ROSTER_GRID: apply option/guarantee/trade badge conditional formatting

- [x] TEAM_COCKPIT: quick drivers + min totals use SelectedYear
