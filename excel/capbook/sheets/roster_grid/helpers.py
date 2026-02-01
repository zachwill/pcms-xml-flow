from __future__ import annotations

from typing import Any

from xlsxwriter.worksheet import Worksheet

from ...named_formulas import _xlpm

# =============================================================================
# Layout Constants
# =============================================================================

COL_BUCKET = 0
COL_COUNTS_TOTAL = 1
COL_COUNTS_ROSTER = 2
COL_NAME = 3
COL_OPTION = 4
COL_GUARANTEE = 5
COL_TRADE = 6
COL_MIN_LABEL = 7
COL_CAP_Y0 = 8
COL_CAP_Y1 = 9
COL_CAP_Y2 = 10
COL_CAP_Y3 = 11
COL_CAP_Y4 = 12
COL_CAP_Y5 = 13
COL_PCT_CAP = 14

YEAR_COLS = [COL_CAP_Y0, COL_CAP_Y1, COL_CAP_Y2, COL_CAP_Y3, COL_CAP_Y4, COL_CAP_Y5]

# Column widths
COLUMN_WIDTHS = {
    COL_BUCKET: 8,
    COL_COUNTS_TOTAL: 5,
    COL_COUNTS_ROSTER: 5,
    COL_NAME: 22,
    COL_OPTION: 6,
    COL_GUARANTEE: 8,
    COL_TRADE: 12,
    COL_MIN_LABEL: 10,
    COL_CAP_Y0: 12,
    COL_CAP_Y1: 12,
    COL_CAP_Y2: 12,
    COL_CAP_Y3: 12,
    COL_CAP_Y4: 12,
    COL_CAP_Y5: 12,
    COL_PCT_CAP: 10,
}


# Row counts for sections
num_roster_rows = 40  # Fixed allocation for roster rows
num_twoway_rows = 6
num_hold_rows = 15
num_dead_rows = 10
num_generated_rows = 15  # Maximum possible fill slots
num_exists_rows = 15  # Allocate slots for exists-only rows


# =============================================================================
# Formula Helpers
# =============================================================================


def roster_let_prefix() -> str:
    """Return LET prefix for roster filtering (mode-aware amount calculation)."""
    cap_choose = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
    tax_choose = ",".join(f"tbl_salary_book_warehouse[tax_y{i}]" for i in range(6))
    apron_choose = ",".join(f"tbl_salary_book_warehouse[apron_y{i}]" for i in range(6))

    return (
        f"_xlpm.cap_col,CHOOSE((SelectedYear-MetaBaseYear+1),{cap_choose}),"
        f"_xlpm.tax_col,CHOOSE((SelectedYear-MetaBaseYear+1),{tax_choose}),"
        f"_xlpm.apron_col,CHOOSE((SelectedYear-MetaBaseYear+1),{apron_choose}),"
        '_xlpm.mode_amt,IF(SelectedMode="Cap",_xlpm.cap_col,IF(SelectedMode="Tax",_xlpm.tax_col,_xlpm.apron_col)),'
        "_xlpm.filter_cond,(tbl_salary_book_warehouse[team_code]=SelectedTeam)*(tbl_salary_book_warehouse[is_two_way]=FALSE)*(_xlpm.mode_amt>0),"
    )


def twoway_let_prefix() -> str:
    """Return LET prefix for two-way filtering (mode-aware amount calculation)."""
    cap_choose = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
    tax_choose = ",".join(f"tbl_salary_book_warehouse[tax_y{i}]" for i in range(6))
    apron_choose = ",".join(f"tbl_salary_book_warehouse[apron_y{i}]" for i in range(6))

    return (
        f"_xlpm.cap_col,CHOOSE((SelectedYear-MetaBaseYear+1),{cap_choose}),"
        f"_xlpm.tax_col,CHOOSE((SelectedYear-MetaBaseYear+1),{tax_choose}),"
        f"_xlpm.apron_col,CHOOSE((SelectedYear-MetaBaseYear+1),{apron_choose}),"
        '_xlpm.mode_amt,IF(SelectedMode="Cap",_xlpm.cap_col,IF(SelectedMode="Tax",_xlpm.tax_col,_xlpm.apron_col)),'
        "_xlpm.filter_cond,(tbl_salary_book_warehouse[team_code]=SelectedTeam)*(tbl_salary_book_warehouse[is_two_way]=TRUE)*(_xlpm.mode_amt>0),"
    )


