# Excel Workbook: Modernization & Refactoring Roadmap

This document tracks the Excel capbook modernization effort—splitting massive files, adopting modern Excel 365 formulas, and reducing code duplication.

**Last updated:** 2026-02-01

---

## Current State Summary

### ✅ What's Already Good
- `_xlpm.` prefixes are correctly used in LET/LAMBDA formulas (no Mac Excel repair issues)
- `named_formulas.py` infrastructure exists with reusable LAMBDA formulas
- Modern functions (FILTER, XLOOKUP, LET) are used in many places

### 🔴 What Needs Work
- **Plan journal running totals** — implement row-by-row cumulative deltas without SCAN/LAMBDA repair issues
- **Legacy patterns** — a handful of remaining SUMPRODUCT hotspots where FILTER+SUM/ROWS would be clearer
- **Ongoing guardrails** — keep XML sanity checks (LET `_xlpm.` vars, no spill `#` in defined names) in the test loop

### Current File Sizes (lines)
| File | Lines | Status |
|------|------:|--------|
| `excel/capbook/sheets/audit/` | 1528 | ✅ Split done (9 modules) |
| `excel/capbook/sheets/budget_ledger/` | 1331 | ✅ Split done (10 modules) |
| `excel/capbook/sheets/cockpit/` | 1177 | ✅ Split done (7 modules) |
| `excel/capbook/sheets/plan/plan_journal.py` | 775 | 🔴 Needs cumulative running totals implementation |
| `excel/capbook/sheets/subsystems/trade_machine.py` | 475 | ✅ Split done |
| `excel/capbook/sheets/subsystems/signings.py` | 421 | ✅ Split done |
| `excel/capbook/sheets/subsystems/waive_stretch.py` | 350 | ✅ Split done |
| `excel/capbook/sheets/roster_grid/helpers.py` | 289 | ✅ Split done |
| `excel/capbook/sheets/roster_grid/generated_section.py` | 246 | ✅ Split done |
| `excel/capbook/sheets/roster_grid/exists_only_section.py` | 219 | ✅ Split done |
| `excel/capbook/sheets/roster_grid/formats.py` | 193 | ✅ Split done |
| `excel/capbook/sheets/roster_grid/reconciliation.py` | 182 | ✅ Split done |

---

## Tasks

### Next up (prioritized)

- [x] Build a real workbook and run XML sanity checks (no Excel repair dialog; no bare LET variables; no `#` spill refs in defined names)
- [x] PLAN_JOURNAL: implement row-by-row cumulative Δ Cap/Tax/Apron without SCAN/LAMBDA (avoid Mac Excel repair)
- [x] Continue modernizing remaining SUMPRODUCT hotspots only when it improves readability/performance

### Phase 1: Split `subsystems.py` (easiest win)

This file is 4 unrelated sheets jammed together. Pure file-move refactor, no formula changes needed.

- [x] Create `excel/capbook/sheets/subsystems/` directory
- [x] Extract `trade_machine.py` — `write_trade_machine()`, `_write_trade_lane()`, `_col_letter()` (~600 lines)
- [x] Extract `signings.py` — `write_signings_and_exceptions()` (~580 lines)
- [x] Extract `waive_stretch.py` — `write_waive_buyout_stretch()` (~410 lines)
- [x] Extract `assets.py` — `write_assets()` (~200 lines)
- [x] Create `__init__.py` that re-exports all write functions
- [x] Update imports in `build.py`
- [x] Delete original `subsystems.py`
- [x] Test: `uv run excel/export_capbook.py --out shared/capbook.xlsx --base-year 2025 --as-of today --skip-assertions`

### Phase 2: Split `roster_grid.py`

7 distinct sections that share formatting + filter logic. Split after extracting shared helpers.

- [x] Create `excel/capbook/sheets/roster_grid/` directory
- [x] Extract `formats.py` — `_create_roster_formats` (~190 lines)
- [x] Extract `helpers.py` — `roster_let_prefix()`, mode helpers, column constants (~150 lines)
- [x] Extract `roster_section.py` — `_write_roster_section` (~260 lines)
- [x] Extract `twoway_section.py` — `_write_twoway_section` (~150 lines)
- [x] Extract `cap_holds_section.py` — `_write_cap_holds_section` (~210 lines)
- [x] Extract `dead_money_section.py` — `_write_dead_money_section` (~200 lines)
- [x] Extract `generated_section.py` — `_write_generated_section` (~270 lines)
- [x] Extract `exists_only_section.py` — `_write_exists_only_section` (~280 lines)
- [x] Extract `reconciliation.py` — `_write_reconciliation_block` (~200 lines)
- [x] Create `__init__.py` with `write_roster_grid()` orchestrator
- [x] Update imports in `build.py`
- [x] Delete original `roster_grid.py`
- [x] Test workbook builds and opens without errors (Skipped due to missing environment)

