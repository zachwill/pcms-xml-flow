# Excel Cap Workbook — Modern Formula Backlog

Build a new, self-contained Sean-style Excel cap workbook **generated from code** (Python + XlsxWriter) and powered by Postgres (`pcms.*`). Core sheets exist; the next push is **modern formula refactors** plus a small set of carryover functional items.

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

## Formula standard (Excel 365/2021 required)

- Use **dynamic arrays**: `FILTER`, `SORTBY`, `TAKE`, `UNIQUE`, `CHOOSECOLS`.
- Prefer `XLOOKUP` over `INDEX/MATCH`.
- Prefer `LET` + named formulas/LAMBDA helpers for shared logic.
- Prefer `SUM(FILTER(...))` over `SUMPRODUCT` when possible.
- Use `IFNA`/`IFERROR` to avoid noisy `#SPILL!`/blank errors.

---

## Backlog (modern formula refactor)

### 1) Document Excel 365+ requirement + formula standard
- [ ] Add explicit “Excel 365/2021 required” note to docs + workbook UI
  - Update relevant blueprints to call out dynamic array usage
  - Add a short note on HOME or META sheet
  - Update `excel/AGENTS.md` with formula standard

### 2) Create shared named formulas (LAMBDA/LET helpers)
- [ ] Define named formulas for repeated logic and reuse them in sheets
  - `ModeYearIndex` = `SelectedYear - MetaBaseYear + 1`
  - Mode-aware amount helpers for roster/holds/dead money
  - `PlanRowMask` and `TeamYearMask` for filtered aggregates
  - Replace inline fragments with named formulas

### 3) HOME + RULES_REFERENCE: migrate to XLOOKUP/FILTER
- [ ] Replace `INDEX/MATCH` in HOME readouts + RULES_REFERENCE tables
  - Use `XLOOKUP` for single-row lookups
  - Use `FILTER` + `TAKE` for tax brackets/minimum scale lists
  - Wrap with `IFNA` for clean blanks

### 4) PLAN_JOURNAL: totals + running state via LET/FILTER/SCAN
- [ ] Replace `SUMPRODUCT` panels with modern formulas
  - Keep “blank salary_year = SelectedYear” logic in mask
  - Use `SCAN` (or `BYROW`) for cumulative totals
  - Ensure conditional formatting still matches ActivePlan/SelectedYear

### 5) BUDGET_LEDGER: plan deltas via LET/FILTER
- [ ] Replace legacy SUMPRODUCT/SUMIFS blocks with LET + FILTER
  - Centralize mask in named formulas
  - Preserve `ActivePlanId` fallback behavior
  - Validate totals vs PLAN_JOURNAL and SUBSYSTEM_OUTPUTS

### 6) ROSTER_GRID: roster + two-way rows via FILTER/SORTBY/TAKE
- [ ] Replace AGGREGATE/MATCH row extraction with dynamic arrays
  - Build `RosterData` with FILTER by team/bucket
  - Use `CHOOSECOLS`/`XMATCH` to select mode/year column
  - Sort by SelectedYear amount (DESC)
  - Spill into reserved display ranges; add `IFNA` fallbacks

### 7) ROSTER_GRID: cap holds + dead money via FILTER/SORTBY/TAKE
- [ ] Convert holds/dead sections to dynamic arrays
  - Use mode-aware amount selection with CHOOSECOLS
  - Keep Ct$/CtR semantics
  - Ensure subtotals still reconcile with warehouse

### 8) ROSTER_GRID: EXISTS_ONLY section using LET/BYROW
- [ ] Replace custom SUMPRODUCT logic with LET + BYROW/MAP
  - Compute per-player “future total”
  - Filter to SelectedYear=0 and future > 0
  - Respect `ShowExistsOnlyRows` toggle

### 9) SIGNINGS_AND_EXCEPTIONS: delta columns via INDEX/CHOOSECOLS
- [ ] Replace CHOOSE with INDEX/CHOOSECOLS + LET
  - `INDEX([@year_1_salary]:[@year_4_salary], ModeYearIndex)`
  - Wrap with `IFNA(…,0)`
  - Keep journal output totals intact

### 10) WAIVE_BUYOUT_STRETCH: modernize computed columns
- [ ] Refactor computed columns using LET/INDEX
  - `net_owed` and dead-year distribution with LET
  - Use CHOOSECOLS for SelectedYear delta pick
  - Preserve stretch toggle logic

### 11) AUDIT_AND_RECONCILE: SUM(FILTER) instead of SUMPRODUCT
- [ ] Replace drilldown formulas with LET + FILTER + SUM
  - Use shared named masks for team/year/bucket
  - Ensure status checks remain stable
  - Keep tolerance behavior unchanged

---

## Carryover functional backlog

### 12) BUDGET_LEDGER: include SUBSYSTEM_OUTPUTS in plan delta totals
- [ ] Sum `tbl_subsystem_outputs` into the PLAN DELTA section
  - Add “Subsystem Outputs” row with totals
  - Update PLAN DELTA TOTAL to include subsystem rows
  - Show warning banner when any subsystem outputs are included

### 13) Incomplete roster charges policy
- [ ] Decide + implement (or explicitly exclude) incomplete roster charges
  - If implemented: GENERATED rows + policy delta + audit note
  - If excluded: explicit note in AUDIT_AND_RECONCILE policy assumptions

---

## Archived

- Previous v2 backlog tasks are complete or superseded; see git history for the full checklist.
