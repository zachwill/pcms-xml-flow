"""
ROSTER_GRID sheet writer - full roster/ledger view with reconciliation.

This module implements:
1. Shared command bar (read-only reference to TEAM_COCKPIT)
2. Roster rows section (from tbl_salary_book_warehouse)
   - Uses Excel 365 dynamic arrays: FILTER, SORTBY, TAKE, LET
   - Single spilling formula per column (replaces per-row AGGREGATE/MATCH)
   - Player name, team, badge columns (option, guarantee, trade restrictions)
   - Multi-year salary columns (mode-aware: cap_y0..cap_y5 / tax_y0..tax_y5 / apron_y0..apron_y5)
   - Bucket classification (ROST/2WAY)
   - Explicit CountsTowardTotal (Ct$) and CountsTowardRoster (CtR) columns
   - MINIMUM label display when is_min_contract=TRUE
   - Conditional formatting for badges (colors cells based on PO/TO/ETO, GTD/PRT/NG, NTC/Kicker)
3. Two-way section (bucket = 2WAY)
   - Uses same FILTER/SORTBY/TAKE pattern as roster section
   - Two-way policy toggles are not implemented yet (totals/counts remain authoritative)
4. Cap holds section (bucket = FA, from tbl_cap_holds_warehouse)
   - Uses Excel 365 dynamic arrays: FILTER, SORTBY, TAKE, LET
   - Filters to SelectedTeam + SelectedYear, sorted by mode-aware amount (DESC)
   - Displays FA type, status, mode-aware amount, % of cap
   - Ct$ = Y, CtR = N (holds count toward cap totals but not roster)
5. Dead money section (bucket = TERM, from tbl_dead_money_warehouse)
   - Uses Excel 365 dynamic arrays: FILTER, SORTBY, TAKE, LET
   - Filters to SelectedTeam + SelectedYear, sorted by mode-aware amount (DESC)
   - Displays waive date, mode-aware amount, % of cap
   - Ct$ = Y, CtR = N (dead money counts toward cap totals but not roster)
6. EXISTS_ONLY section (non-counting rows for analyst reference)
   - Uses Excel 365 dynamic arrays: LET, FILTER, SORTBY, TAKE
   - Computes per-player "future total" (sum of future-year amounts in any mode)
   - Filters for: SelectedTeam + SelectedYear cap/tax/apron all zero + future_total > 0
   - Sorted by mode-aware future amount (DESC) - biggest future commitments first
   - Shows players with $0 in SelectedYear but non-zero in future years
   - Controlled by ShowExistsOnlyRows toggle ("Yes" to show, "No" to hide)
   - Bucket = EXISTS, Ct$ = N, CtR = N (never counted in totals)
7. Totals + reconciliation block vs DATA_team_salary_warehouse
8. % of cap display helper

Per the blueprint (excel-cap-book-blueprint.md):
- Every headline total must be reconcilable to the authoritative ledger
- Drilldown tables are labeled by bucket and scoped to the snapshot
- CountsTowardTotal/CountsTowardRoster columns make counting logic explicit
- EXISTS_ONLY rows are "visible artifacts that do not count (for reference only)"

Design notes:
- Uses Excel 365+ dynamic array formulas: FILTER, SORTBY, TAKE, LET, IFNA
- Spill formulas reduce row-by-row formula complexity and improve performance
- SelectedMode ("Cap"/"Tax"/"Apron") controls which salary columns are displayed
- Reconciliation block sums rows and compares to team_salary_warehouse totals (mode-aware)
- Conditional formatting highlights deltas ≠ 0
- Two-way rows display Ct$=Y (counts toward cap totals per CBA), CtR=N (does not count toward 15-player roster)
- Cap holds and dead money sections use LET-based spill formulas with mode-aware filtering
- EXISTS_ONLY section uses LET-based spill formulas with per-player future_total computation

Badge formatting (aligned to web UI conventions from web/src/features/SalaryBook/):
- Option: PO/PLYR (blue), TO/TEAM (purple), ETO/PLYTF (orange)
- Guarantee: GTD (green text), PRT (amber bg), NG (red bg)
- Trade: NTC (red), Kicker (orange), Restricted (amber)
"""

from __future__ import annotations

from typing import Any

import xlsxwriter.utility

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import FMT_MONEY, FMT_PERCENT
from ..named_formulas import (
    roster_col_formula,
    roster_derived_formula,
    twoway_col_formula,
    cap_holds_col_formula,
    dead_money_col_formula,
    _xlpm,
)
from .command_bar import (
    write_command_bar_readonly,
    get_content_start_row,
)


# =============================================================================
# Layout Constants
# =============================================================================

# Column layout for roster grid
# A=0: Row Type/Bucket
# B=1: CountsTowardTotal (Y/N) - explicit per blueprint
# C=2: CountsTowardRoster (Y/N) - explicit per blueprint
# D=3: Player/Hold Name
# E=4: Option Badge
# F=5: Guarantee Status
# G=6: Trade Restriction
# H=7: Min Contract label
# I=8: cap_y0 (base year)
# J-N=9-13: cap_y1..cap_y5
# O=14: Total / % of Cap

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


# =============================================================================
# Formula Helpers
# =============================================================================


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
    """SUMPRODUCT of selected-year, mode-aware amounts from tbl_salary_book_warehouse.

    Uses SelectedMode to pick between cap/tax/apron columns.

    Args:
        is_two_way: "TRUE" / "FALSE" to filter, or None for all rows.

    Returns expression (no leading '=')
    """

    amount_sel = _salary_book_choose_mode_aware()
    base = f"(tbl_salary_book_warehouse[team_code]=SelectedTeam)"
    if is_two_way is not None:
        base += f"*(tbl_salary_book_warehouse[is_two_way]={is_two_way})"
    return f"SUMPRODUCT({base}*{amount_sel})"


def _salary_book_countproduct(is_two_way: str) -> str:
    """Count rows with selected-year, mode-aware amount > 0 via SUMPRODUCT."""

    amount_sel = _salary_book_choose_mode_aware()
    return (
        "SUMPRODUCT(--(tbl_salary_book_warehouse[team_code]=SelectedTeam),"
        f"--(tbl_salary_book_warehouse[is_two_way]={is_two_way}),"
        f"--({amount_sel}>0))"
    )


def _cap_holds_amount_col() -> str:
    """Return mode-aware amount column name for cap holds warehouse.

    tbl_cap_holds_warehouse has: cap_amount, tax_amount, apron_amount
    """
    return (
        'IF(SelectedMode="Cap",tbl_cap_holds_warehouse[cap_amount],'
        'IF(SelectedMode="Tax",tbl_cap_holds_warehouse[tax_amount],'
        'tbl_cap_holds_warehouse[apron_amount]))'
    )


def _dead_money_amount_col() -> str:
    """Return mode-aware amount column name for dead money warehouse.

    tbl_dead_money_warehouse has: cap_value, tax_value, apron_value
    """
    return (
        'IF(SelectedMode="Cap",tbl_dead_money_warehouse[cap_value],'
        'IF(SelectedMode="Tax",tbl_dead_money_warehouse[tax_value],'
        'tbl_dead_money_warehouse[apron_value]))'
    )


def _mode_year_label(year_offset: int) -> str:
    """Return a formula for a year column header showing mode + year.

    E.g., for year_offset=0: displays "Cap 2025" when SelectedMode="Cap" and base_year=2025

    Returns formula string with leading '='.
    """
    return f'=SelectedMode&\" \"&(MetaBaseYear+{year_offset})'


def _warehouse_bucket_col(bucket: str) -> str:
    """Return mode-aware warehouse column name for a bucket.

    Maps bucket (rost/fa/term/2way) to mode-appropriate column in team_salary_warehouse.
    E.g., bucket="rost" with SelectedMode="Cap" → "cap_rost"
    """
    return (
        f'IF(SelectedMode="Cap","cap_{bucket}",'
        f'IF(SelectedMode="Tax","tax_{bucket}",'
        f'"apron_{bucket}"))'
    )


def _warehouse_total_col() -> str:
    """Return mode-aware total column name for team_salary_warehouse.

    Maps SelectedMode to cap_total, tax_total, or apron_total.
    """
    return (
        'IF(SelectedMode="Cap","cap_total",'
        'IF(SelectedMode="Tax","tax_total",'
        '"apron_total"))'
    )


# =============================================================================
# Format Helpers
# =============================================================================

def _create_roster_formats(workbook: Workbook) -> dict[str, Any]:
    """Create formats specific to the roster grid."""
    formats = {}

    # Section headers
    formats["section_header"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#E5E7EB",  # gray-200
        "bottom": 2,
    })

    # Exists-only section header (distinct purple color to indicate non-counting)
    formats["section_header_exists_only"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#EDE9FE",  # purple-100
        "font_color": "#6B21A8",  # purple-800
        "bottom": 2,
    })

    # Column headers
    formats["col_header"] = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "bg_color": "#F3F4F6",  # gray-100
        "align": "center",
        "bottom": 1,
    })

    # Money format
    formats["money"] = workbook.add_format({"num_format": FMT_MONEY})
    formats["money_bold"] = workbook.add_format({"num_format": FMT_MONEY, "bold": True})

    # Percent format
    formats["percent"] = workbook.add_format({"num_format": FMT_PERCENT, "align": "center"})

    # Badge formats (option/guarantee/trade)
    formats["badge_po"] = workbook.add_format({
        "bg_color": "#DBEAFE",  # blue-100
        "font_color": "#1E40AF",  # blue-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_to"] = workbook.add_format({
        "bg_color": "#EDE9FE",  # purple-100
        "font_color": "#5B21B6",  # purple-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_eto"] = workbook.add_format({
        "bg_color": "#FFEDD5",  # orange-100
        "font_color": "#9A3412",  # orange-800
        "align": "center",
        "font_size": 9,
    })

    formats["badge_gtd"] = workbook.add_format({
        "font_color": "#166534",  # green-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_prt"] = workbook.add_format({
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_ng"] = workbook.add_format({
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "align": "center",
        "font_size": 9,
    })

    # Trade restriction badges
    formats["badge_no_trade"] = workbook.add_format({
        "bg_color": "#FEE2E2",
        "font_color": "#991B1B",
        "align": "center",
        "font_size": 9,
    })
    formats["badge_kicker"] = workbook.add_format({
        "bg_color": "#FFEDD5",
        "font_color": "#9A3412",
        "align": "center",
        "font_size": 9,
    })
    formats["badge_consent"] = workbook.add_format({
        "bg_color": "#FEF3C7",
        "font_color": "#92400E",
        "align": "center",
        "font_size": 9,
    })

    # Minimum contract label
    formats["min_label"] = workbook.add_format({
        "italic": True,
        "font_color": "#6B7280",  # gray-500
        "font_size": 9,
        "align": "center",
    })

    # Bucket labels
    formats["bucket_rost"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
    })
    formats["bucket_fa"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#1E40AF",  # blue-800
    })
    formats["bucket_term"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#991B1B",  # red-800
    })
    formats["bucket_2way"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#6B7280",  # gray-500
        "italic": True,
    })
    formats["bucket_exists_only"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#9333EA",  # purple-600
        "italic": True,
    })

    # Counts column formats (Y/N badges)
    formats["counts_yes"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#166534",  # green-800
        "bold": True,
    })
    formats["counts_no"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#9CA3AF",  # gray-400
        "italic": True,
    })

    # Subtotal row
    formats["subtotal"] = workbook.add_format({
        "bold": True,
        "top": 1,
        "num_format": FMT_MONEY,
    })
    formats["subtotal_label"] = workbook.add_format({
        "bold": True,
        "top": 1,
    })

    # Reconciliation section
    formats["reconcile_header"] = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "bg_color": "#FEF3C7",  # amber-100
    })
    formats["reconcile_label"] = workbook.add_format({
        "font_size": 9,
    })
    formats["reconcile_value"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_size": 9,
    })
    formats["reconcile_delta_zero"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_size": 9,
        "bg_color": "#D1FAE5",  # green-100
        "font_color": "#065F46",  # green-800
    })
    formats["reconcile_delta_nonzero"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_size": 9,
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "bold": True,
    })

    return formats


