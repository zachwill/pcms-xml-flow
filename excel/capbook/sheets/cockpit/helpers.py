"""
Formula helpers for TEAM_COCKPIT sheet.

Provides reusable formula builders for lookups, aggregations, and mode-aware logic.
"""

from __future__ import annotations


# =============================================================================
# Formula Helpers
# =============================================================================


def sumifs_formula(data_col: str) -> str:
    """Build SUMIFS formula to look up a value from tbl_team_salary_warehouse.

    Uses SelectedTeam and SelectedYear to filter.
    SUMIFS works well for numeric values with two-column lookup.
    """
    return (
        f"=SUMIFS(tbl_team_salary_warehouse[{data_col}],"
        f"tbl_team_salary_warehouse[team_code],SelectedTeam,"
        f"tbl_team_salary_warehouse[salary_year],SelectedYear)"
    )


def salary_book_choose_cap() -> str:
    """Return an Excel CHOOSE() expression selecting the correct cap_y* column for SelectedYear.

    The workbook exports salary_book_warehouse with relative-year columns
    (cap_y0..cap_y5) relative to MetaBaseYear.

    SelectedYear is an absolute salary_year; we map it to a relative offset:
        idx = (SelectedYear - MetaBaseYear) + 1

    Returns an expression (no leading '=') suitable for embedding in AGGREGATE formulas.
    """
    cols = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
    return f"CHOOSE(SelectedYear-MetaBaseYear+1,{cols})"


def min_contract_let_prefix() -> str:
    """Return the LET prefix for min-contract filtering.

    Defines:
    - mode_amt: mode-aware amount for SelectedYear (cap by default for min contracts)
    - filter_cond: team match + is_min_contract=TRUE

    Used by both count and sum formulas for min contracts.
    """
    # Min contracts use cap amounts for SelectedYear
    # Uses CHOOSE to pick the correct cap_y* column based on SelectedYear
    return (
        "_xlpm.mode_amt,CHOOSE(SelectedYear-MetaBaseYear+1,"
        + ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
        + "),"
        "_xlpm.filter_cond,(tbl_salary_book_warehouse[team_code]=SelectedTeam)*"
        "(tbl_salary_book_warehouse[is_min_contract]=TRUE),"
    )


def salary_book_min_contract_count_formula() -> str:
    """Return a LET+FILTER+ROWS formula for counting min-contract players.

    Uses ROWS(FILTER(...)) instead of COUNTIFS for consistency with the
    modern formula standard (Excel 365+).

    Returns a formula string (with leading '=').
    """
    return (
        "=LET("
        + min_contract_let_prefix()
        + "IFERROR(ROWS(FILTER(tbl_salary_book_warehouse[player_id],_xlpm.filter_cond)),0))"
    )


def salary_book_min_contract_sum_formula() -> str:
    """Return a LET+FILTER+SUM formula for summing min-contract cap amounts.

    Filters by team_code=SelectedTeam AND is_min_contract=TRUE.
    Uses CHOOSE to pick the correct cap_y* column for SelectedYear.

    Returns a formula string (with leading '=').
    """
    return (
        "=LET("
        + min_contract_let_prefix()
        + "IFERROR(SUM(FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0)),0))"
    )


def if_formula(data_col: str) -> str:
    """Build XLOOKUP formula for boolean/text values from tbl_team_salary_warehouse.

    For booleans like is_repeater_taxpayer, we convert to display text.
    """
    return (
        f"=IFERROR(XLOOKUP(1,(tbl_team_salary_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_team_salary_warehouse[salary_year]=SelectedYear),"
        f'tbl_team_salary_warehouse[{data_col}],""),"")'
    )


# Helper to get mode index without inline array constant (XlsxWriter bug in CF formulas)
# Returns: IF(SelectedMode="Cap",1,IF(SelectedMode="Tax",2,IF(SelectedMode="Apron",3,0)))
MODE_INDEX_EXPR = 'IF(SelectedMode="Cap",1,IF(SelectedMode="Tax",2,IF(SelectedMode="Apron",3,0)))'


def mode_drilldown_sum_formula() -> str:
    """Build formula to sum drilldowns for SelectedMode (Cap/Tax/Apron).
    
    Uses modern Excel 365 formulas (FILTER + SUM) and named formulas
    to replace legacy SUMPRODUCT patterns.
    
    Returns an expression (no leading '=') suitable for use in formulas.
    """
    # salary_book_warehouse sum (both roster and two-way)
    # Uses SalaryBookModeAmt() which handles both SelectedMode and SelectedYear
    salary_book_sum = (
        "SUM(FILTER(SalaryBookModeAmt(),(tbl_salary_book_warehouse[team_code]=SelectedTeam),0))"
    )
    
    # cap_holds_warehouse sum
    # Uses CapHoldsModeAmt() which handles SelectedMode
    cap_holds_sum = (
        "SUM(FILTER(CapHoldsModeAmt(),"
        "(tbl_cap_holds_warehouse[team_code]=SelectedTeam)*"
        "(tbl_cap_holds_warehouse[salary_year]=SelectedYear),0))"
    )
    
    # dead_money_warehouse sum
    # Uses DeadMoneyModeAmt() which handles SelectedMode
    dead_money_sum = (
        "SUM(FILTER(DeadMoneyModeAmt(),"
        "(tbl_dead_money_warehouse[team_code]=SelectedTeam)*"
        "(tbl_dead_money_warehouse[salary_year]=SelectedYear),0))"
    )
    
    return f"({salary_book_sum}+{cap_holds_sum}+{dead_money_sum})"


def mode_warehouse_total_formula() -> str:
    """Build formula to get warehouse total for SelectedMode.
    
    Uses CHOOSE with nested IF for mode selection (avoids inline array constants
    which cause XlsxWriter issues in conditional formatting).
    
    Returns an expression (no leading '=') suitable for use in formulas.
    """
    return (
        f'CHOOSE({MODE_INDEX_EXPR},'
        "SUMIFS(tbl_team_salary_warehouse[cap_total],"
        "tbl_team_salary_warehouse[team_code],SelectedTeam,"
        "tbl_team_salary_warehouse[salary_year],SelectedYear),"
        "SUMIFS(tbl_team_salary_warehouse[tax_total],"
        "tbl_team_salary_warehouse[team_code],SelectedTeam,"
        "tbl_team_salary_warehouse[salary_year],SelectedYear),"
        "SUMIFS(tbl_team_salary_warehouse[apron_total],"
        "tbl_team_salary_warehouse[team_code],SelectedTeam,"
        "tbl_team_salary_warehouse[salary_year],SelectedYear))"
    )