def _mode_prefix_expr() -> str:
    """Return an Excel expression that maps SelectedMode to a column prefix.

    SelectedMode is one of: "Cap", "Tax", "Apron"
    This returns "cap", "tax", or "apron" for use in dynamic column references.

    Returns an expression (no leading '=') suitable for embedding in formulas.
    """
    return 'LOWER(SelectedMode)'


def _salary_book_choose(col_base: str) -> str:
    """Return an Excel CHOOSE() expression selecting the correct *_y{0..5} column.

    The workbook exports salary_book_warehouse as relative-year columns
    (cap_y0..cap_y5, tax_y0..tax_y5, etc.) relative to META.base_year.

    SelectedYear is an absolute salary_year; we map it to a relative offset:
        idx = (SelectedYear - MetaBaseYear) + 1

    Args:
        col_base: Column prefix ("cap", "tax", "apron", or dynamic expression)

    Returns an expression (no leading '=') suitable for embedding in formulas.
    """

    cols = ",".join(
        f"tbl_salary_book_warehouse[{col_base}_y{i}]" for i in range(6)
    )
    return f"CHOOSE(SelectedYear-MetaBaseYear+1,{cols})"


def _salary_book_choose_mode_aware() -> str:
    """Return an Excel expression selecting the correct mode-aware column for SelectedYear.

    Uses SelectedMode ("Cap"/"Tax"/"Apron") to pick between cap_y*, tax_y*, apron_y* columns,
    then uses SelectedYear to pick the correct relative year offset.

    Returns an expression (no leading '=') suitable for embedding in formulas.
    """
    # We need to nest CHOOSE: outer for mode, inner for year
    # Mode: Cap=1, Tax=2, Apron=3
    # Year offset: (SelectedYear - MetaBaseYear) + 1 gives 1..6

    cap_cols = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
    tax_cols = ",".join(f"tbl_salary_book_warehouse[tax_y{i}]" for i in range(6))
    apron_cols = ",".join(f"tbl_salary_book_warehouse[apron_y{i}]" for i in range(6))

    year_idx = "SelectedYear-MetaBaseYear+1"

    return (
        f'IF(SelectedMode="Cap",CHOOSE({year_idx},{cap_cols}),'
        f'IF(SelectedMode="Tax",CHOOSE({year_idx},{tax_cols}),'
        f'CHOOSE({year_idx},{apron_cols})))'
    )


def _salary_book_sumproduct(is_two_way: str | None = None) -> str:
    """Return a SUM(FILTER(...)) expression for salary_book_warehouse mode-aware amount.

    Args:
        is_two_way: "TRUE" or "FALSE" or None (all)

    Returns an expression (no leading '=') suitable for embedding in formulas.
    """
    if is_two_way == "FALSE":
        return "SUM(FILTER(SalaryBookModeAmt(),SalaryBookRosterFilter(),0))"
    elif is_two_way == "TRUE":
        return "SUM(FILTER(SalaryBookModeAmt(),SalaryBookTwoWayFilter(),0))"
    else:
        # Combined filter
        return "SUM(FILTER(SalaryBookModeAmt(),(tbl_salary_book_warehouse[team_code]=SelectedTeam)*(SalaryBookModeAmt()>0),0))"


