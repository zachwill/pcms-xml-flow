"""
Named Formulas (LAMBDA/LET helpers) for the Excel Cap Workbook.

This module defines reusable named formulas that centralize repeated logic.

**Excel 365/2021 Required:** These formulas use LAMBDA which requires Excel 365
or Excel 2021. Earlier versions will show #NAME? errors.

**CRITICAL:** All LAMBDA parameter names and LET variable names MUST use the
`_xlpm.` prefix or Mac Excel will show repair dialogs.

Named formulas defined here:

1. ModeYearIndex (simple)
   - Returns the 1-based relative year index: SelectedYear - MetaBaseYear + 1
   - Values: 1 (base year) through 6 (base year + 5)

2. SalaryBookModeAmt (LAMBDA)
   - Computes mode-aware amount for SelectedYear from salary_book_warehouse
   - Returns: cap/tax/apron amount based on SelectedMode + SelectedYear

3. SalaryBookOptionCol (LAMBDA)
   - Returns the option_yN column for SelectedYear

4. SalaryBookGuaranteeCol (LAMBDA)
   - Returns the guaranteed_amount_yN column for SelectedYear

5. SalaryBookGuaranteeLabel (LAMBDA)
   - Returns GTD/PRT/NG label for SelectedYear

6. SalaryBookRosterFilter (LAMBDA)
   - Filters salary_book_warehouse for roster players (non-two-way)
   - Returns: filter condition array for use with FILTER()

7. SalaryBookTwoWayFilter (LAMBDA)
   - Filters salary_book_warehouse for two-way players
   - Returns: filter condition array

8. FilterSortTake (LAMBDA)
   - Generic: filters a column, sorts by another, takes N rows
   - The workhorse for all spilling roster columns

9. CapHoldsModeAmt (LAMBDA)
   - Mode-aware amount for cap_holds_warehouse

10. DeadMoneyModeAmt (LAMBDA)
   - Mode-aware amount for dead_money_warehouse

11. PlanRowMask (LAMBDA)
   - Filter mask for plan_journal rows

Usage in roster_grid.py:
    # Before (repeated 40+ times):
    \"=LET(cap_col,CHOOSE(...),tax_col,CHOOSE(...),mode_amt,IF(...),filter_cond,...,
          filtered,FILTER(col,filter_cond),sorted,FILTER(mode_amt,filter_cond),
          TAKE(SORTBY(filtered,sorted,-1),40))\"
    
    # After (single call):
    \"=FilterSortTake(tbl_salary_book_warehouse[player_name],
                     SalaryBookModeAmt(),
                     SalaryBookRosterFilter(),
                     40)\"

Design notes:
- All LAMBDA params use `_xlpm.` prefix (required for Mac Excel compatibility)
- All LET variables use `_xlpm.` prefix
- Formulas reference global named ranges (SelectedYear, SelectedMode, etc.)
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook


# =============================================================================
# Named Formula Definitions
# =============================================================================

# Simple named formulas (single expressions, no parameters)
SIMPLE_NAMED_FORMULAS: dict[str, str] = {
    # ModeYearIndex: 1-based year offset (1..6)
    # Use: CHOOSE(ModeYearIndex, cap_y0, cap_y1, ...)
    "ModeYearIndex": "=SelectedYear-MetaBaseYear+1",
}


# -----------------------------------------------------------------------------
# LAMBDA helper: prefix all variable names with _xlpm.
# -----------------------------------------------------------------------------
def _xlpm(var: str) -> str:
    """Prefix a variable name with _xlpm. for LET/LAMBDA formulas."""
    return f"_xlpm.{var}"


# Shorthand for common variable names
_CAP_COL = _xlpm("cap_col")
_TAX_COL = _xlpm("tax_col")
_APRON_COL = _xlpm("apron_col")
_MODE_AMT = _xlpm("mode_amt")
_FILTER_COND = _xlpm("filter_cond")
_FILTERED = _xlpm("filtered")
_SORTED = _xlpm("sorted")
_RESULT = _xlpm("result")
_COL = _xlpm("col")
_SORT_COL = _xlpm("sort_col")
_COND = _xlpm("cond")
_N = _xlpm("n")
_DEFAULT = _xlpm("default")


# -----------------------------------------------------------------------------
# Build LAMBDA formulas with proper _xlpm. prefixes
# -----------------------------------------------------------------------------

def _build_salary_book_mode_amt() -> str:
    """
    SalaryBookModeAmt: returns mode-aware amount for SelectedYear.
    
    No parameters - operates on tbl_salary_book_warehouse columns directly.
    Returns an array (one value per row in the table).
    
    Logic:
      cap_col = CHOOSE(ModeYearIndex, cap_y0, cap_y1, ..., cap_y5)
      tax_col = CHOOSE(ModeYearIndex, tax_y0, tax_y1, ..., tax_y5)
      apron_col = CHOOSE(ModeYearIndex, apron_y0, apron_y1, ..., apron_y5)
      mode_amt = IF(SelectedMode="Cap", cap_col, IF(SelectedMode="Tax", tax_col, apron_col))
    """
    cap_cols = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
    tax_cols = ",".join(f"tbl_salary_book_warehouse[tax_y{i}]" for i in range(6))
    apron_cols = ",".join(f"tbl_salary_book_warehouse[apron_y{i}]" for i in range(6))
    
    return (
        "=LET("
        f"{_CAP_COL},CHOOSE(ModeYearIndex,{cap_cols}),"
        f"{_TAX_COL},CHOOSE(ModeYearIndex,{tax_cols}),"
        f"{_APRON_COL},CHOOSE(ModeYearIndex,{apron_cols}),"
        f'IF(SelectedMode="Cap",{_CAP_COL},IF(SelectedMode="Tax",{_TAX_COL},{_APRON_COL})))'
    )


def _build_salary_book_roster_filter() -> str:
    """
    SalaryBookRosterFilter: returns filter condition for roster players.
    
    No parameters - uses SalaryBookModeAmt internally.
    Returns: (team_code=SelectedTeam) * (is_two_way=FALSE) * (mode_amt>0)
    """
    return (
        "=LET("
        f"{_MODE_AMT},SalaryBookModeAmt(),"
        f"(tbl_salary_book_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_salary_book_warehouse[is_two_way]=FALSE)*"
        f"({_MODE_AMT}>0))"
    )


def _build_salary_book_twoway_filter() -> str:
    """
    SalaryBookTwoWayFilter: returns filter condition for two-way players.
    
    Same as roster but is_two_way=TRUE.
    """
    return (
        "=LET("
        f"{_MODE_AMT},SalaryBookModeAmt(),"
        f"(tbl_salary_book_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_salary_book_warehouse[is_two_way]=TRUE)*"
        f"({_MODE_AMT}>0))"
    )


def _build_filter_sort_take() -> str:
    """
    FilterSortTake: generic FILTER + SORTBY (desc) + TAKE.
    
    Parameters:
      col: column to filter and return
      sort_col: column to sort by (descending)
      cond: filter condition (boolean array)
      n: number of rows to take
    
    Returns: IFNA(TAKE(SORTBY(FILTER(col, cond), FILTER(sort_col, cond), -1), n), "")
    """
    return (
        f"=LAMBDA({_COL},{_SORT_COL},{_COND},{_N},"
        f"LET("
        f"{_FILTERED},FILTER({_COL},{_COND},\"\"),"
        f"{_SORTED},FILTER({_SORT_COL},{_COND},0),"
        f"IFNA(TAKE(SORTBY({_FILTERED},{_SORTED},-1),{_N}),\"\")))"
    )


def _build_filter_sort_take_with_default() -> str:
    """
    FilterSortTakeDefault: same as FilterSortTake but with custom default.
    
    Parameters:
      col, sort_col, cond, n: same as FilterSortTake
      default: value to use for empty/short results
    """
    return (
        f"=LAMBDA({_COL},{_SORT_COL},{_COND},{_N},{_DEFAULT},"
        f"LET("
        f"{_FILTERED},FILTER({_COL},{_COND},{_DEFAULT}),"
        f"{_SORTED},FILTER({_SORT_COL},{_COND},0),"
        f"IFNA(TAKE(SORTBY({_FILTERED},{_SORTED},-1),{_N}),{_DEFAULT})))"
    )


def _build_cap_holds_mode_amt() -> str:
    """
    CapHoldsModeAmt: mode-aware amount for cap_holds_warehouse.
    
    Simpler than salary_book - just one column per mode (no yearly variants).
    """
    return (
        '=IF(SelectedMode="Cap",tbl_cap_holds_warehouse[cap_amount],'
        'IF(SelectedMode="Tax",tbl_cap_holds_warehouse[tax_amount],'
        'tbl_cap_holds_warehouse[apron_amount]))'
    )


def _build_cap_holds_filter() -> str:
    """
    CapHoldsFilter: filter condition for cap holds.
    
    Returns: (team_code=SelectedTeam) * (salary_year=SelectedYear) * (mode_amt>0)
    """
    return (
        "=LET("
        f"{_MODE_AMT},CapHoldsModeAmt(),"
        f"(tbl_cap_holds_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_cap_holds_warehouse[salary_year]=SelectedYear)*"
        f"({_MODE_AMT}>0))"
    )


def _build_dead_money_mode_amt() -> str:
    """
    DeadMoneyModeAmt: mode-aware amount for dead_money_warehouse.
    """
    return (
        '=IF(SelectedMode="Cap",tbl_dead_money_warehouse[cap_value],'
        'IF(SelectedMode="Tax",tbl_dead_money_warehouse[tax_value],'
        'tbl_dead_money_warehouse[apron_value]))'
    )


def _build_dead_money_filter() -> str:
    """
    DeadMoneyFilter: filter condition for dead money.
    """
    return (
        "=LET("
        f"{_MODE_AMT},DeadMoneyModeAmt(),"
        f"(tbl_dead_money_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_dead_money_warehouse[salary_year]=SelectedYear)*"
        f"({_MODE_AMT}>0))"
    )


def _build_plan_row_mask() -> str:
    """
    PlanRowMask: filter mask for plan_journal rows.
    
    Parameters:
      plan_id_col: plan_id column
      salary_year_col: salary_year column  
      enabled_col: enabled column
    
    Returns: TRUE for rows matching ActivePlanId + SelectedYear + enabled="Yes"
    Handles blank plan_id (matches all plans) and blank salary_year (matches all years).
    """
    _PID = _xlpm("pid")
    _SY = _xlpm("sy")
    _EN = _xlpm("en")
    
    return (
        f"=LAMBDA({_PID},{_SY},{_EN},"
        f'(({_PID}=ActivePlanId)+({_PID}=""))*'
        f'(({_SY}=SelectedYear)+({_SY}=""))*'
        f'({_EN}="Yes"))'
    )


def _build_salary_book_option_col() -> str:
    """
    SalaryBookOptionCol: returns the option_yN column for SelectedYear.
    """
    option_cols = ",".join(f"tbl_salary_book_warehouse[option_y{i}]" for i in range(6))
    return f"=CHOOSE(ModeYearIndex,{option_cols})"


def _build_salary_book_guarantee_label() -> str:
    """
    SalaryBookGuaranteeLabel: returns GTD/PRT/NG label for SelectedYear.
    """
    gtd_full_cols = ",".join(f"tbl_salary_book_warehouse[is_fully_guaranteed_y{i}]" for i in range(6))
    gtd_part_cols = ",".join(f"tbl_salary_book_warehouse[is_partially_guaranteed_y{i}]" for i in range(6))
    gtd_non_cols = ",".join(f"tbl_salary_book_warehouse[is_non_guaranteed_y{i}]" for i in range(6))
    
    _GTD_FULL = _xlpm("gtd_full")
    _GTD_PART = _xlpm("gtd_part")
    _GTD_NON = _xlpm("gtd_non")
    
    return (
        "=LET("
        f"{_GTD_FULL},CHOOSE(ModeYearIndex,{gtd_full_cols}),"
        f"{_GTD_PART},CHOOSE(ModeYearIndex,{gtd_part_cols}),"
        f"{_GTD_NON},CHOOSE(ModeYearIndex,{gtd_non_cols}),"
        f'IF({_GTD_FULL}=TRUE,"GTD",IF({_GTD_PART}=TRUE,"PRT",IF({_GTD_NON}=TRUE,"NG",""))))'
    )


def _build_salary_book_guarantee_col() -> str:
    """
    SalaryBookGuaranteeCol: returns the guaranteed_amount_yN column for SelectedYear.
    """
    amt_cols = ",".join(f"tbl_salary_book_warehouse[guaranteed_amount_y{i}]" for i in range(6))
    return f"=CHOOSE(ModeYearIndex,{amt_cols})"


# LAMBDA named formulas: (formula_builder, description)
# Using builders so we can construct with proper _xlpm. prefixes
LAMBDA_NAMED_FORMULAS: dict[str, tuple[str, str]] = {
    "SalaryBookModeAmt": (
        _build_salary_book_mode_amt(),
        "Mode-aware amount for SelectedYear from salary_book_warehouse (array)",
    ),
    "SalaryBookOptionCol": (
        _build_salary_book_option_col(),
        "Option column for SelectedYear from salary_book_warehouse",
    ),
    "SalaryBookGuaranteeCol": (
        _build_salary_book_guarantee_col(),
        "Guaranteed amount column for SelectedYear from salary_book_warehouse",
    ),
    "SalaryBookGuaranteeLabel": (
        _build_salary_book_guarantee_label(),
        "Guarantee label (GTD/PRT/NG) for SelectedYear",
    ),
    "SalaryBookRosterFilter": (
        _build_salary_book_roster_filter(),
        "Filter condition for roster players (non-two-way, has amount)",
    ),
    "SalaryBookTwoWayFilter": (
        _build_salary_book_twoway_filter(),
        "Filter condition for two-way players",
    ),
    "FilterSortTake": (
        _build_filter_sort_take(),
        "Generic: FILTER col by cond, SORTBY sort_col desc, TAKE n rows",
    ),
    "FilterSortTakeDefault": (
        _build_filter_sort_take_with_default(),
        "Same as FilterSortTake but with custom default value",
    ),
    "CapHoldsModeAmt": (
        _build_cap_holds_mode_amt(),
        "Mode-aware amount for cap_holds_warehouse",
    ),
    "CapHoldsFilter": (
        _build_cap_holds_filter(),
        "Filter condition for cap holds (team + year + has amount)",
    ),
    "DeadMoneyModeAmt": (
        _build_dead_money_mode_amt(),
        "Mode-aware amount for dead_money_warehouse",
    ),
    "DeadMoneyFilter": (
        _build_dead_money_filter(),
        "Filter condition for dead money (team + year + has amount)",
    ),
    "PlanRowMask": (
        _build_plan_row_mask(),
        "Filter mask for plan_journal rows (ActivePlanId + SelectedYear + enabled)",
    ),
}


def define_named_formulas(workbook: Workbook) -> dict[str, str]:
    """
    Define all named formulas in the workbook.
    
    These are workbook-scoped named ranges that contain formulas (not cell refs).
    They enable formula reuse and make complex formulas more readable.
    
    Call this early in the build process, after META named ranges are defined
    but before UI sheets are written.
    
    Args:
        workbook: The XlsxWriter Workbook
        
    Returns:
        dict mapping formula name -> formula expression (for reference/logging)
    """
    defined: dict[str, str] = {}
    
    # Define simple named formulas
    for name, formula in SIMPLE_NAMED_FORMULAS.items():
        workbook.define_name(name, formula)
        defined[name] = formula
    
    # Define LAMBDA-based named formulas
    for name, (formula, _description) in LAMBDA_NAMED_FORMULAS.items():
        workbook.define_name(name, formula)
        defined[name] = formula
    
    return defined


def get_formula_documentation() -> list[dict[str, Any]]:
    """
    Return documentation for all named formulas.
    
    This can be used to populate a reference section or documentation sheet.
    
    Returns:
        List of dicts with keys: name, formula, description, type
    """
    docs: list[dict[str, Any]] = []
    
    for name, formula in SIMPLE_NAMED_FORMULAS.items():
        docs.append({
            "name": name,
            "formula": formula,
            "description": "Simple expression (no parameters)",
            "type": "simple",
        })
    
    for name, (formula, description) in LAMBDA_NAMED_FORMULAS.items():
        docs.append({
            "name": name,
            "formula": formula,
            "description": description,
            "type": "lambda",
        })
    
    return docs


# =============================================================================
# Formula Usage Helpers (for use in sheet code)
# =============================================================================

def roster_col_formula(column: str, take_n: int = 40) -> str:
    """
    Return formula for a roster column using named formulas.
    
    Example:
        roster_col_formula("tbl_salary_book_warehouse[player_name]")
        -> "=FilterSortTake(tbl_salary_book_warehouse[player_name],SalaryBookModeAmt(),SalaryBookRosterFilter(),40)"
    """
    return f"=FilterSortTake({column},SalaryBookModeAmt(),SalaryBookRosterFilter(),{take_n})"


def twoway_col_formula(column: str, take_n: int = 10) -> str:
    """Return formula for a two-way column."""
    return f"=FilterSortTake({column},SalaryBookModeAmt(),SalaryBookTwoWayFilter(),{take_n})"


def cap_holds_col_formula(column: str, take_n: int = 15) -> str:
    """Return formula for a cap holds column."""
    return f"=FilterSortTake({column},CapHoldsModeAmt(),CapHoldsFilter(),{take_n})"


def dead_money_col_formula(column: str, take_n: int = 10) -> str:
    """Return formula for a dead money column."""
    return f"=FilterSortTake({column},DeadMoneyModeAmt(),DeadMoneyFilter(),{take_n})"


def roster_derived_formula(column: str, transform: str, take_n: int = 40) -> str:
    """
    Return formula for a derived roster column (e.g., badge from name).
    
    Example:
        roster_derived_formula(
            "tbl_salary_book_warehouse[player_name]",
            'IF({result}<>"","ROST","")'
        )
    
    The {result} placeholder is replaced with the FilterSortTake result via LET.
    """
    _RES = _xlpm("res")
    inner = f"FilterSortTake({column},SalaryBookModeAmt(),SalaryBookRosterFilter(),{take_n})"
    # Replace {result} with the LET variable
    transformed = transform.replace("{result}", _RES)
    return f"=LET({_RES},{inner},{transformed})"


def SalaryBookYearCol(col_prefix: str) -> str:
    """Return CHOOSE formula for a set of yearly columns."""
    cols = ",".join(f"tbl_salary_book_warehouse[{col_prefix}_y{i}]" for i in range(6))
    return f"CHOOSE(ModeYearIndex,{cols})"


def roster_option_formula(take_n: int = 40) -> str:
    """Return complete option badge column formula."""
    return f"=FilterSortTake(SalaryBookOptionCol(),SalaryBookModeAmt(),SalaryBookRosterFilter(),{take_n})"


def roster_guarantee_formula(take_n: int = 40) -> str:
    """Return complete guarantee label formula."""
    return f"=FilterSortTake(SalaryBookGuaranteeLabel(),SalaryBookModeAmt(),SalaryBookRosterFilter(),{take_n})"


def roster_salary_formula(yi: int, take_n: int = 40) -> str:
    """Return mode-aware salary column formula for a specific year offset (0-5)."""
    _VAL = _xlpm("val")
    # In yi offset year, we still sort by SelectedYear mode_amt
    inner = (
        f'IF(SelectedMode="Cap",tbl_salary_book_warehouse[cap_y{yi}],'
        f'IF(SelectedMode="Tax",tbl_salary_book_warehouse[tax_y{yi}],'
        f'tbl_salary_book_warehouse[apron_y{yi}]))'
    )
    return f"=FilterSortTake({inner},SalaryBookModeAmt(),SalaryBookRosterFilter(),{take_n})"


def roster_pct_of_cap_formula(take_n: int = 40) -> str:
    """Return salary / cap_limit percentage formula."""
    _AMT = _xlpm("amt")
    _LIMIT = _xlpm("cap_limit")
    inner = f"FilterSortTake(SalaryBookModeAmt(),SalaryBookModeAmt(),SalaryBookRosterFilter(),{take_n})"
    cap_limit = "SUMIFS(tbl_system_values[salary_cap_amount],tbl_system_values[salary_year],SelectedYear)"
    return f"=LET({_AMT},{inner},{_LIMIT},{cap_limit},IF({_AMT}=\"\",\"\",{_AMT}/{_LIMIT}))"