# =============================================================================
# Section Writers
# =============================================================================

def _write_column_headers(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    year_labels: list[str],
) -> int:
    """Write the column headers for the roster grid.

    Returns next row.
    """
    fmt = formats["col_header"]

    worksheet.write(row, COL_BUCKET, "Bucket", fmt)
    worksheet.write(row, COL_COUNTS_TOTAL, "Ct$", fmt)  # CountsTowardTotal
    worksheet.write(row, COL_COUNTS_ROSTER, "CtR", fmt)  # CountsTowardRoster
    worksheet.write(row, COL_NAME, "Name", fmt)
    worksheet.write(row, COL_OPTION, "Opt", fmt)
    worksheet.write(row, COL_GUARANTEE, "GTD", fmt)
    worksheet.write(row, COL_TRADE, "Trade", fmt)
    worksheet.write(row, COL_MIN_LABEL, "Type", fmt)

    for i, label in enumerate(year_labels):
        if isinstance(label, str) and label.startswith("="):
            worksheet.write_formula(row, COL_CAP_Y0 + i, label, fmt)
        else:
            worksheet.write(row, COL_CAP_Y0 + i, label, fmt)

    worksheet.write(row, COL_PCT_CAP, "% Cap", fmt)

    return row + 1


def _write_roster_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> tuple[int, int]:
    """Write the roster rows section (from tbl_salary_book_warehouse).

    Uses Excel 365 dynamic array formulas (FILTER, SORTBY, TAKE, CHOOSECOLS).
    Rows are spilled from a single formula that:
    1. FILTERs to SelectedTeam + non-two-way + has amount in SelectedYear
    2. SORTBYs by SelectedYear mode-aware amount (DESC)
    3. TAKEs the first N rows (max 40)
    4. Uses CHOOSECOLS + INDEX for mode-aware column selection

    Returns (next_row, data_start_row) for reconciliation formulas.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "ROSTER (Active Contracts)", section_fmt)
    row += 1

    # Note about formula-driven display (updated for dynamic arrays)
    worksheet.write(row, COL_BUCKET, "Dynamic array: players for SelectedTeam sorted by SelectedYear amount (uses FILTER/SORTBY)", roster_formats["reconcile_label"])
    row += 1

    # Column headers
    # Year labels: show mode + absolute year (e.g., "Cap 2025", "Tax 2025")
    year_labels = [
        _mode_year_label(0),
        _mode_year_label(1),
        _mode_year_label(2),
        _mode_year_label(3),
        _mode_year_label(4),
        _mode_year_label(5),
    ]
    row = _write_column_headers(worksheet, row, roster_formats, year_labels)

    data_start_row = row

    # =========================================================================
    # Dynamic Array Formula: FILTER + SORTBY for roster rows
    # =========================================================================
    #
    # Design: We write ONE spilling formula per column that extracts and sorts
    # the matching players. Each column uses the same FILTER/SORTBY logic but
    # returns a different field.
    #
    # The mode-aware SelectedYear amount for filtering and sorting:
    #   LET(
    #     tbl, tbl_salary_book_warehouse,
    #     cap_col, CHOOSE((SelectedYear-MetaBaseYear+1), tbl[cap_y0], tbl[cap_y1], ...),
    #     tax_col, CHOOSE((SelectedYear-MetaBaseYear+1), tbl[tax_y0], tbl[tax_y1], ...),
    #     apron_col, CHOOSE((SelectedYear-MetaBaseYear+1), tbl[apron_y0], tbl[apron_y1], ...),
    #     mode_amt, IF(SelectedMode="Cap", cap_col, IF(SelectedMode="Tax", tax_col, apron_col)),
    #     ...
    #   )
    #
    # Filter criteria: team_code = SelectedTeam AND is_two_way = FALSE AND mode_amt > 0
    # Sort: by mode_amt DESC
    # Take: first 40 rows

    num_roster_rows = 40  # Fixed allocation for roster rows

    # Helper to build the common LET prefix for roster data extraction
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

    # Helper to build SORTBY + TAKE wrapper
    def sortby_take_wrapper(filtered_expr: str, sort_by: str = "mode_amt", take_n: int = num_roster_rows) -> str:
        """Wrap a FILTER result with SORTBY (desc) and TAKE."""
        return f"TAKE(SORTBY({filtered_expr},{sort_by},-1),{take_n})"

    # -------------------------------------------------------------------------
    # Player Name column (spills down)
    # -------------------------------------------------------------------------
    name_formula = (
        "=LET("
        + roster_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"  # Need mode_amt for sorting
        + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"))"
    )
    worksheet.write_formula(row, COL_NAME, name_formula)

    # -------------------------------------------------------------------------
    # Bucket column (ROST for non-empty rows)
    # -------------------------------------------------------------------------
    # Since we can't easily reference the spilled name column, we replicate the filter
    bucket_formula = (
        "=LET("
        + roster_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"),"
        + 'IF(_xlpm.names<>"","ROST",""))'
    )
    worksheet.write_formula(row, COL_BUCKET, bucket_formula, roster_formats["bucket_rost"])

    # -------------------------------------------------------------------------
    # CountsTowardTotal column (Y for non-empty)
    # -------------------------------------------------------------------------
    ct_total_formula = (
        "=LET("
        + roster_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"),"
        + 'IF(_xlpm.names<>"","Y",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, ct_total_formula, roster_formats["counts_yes"])

    # -------------------------------------------------------------------------
    # CountsTowardRoster column (Y for ROST)
    # -------------------------------------------------------------------------
    ct_roster_formula = (
        "=LET("
        + roster_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"),"
        + 'IF(_xlpm.names<>"","Y",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_ROSTER, ct_roster_formula, roster_formats["counts_yes"])

    # -------------------------------------------------------------------------
    # Option badge column (spills down)
    # -------------------------------------------------------------------------
    # Uses CHOOSE to select the right option_y* column for SelectedYear
    opt_choose = ",".join(f"tbl_salary_book_warehouse[option_y{i}]" for i in range(6))
    option_formula = (
        "=LET("
        + roster_let_prefix()
        + f"_xlpm.opt_col,CHOOSE((SelectedYear-MetaBaseYear+1),{opt_choose}),"
        + "_xlpm.filtered,FILTER(_xlpm.opt_col,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"))"
    )
    worksheet.write_formula(row, COL_OPTION, option_formula)

    # -------------------------------------------------------------------------
    # Guarantee status column (GTD/PRT/NG)
    # -------------------------------------------------------------------------
    # Needs to check is_fully_guaranteed, is_partially_guaranteed, is_non_guaranteed for SelectedYear
    gtd_full_choose = ",".join(f"tbl_salary_book_warehouse[is_fully_guaranteed_y{i}]" for i in range(6))
    gtd_part_choose = ",".join(f"tbl_salary_book_warehouse[is_partially_guaranteed_y{i}]" for i in range(6))
    gtd_non_choose = ",".join(f"tbl_salary_book_warehouse[is_non_guaranteed_y{i}]" for i in range(6))
    guarantee_formula = (
        "=LET("
        + roster_let_prefix()
        + f"_xlpm.gtd_full,CHOOSE((SelectedYear-MetaBaseYear+1),{gtd_full_choose}),"
        + f"_xlpm.gtd_part,CHOOSE((SelectedYear-MetaBaseYear+1),{gtd_part_choose}),"
        + f"_xlpm.gtd_non,CHOOSE((SelectedYear-MetaBaseYear+1),{gtd_non_choose}),"
        + '_xlpm.gtd_label,IF(_xlpm.gtd_full=TRUE,"GTD",IF(_xlpm.gtd_part=TRUE,"PRT",IF(_xlpm.gtd_non=TRUE,"NG",""))),'
        + "_xlpm.filtered,FILTER(_xlpm.gtd_label,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"))"
    )
    worksheet.write_formula(row, COL_GUARANTEE, guarantee_formula)

    # -------------------------------------------------------------------------
    # Trade restriction column (NTC/Kicker/Restricted)
    # -------------------------------------------------------------------------
    trade_formula = (
        "=LET("
        + roster_let_prefix()
        + '_xlpm.trade_label,IF(tbl_salary_book_warehouse[is_no_trade]=TRUE,"NTC",'
        + 'IF(tbl_salary_book_warehouse[is_trade_bonus]=TRUE,"Kicker",'
        + 'IF(tbl_salary_book_warehouse[is_trade_restricted_now]=TRUE,"Restricted",""))),'
        + "_xlpm.filtered,FILTER(_xlpm.trade_label,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"))"
    )
    worksheet.write_formula(row, COL_TRADE, trade_formula)

    # -------------------------------------------------------------------------
    # Minimum contract label column
    # -------------------------------------------------------------------------
    min_formula = (
        "=LET("
        + roster_let_prefix()
        + '_xlpm.min_label,IF(tbl_salary_book_warehouse[is_min_contract]=TRUE,"MINIMUM",""),' 
        + "_xlpm.filtered,FILTER(_xlpm.min_label,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"))"
    )
    worksheet.write_formula(row, COL_MIN_LABEL, min_formula, roster_formats["min_label"])

    # -------------------------------------------------------------------------
    # Salary columns (cap_y0..cap_y5 or tax_y0..tax_y5 or apron_y0..apron_y5)
    # Mode-aware: use SelectedMode to pick the prefix
    # -------------------------------------------------------------------------
    for yi in range(6):
        sal_formula = (
            "=LET("
            + roster_let_prefix()
            + f'_xlpm.year_col,IF(SelectedMode="Cap",tbl_salary_book_warehouse[cap_y{yi}],'
            + f'IF(SelectedMode="Tax",tbl_salary_book_warehouse[tax_y{yi}],'
            + f"tbl_salary_book_warehouse[apron_y{yi}])),"
            + "_xlpm.filtered,FILTER(_xlpm.year_col,_xlpm.filter_cond,\"\"),"
            + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
            + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"))"
        )
        worksheet.write_formula(row, COL_CAP_Y0 + yi, sal_formula, roster_formats["money"])

    # -------------------------------------------------------------------------
    # % of cap column (SelectedYear amount / salary_cap_amount)
    # -------------------------------------------------------------------------
    pct_formula = (
        "=LET("
        + roster_let_prefix()
        + "_xlpm.filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "_xlpm.sorted_amt,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_roster_rows) + "),\"\"),"
        + "_xlpm.cap_limit,SUMIFS(tbl_system_values[salary_cap_amount],tbl_system_values[salary_year],SelectedYear),"
        + 'IF(_xlpm.sorted_amt="","",_xlpm.sorted_amt/_xlpm.cap_limit))'
    )
    worksheet.write_formula(row, COL_PCT_CAP, pct_formula, roster_formats["percent"])

    # Move past spill zone (40 rows allocated)
    row += num_roster_rows

    data_end_row = row - 1

    # Subtotal row for ROST bucket (selected year)
    worksheet.write(row, COL_NAME, "Roster Subtotal:", roster_formats["subtotal_label"])

    worksheet.write_formula(
        row,
        COL_CAP_Y0,
        f"={_salary_book_sumproduct(is_two_way='FALSE')}",
        roster_formats["subtotal"],
    )

    # Count of roster players with selected-year cap > 0
    worksheet.write_formula(
        row,
        COL_BUCKET,
        f"={_salary_book_countproduct('FALSE')}",
        roster_formats["subtotal_label"],
    )

    row += 2  # Blank row

    return row, data_start_row


def _write_twoway_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the two-way contracts section.

    Uses Excel 365 dynamic array formulas (FILTER, SORTBY, TAKE).
    Same pattern as roster section but filters for is_two_way = TRUE.

    Returns next row.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "TWO-WAY CONTRACTS", section_fmt)
    row += 1

    # Column headers - mode-aware year labels
    year_labels = [
        _mode_year_label(0),
        _mode_year_label(1),
        _mode_year_label(2),
        _mode_year_label(3),
        _mode_year_label(4),
        _mode_year_label(5),
    ]
    row = _write_column_headers(worksheet, row, roster_formats, year_labels)

    data_start_row = row

    # Two-way rows (fewer slots - typically max 3 per team)
    num_twoway_rows = 6

    # Helper to build the common LET prefix for two-way data extraction
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

    # -------------------------------------------------------------------------
    # Player Name column (spills down)
    # -------------------------------------------------------------------------
    name_formula = (
        "=LET("
        + twoway_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_twoway_rows) + "),\"\"))"
    )
    worksheet.write_formula(row, COL_NAME, name_formula)

    # -------------------------------------------------------------------------
    # Bucket column (2WAY for non-empty rows)
    # -------------------------------------------------------------------------
    bucket_formula = (
        "=LET("
        + twoway_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_twoway_rows) + "),\"\"),"
        + 'IF(_xlpm.names<>"","2WAY",""))'
    )
    worksheet.write_formula(row, COL_BUCKET, bucket_formula, roster_formats["bucket_2way"])

    # -------------------------------------------------------------------------
    # CountsTowardTotal column (Y - two-way contracts count toward cap totals per CBA)
    # -------------------------------------------------------------------------
    ct_total_formula = (
        "=LET("
        + twoway_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_twoway_rows) + "),\"\"),"
        + 'IF(_xlpm.names<>"","Y",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, ct_total_formula, roster_formats["counts_yes"])

    # -------------------------------------------------------------------------
    # CountsTowardRoster column (N - two-way does NOT count toward 15-player roster)
    # -------------------------------------------------------------------------
    ct_roster_formula = (
        "=LET("
        + twoway_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + "_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_twoway_rows) + "),\"\"),"
        + 'IF(_xlpm.names<>"","N",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_ROSTER, ct_roster_formula, roster_formats["counts_no"])

    # Option/Guarantee/Trade - empty for two-way contracts (they don't have these)
    worksheet.write(row, COL_OPTION, "")
    worksheet.write(row, COL_GUARANTEE, "")
    worksheet.write(row, COL_TRADE, "")
    worksheet.write(row, COL_MIN_LABEL, "")

    # -------------------------------------------------------------------------
    # Salary columns - mode-aware
    # -------------------------------------------------------------------------
    for yi in range(6):
        sal_formula = (
            "=LET("
            + twoway_let_prefix()
            + f'_xlpm.year_col,IF(SelectedMode="Cap",tbl_salary_book_warehouse[cap_y{yi}],'
            + f'IF(SelectedMode="Tax",tbl_salary_book_warehouse[tax_y{yi}],'
            + f"tbl_salary_book_warehouse[apron_y{yi}])),"
            + "_xlpm.filtered,FILTER(_xlpm.year_col,_xlpm.filter_cond,\"\"),"
            + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
            + "IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1)," + str(num_twoway_rows) + "),\"\"))"
        )
        worksheet.write_formula(row, COL_CAP_Y0 + yi, sal_formula, roster_formats["money"])

    # Move past spill zone (6 rows allocated)
    row += num_twoway_rows

    # Subtotal for two-way (selected year, mode-aware)
    worksheet.write(row, COL_NAME, "Two-Way Subtotal:", roster_formats["subtotal_label"])
    worksheet.write_formula(
        row,
        COL_CAP_Y0,
        f"={_salary_book_sumproduct(is_two_way='TRUE')}",
        roster_formats["subtotal"],
    )

    worksheet.write_formula(
        row,
        COL_BUCKET,
        f"={_salary_book_countproduct('TRUE')}",
        roster_formats["subtotal_label"],
    )

    row += 2

    return row


def _write_cap_holds_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the cap holds section (bucket = FA).

    Uses Excel 365 dynamic array formulas (FILTER, SORTBY, TAKE).
    Rows are spilled from a single formula that:
    1. FILTERs to SelectedTeam + SelectedYear + mode-aware amount > 0
    2. SORTBYs by mode-aware amount (DESC)
    3. TAKEs the first N rows (max 15)

    Returns next row.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "CAP HOLDS (Free Agent Rights)", section_fmt)
    row += 1

    # Note about formula-driven display
    worksheet.write(row, COL_BUCKET, "Dynamic array: cap holds for SelectedTeam sorted by SelectedYear amount (uses FILTER/SORTBY)", roster_formats["reconcile_label"])
    row += 1

    # Simplified column headers for holds - mode-aware amount header
    fmt = roster_formats["col_header"]
    worksheet.write(row, COL_BUCKET, "Bucket", fmt)
    worksheet.write(row, COL_COUNTS_TOTAL, "Ct$", fmt)
    worksheet.write(row, COL_COUNTS_ROSTER, "CtR", fmt)
    worksheet.write(row, COL_NAME, "Player", fmt)
    worksheet.write(row, COL_OPTION, "FA Type", fmt)
    worksheet.write(row, COL_GUARANTEE, "", fmt)
    worksheet.write(row, COL_TRADE, "Status", fmt)
    worksheet.write(row, COL_MIN_LABEL, "", fmt)
    # Mode-aware Amount header
    worksheet.write_formula(row, COL_CAP_Y0, '=SelectedMode&" Amount"', fmt)
    for yi in range(1, 6):
        worksheet.write(row, COL_CAP_Y0 + yi, "", fmt)
    worksheet.write(row, COL_PCT_CAP, "% Cap", fmt)
    row += 1

    data_start_row = row

    # Cap hold rows - using dynamic arrays
    num_hold_rows = 15

    # =========================================================================
    # Dynamic Array Formula: FILTER + SORTBY for cap holds
    # =========================================================================
    #
    # LET-based approach:
    #   mode_amt = IF(SelectedMode="Cap", cap_amount, IF(SelectedMode="Tax", tax_amount, apron_amount))
    #   filter_cond = (team_code = SelectedTeam) * (salary_year = SelectedYear) * (mode_amt > 0)
    #   filtered_col = FILTER(column, filter_cond, "")
    #   sorted_amounts = FILTER(mode_amt, filter_cond, 0)  -- for sort key
    #   result = TAKE(SORTBY(filtered_col, sorted_amounts, -1), num_hold_rows)

    def cap_holds_let_prefix() -> str:
        """Return LET prefix for cap holds filtering (mode-aware amount calculation)."""
        return (
            '_xlpm.mode_amt,IF(SelectedMode="Cap",tbl_cap_holds_warehouse[cap_amount],'
            'IF(SelectedMode="Tax",tbl_cap_holds_warehouse[tax_amount],'
            'tbl_cap_holds_warehouse[apron_amount])),'
            '_xlpm.filter_cond,(tbl_cap_holds_warehouse[team_code]=SelectedTeam)*'
            '(tbl_cap_holds_warehouse[salary_year]=SelectedYear)*(_xlpm.mode_amt>0),'
        )

    # -------------------------------------------------------------------------
    # Player Name column (spills down)
    # -------------------------------------------------------------------------
    name_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_cap_holds_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"))"
    )
    worksheet.write_formula(row, COL_NAME, name_formula)

    # -------------------------------------------------------------------------
    # Bucket column (FA for non-empty rows)
    # -------------------------------------------------------------------------
    bucket_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_cap_holds_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","FA",""))'
    )
    worksheet.write_formula(row, COL_BUCKET, bucket_formula, roster_formats["bucket_fa"])

    # -------------------------------------------------------------------------
    # CountsTowardTotal column (Y for non-empty)
    # -------------------------------------------------------------------------
    ct_total_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_cap_holds_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","Y",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, ct_total_formula, roster_formats["counts_yes"])

    # -------------------------------------------------------------------------
    # CountsTowardRoster column (N for FA - holds don't count toward roster)
    # -------------------------------------------------------------------------
    ct_roster_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_cap_holds_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","N",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_ROSTER, ct_roster_formula, roster_formats["counts_no"])

    # -------------------------------------------------------------------------
    # FA designation column (RFA/UFA/etc.)
    # -------------------------------------------------------------------------
    fa_type_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_cap_holds_warehouse[free_agent_designation_lk],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"))"
    )
    worksheet.write_formula(row, COL_OPTION, fa_type_formula)

    # Guarantee - empty for holds
    worksheet.write(row, COL_GUARANTEE, "")

    # -------------------------------------------------------------------------
    # FA status column
    # -------------------------------------------------------------------------
    fa_status_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_cap_holds_warehouse[free_agent_status_lk],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"))"
    )
    worksheet.write_formula(row, COL_TRADE, fa_status_formula)

    # Min label - empty for holds
    worksheet.write(row, COL_MIN_LABEL, "")

    # -------------------------------------------------------------------------
    # Amount column (mode-aware, spills down)
    # -------------------------------------------------------------------------
    amount_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"))"
    )
    worksheet.write_formula(row, COL_CAP_Y0, amount_formula, roster_formats["money"])

    # -------------------------------------------------------------------------
    # % of cap column
    # -------------------------------------------------------------------------
    pct_formula = (
        "=LET("
        + cap_holds_let_prefix()
        + "_xlpm.filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.sorted_amt,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_hold_rows}),\"\"),"
        + "_xlpm.cap_limit,SUMIFS(tbl_system_values[salary_cap_amount],tbl_system_values[salary_year],SelectedYear),"
        + 'IF(_xlpm.sorted_amt="","",_xlpm.sorted_amt/_xlpm.cap_limit))'
    )
    worksheet.write_formula(row, COL_PCT_CAP, pct_formula, roster_formats["percent"])

    # Move past spill zone
    row += num_hold_rows

    # Subtotal for holds - mode-aware (using LET + SUM(FILTER))
    worksheet.write(row, COL_NAME, "Holds Subtotal:", roster_formats["subtotal_label"])
    subtotal_formula = (
        "=LET("
        '_xlpm.mode_amt,IF(SelectedMode="Cap",tbl_cap_holds_warehouse[cap_amount],'
        'IF(SelectedMode="Tax",tbl_cap_holds_warehouse[tax_amount],'
        'tbl_cap_holds_warehouse[apron_amount])),'
        '_xlpm.filter_cond,(tbl_cap_holds_warehouse[team_code]=SelectedTeam)*'
        '(tbl_cap_holds_warehouse[salary_year]=SelectedYear)*(_xlpm.mode_amt>0),'
        'SUM(FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0)))'
    )
    worksheet.write_formula(row, COL_CAP_Y0, subtotal_formula, roster_formats["subtotal"])

    count_formula = (
        "=LET("
        '_xlpm.mode_amt,IF(SelectedMode="Cap",tbl_cap_holds_warehouse[cap_amount],'
        'IF(SelectedMode="Tax",tbl_cap_holds_warehouse[tax_amount],'
        'tbl_cap_holds_warehouse[apron_amount])),'
        '_xlpm.filter_cond,(tbl_cap_holds_warehouse[team_code]=SelectedTeam)*'
        '(tbl_cap_holds_warehouse[salary_year]=SelectedYear)*(_xlpm.mode_amt>0),'
        'ROWS(FILTER(tbl_cap_holds_warehouse[player_name],_xlpm.filter_cond,"")))'
    )
    worksheet.write_formula(row, COL_BUCKET, count_formula, roster_formats["subtotal_label"])

    row += 2

    return row


def _write_dead_money_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the dead money section (bucket = TERM).

    Uses Excel 365 dynamic array formulas (FILTER, SORTBY, TAKE).
    Rows are spilled from a single formula that:
    1. FILTERs to SelectedTeam + SelectedYear + mode-aware amount > 0
    2. SORTBYs by mode-aware amount (DESC)
    3. TAKEs the first N rows (max 10)

    Returns next row.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "DEAD MONEY (Terminated Contracts)", section_fmt)
    row += 1

    # Note about formula-driven display
    worksheet.write(row, COL_BUCKET, "Dynamic array: dead money for SelectedTeam sorted by SelectedYear amount (uses FILTER/SORTBY)", roster_formats["reconcile_label"])
    row += 1

    # Column headers - mode-aware amount header
    fmt = roster_formats["col_header"]
    worksheet.write(row, COL_BUCKET, "Bucket", fmt)
    worksheet.write(row, COL_COUNTS_TOTAL, "Ct$", fmt)
    worksheet.write(row, COL_COUNTS_ROSTER, "CtR", fmt)
    worksheet.write(row, COL_NAME, "Player", fmt)
    worksheet.write(row, COL_OPTION, "", fmt)
    worksheet.write(row, COL_GUARANTEE, "", fmt)
    worksheet.write(row, COL_TRADE, "Waive Date", fmt)
    worksheet.write(row, COL_MIN_LABEL, "", fmt)
    # Mode-aware Amount header
    worksheet.write_formula(row, COL_CAP_Y0, '=SelectedMode&" Amount"', fmt)
    for yi in range(1, 6):
        worksheet.write(row, COL_CAP_Y0 + yi, "", fmt)
    worksheet.write(row, COL_PCT_CAP, "% Cap", fmt)
    row += 1

    data_start_row = row

    # Dead money rows - using dynamic arrays
    num_dead_rows = 10

    # =========================================================================
    # Dynamic Array Formula: FILTER + SORTBY for dead money
    # =========================================================================
    #
    # LET-based approach:
    #   mode_amt = IF(SelectedMode="Cap", cap_value, IF(SelectedMode="Tax", tax_value, apron_value))
    #   filter_cond = (team_code = SelectedTeam) * (salary_year = SelectedYear) * (mode_amt > 0)
    #   filtered_col = FILTER(column, filter_cond, "")
    #   sorted_amounts = FILTER(mode_amt, filter_cond, 0)  -- for sort key
    #   result = TAKE(SORTBY(filtered_col, sorted_amounts, -1), num_dead_rows)

    def dead_money_let_prefix() -> str:
        """Return LET prefix for dead money filtering (mode-aware amount calculation)."""
        return (
            '_xlpm.mode_amt,IF(SelectedMode="Cap",tbl_dead_money_warehouse[cap_value],'
            'IF(SelectedMode="Tax",tbl_dead_money_warehouse[tax_value],'
            'tbl_dead_money_warehouse[apron_value])),'
            '_xlpm.filter_cond,(tbl_dead_money_warehouse[team_code]=SelectedTeam)*'
            '(tbl_dead_money_warehouse[salary_year]=SelectedYear)*(_xlpm.mode_amt>0),'
        )

    # -------------------------------------------------------------------------
    # Player Name column (spills down)
    # -------------------------------------------------------------------------
    name_formula = (
        "=LET("
        + dead_money_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_dead_money_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_dead_rows}),\"\"))"
    )
    worksheet.write_formula(row, COL_NAME, name_formula)

    # -------------------------------------------------------------------------
    # Bucket column (TERM for non-empty rows)
    # -------------------------------------------------------------------------
    bucket_formula = (
        "=LET("
        + dead_money_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_dead_money_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_dead_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","TERM",""))'
    )
    worksheet.write_formula(row, COL_BUCKET, bucket_formula, roster_formats["bucket_term"])

    # -------------------------------------------------------------------------
    # CountsTowardTotal column (Y for non-empty)
    # -------------------------------------------------------------------------
    ct_total_formula = (
        "=LET("
        + dead_money_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_dead_money_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_dead_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","Y",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, ct_total_formula, roster_formats["counts_yes"])

    # -------------------------------------------------------------------------
    # CountsTowardRoster column (N for TERM - dead money doesn't count toward roster)
    # -------------------------------------------------------------------------
    ct_roster_formula = (
        "=LET("
        + dead_money_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_dead_money_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_dead_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","N",""))'
    )
    worksheet.write_formula(row, COL_COUNTS_ROSTER, ct_roster_formula, roster_formats["counts_no"])

    # Option - empty for dead money
    worksheet.write(row, COL_OPTION, "")

    # Guarantee - empty for dead money
    worksheet.write(row, COL_GUARANTEE, "")

    # -------------------------------------------------------------------------
    # Waive Date column (spills down)
    # -------------------------------------------------------------------------
    waive_date_formula = (
        "=LET("
        + dead_money_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_dead_money_warehouse[waive_date],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_dead_rows}),\"\"))"
    )
    worksheet.write_formula(row, COL_TRADE, waive_date_formula)

    # Min label - empty for dead money
    worksheet.write(row, COL_MIN_LABEL, "")

    # -------------------------------------------------------------------------
    # Amount column (mode-aware, spills down)
    # -------------------------------------------------------------------------
    amount_formula = (
        "=LET("
        + dead_money_let_prefix()
        + "_xlpm.filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_dead_rows}),\"\"))"
    )
    worksheet.write_formula(row, COL_CAP_Y0, amount_formula, roster_formats["money"])

    # -------------------------------------------------------------------------
    # % of cap column
    # -------------------------------------------------------------------------
    pct_formula = (
        "=LET("
        + dead_money_let_prefix()
        + "_xlpm.filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sorted_filtered,FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0),"
        + f"_xlpm.sorted_amt,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sorted_filtered,-1),{num_dead_rows}),\"\"),"
        + "_xlpm.cap_limit,SUMIFS(tbl_system_values[salary_cap_amount],tbl_system_values[salary_year],SelectedYear),"
        + 'IF(_xlpm.sorted_amt="","",_xlpm.sorted_amt/_xlpm.cap_limit))'
    )
    worksheet.write_formula(row, COL_PCT_CAP, pct_formula, roster_formats["percent"])

    # Move past spill zone
    row += num_dead_rows

    # Subtotal for dead money - mode-aware (using LET + SUM(FILTER))
    worksheet.write(row, COL_NAME, "Dead Money Subtotal:", roster_formats["subtotal_label"])
    subtotal_formula = (
        "=LET("
        '_xlpm.mode_amt,IF(SelectedMode="Cap",tbl_dead_money_warehouse[cap_value],'
        'IF(SelectedMode="Tax",tbl_dead_money_warehouse[tax_value],'
        'tbl_dead_money_warehouse[apron_value])),'
        '_xlpm.filter_cond,(tbl_dead_money_warehouse[team_code]=SelectedTeam)*'
        '(tbl_dead_money_warehouse[salary_year]=SelectedYear)*(_xlpm.mode_amt>0),'
        'SUM(FILTER(_xlpm.mode_amt,_xlpm.filter_cond,0)))'
    )
    worksheet.write_formula(row, COL_CAP_Y0, subtotal_formula, roster_formats["subtotal"])

    count_formula = (
        "=LET("
        '_xlpm.mode_amt,IF(SelectedMode="Cap",tbl_dead_money_warehouse[cap_value],'
        'IF(SelectedMode="Tax",tbl_dead_money_warehouse[tax_value],'
        'tbl_dead_money_warehouse[apron_value])),'
        '_xlpm.filter_cond,(tbl_dead_money_warehouse[team_code]=SelectedTeam)*'
        '(tbl_dead_money_warehouse[salary_year]=SelectedYear)*(_xlpm.mode_amt>0),'
        'ROWS(FILTER(tbl_dead_money_warehouse[player_name],_xlpm.filter_cond,"")))'
    )
    worksheet.write_formula(row, COL_BUCKET, count_formula, roster_formats["subtotal_label"])

    row += 2

    return row


def _write_generated_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the GENERATED section (fill rows for roster assumptions).

    This section generates fill rows when RosterFillTarget is 12/14/15.
    The number of rows generated = RosterFillTarget - current_roster_count.

    Per mental-models-and-design-principles.md:
    - Generated rows must appear as GENERATED rows (visible bucket label)
    - They must be toggleable (RosterFillTarget=0 to disable)
    - They must be labeled as assumptions (not facts)

    Per the backlog:
    - RosterFillType controls the salary amount:
      - "Rookie Min" = rookie 1st-round min (pick 30) from tbl_rookie_scale
      - "Vet Min" = 0-year vet minimum from tbl_minimum_scale
      - "Cheapest" = MIN(rookie_min, vet_min)
    - Generated rows have Ct$=Y (count toward totals), CtR=Y (count toward roster)
    - Yellow/gold styling to distinguish from real contracts

    The section is controlled by RosterFillTarget toggle:
    - When 0 (default): section is collapsed with a message
    - When 12/14/15: shows generated fill rows

    Returns next row.
    """
    # Create special format for generated rows (gold/amber background)
    generated_section_fmt = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
        "bottom": 1,
    })

    generated_row_fmt = workbook.add_format({
        "bg_color": "#FFFBEB",  # amber-50
        "font_color": "#78350F",  # amber-900
    })

    generated_money_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "bg_color": "#FFFBEB",  # amber-50
        "font_color": "#78350F",  # amber-900
    })

    generated_badge_fmt = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#B45309",  # amber-700
        "italic": True,
        "bg_color": "#FFFBEB",  # amber-50
    })

    generated_counts_fmt = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#166534",  # green-800
        "bold": True,
        "bg_color": "#FFFBEB",  # amber-50
    })

    # Section header
    worksheet.merge_range(
        row, COL_BUCKET, row, COL_PCT_CAP,
        "GENERATED (Roster Fill Assumptions - policy-driven, NOT authoritative)",
        generated_section_fmt
    )
    row += 1

    # Explanatory note
    note_fmt = workbook.add_format({
        "italic": True,
        "font_size": 9,
        "font_color": "#92400E",  # amber-800
        "bg_color": "#FFFBEB",  # amber-50
    })
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "", note_fmt)
    worksheet.write(
        row, COL_BUCKET,
        "Generated fill rows based on RosterFillTarget/RosterFillType. Set RosterFillTarget=0 to disable.",
        note_fmt
    )
    row += 1

    # Conditional header row
    # When RosterFillTarget = 0, show "disabled" message; otherwise show column headers
    fmt = roster_formats["col_header"]

    worksheet.write_formula(
        row, COL_BUCKET,
        '=IF(RosterFillTarget=0,"RosterFillTarget=0 (disabled)","Bucket")',
        fmt
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, '=IF(RosterFillTarget=0,"","Ct$")', fmt)
    worksheet.write_formula(row, COL_COUNTS_ROSTER, '=IF(RosterFillTarget=0,"","CtR")', fmt)
    worksheet.write_formula(row, COL_NAME, '=IF(RosterFillTarget=0,"","Name")', fmt)
    worksheet.write_formula(row, COL_OPTION, '=IF(RosterFillTarget=0,"","")', fmt)
    worksheet.write_formula(row, COL_GUARANTEE, '=IF(RosterFillTarget=0,"","")', fmt)
    worksheet.write_formula(row, COL_TRADE, '=IF(RosterFillTarget=0,"","")', fmt)
    worksheet.write_formula(row, COL_MIN_LABEL, '=IF(RosterFillTarget=0,"","Type")', fmt)

    # Year column headers (show year when active)
    for yi in range(6):
        worksheet.write_formula(
            row, COL_CAP_Y0 + yi,
            f'=IF(RosterFillTarget=0,"",SelectedMode&" "&(MetaBaseYear+{yi}))',
            fmt
        )
    worksheet.write_formula(row, COL_PCT_CAP, '=IF(RosterFillTarget=0,"","Note")', fmt)
    row += 1

    # =========================================================================
    # Fill amount formulas
    # =========================================================================
    # We need to compute the fill salary based on RosterFillType:
    # - "Rookie Min": look up rookie scale for SelectedYear, pick 30, year 1 salary
    # - "Vet Min": look up minimum_scale for SelectedYear, years_of_service = 0
    # - "Cheapest": MIN of the two above
    #
    # Formula references:
    # - tbl_rookie_scale: columns salary_year, pick_number, salary_year_1
    # - tbl_minimum_scale: columns salary_year, years_of_service, minimum_salary_amount
    #
    # NOTE on mode-awareness (Cap/Tax/Apron):
    # ----------------------------------------
    # Fill amounts do NOT vary by SelectedMode. This is intentional and correct:
    #
    # 1. Minimum salary contracts (both rookie and veteran) count the SAME toward
    #    cap, tax, and apron thresholds. The CBA defines a single minimum salary
    #    amount that is mode-independent.
    #
    # 2. The distinction between cap/tax/apron modes affects how thresholds are
    #    calculated and which limits apply, NOT the contract salary amounts.
    #
    # 3. In salary_book_warehouse, minimum contracts have identical values in
    #    cap_y*, tax_y*, and apron_y* columns (no mode-specific adjustments).
    #
    # Therefore, the fill_amount_formula uses the base salary values from
    # tbl_rookie_scale and tbl_minimum_scale without mode branching.

    # Rookie min formula (pick 30, year 1 salary for SelectedYear)
    rookie_min_formula = (
        "SUMIFS(tbl_rookie_scale[salary_year_1],"
        "tbl_rookie_scale[salary_year],SelectedYear,"
        "tbl_rookie_scale[pick_number],30)"
    )

    # Vet min formula (0 years of service for SelectedYear)
    vet_min_formula = (
        "SUMIFS(tbl_minimum_scale[minimum_salary_amount],"
        "tbl_minimum_scale[salary_year],SelectedYear,"
        "tbl_minimum_scale[years_of_service],0)"
    )

    # Fill amount formula (based on RosterFillType)
    fill_amount_formula = (
        f'IF(RosterFillType="Rookie Min",{rookie_min_formula},'
        f'IF(RosterFillType="Vet Min",{vet_min_formula},'
        f'MIN({rookie_min_formula},{vet_min_formula})))'  # Cheapest = MIN
    )

    # =========================================================================
    # Current roster count formula
    # =========================================================================
    # Count of roster players (non-two-way) with selected-year cap > 0
    cap_choose_expr = _salary_book_choose_mode_aware()
    current_roster_count_formula = (
        "SUMPRODUCT(--(tbl_salary_book_warehouse[team_code]=SelectedTeam),"
        "--(tbl_salary_book_warehouse[is_two_way]=FALSE),"
        f"--({cap_choose_expr}>0))"
    )

    # Number of fill rows needed = MAX(0, RosterFillTarget - current_roster_count)
    fill_rows_needed_formula = f"MAX(0,RosterFillTarget-{current_roster_count_formula})"

    # =========================================================================
    # Generated rows (up to 15 slots - max possible fills)
    # =========================================================================
    num_generated_rows = 15  # Maximum possible fill slots

    for i in range(1, num_generated_rows + 1):
        # This row is visible if: RosterFillTarget > 0 AND i <= fill_rows_needed
        row_active_formula = f"AND(RosterFillTarget>0,{i}<={fill_rows_needed_formula})"

        # Bucket (GENERATED)
        bucket_formula = f'=IF({row_active_formula},"GEN","")'
        worksheet.write_formula(row, COL_BUCKET, bucket_formula, generated_badge_fmt)

        # CountsTowardTotal: GENERATED rows count toward total (Y)
        counts_total_formula = f'=IF({row_active_formula},"Y","")'
        worksheet.write_formula(row, COL_COUNTS_TOTAL, counts_total_formula, generated_counts_fmt)

        # CountsTowardRoster: GENERATED rows count toward roster (Y)
        counts_roster_formula = f'=IF({row_active_formula},"Y","")'
        worksheet.write_formula(row, COL_COUNTS_ROSTER, counts_roster_formula, generated_counts_fmt)

        # Name (show fill type)
        name_formula = f'=IF({row_active_formula},"Fill Slot #"&{i}&" ("&RosterFillType&")","")'
        worksheet.write_formula(row, COL_NAME, name_formula, generated_row_fmt)

        # Option/Guarantee/Trade - empty for generated rows
        worksheet.write_formula(row, COL_OPTION, f'=IF({row_active_formula},"","")', generated_row_fmt)
        worksheet.write_formula(row, COL_GUARANTEE, f'=IF({row_active_formula},"","")', generated_row_fmt)
        worksheet.write_formula(row, COL_TRADE, f'=IF({row_active_formula},"","")', generated_row_fmt)

        # Type label (FILL)
        type_formula = f'=IF({row_active_formula},"FILL","")'
        worksheet.write_formula(row, COL_MIN_LABEL, type_formula, generated_badge_fmt)

        # Salary columns - show fill amount for y0 (SelectedYear relative offset)
        # Only y0 gets the fill amount (single-year assumption)
        for yi in range(6):
            if yi == 0:
                # Selected year gets the fill amount (offset 0 = MetaBaseYear)
                # But we want it to appear in the column matching SelectedYear
                # Since columns are fixed (cap_y0..cap_y5 = MetaBaseYear..+5),
                # we show fill amount only when the column year matches SelectedYear
                sal_formula = (
                    f'=IF(AND({row_active_formula},(MetaBaseYear+{yi})=SelectedYear),'
                    f'{fill_amount_formula},"")'
                )
            else:
                # Future years also check if they match SelectedYear
                sal_formula = (
                    f'=IF(AND({row_active_formula},(MetaBaseYear+{yi})=SelectedYear),'
                    f'{fill_amount_formula},"")'
                )
            worksheet.write_formula(row, COL_CAP_Y0 + yi, sal_formula, generated_money_fmt)

        # Note column
        note_formula = f'=IF({row_active_formula},"Assumption","")'
        worksheet.write_formula(row, COL_PCT_CAP, note_formula, generated_badge_fmt)

        row += 1

    # =========================================================================
    # Subtotals row
    # =========================================================================
    # Show count and total for generated rows
    worksheet.write_formula(
        row, COL_NAME,
        f'=IF(RosterFillTarget>0,"Generated Fill Total:","")',
        roster_formats["subtotal_label"]
    )

    # Total fill amount = fill_rows_needed * fill_amount
    total_fill_formula = (
        f'=IF(RosterFillTarget>0,'
        f'{fill_rows_needed_formula}*{fill_amount_formula},"")'
    )
    worksheet.write_formula(row, COL_CAP_Y0, total_fill_formula, roster_formats["subtotal"])

    # Count of generated rows
    worksheet.write_formula(
        row, COL_BUCKET,
        f'=IF(RosterFillTarget>0,{fill_rows_needed_formula},"")',
        roster_formats["subtotal_label"]
    )

    row += 2

    return row