def _salary_book_countproduct(is_two_way: str) -> str:
    """Return a ROWS(FILTER(...)) expression for counting roster/two-way players.

    Only counts players where mode-aware amount > 0.

    Args:
        is_two_way: "TRUE" or "FALSE"

    Returns an expression (no leading '=') suitable for embedding in formulas.
    """
    filter_name = "SalaryBookRosterFilter()" if is_two_way == "FALSE" else "SalaryBookTwoWayFilter()"
    # Use LET to avoid double-evaluation of FILTER and handle empty case
    return f'LET(_xlpm.f,FILTER(tbl_salary_book_warehouse[player_name],{filter_name},#N/A),IF(ISNA(_xlpm.f),0,ROWS(_xlpm.f)))'


def _cap_holds_sumproduct() -> str:
    """Return a SUM(FILTER(...)) expression for cap holds."""
    return "SUM(FILTER(CapHoldsModeAmt(),CapHoldsFilter(),0))"


def _cap_holds_countproduct() -> str:
    """Return a ROWS(FILTER(...)) expression for counting cap holds."""
    return 'LET(_xlpm.f,FILTER(tbl_cap_holds_warehouse[player_name],CapHoldsFilter(),#N/A),IF(ISNA(_xlpm.f),0,ROWS(_xlpm.f)))'


def _dead_money_sumproduct() -> str:
    """Return a SUM(FILTER(...)) expression for dead money."""
    return "SUM(FILTER(DeadMoneyModeAmt(),DeadMoneyFilter(),0))"


def _dead_money_countproduct() -> str:
    """Return a ROWS(FILTER(...)) expression for counting dead money rows."""
    return 'LET(_xlpm.f,FILTER(tbl_dead_money_warehouse[player_name],DeadMoneyFilter(),#N/A),IF(ISNA(_xlpm.f),0,ROWS(_xlpm.f)))'


def _mode_year_label(year_offset: int) -> str:
    """Return formula for mode-aware year label (e.g. '2025 Cap')."""
    return f'=SelectedYear+{year_offset} & " " & SelectedMode'


def _warehouse_bucket_col(bucket: str) -> str:
    """Return formula for fetching bucket total from team_salary_warehouse."""
    # Bucket columns in tbl_team_salary_warehouse are named: {mode}_{bucket}_amt
    # mode = LOWER(SelectedMode)
    # bucket = LOWER(bucket)
    mode_prefix = _mode_prefix_expr()
    col_name = f'{mode_prefix} & "_{bucket.lower()}_amt"'

    # We need to use INDIRECT to reference the dynamic column name
    # But table refs inside INDIRECT are tricky.
    # Better: use XLOOKUP on the team + year, then use CHOOSECOLS?
    # Actually, we know the column names are fixed patterns.
    # We can use LET + CHOOSE to pick the column.

    # Available columns: cap_rost_amt, cap_fa_amt, cap_term_amt, cap_2way_amt, etc.
    buckets = ["ROST", "FA", "TERM", "2WAY"]
    modes = ["cap", "tax", "apron"]

    # This is getting complex. Let's use a simpler approach:
    # SUMIFS(tbl_team_salary_warehouse[cap_rost_amt], ...) if mode="Cap" and bucket="ROST"
    return (
        f'SUMIFS(INDIRECT("tbl_team_salary_warehouse[" & {_mode_prefix_expr()} & "_{bucket.lower()}_amt]"), '
        'tbl_team_salary_warehouse[team_code], SelectedTeam, '
        'tbl_team_salary_warehouse[salary_year], SelectedYear)'
    )


def _warehouse_total_col() -> str:
    """Return formula for fetching total salary from team_salary_warehouse."""
    # Column names: total_cap_salary, total_tax_salary, total_apron_salary
    return (
        f'SUMIFS(INDIRECT("tbl_team_salary_warehouse[total_" & {_mode_prefix_expr()} & "_salary]"), '
        'tbl_team_salary_warehouse[team_code], SelectedTeam, '
        'tbl_team_salary_warehouse[salary_year], SelectedYear)'
    )


