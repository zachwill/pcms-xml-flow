# Excel Cap Workbook - Task Backlog

Build a new, self-contained Sean-style Excel cap workbook **generated from code** (Python + XlsxWriter) and powered by Postgres (`pcms.*`).

**Canon:** `reference/blueprints/README.md` (start there)

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

### Phase 0 - Baseline scaffold (already done)
- [x] Baseline exporter + workbook scaffold
  - Module structure + CLI entrypoint
  - Base `DATA_*` extracts + tables
  - UI stubs + META + validation handling
  - TEAM_COCKPIT v1 readouts
  - XlsxWriter helpers + badge color mapping

### Phase 1 - Data contract expansion (tables first)
- [x] Expand core `DATA_*` tables + contract
  - Add `DATA_rookie_scale` (from `pcms.rookie_scale_amounts`, base_year..+5, league)
  - Add `DATA_minimum_scale` (from `pcms.league_salary_scales`)
  - Expand `DATA_system_values` with key constants (MLE, BAE, TPE allowance, etc.)
  - Update `DATA_SHEETS`, `dataset_specs`, and data contract doc
  - Bump `DATA_CONTRACT_VERSION` to v2-2026-01-31

### Phase 2 - Shared command bar + named ranges
- [x] Implement shared command bar across **all UI sheets**
  - Create `excel/capbook/sheets/command_bar.py` helper + use in every UI sheet
  - Add plan selectors + named ranges: `ActivePlan`, `ComparePlanA/B/C/D`
  - Add policy toggles + named ranges: `RosterFillTarget`, `RosterFillType`, `CountTwoWayInRoster`, `CountTwoWayInTotals`, `ShowExistsOnlyRows`
  - Add input styling (`formats["input"]`), unlock inputs, protect UI sheets
  - Define named ranges for META fields (`MetaValidationStatus`, `MetaRefreshedAt`, `MetaBaseYear`, `MetaAsOfDate`, `MetaDataContractVersion`)

### Phase 3 — TEAM_COCKPIT (alerts + drivers)
- [x] Implement cockpit alert stack + drivers
  - Validation banner referencing `MetaValidationStatus`
  - Alert stack formulas (validation failed, reconcile delta, fill rows on)
  - Quick drivers: top cap hits, top dead money, top holds
  - "Minimum contracts" count + total readout (using `is_min_contract`)

### Phase 4 - ROSTER_GRID (ledger view v1)
- [x] Implement roster ledger view with reconciliation
  - Layout + shared command bar
  - Roster rows (salary book wide table + badges + bucket flags)
  - Cap holds section (bucket = FA) + dead money section (bucket = TERM)
  - Totals + reconciliation block vs `DATA_team_salary_warehouse`
  - `MINIMUM` label semantics + `% of cap` display helper

### Phase 5 - BUDGET_LEDGER (authoritative totals v1)
- [x] Implement budget ledger snapshot + derived totals
  - Snapshot totals from `DATA_team_salary_warehouse`
  - Placeholder plan delta section (zeros for now)
  - Derived totals + delta vs snapshot

### Phase 6 - AUDIT_AND_RECONCILE (minimal explainability)
- [x] Implement audit + reconciliation section
  - Totals from `DATA_team_salary_warehouse`
  - Sums from roster/holds/dead money (salary_book, cap_holds, dead_money warehouses)
  - Visible deltas + conditional formatting (green=OK, red=mismatch)
  - Row counts + counts-vs-exists summary
  - Summary banner with at-a-glance reconciliation status
  - Policy assumptions section showing current toggle values
  - Shared command bar (consistent with other UI sheets)

### Phase 7 - Scenario engine baseline
- [x] Implement PLAN tables + wiring
  - `PLAN_MANAGER` table (Plan ID, name, notes, created_at)
  - `PLAN_JOURNAL` input table with validation for Action Type
  - Wire `ActivePlan` validation list from `PLAN_MANAGER`
  - Plan delta summary in `BUDGET_LEDGER` sourced from `PLAN_JOURNAL`

### Phase 8 - Subsystem sheets (inputs → journal stubs)
- [x] Implement subsystem sheet v1 layouts
  - TRADE_MACHINE lanes A-D (inputs + outgoing/incoming totals)
  - SIGNINGS_AND_EXCEPTIONS input table + delta columns
  - WAIVE_BUYOUT_STRETCH input table + delta columns
  - ASSETS inventory (exceptions + draft picks) filtered by `SelectedTeam`

### Phase 9 - RULES_REFERENCE (memory aids)
- [x] Implement rules reference tables + notes
  - Tax rates table (from `DATA_tax_rates`)
  - Minimum + rookie scale tables (from new datasets)
  - Salary matching tiers table (static)
  - Apron gate / hard-cap trigger notes (static)

### Phase 10 - Docs + integration
- [x] Documentation + workflow integration
  - Update `excel/AGENTS.md` with current CLI usage + dataset list
  - Add Windmill step to build workbook after PCMS refresh (import flow)