def _write_exists_only_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the EXISTS_ONLY section (non-counting rows for analyst reference).

    This section shows players who:
    - Belong to SelectedTeam
    - Have $0 in SelectedYear (across all modes: cap/tax/apron all zero)
    - But have non-zero amounts in a future year

    These rows "exist" in the salary book but do NOT count toward current year totals.
    They're useful for planning context (e.g., future-year commitments, option years).

    The section is controlled by ShowExistsOnlyRows toggle:
    - When "No" (default): shows a collapsed message explaining the section is hidden
    - When "Yes": shows the full listing of exists-only rows

    Per the blueprint (mental-models-and-design-principles.md):
    - EXISTS_ONLY rows are labeled as "visible artifacts that do not count (for reference only)"
    - Ct$ = N, CtR = N (never counted)

    Uses Excel 365 dynamic arrays: LET, FILTER, SORTBY, TAKE, BYROW (or MAP for per-row computation).
    The future_total is computed per-player as the sum of future-year amounts (any mode).

    Returns next row.
    """
    section_fmt = roster_formats["section_header_exists_only"]

    # Section header with explanatory text
    worksheet.merge_range(
        row, COL_BUCKET, row, COL_PCT_CAP,
        "EXISTS_ONLY (Future-Year Contracts - does NOT count in SelectedYear)",
        section_fmt
    )
    row += 1

    # Explanatory note
    note_fmt = workbook.add_format({
        "italic": True,
        "font_size": 9,
        "font_color": "#6B7280",  # gray-500
    })
    worksheet.write(
        row, COL_BUCKET,
        "Players with $0 this year but future-year amounts. For analyst reference only - excluded from totals.",
        note_fmt
    )
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "", note_fmt)
    worksheet.write(
        row, COL_BUCKET,
        "Players with $0 this year but future-year amounts. For analyst reference only - excluded from totals.",
        note_fmt
    )
    row += 1

    # Note about dynamic arrays
    worksheet.write(row, COL_BUCKET, "Dynamic array: EXISTS_ONLY players filtered by future-year amounts (uses LET/FILTER/SORTBY)", roster_formats["reconcile_label"])
    row += 1

    # Column headers (only shown when ShowExistsOnlyRows = "Yes")
    fmt = roster_formats["col_header"]
    hidden_text_fmt = workbook.add_format({
        "italic": True,
        "font_color": "#9CA3AF",  # gray-400
        "font_size": 9,
    })

    # Write conditional header row
    # When ShowExistsOnlyRows = "Yes", show column headers; otherwise show toggle hint
    worksheet.write_formula(
        row, COL_BUCKET,
        '=IF(ShowExistsOnlyRows="Yes","Bucket","Set ShowExistsOnlyRows=Yes to display")',
        fmt
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, '=IF(ShowExistsOnlyRows="Yes","Ct$","")', fmt)
    worksheet.write_formula(row, COL_COUNTS_ROSTER, '=IF(ShowExistsOnlyRows="Yes","CtR","")', fmt)
    worksheet.write_formula(row, COL_NAME, '=IF(ShowExistsOnlyRows="Yes","Name","")', fmt)
    worksheet.write_formula(row, COL_OPTION, '=IF(ShowExistsOnlyRows="Yes","","")', fmt)
    worksheet.write_formula(row, COL_GUARANTEE, '=IF(ShowExistsOnlyRows="Yes","","")', fmt)
    worksheet.write_formula(row, COL_TRADE, '=IF(ShowExistsOnlyRows="Yes","","")', fmt)
    worksheet.write_formula(row, COL_MIN_LABEL, '=IF(ShowExistsOnlyRows="Yes","Future Total","")', fmt)

    # Year column headers (show year when active)
    for yi in range(6):
        worksheet.write_formula(
            row, COL_CAP_Y0 + yi,
            f'=IF(ShowExistsOnlyRows="Yes",SelectedMode&" "&(MetaBaseYear+{yi}),"")',
            fmt
        )
    worksheet.write_formula(row, COL_PCT_CAP, '=IF(ShowExistsOnlyRows="Yes","Note","")', fmt)
    row += 1

    # =========================================================================
    # Dynamic Array Formula: LET + FILTER + SORTBY for EXISTS_ONLY rows
    # =========================================================================
    #
    # Design: We use a single spilling formula per column that:
    # 1. Computes per-row "current year amount" (all modes must be zero)
    # 2. Computes per-row "future total" (sum of future years in any mode)
    # 3. FILTERs to SelectedTeam + current=0 + future>0
    # 4. SORTBYs by future_total (DESC) - biggest future commitments first
    # 5. TAKEs first N rows
    #
    # The future_total calculation uses CHOOSE with (SelectedYear-MetaBaseYear+1) to determine
    # which years are "future" relative to SelectedYear.

    num_exists_rows = 15  # Allocate slots for exists-only rows

    # -------------------------------------------------------------------------
    # LET prefix for EXISTS_ONLY filtering
    # -------------------------------------------------------------------------
    # We need to compute:
    # - curr_cap, curr_tax, curr_apron: selected year amounts (all must be 0)
    # - future_cap, future_tax, future_apron: sum of future-year amounts per mode
    # - future_total: future_cap + future_tax + future_apron (for filter criterion)
    # - future_mode_aware: mode-specific future sum (for sorting)
    # - filter_cond: team match AND all curr=0 AND future_total>0
    #
    # For the future sum, we use CHOOSE with (SelectedYear-MetaBaseYear+1):
    # - (SelectedYear-MetaBaseYear+1)=1 (base year): future = y1+y2+y3+y4+y5
    # - (SelectedYear-MetaBaseYear+1)=2 (base+1): future = y2+y3+y4+y5
    # - etc.

    def exists_only_let_prefix() -> str:
        """Return LET prefix for EXISTS_ONLY filtering (computes current and future amounts)."""
        # Current year amounts per mode (using CHOOSE with (SelectedYear-MetaBaseYear+1))
        cap_curr = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
        tax_curr = ",".join(f"tbl_salary_book_warehouse[tax_y{i}]" for i in range(6))
        apron_curr = ",".join(f"tbl_salary_book_warehouse[apron_y{i}]" for i in range(6))

        # Future year sums per mode (CHOOSE returns sum of years after selected)
        # For each starting index, sum remaining years
        def future_choose(prefix: str) -> str:
            sums = []
            for start_idx in range(6):
                if start_idx >= 5:
                    sums.append("0")  # Year 5 has no future
                else:
                    cols = "+".join(f"tbl_salary_book_warehouse[{prefix}_y{j}]" for j in range(start_idx + 1, 6))
                    sums.append(f"({cols})")
            return f"CHOOSE((SelectedYear-MetaBaseYear+1),{','.join(sums)})"

        return (
            # Current year amounts per mode
            f"_xlpm.curr_cap,CHOOSE((SelectedYear-MetaBaseYear+1),{cap_curr}),"
            f"_xlpm.curr_tax,CHOOSE((SelectedYear-MetaBaseYear+1),{tax_curr}),"
            f"_xlpm.curr_apron,CHOOSE((SelectedYear-MetaBaseYear+1),{apron_curr}),"
            # Future year sums per mode
            f"_xlpm.future_cap,{future_choose('cap')},"
            f"_xlpm.future_tax,{future_choose('tax')},"
            f"_xlpm.future_apron,{future_choose('apron')},"
            # Combined future total (any mode) - used for filter criterion
            "_xlpm.future_total,_xlpm.future_cap+_xlpm.future_tax+_xlpm.future_apron,"
            # Mode-aware future sum - used for sorting/display
            '_xlpm.future_mode,IF(SelectedMode="Cap",_xlpm.future_cap,IF(SelectedMode="Tax",_xlpm.future_tax,_xlpm.future_apron)),'
            # Filter condition: team match AND all current = 0 AND future > 0
            "_xlpm.filter_cond,(tbl_salary_book_warehouse[team_code]=SelectedTeam)*(_xlpm.curr_cap=0)*(_xlpm.curr_tax=0)*(_xlpm.curr_apron=0)*(_xlpm.future_total>0),"
        )

    # -------------------------------------------------------------------------
    # Player Name column (spills down)
    # -------------------------------------------------------------------------
    # When ShowExistsOnlyRows="No", returns empty array; otherwise spills names
    name_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",LET('
        + exists_only_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sort_key,FILTER(_xlpm.future_mode,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sort_key,-1),{num_exists_rows}),\"\")))"
    )
    worksheet.write_formula(row, COL_NAME, name_formula)

    # -------------------------------------------------------------------------
    # Bucket column (EXISTS for non-empty rows)
    # -------------------------------------------------------------------------
    bucket_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",LET('
        + exists_only_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sort_key,FILTER(_xlpm.future_mode,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sort_key,-1),{num_exists_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","EXISTS","")))'
    )
    worksheet.write_formula(row, COL_BUCKET, bucket_formula, roster_formats["bucket_exists_only"])

    # -------------------------------------------------------------------------
    # CountsTowardTotal column (N for EXISTS_ONLY - never counts)
    # -------------------------------------------------------------------------
    ct_total_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",LET('
        + exists_only_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sort_key,FILTER(_xlpm.future_mode,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sort_key,-1),{num_exists_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","N","")))'
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, ct_total_formula, roster_formats["counts_no"])

    # -------------------------------------------------------------------------
    # CountsTowardRoster column (N for EXISTS_ONLY - never counts)
    # -------------------------------------------------------------------------
    ct_roster_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",LET('
        + exists_only_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sort_key,FILTER(_xlpm.future_mode,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sort_key,-1),{num_exists_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","N","")))'
    )
    worksheet.write_formula(row, COL_COUNTS_ROSTER, ct_roster_formula, roster_formats["counts_no"])

    # Option/Guarantee/Trade - empty for EXISTS_ONLY (these are future contracts)
    worksheet.write(row, COL_OPTION, "")
    worksheet.write(row, COL_GUARANTEE, "")
    worksheet.write(row, COL_TRADE, "")

    # -------------------------------------------------------------------------
    # Future Total column (shows mode-aware future sum for context)
    # -------------------------------------------------------------------------
    future_total_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",LET('
        + exists_only_let_prefix()
        + "_xlpm.filtered,FILTER(_xlpm.future_mode,_xlpm.filter_cond,\"\"),"
        + "_xlpm.sort_key,FILTER(_xlpm.future_mode,_xlpm.filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sort_key,-1),{num_exists_rows}),\"\")))"
    )
    worksheet.write_formula(row, COL_MIN_LABEL, future_total_formula, roster_formats["money"])

    # -------------------------------------------------------------------------
    # Salary columns - show all years (mode-aware) so analyst can see future money
    # -------------------------------------------------------------------------
    for yi in range(6):
        sal_formula = (
            '=IF(ShowExistsOnlyRows<>"Yes","",LET('
            + exists_only_let_prefix()
            + f'_xlpm.year_col,IF(SelectedMode="Cap",tbl_salary_book_warehouse[cap_y{yi}],'
            + f'IF(SelectedMode="Tax",tbl_salary_book_warehouse[tax_y{yi}],'
            + f"tbl_salary_book_warehouse[apron_y{yi}])),"
            + "_xlpm.filtered,FILTER(_xlpm.year_col,_xlpm.filter_cond,\"\"),"
            + "_xlpm.sort_key,FILTER(_xlpm.future_mode,_xlpm.filter_cond,0),"
            + f"IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sort_key,-1),{num_exists_rows}),\"\")))"
        )
        worksheet.write_formula(row, COL_CAP_Y0 + yi, sal_formula, roster_formats["money"])

    # -------------------------------------------------------------------------
    # Note column - display "Future $" for non-empty rows
    # -------------------------------------------------------------------------
    note_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",LET('
        + exists_only_let_prefix()
        + "_xlpm.filtered,FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,\"\"),"
        + "_xlpm.sort_key,FILTER(_xlpm.future_mode,_xlpm.filter_cond,0),"
        + f"_xlpm.names,IFNA(TAKE(SORTBY(_xlpm.filtered,_xlpm.sort_key,-1),{num_exists_rows}),\"\"),"
        + 'IF(_xlpm.names<>"","Future $","")))'
    )
    worksheet.write_formula(row, COL_PCT_CAP, note_formula, hidden_text_fmt)

    # Move past spill zone
    row += num_exists_rows

    # -------------------------------------------------------------------------
    # Count of exists-only rows (informational only, not part of totals)
    # -------------------------------------------------------------------------
    # Using LET + SUM(FILTER) pattern instead of SUMPRODUCT
    count_label_formula = '=IF(ShowExistsOnlyRows="Yes","Exists-Only Count:","")'
    worksheet.write_formula(row, COL_NAME, count_label_formula, roster_formats["subtotal_label"])

    # Count formula using LET + ROWS(FILTER)
    count_value_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",LET('
        + exists_only_let_prefix()
        + 'ROWS(FILTER(tbl_salary_book_warehouse[player_name],_xlpm.filter_cond,""))))'
    )
    worksheet.write_formula(row, COL_BUCKET, count_value_formula, roster_formats["subtotal_label"])

    row += 2

    return row


def _write_reconciliation_block(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the reconciliation block comparing grid sums to warehouse totals.

    This is the critical section that proves the ledger is trustworthy.
    Reconciliation is mode-aware: compares cap/tax/apron based on SelectedMode.

    Returns next row.
    """
    reconcile_header = roster_formats["reconcile_header"]
    label_fmt = roster_formats["reconcile_label"]
    value_fmt = roster_formats["reconcile_value"]

    # Section header - mode-aware
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "", reconcile_header)
    worksheet.write_formula(
        row, COL_BUCKET,
        '="RECONCILIATION ("&SelectedMode&" mode vs DATA_team_salary_warehouse)"',
        reconcile_header
    )
    row += 1
    row += 1  # Blank row

    # Column labels
    worksheet.write(row, COL_NAME, "", label_fmt)
    worksheet.write(row, COL_CAP_Y0, "Grid Sum", roster_formats["col_header"])
    worksheet.write(row, COL_CAP_Y1, "Warehouse", roster_formats["col_header"])
    worksheet.write(row, COL_CAP_Y2, "Delta", roster_formats["col_header"])
    row += 1

    # Define the bucket comparisons - mode-aware
    # Grid formulas use _salary_book_sumproduct which is already mode-aware
    # Warehouse lookups need to use the mode-appropriate column

    # Mode-aware SUMIFS helper for cap_holds
    cap_holds_mode_sumif = (
        'IF(SelectedMode="Cap",'
        'SUMIFS(tbl_cap_holds_warehouse[cap_amount],tbl_cap_holds_warehouse[team_code],SelectedTeam,tbl_cap_holds_warehouse[salary_year],SelectedYear),'
        'IF(SelectedMode="Tax",'
        'SUMIFS(tbl_cap_holds_warehouse[tax_amount],tbl_cap_holds_warehouse[team_code],SelectedTeam,tbl_cap_holds_warehouse[salary_year],SelectedYear),'
        'SUMIFS(tbl_cap_holds_warehouse[apron_amount],tbl_cap_holds_warehouse[team_code],SelectedTeam,tbl_cap_holds_warehouse[salary_year],SelectedYear)))'
    )

    # Mode-aware SUMIFS helper for dead_money
    dead_money_mode_sumif = (
        'IF(SelectedMode="Cap",'
        'SUMIFS(tbl_dead_money_warehouse[cap_value],tbl_dead_money_warehouse[team_code],SelectedTeam,tbl_dead_money_warehouse[salary_year],SelectedYear),'
        'IF(SelectedMode="Tax",'
        'SUMIFS(tbl_dead_money_warehouse[tax_value],tbl_dead_money_warehouse[team_code],SelectedTeam,tbl_dead_money_warehouse[salary_year],SelectedYear),'
        'SUMIFS(tbl_dead_money_warehouse[apron_value],tbl_dead_money_warehouse[team_code],SelectedTeam,tbl_dead_money_warehouse[salary_year],SelectedYear)))'
    )

    # Mode-aware warehouse bucket column lookup
    # For each bucket, we pick cap_*/tax_*/apron_* based on SelectedMode
    def warehouse_bucket_formula(bucket: str) -> str:
        """Generate mode-aware SUMIFS for a warehouse bucket."""
        return (
            f'IF(SelectedMode="Cap",'
            f'SUMIFS(tbl_team_salary_warehouse[cap_{bucket}],tbl_team_salary_warehouse[team_code],SelectedTeam,tbl_team_salary_warehouse[salary_year],SelectedYear),'
            f'IF(SelectedMode="Tax",'
            f'SUMIFS(tbl_team_salary_warehouse[tax_{bucket}],tbl_team_salary_warehouse[team_code],SelectedTeam,tbl_team_salary_warehouse[salary_year],SelectedYear),'
            f'SUMIFS(tbl_team_salary_warehouse[apron_{bucket}],tbl_team_salary_warehouse[team_code],SelectedTeam,tbl_team_salary_warehouse[salary_year],SelectedYear)))'
        )

    buckets = [
        (
            "Roster (ROST)",
            "rost",
            _salary_book_sumproduct(is_two_way="FALSE"),
        ),
        (
            "Two-Way (2WAY)",
            "2way",
            _salary_book_sumproduct(is_two_way="TRUE"),
        ),
        (
            "Holds (FA)",
            "fa",
            cap_holds_mode_sumif,
        ),
        (
            "Dead Money (TERM)",
            "term",
            dead_money_mode_sumif,
        ),
    ]

    for label, bucket_suffix, grid_formula in buckets:
        worksheet.write(row, COL_NAME, label, label_fmt)

        # Grid sum (from our formulas above - already mode-aware)
        grid_cell = f"={grid_formula}"
        worksheet.write_formula(row, COL_CAP_Y0, grid_cell, value_fmt)

        # Warehouse value - mode-aware bucket lookup
        warehouse_formula = f"={warehouse_bucket_formula(bucket_suffix)}"
        worksheet.write_formula(row, COL_CAP_Y1, warehouse_formula, value_fmt)

        # Delta (grid - warehouse)
        delta_cell_grid = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_CAP_Y0)
        delta_cell_warehouse = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_CAP_Y1)
        delta_formula = f"={delta_cell_grid}-{delta_cell_warehouse}"
        worksheet.write_formula(row, COL_CAP_Y2, delta_formula, value_fmt)

        # Conditional formatting for delta
        worksheet.conditional_format(row, COL_CAP_Y2, row, COL_CAP_Y2, {
            "type": "cell",
            "criteria": "==",
            "value": 0,
            "format": roster_formats["reconcile_delta_zero"],
        })
        worksheet.conditional_format(row, COL_CAP_Y2, row, COL_CAP_Y2, {
            "type": "cell",
            "criteria": "!=",
            "value": 0,
            "format": roster_formats["reconcile_delta_nonzero"],
        })

        row += 1

    # Total row - mode-aware
    row += 1
    # Dynamic label showing mode
    worksheet.write_formula(row, COL_NAME, '="TOTAL ("&LOWER(SelectedMode)&"_total)"', roster_formats["subtotal_label"])

    # Total grid sum (sum all buckets) - mode-aware
    total_grid_formula = (
        f"={_salary_book_sumproduct()}"
        f"+{cap_holds_mode_sumif}"
        f"+{dead_money_mode_sumif}"
    )
    worksheet.write_formula(row, COL_CAP_Y0, total_grid_formula, roster_formats["subtotal"])

    # Warehouse total - mode-aware (cap_total / tax_total / apron_total)
    total_warehouse_formula = (
        '=IF(SelectedMode="Cap",'
        'SUMIFS(tbl_team_salary_warehouse[cap_total],tbl_team_salary_warehouse[team_code],SelectedTeam,tbl_team_salary_warehouse[salary_year],SelectedYear),'
        'IF(SelectedMode="Tax",'
        'SUMIFS(tbl_team_salary_warehouse[tax_total],tbl_team_salary_warehouse[team_code],SelectedTeam,tbl_team_salary_warehouse[salary_year],SelectedYear),'
        'SUMIFS(tbl_team_salary_warehouse[apron_total],tbl_team_salary_warehouse[team_code],SelectedTeam,tbl_team_salary_warehouse[salary_year],SelectedYear)))'
    )
    worksheet.write_formula(row, COL_CAP_Y1, total_warehouse_formula, roster_formats["subtotal"])

    # Total delta
    total_delta_grid = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_CAP_Y0)
    total_delta_warehouse = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_CAP_Y1)
    worksheet.write_formula(row, COL_CAP_Y2, f"={total_delta_grid}-{total_delta_warehouse}", roster_formats["subtotal"])

    worksheet.conditional_format(row, COL_CAP_Y2, row, COL_CAP_Y2, {
        "type": "cell",
        "criteria": "==",
        "value": 0,
        "format": roster_formats["reconcile_delta_zero"],
    })
    worksheet.conditional_format(row, COL_CAP_Y2, row, COL_CAP_Y2, {
        "type": "cell",
        "criteria": "!=",
        "value": 0,
        "format": roster_formats["reconcile_delta_nonzero"],
    })

    row += 2

    # Reconciliation status message
    status_formula = (
        f"=IF({total_delta_grid}-{total_delta_warehouse}=0,"
        f"\"✓ Reconciled - \"&SelectedMode&\" grid sums match warehouse totals\","
        f"\"⚠ MISMATCH - \"&SelectedMode&\" grid sums differ from warehouse totals\")"
    )
    worksheet.write_formula(row, COL_NAME, status_formula)
    worksheet.merge_range(row, COL_NAME, row, COL_CAP_Y2, "", roster_formats["reconcile_label"])
    worksheet.write_formula(row, COL_NAME, status_formula)

    # Conditional formatting for status row
    worksheet.conditional_format(row, COL_NAME, row, COL_CAP_Y2, {
        "type": "formula",
        "criteria": f"={total_delta_grid}={total_delta_warehouse}",
        "format": roster_formats["reconcile_delta_zero"],
    })
    worksheet.conditional_format(row, COL_NAME, row, COL_CAP_Y2, {
        "type": "formula",
        "criteria": f"={total_delta_grid}<>{total_delta_warehouse}",
        "format": roster_formats["reconcile_delta_nonzero"],
    })

    row += 2

    return row