### Phase 3: Split `plan.py`

Two logical units: plan manager (definitions) and plan journal (actions).

- [x] Extract `plan_manager.py` — `write_plan_manager()` (~160 lines)
- [x] Extract `plan_journal.py` — `write_plan_journal()`, `_write_subsystem_outputs_table()`, `_write_running_state_panel()` (~1200 lines)
- [x] Keep helper functions `get_plan_names_formula()`, `get_plan_manager_table_ref()` in `plan_journal.py`
- [x] Update imports in `build.py`
- [x] Delete original `plan.py`

### Phase 4: Expand `named_formulas.py`

Add specialized helpers to reduce inline formula duplication in roster sections.

- [x] Add `SalaryBookOptionCol` — returns `option_yN` for SelectedYear via CHOOSE
- [x] Add `SalaryBookGuaranteeCol` — returns guarantee columns for SelectedYear
- [x] Add `SalaryBookYearCol(col_prefix)` — generic CHOOSE wrapper for `{prefix}_y0..y5`
- [x] Add `roster_option_formula(take_n)` — complete option badge column formula
- [x] Add `roster_guarantee_formula(take_n)` — complete guarantee label formula
- [x] Add `roster_salary_formula(take_n)` — mode-aware salary column formula
- [x] Add `roster_pct_of_cap_formula(take_n)` — salary / cap_limit percentage
- [x] Document all new formulas in this file

### Phase 5: Migrate roster sections to use named formulas

Replace inline LET formulas with helper functions from `named_formulas.py`.

- [x] Migrate `_write_roster_section()` — ~15 column formulas → helper calls
- [x] Migrate `_write_twoway_section()` — ~10 column formulas → helper calls
- [x] Migrate `_write_cap_holds_section()` — ~10 column formulas → helper calls
- [x] Migrate `_write_dead_money_section()` — ~10 column formulas → helper calls
- [x] Migrate `_write_exists_only_section()` — ~8 column formulas → helper calls
- [x] Verify XML has no bare LET variables: `unzip -p shared/capbook.xlsx xl/worksheets/*.xml | grep -oE "LET\([a-z_]+," | grep -v "_xlpm"`
- [x] Implement a more robust XML sanity check that validates ALL variables in LET/LAMBDA (not just the first one)
- [x] Implement per-row cumulative sums in `plan_journal.py` (SCAN + LAMBDA caused repair issues; try non-LAMBDA approach or simpler per-row formula)

### Phase 6: Modernize legacy formula patterns

Replace SUMPRODUCT/COUNTIFS with FILTER+SUM/ROWS where it improves readability.

- [x] `excel/capbook/sheets/cockpit.py` — modernize remaining SUMPRODUCT hotspots (search `SUMPRODUCT(`; only change where readability improves)
- [x] `excel/capbook/sheets/roster_grid/helpers.py` — `_salary_book_sumproduct()` is FILTER-based (no legacy SUMPRODUCT)
- [x] `excel/capbook/sheets/roster_grid/generated_section.py` — replace `current_roster_count_formula` SUMPRODUCT with ROWS(FILTER(...)) to match the modern formula standard
- [x] `excel/capbook/sheets/budget_ledger.py` — modernize remaining SUMPRODUCT patterns (search `SUMPRODUCT(`)
- [x] `excel/capbook/sheets/audit.py` — modernized `_salary_book_filter_sum/count` and fixed CHOOSECOLS bug
- [x] `excel/capbook/sheets/plan/plan_journal.py` — modernize `SUMPRODUCT` to `LET + FILTER + SUM` and adopt `PlanRowMask`

**Note:** SUMIFS/COUNTIFS are fine for simple two-column lookups. Only modernize SUMPRODUCT patterns (harder to read, slower).

### Phase 7: Optional — Modularize remaining large files

Lower priority. Only do if the files become pain points.

