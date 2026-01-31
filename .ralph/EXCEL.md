# Excel Cap Workbook - Backlog

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

### 1) ROSTER_GRID: implement EXISTS_ONLY rows + wire `ShowExistsOnlyRows`
- [x] Add an `EXISTS_ONLY` section (non-counting rows) for analyst reference
  - Implemented: shows players with `team_code=SelectedTeam` who have $0 in SelectedYear (all modes: cap/tax/apron = 0) but non-zero in a future year column
  - When `ShowExistsOnlyRows="No"` (default), section displays a collapsed message; when `"Yes"`, full listing shown
  - Labeled as "EXISTS" bucket with Ct$="N", CtR="N" (never counts)
  - Purple styling to visually distinguish from counting sections
  - Updated TEAM_COCKPIT + BUDGET_LEDGER to show info message instead of "NOT YET IMPLEMENTED" warning

### 2) Two-way toggles: decide + implement real semantics without breaking reconciliation trust
- [ ] Decide what `CountTwoWayInTotals` / `CountTwoWayInRoster` mean, and implement accordingly
  - Current behavior (intentional, for trust):
    - Authoritative totals always come from `tbl_team_salary_warehouse` (includes 2-way)
    - `ROSTER_GRID` Ct$/CtR are **authoritative** (2-way Ct$=Y, CtR=N)
    - If either toggle is set to "Yes", the workbook shows **NOT YET IMPLEMENTED** warnings
  - Next step options (pick one):
    - (A) Treat toggles as **display-only** and rename/relocate them (or remove them)
    - (B) Add a clearly labeled **policy-adjusted** total/count (excluding 2-way) that is explicitly *not* the authoritative total

### 3) Roster fill (generated rows): implement minimal, explicit, toggleable generation
- [ ] Add a `GENERATED` section that creates fill rows when `RosterFillTarget` is 12/14/15
  - Generate `RosterFillTarget - current_roster_count` rows
  - Choose amounts based on `RosterFillType` (`Rookie Min` / `Vet Min` / `Cheapest`) using `tbl_minimum_scale` / `tbl_rookie_scale`
  - Generated rows must:
    - be visibly labeled as generated assumptions
    - be toggleable by setting `RosterFillTarget=0`
    - be auditable/reconcilable in `AUDIT_AND_RECONCILE` (as policy deltas, not silently merged)

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

- [x] Policy toggles: make "not implemented yet" explicit (no silent defaults)
  - When `RosterFillTarget > 0`, show a **loud** "NOT YET IMPLEMENTED" warning in `TEAM_COCKPIT` and `BUDGET_LEDGER`
  - When `ShowExistsOnlyRows = "Yes"`, show a **loud** "NOT YET IMPLEMENTED" warning in `TEAM_COCKPIT` and `BUDGET_LEDGER`

- [x] Two-way toggles: stop misleading implications while keeping reconciliation trust
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
