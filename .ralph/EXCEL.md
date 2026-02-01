# Excel Cap Workbook - Supervisor Backlog

Build a new, self-contained Sean-style Excel cap workbook **generated from code** (Python + XlsxWriter) and powered by Postgres (`pcms.*`).

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
- Use `IFNA`/`IFERROR` to avoid noisy `#SPILL!` and lookup errors.

---

## Backlog (next work)

### 13) TEAM_COCKPIT: Minimum contracts readout without SUMPRODUCT
- [x] Replace min-contract SUMPRODUCT logic with `LET + FILTER + SUM/ROWS`
  - Replace `Min Contract Total` SUMPRODUCT (SelectedYear cap amounts)
  - Also replaced `Min Contract Count` COUNTIFS with `ROWS(FILTER(...))`
  - Total $ and count should match current results
  - Keep display clean (0 instead of errors via IFERROR)

### 14) TEAM_COCKPIT: Plan comparison deltas without SUMPRODUCT
- [x] Replace SUMPRODUCT-based compare-plan deltas + action counts with `LET + FILTER + SUM/ROWS`
  - Use `XLOOKUP` to resolve `ComparePlan{A..D}` → `plan_id`
  - Filter rules must match journal semantics:
    - `(plan_id = resolved_plan_id OR plan_id = "")`
    - `(salary_year = SelectedYear OR salary_year = "")`
    - `enabled = "Yes"`
  - Preserve existing warnings for blank/Baseline compare plans

---

## Completed (recent)

### 12) TEAM_COCKPIT: Quick Drivers via FILTER/SORTBY/TAKE
- [x] Replace AGGREGATE/MATCH "top N" extraction with spill formulas
  - Build Top Cap Hits / Top Holds / Top Dead Money as dynamic arrays
  - Prefer `LET + FILTER + SORTBY + TAKE` (single spill per panel)
  - Mode-aware sorting (respects SelectedMode: Cap/Tax/Apron)
  - Totals now use `SUM(FILTER(...))` instead of SUMIFS (mode-aware)

### 1) Document Excel 365+ requirement + formula standard
- [x] Add explicit "Excel 365/2021 required" note to docs + workbook UI

### 2) Create shared named formulas (LAMBDA/LET helpers)
- [x] Define named formulas for repeated logic and reuse them in sheets

### 3) HOME + RULES_REFERENCE: migrate to XLOOKUP/FILTER
- [x] Replace `INDEX/MATCH` in HOME readouts + RULES_REFERENCE tables

### 4) PLAN_JOURNAL: totals + running state via LET/FILTER/SCAN
- [x] Replace `SUMPRODUCT` panels with modern formulas

### 5) BUDGET_LEDGER: plan deltas via LET/FILTER
- [x] Replace legacy SUMPRODUCT/SUMIFS blocks with LET + FILTER

### 6) ROSTER_GRID: roster + two-way rows via FILTER/SORTBY/TAKE
- [x] Replace AGGREGATE/MATCH row extraction with dynamic arrays

### 7) ROSTER_GRID: cap holds + dead money via FILTER/SORTBY/TAKE
- [x] Convert **CAP HOLDS** and **DEAD MONEY** sections to dynamic arrays
  - Build spill ranges from `tbl_cap_holds_warehouse` / `tbl_dead_money_warehouse` filtered by `SelectedTeam + SelectedYear`
  - Sort by SelectedYear amount (DESC) using `SORTBY`
  - Take first N (match current UI row budgets) using `TAKE`
  - Keep Ct$/CtR semantics explicit
  - Ensure section subtotals reconcile (to `tbl_team_salary_warehouse` buckets)

### 8) ROSTER_GRID: EXISTS_ONLY section using LET/BYROW or MAP
- [x] Replace remaining custom aggregation logic with spill formulas
  - Compute per-player "future total" (SelectedYear=0 but future > 0)
  - Respect `ShowExistsOnlyRows` toggle
  - Keep Ct$=N, CtR=N (never counted)

### 9) SIGNINGS_AND_EXCEPTIONS: delta columns via INDEX/CHOOSECOLS
- [x] Replace contract-year delta pick logic with `INDEX`/`CHOOSECOLS` + `ModeYearIndex`
  - `LET(idx, ModeYearIndex, IF(idx>4, 0, IFNA(INDEX([@year_1_salary]:[@year_4_salary], 1, idx), 0)))`
  - Handles years beyond 4-year contract window (returns 0)
  - Uses `ModeYearIndex` named formula from `named_formulas.py`
  - Journal Output totals unchanged (still use SUBTOTAL on delta columns)

### 10) WAIVE_BUYOUT_STRETCH: modernize computed columns
- [x] Refactor computed columns using `LET` + `INDEX`
  - `net_owed` and dead-year distribution using `LET`
  - Use `INDEX` + `ModeYearIndex` for SelectedYear delta pick
  - Preserve stretch toggle logic and validations

### 11) AUDIT_AND_RECONCILE: SUM(FILTER) instead of SUMPRODUCT
- [x] Replace drilldown formulas with `LET + FILTER + SUM`
  - Uses LET + CHOOSECOLS + FILTER for salary_book year-column selection
  - Uses shared PlanRowMask LAMBDA for plan_journal filtering
  - Tolerance behavior unchanged (ABS < 1 is OK)
  - Non-zero deltas remain visually loud (red conditional formatting)

### 17) TRADE_MACHINE: journal output rows
- [x] Add per-lane Journal Output rows

### 18) PLAN_JOURNAL: SUBSYSTEM_OUTPUTS staging table (no copy/paste)
- [x] Add `tbl_subsystem_outputs` rollup

### 19) BUDGET_LEDGER: include SUBSYSTEM_OUTPUTS in plan delta totals
- [x] Sum `tbl_subsystem_outputs` into the PLAN DELTA section

### 20) Incomplete roster charges policy
- [x] **Decision:** Explicitly EXCLUDED (not implemented)
  - Documented in `excel-cap-book-blueprint.md` and `mental-models-and-design-principles.md`
  - Shown as "Not Implemented" in `AUDIT_AND_RECONCILE`

---

## Archived

- Previous v2 backlog tasks are complete or superseded; see git history for the full checklist.
