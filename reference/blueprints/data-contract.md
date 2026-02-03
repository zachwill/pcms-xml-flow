# Data Contract (Postgres → Excel)

**Version:** v4-2026-02-01

The stable interface between Postgres (`pcms.*`) and the Excel workbook (`DATA_*` sheets).

---

## Principles

1. **No live DB in Excel** — Workbook is portable/offline. All data embedded at build time.
2. **Pull from warehouses** — Extract from `pcms.*_warehouse` tables, not raw joins.
3. **Amounts in dollars** — Integer dollars. Excel formats for display.
4. **Keys over names** — All joins via stable keys (`player_id`, `team_code`, `salary_year`).
5. **6-year horizon** — `base_year` through `base_year + 5`.
6. **Mirror Postgres column names** — no renames/aliases (e.g. `cap_2025`, not `cap_y0`).
7. **UI-friendly derived columns are allowed** — but must be explicitly labeled with a `ui_` prefix (e.g. `ui_bracket_number`).

---

## Datasets

| Excel Sheet | Excel Table | Postgres Source | Purpose |
|-------------|-------------|-----------------|---------|
| DATA_system_values | tbl_system_values | pcms.league_system_values | Cap/tax/apron thresholds, exception amounts |
| DATA_tax_rates | tbl_tax_rates | pcms.league_tax_rates | Luxury tax brackets |
| DATA_rookie_scale | tbl_rookie_scale | pcms.rookie_scale_amounts | Rookie scale by pick |
| DATA_minimum_scale | tbl_minimum_scale | pcms.league_salary_scales | Min salary by YOS |
| DATA_team_salary_warehouse | tbl_team_salary_warehouse | pcms.team_salary_warehouse | **Authoritative team totals** |
| DATA_salary_book_warehouse | tbl_salary_book_warehouse | pcms.salary_book_warehouse | Wide salary book (UI display) |
| DATA_salary_book_yearly | tbl_salary_book_yearly | pcms.salary_book_yearly | Tall salary book (calculations) |
| DATA_cap_holds_warehouse | tbl_cap_holds_warehouse | pcms.cap_holds_warehouse | Cap holds/rights |
| DATA_dead_money_warehouse | tbl_dead_money_warehouse | pcms.dead_money_warehouse | Dead money |
| DATA_exceptions_warehouse | tbl_exceptions_warehouse | pcms.exceptions_warehouse | Exception inventory |
| DATA_draft_picks_warehouse | tbl_draft_picks_warehouse | pcms.draft_picks_warehouse | Draft pick ownership |

---

## Key datasets

### tbl_team_salary_warehouse (authoritative)

**Source:** `pcms.team_salary_warehouse`

The authoritative totals. UI totals must match or reconcile to this.

**Key columns:**
- `team_code`, `salary_year`
- `cap_total`, `tax_total`, `apron_total`
- `salary_cap_amount`, `tax_level_amount`, `tax_apron_amount`, `tax_apron2_amount`
- `is_taxpayer`, `is_repeater_taxpayer`, `apron_level_lk`
- `roster_row_count`, `two_way_row_count`

### tbl_salary_book_warehouse (wide)

**Source:** `pcms.salary_book_warehouse`

Player roster with multi-year salaries in explicit year columns.

This sheet/table is intentionally a near 1:1 mirror of Postgres:
- No renamed columns (no `cap_y0`, etc)
- Year columns stay as `cap_2025`, `cap_2026`, … (whatever exists in the warehouse)

**Key columns (examples):**
- `player_id`, `player_name`, `team_code`
- `cap_2025..cap_2030`, `tax_2025..tax_2030`, `apron_2025..apron_2030`
- `is_two_way`

For year-aware calculations in the UI, prefer the tall table: `tbl_salary_book_yearly`.

### tbl_system_values

**Source:** `pcms.league_system_values`

CBA thresholds and constants.

**Key columns:**
- `salary_year`
- `salary_cap_amount`, `tax_level_amount`, `tax_apron_amount`, `tax_apron2_amount`
- Exception amounts: `non_taxpayer_mid_level_amount`, `taxpayer_mid_level_amount`, etc.
- Season calendar (proration): `days_in_season`, `playing_start_at`, `playing_end_at` (plus league-year bounds `season_start_at`, `season_end_at`)

---

## Build process

```bash
uv run excel/export_capbook.py \
  --out shared/capbook.xlsx \
  --base-year 2025 \
  --as-of today
```

1. Run SQL assertions (unless `--skip-assertions`)
2. Extract datasets from Postgres
3. Generate workbook with XlsxWriter
4. Write META sheet (timestamp, base_year, as_of, git SHA, validation status)

---

## META sheet

Every workbook includes build metadata:

- `refreshed_at` — Build timestamp
- `base_year` — Starting year (e.g., 2025)
- `as_of_date` — Snapshot date
- `exporter_git_sha` — Exporter commit hash
- `validation_status` — PASS or FAILED
- `data_contract_version` — This contract version

---

## Reconciliation

**Rule:** UI totals must reconcile to `tbl_team_salary_warehouse`.

If there's a mismatch, `META.validation_status = FAILED` and the delta is recorded.

---

## Change management

- **Additive columns:** OK (workbook ignores unused)
- **Renames/removals:** Requires contract update + workbook generator update

Extractors live in `excel/capbook/extract.py`.

**Current contract version:** see `excel/capbook/build.py` (`DATA_CONTRACT_VERSION`).