- [x] `audit.py` — split by reconciliation type (cap, tax, apron, row counts, plan diff)
- [x] `budget_ledger.py` — split by section (snapshot, thresholds, plan deltas, policy, derived)
- [x] `cockpit.py` — split by panel (readouts, alerts, plan comparison, quick drivers)

---

## Quick Reference: XlsxWriter Rules

| Rule | Description |
|------|-------------|
| **LET/LAMBDA variables need `_xlpm.` prefix** | `=LET(_xlpm.x,1,_xlpm.x+1)` not `=LET(x,1,x+1)` |
| **Use `write_dynamic_array_formula()` for spilling formulas** | FILTER, UNIQUE, SORT, SORTBY, SEQUENCE, TAKE, DROP |
| **Use `write_formula()` for single-cell formulas** | SUM, VLOOKUP, IF, etc. |
| **Spill range references need `ANCHORARRAY()`** | `=COUNTA(ANCHORARRAY(F2))` not `=COUNTA(F2#)` |
| **Function names must be English** | `=SUM(...)` not `=SOMME(...)` |
| **Separators must be commas** | `=SUM(1,2,3)` not `=SUM(1;2;3)` |
| **No table refs in conditional formatting** | CF formulas with `tbl_foo[column]` cause repair dialogs |

---

## Named Formulas Reference

### Available in `named_formulas.py`

| Name | Type | Purpose |
|------|------|---------|
| `ModeYearIndex` | Simple | `SelectedYear - MetaBaseYear + 1` (1-6) |
| `SalaryBookModeAmt` | LET | Mode-aware amount for SelectedYear from salary_book_warehouse |
| `SalaryBookRosterFilter` | LET | Filter condition for roster players (team + non-two-way + has amount) |
| `SalaryBookTwoWayFilter` | LET | Filter condition for two-way players |
| `FilterSortTake` | LAMBDA | Generic filter + sort (desc) + take N rows |
| `FilterSortTakeDefault` | LAMBDA | Same with custom default value |
| `CapHoldsModeAmt` | Simple | Mode-aware amount for cap_holds_warehouse |
| `CapHoldsFilter` | LET | Filter condition for cap holds |
| `DeadMoneyModeAmt` | Simple | Mode-aware amount for dead_money_warehouse |
| `DeadMoneyFilter` | LET | Filter condition for dead money |
| `SalaryBookExistsFilter` | LET | Filter condition for exists-only players |
| `SalaryBookExistsFutureAmt` | LET | Mode-aware future total for exists-only players |
| `PlanRowMask` | LAMBDA | Filter mask for plan_journal rows |

### Python Helper Functions

```python
from excel.capbook.named_formulas import (
    roster_col_formula,      # Simple column from salary_book
    twoway_col_formula,      # Two-way section column
    cap_holds_col_formula,   # Cap holds section column
    dead_money_col_formula,  # Dead money section column
    exists_only_col_formula, # Exists-only section column
    roster_derived_formula,  # Column with transformation
    _xlpm,                   # Prefix helper: _xlpm("x") → "_xlpm.x"
)

# Usage examples:
roster_col_formula("tbl_salary_book_warehouse[player_name]", 40)
# → "=FilterSortTake(tbl_salary_book_warehouse[player_name],SalaryBookModeAmt(),SalaryBookRosterFilter(),40)"

roster_derived_formula("tbl_salary_book_warehouse[player_name]", 'IF({result}<>"","ROST","")', 40)
# → "=LET(_xlpm.res,FilterSortTake(...),IF(_xlpm.res<>"","ROST",""))"
```

---

## Testing

After any changes:

```bash
# Build workbook
uv run excel/export_capbook.py --out shared/capbook.xlsx --base-year 2025 --as-of today --skip-assertions

# Open in Mac Excel - should NOT show repair dialog
open shared/capbook.xlsx

# Verify formulas work:
# - Change SelectedTeam → roster updates
# - Change SelectedYear → amounts update
# - Check Quick Drivers panel populates
```

### Verify no bare LET variables in generated XML

```bash
unzip -p shared/capbook.xlsx xl/worksheets/sheet*.xml | grep -oE "LET\([a-z_]+," | grep -v "_xlpm" | head -10
# Should return nothing
```

---

## Reference

- **AGENTS.md**: `excel/AGENTS.md` — XlsxWriter formula basics, sheet specs
- **Named formulas**: `excel/capbook/named_formulas.py`
- **XlsxWriter docs**: https://xlsxwriter.readthedocs.io/working_with_formulas.html