def _write_column_headers(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    year_labels: list[str],
) -> int:
    """Write the column headers for the roster grid.

    Returns next row.
    """
    worksheet.write(row, COL_BUCKET, "Bucket", formats["col_header"])
    worksheet.write(row, COL_COUNTS_TOTAL, "Ct$", formats["col_header"])
    worksheet.write(row, COL_COUNTS_ROSTER, "CtR", formats["col_header"])
    worksheet.write(row, COL_NAME, "Player / Hold Name", formats["col_header"])
    worksheet.write(row, COL_OPTION, "Opt", formats["col_header"])
    worksheet.write(row, COL_GUARANTEE, "Gtd", formats["col_header"])
    worksheet.write(row, COL_TRADE, "Trade Restr", formats["col_header"])
    worksheet.write(row, COL_MIN_LABEL, "Min?", formats["col_header"])

    # Multi-year headers
    for i, label in enumerate(year_labels):
        worksheet.write_formula(row, COL_CAP_Y0 + i, label, formats["col_header"])

    worksheet.write(row, COL_PCT_CAP, "% Cap", formats["col_header"])

    return row + 1


def _apply_badge_conditional_formatting(
    worksheet: Worksheet,
    formats: dict[str, Any],
    start_row: int,
    end_row: int,
) -> None:
    """Apply conditional formatting for badges (option, guarantee, trade)."""

    # 1. Option badges (PO, TO, ETO)
    worksheet.conditional_format(start_row, COL_OPTION, end_row, COL_OPTION, {
        "type": "cell", "criteria": "equal to", "value": '"PO"', "format": formats["badge_po"]
    })
    worksheet.conditional_format(start_row, COL_OPTION, end_row, COL_OPTION, {
        "type": "cell", "criteria": "equal to", "value": '"PLYR"', "format": formats["badge_po"]
    })
    worksheet.conditional_format(start_row, COL_OPTION, end_row, COL_OPTION, {
        "type": "cell", "criteria": "equal to", "value": '"TO"', "format": formats["badge_to"]
    })
    worksheet.conditional_format(start_row, COL_OPTION, end_row, COL_OPTION, {
        "type": "cell", "criteria": "equal to", "value": '"TEAM"', "format": formats["badge_to"]
    })
    worksheet.conditional_format(start_row, COL_OPTION, end_row, COL_OPTION, {
        "type": "cell", "criteria": "equal to", "value": '"ETO"', "format": formats["badge_eto"]
    })
    worksheet.conditional_format(start_row, COL_OPTION, end_row, COL_OPTION, {
        "type": "cell", "criteria": "equal to", "value": '"PLYTF"', "format": formats["badge_eto"]
    })

    # 2. Guarantee badges (GTD, PRT, NG)
    worksheet.conditional_format(start_row, COL_GUARANTEE, end_row, COL_GUARANTEE, {
        "type": "cell", "criteria": "equal to", "value": '"GTD"', "format": formats["badge_gtd"]
    })
    worksheet.conditional_format(start_row, COL_GUARANTEE, end_row, COL_GUARANTEE, {
        "type": "cell", "criteria": "equal to", "value": '"PRT"', "format": formats["badge_prt"]
    })
    worksheet.conditional_format(start_row, COL_GUARANTEE, end_row, COL_GUARANTEE, {
        "type": "cell", "criteria": "equal to", "value": '"NG"', "format": formats["badge_ng"]
    })

    # 3. Trade restriction badges
    worksheet.conditional_format(start_row, COL_TRADE, end_row, COL_TRADE, {
        "type": "cell", "criteria": "containing", "value": '"NTC"', "format": formats["badge_no_trade"]
    })
    worksheet.conditional_format(start_row, COL_TRADE, end_row, COL_TRADE, {
        "type": "cell", "criteria": "containing", "value": '"Consent"', "format": formats["badge_consent"]
    })
    worksheet.conditional_format(start_row, COL_TRADE, end_row, COL_TRADE, {
        "type": "cell", "criteria": "containing", "value": '"Kicker"', "format": formats["badge_kicker"]
    })
    worksheet.conditional_format(start_row, COL_TRADE, end_row, COL_TRADE, {
        "type": "cell", "criteria": "containing", "value": '"Restricted"', "format": formats["badge_consent"]
    })
