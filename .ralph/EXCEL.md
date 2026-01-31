# Excel Cap Workbook — Backlog

Build a new, self-contained, Sean-style Excel cap workbook **generated from code** (Python + XlsxWriter) and powered by Postgres (`pcms.*`).

**Canon:** `reference/blueprints/README.md` (start there)

This backlog is intentionally concrete. The Excel agent should do **one task per iteration**, commit, and exit.

## Rules

- The workbook is a **build artifact**. Prefer deterministic code-gen over manual Excel editing.
- Prefer **single-file** workbook output (portable/offline). No external workbook links.
- Prefer **warehouse-backed** extracts (`pcms.*_warehouse`, `pcms.salary_book_yearly`).
- Use `shared/` for generated artifacts (gitignored).
- All money amounts are **dollars (int)** unless explicitly documented.
- Record `META` fields so every workbook snapshot is reproducible.
- When implementing **Excel UI formatting** (labels, colors, badges), reuse existing conventions from `web/src/features/SalaryBook/`.
  - Examples: `MINIMUM` label for min contracts, `% of cap` display, option/guarantee/restriction colors.

## Tasks

- [x] Create Python module skeleton under `excel/capbook/` (multiple files; keep it small):
  - `excel/capbook/db.py` — connect + query helpers + run assertions
  - `excel/capbook/extract.py` — dataset extract functions per data contract
  - `excel/capbook/xlsx.py` — XlsxWriter helpers (formats, tables, named ranges)
  - `excel/capbook/build.py` — orchestrate workbook build (calls extract + sheet writers)

- [ ] Create `excel/export_capbook.py` entrypoint (PEP-723 style like other scripts) that:
  - depends on `xlsxwriter` + `psycopg[binary]`
  - accepts `--out`, `--base-year`, `--as-of` (and optional `--league` default NBA)
  - calls `capbook.build.build_capbook(...)`

- [ ] Implement helper: `get_git_sha()` (used by workbook `META`)

- [ ] Implement `META` sheet writer:
  - fields: refreshed_at, base_year, as_of_date, exporter_git_sha, validation_status
  - add a visible “FAILED” banner cell if validations fail

- [ ] Implement workbook skeleton creation (code, not a template):
  - Create UI sheets (empty stubs to start): `HOME`, `TEAM_COCKPIT`, `ROSTER_GRID`, `BUDGET_LEDGER`, `PLAN_MANAGER`, `PLAN_JOURNAL`, `TRADE_MACHINE`, `SIGNINGS_AND_EXCEPTIONS`, `WAIVE_BUYOUT_STRETCH`, `ASSETS`, `AUDIT_AND_RECONCILE`, `RULES_REFERENCE`
  - Create data sheets: `DATA_system_values`, `DATA_tax_rates`, `DATA_team_salary_warehouse`, `DATA_salary_book_warehouse`, `DATA_salary_book_yearly`, `DATA_cap_holds_warehouse`, `DATA_dead_money_warehouse`, `DATA_exceptions_warehouse`, `DATA_draft_picks_warehouse`
  - Hide `DATA_*` sheets

- [ ] Add XlsxWriter helper to write an Excel Table with a stable name:
  - Example: `write_table(worksheet, table_name, start_row, start_col, columns, rows)`
  - Always set explicit headers and a deterministic table range

- [ ] Audit existing UI conventions in `web/src/features/SalaryBook/` and codify them as Excel format constants in `excel/capbook/xlsx.py`:
  - `MINIMUM` display for min contracts (`PlayerRow.tsx`)
  - `% of cap` formatting conventions (`playerRowHelpers.ts`)
  - option/guarantee/consent/restriction color semantics (`badges/*`, `TradeRestrictions.tsx`)

- [ ] Implement dataset extract: `tbl_system_values` → `DATA_system_values`

- [ ] Implement dataset extract: `tbl_tax_rates` → `DATA_tax_rates`

- [ ] Implement dataset extract: `tbl_team_salary_warehouse` → `DATA_team_salary_warehouse` (base_year..base_year+5)

- [ ] Implement dataset extract: `tbl_salary_book_warehouse` → `DATA_salary_book_warehouse`
  - Export **relative-year columns** (cap_y0..cap_y5, tax_y0..tax_y5, apron_y0..apron_y5) based on `--base-year`

- [ ] Implement dataset extract: `tbl_salary_book_yearly` → `DATA_salary_book_yearly` (base_year..base_year+5)

- [ ] Implement dataset extract: `tbl_cap_holds_warehouse` → `DATA_cap_holds_warehouse`

- [ ] Implement dataset extract: `tbl_dead_money_warehouse` → `DATA_dead_money_warehouse`

- [ ] Implement dataset extract: `tbl_exceptions_warehouse` → `DATA_exceptions_warehouse`

- [ ] Implement dataset extract: `tbl_draft_picks_warehouse` → `DATA_draft_picks_warehouse`

- [ ] Add build step: run SQL assertions (`queries/sql/run_all.sql`) before writing workbook.
  - If assertions fail: set `META.validation_status = FAILED` and include error message(s)

- [ ] Add build step: lightweight reconciliation summary written to `META` (even if partial v1)
  - Example: for a sample team/year confirm `cap_total = cap_rost + cap_fa + cap_term + cap_2way`

- [ ] Implement workbook-defined names for cockpit command bar inputs:
  - `SelectedTeam`, `SelectedYear`, `AsOfDate`, `SelectedMode`
  - Place them in `TEAM_COCKPIT` and define names via `workbook.define_name(...)`

- [ ] Add data validation dropdown for `SelectedTeam` based on distinct `team_code` values

- [ ] Implement minimal `TEAM_COCKPIT` readouts driven from `DATA_team_salary_warehouse`:
  - cap position, tax position, room under apron 1/2, roster count, repeater flag
  - keep it formula-light; correctness + reconciliation beats polish

- [ ] Implement minimal `AUDIT_AND_RECONCILE` section:
  - show selected team/year totals from `DATA_team_salary_warehouse`
  - show row counts + basic sums from drilldown tables
  - show a visible delta (even if it’s not 0 yet)

- [ ] Document local usage in `excel/AGENTS.md` once CLI stabilizes
