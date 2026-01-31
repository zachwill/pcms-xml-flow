# Excel Cap Workbook - Audit Remediation Backlog

Build a new, self-contained Sean-style Excel cap workbook **generated from code** (Python + XlsxWriter) and powered by Postgres (`pcms.*`).

This backlog reflects the post-v2 audit. Core sheets exist; remaining work focuses on correctness, usability, and policy wiring.

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

### 1) Make PLAN + subsystem input tables truly editable
- [x] Unlock input tables on protected sheets
  - Apply unlocked input formats to `tbl_plan_manager`, `tbl_plan_journal`, `tbl_signings_input`, `tbl_waive_input`
  - Confirm sheet protection still prevents formula overwrites but allows user edits
  - Add a quick note in each sheet explaining editable zones

### 2) Wire ActivePlan filtering for plan deltas
- [x] Budget ledger plan deltas must respect `ActivePlan`
  - Add named range `ActivePlanId` (lookup plan_id from `tbl_plan_manager[plan_name]=ActivePlan`)
  - Update plan delta SUMIFS to filter by `plan_id = ActivePlanId`
  - Add fallback behavior if ActivePlanId is blank

### 3) ROSTER_GRID structure + SelectedYear alignment
- [x] Add explicit "CountsTowardTotal" / "CountsTowardRoster" columns
  - Make bucket logic explicit (ROST / 2WAY / FA / TERM / EXISTS_ONLY)
  - Honor `CountTwoWayInRoster` + `CountTwoWayInTotals` toggles
  - Ensure % of cap and MINIMUM label use **SelectedYear** values
  - Fix subtotal placement so SelectedYear totals align with the displayed year column

### 4) ROSTER_GRID mode-aware amounts (Cap / Tax / Apron)
- [ ] Make the roster grid amounts switch by `SelectedMode`
  - Either add a mode-switch column (single-year display) **or** provide 3 side-by-side blocks
  - Update reconciliation block to match the active mode
  - Keep formulas compatible with relative-year columns

### 5) Apply badge formatting in ROSTER_GRID
- [ ] Map option/guarantee/trade restriction text → colored badges
  - Use XlsxWriter formats aligned to web UI colors
  - Apply conditional formatting by cell value (PO/TO/ETO, GTD/PRT/NG, NTC/Kicker/Restricted)

### 6) TEAM_COCKPIT drivers use SelectedYear
- [ ] Update cockpit quick drivers + min totals to be SelectedYear-aware
  - Top cap hits should use SelectedYear (not always cap_y0)
  - Min contract totals should use SelectedYear cap amounts
  - Keep formulas stable with relative-year columns

### 7) AUDIT_AND_RECONCILE: add apron reconciliation
- [ ] Add apron bucket + total reconciliation (warehouse vs drilldowns)
  - Include apron deltas in the summary banner logic
  - Keep conditional formatting consistent with cap/tax sections

### 8) Policy toggles actually affect outputs
- [ ] Wire policy toggles into calculations
  - `ShowExistsOnlyRows` should control display of non-counting rows
  - `RosterFillTarget` / `RosterFillType` should at least surface a visible "not yet implemented" warning
  - Add simple policy summary warnings in TEAM_COCKPIT + AUDIT