# =============================================================================
# Badge Conditional Formatting
# =============================================================================

def _apply_badge_conditional_formatting(
    worksheet: Worksheet,
    roster_formats: dict[str, Any],
    roster_start_row: int,
    roster_end_row: int,
) -> None:
    """Apply conditional formatting to option/guarantee/trade badge columns.

    Colors cell backgrounds based on text values, matching web UI conventions:
    - Option badges: PO (blue), TO (purple), ETO (orange)
    - Guarantee badges: GTD (green text), PRT (amber), NG (red)
    - Trade restriction badges: NTC (red), Kicker (orange), Restricted (amber)

    Args:
        worksheet: The ROSTER_GRID worksheet
        roster_formats: Dict containing badge formats
        roster_start_row: First data row (0-indexed)
        roster_end_row: Last data row (0-indexed)
    """
    # Option column (COL_OPTION = 4)
    # Values: PO, TO, ETO (also handles raw DB values: PLYR, TEAM, PLYTF)
    option_rules = [
        # Player Option (blue)
        ("PO", roster_formats["badge_po"]),
        ("PLYR", roster_formats["badge_po"]),
        ("PLAYER", roster_formats["badge_po"]),
        # Team Option (purple)
        ("TO", roster_formats["badge_to"]),
        ("TEAM", roster_formats["badge_to"]),
        # Early Termination Option (orange)
        ("ETO", roster_formats["badge_eto"]),
        ("PLYTF", roster_formats["badge_eto"]),
    ]

    for value, fmt in option_rules:
        worksheet.conditional_format(
            roster_start_row, COL_OPTION, roster_end_row, COL_OPTION,
            {
                "type": "cell",
                "criteria": "==",
                "value": f'"{value}"',
                "format": fmt,
            }
        )

    # Guarantee column (COL_GUARANTEE = 5)
    # Values: GTD, PRT, NG
    guarantee_rules = [
        ("GTD", roster_formats["badge_gtd"]),
        ("PRT", roster_formats["badge_prt"]),
        ("NG", roster_formats["badge_ng"]),
    ]

    for value, fmt in guarantee_rules:
        worksheet.conditional_format(
            roster_start_row, COL_GUARANTEE, roster_end_row, COL_GUARANTEE,
            {
                "type": "cell",
                "criteria": "==",
                "value": f'"{value}"',
                "format": fmt,
            }
        )

    # Trade restriction column (COL_TRADE = 6)
    # Values: NTC, Kicker, Restricted
    trade_rules = [
        ("NTC", roster_formats["badge_no_trade"]),
        ("Kicker", roster_formats["badge_kicker"]),
        ("Restricted", roster_formats["badge_consent"]),
    ]

    for value, fmt in trade_rules:
        worksheet.conditional_format(
            roster_start_row, COL_TRADE, roster_end_row, COL_TRADE,
            {
                "type": "cell",
                "criteria": "==",
                "value": f'"{value}"',
                "format": fmt,
            }
        )


# =============================================================================
# Main Writer
# =============================================================================

def write_roster_grid(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write ROSTER_GRID sheet with full roster/ledger view and reconciliation.

    The roster grid shows:
    - All roster contracts (bucket = ROST) with badges and multi-year salaries
    - Two-way contracts (bucket = 2WAY)
    - Cap holds (bucket = FA)
    - Dead money (bucket = TERM)
    - EXISTS_ONLY section (non-counting rows with future-year amounts)
    - Reconciliation block proving grid sums match warehouse totals

    Per the blueprint:
    - Every headline total must be reconcilable
    - Detail tables are labeled by bucket
    - MINIMUM label appears for min contracts
    - % of cap displayed for context
    - EXISTS_ONLY rows are clearly labeled as non-counting (Ct$=N, CtR=N)

    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The ROSTER_GRID worksheet
        formats: Standard format dict from create_standard_formats
    """
    # Sheet title
    worksheet.write(0, 0, "ROSTER GRID", formats["header"])
    worksheet.write(1, 0, "Full roster/ledger view with explicit bucket classification")

    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)

    # Set column widths
    for col, width in COLUMN_WIDTHS.items():
        worksheet.set_column(col, col, width)

    # Create roster-specific formats
    roster_formats = _create_roster_formats(workbook)

    # Content starts after command bar
    content_row = get_content_start_row()

    # 1. Roster section (active contracts)
    content_row, roster_data_start = _write_roster_section(workbook, worksheet, content_row, formats, roster_formats)

    # Calculate roster data end row for conditional formatting
    # _write_roster_section writes 40 data rows (num_roster_rows = 40)
    roster_data_end = roster_data_start + 40 - 1

    # 2. Two-way section
    content_row = _write_twoway_section(workbook, worksheet, content_row, formats, roster_formats)

    # 3. Cap holds section
    content_row = _write_cap_holds_section(workbook, worksheet, content_row, formats, roster_formats)

    # 4. Dead money section
    content_row = _write_dead_money_section(workbook, worksheet, content_row, formats, roster_formats)

    # 5. GENERATED section (roster fill assumptions)
    # Creates fill rows when RosterFillTarget is 12/14/15
    # Controlled by RosterFillTarget toggle (0 = disabled)
    content_row = _write_generated_section(workbook, worksheet, content_row, formats, roster_formats)

    # 6. EXISTS_ONLY section (non-counting rows for analyst reference)
    # Shows players with $0 in SelectedYear but future-year amounts
    # Controlled by ShowExistsOnlyRows toggle (hidden when "No")
    content_row = _write_exists_only_section(workbook, worksheet, content_row, formats, roster_formats)

    # 7. Reconciliation block
    content_row = _write_reconciliation_block(workbook, worksheet, content_row, formats, roster_formats)

    # 8. Apply badge conditional formatting to roster section
    # Colors option/guarantee/trade columns based on cell values
    _apply_badge_conditional_formatting(
        worksheet, roster_formats, roster_data_start, roster_data_end
    )

    # Sheet protection
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })
