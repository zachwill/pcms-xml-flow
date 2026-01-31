"""
ROSTER_GRID sheet writer - full roster/ledger view with reconciliation.

This module implements:
1. Shared command bar (read-only reference to TEAM_COCKPIT)
2. Roster rows section (from tbl_salary_book_warehouse)
   - Player name, team, badge columns (option, guarantee, trade restrictions)
   - Multi-year salary columns (mode-aware: cap_y0..cap_y5 / tax_y0..tax_y5 / apron_y0..apron_y5)
   - Bucket classification (ROST/2WAY)
   - Explicit CountsTowardTotal (Ct$) and CountsTowardRoster (CtR) columns
   - MINIMUM label display when is_min_contract=TRUE
   - Conditional formatting for badges (colors cells based on PO/TO/ETO, GTD/PRT/NG, NTC/Kicker)
3. Two-way section (bucket = 2WAY)
   - Respects CountTwoWayInRoster and CountTwoWayInTotals policy toggles
4. Cap holds section (bucket = FA, from tbl_cap_holds_warehouse)
5. Dead money section (bucket = TERM, from tbl_dead_money_warehouse)
6. Totals + reconciliation block vs DATA_team_salary_warehouse
7. % of cap display helper

Per the blueprint (excel-cap-book-blueprint.md):
- Every headline total must be reconcilable to the authoritative ledger
- Drilldown tables are labeled by bucket and scoped to the snapshot
- CountsTowardTotal/CountsTowardRoster columns make counting logic explicit

Design notes:
- Uses Excel formulas filtered by SelectedTeam + SelectedYear + SelectedMode
- SelectedMode ("Cap"/"Tax"/"Apron") controls which salary columns are displayed
- Reconciliation block sums rows and compares to team_salary_warehouse totals (mode-aware)
- Conditional formatting highlights deltas ≠ 0
- Two-way counting respects policy toggles: CountTwoWayInRoster, CountTwoWayInTotals

Badge formatting (aligned to web UI conventions from web/src/features/SalaryBook/):
- Option: PO/PLYR (blue), TO/TEAM (purple), ETO/PLYTF (orange)
- Guarantee: GTD (green text), PRT (amber bg), NG (red bg)
- Trade: NTC (red), Kicker (orange), Restricted (amber)
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import FMT_MONEY, FMT_PERCENT
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
        "bottom": 1,
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

    Uses formulas that filter by SelectedTeam. Rows are formula-driven.
    For v1, we write a fixed number of formula rows (50) that show data
    when available and blank when not.

    Returns (next_row, data_start_row) for reconciliation formulas.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "ROSTER (Active Contracts)", section_fmt)
    row += 1

    # Note about formula-driven display
    worksheet.write(row, COL_BUCKET, "Showing players for selected team (SelectedTeam)", roster_formats["reconcile_label"])
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

    # Write formula rows for roster players
    # We use a fixed set of rows with IFERROR(INDEX/MATCH) formulas
    # that return blank if no matching player exists.

    # For MVP: use formulas that pull from the table based on row position
    # This approach uses AGGREGATE + SMALL to get unique players sorted by mode-aware amount

    num_roster_rows = 40  # Fixed allocation for roster rows

    # Use mode-aware amount for sorting (largest first)
    amount_sel = _salary_book_choose_mode_aware()
    option_sel = _salary_book_choose("option")
    gtd_full_sel = _salary_book_choose("is_fully_guaranteed")
    gtd_part_sel = _salary_book_choose("is_partially_guaranteed")
    gtd_non_sel = _salary_book_choose("is_non_guaranteed")

    criteria = "((tbl_salary_book_warehouse[team_code]=SelectedTeam)*(tbl_salary_book_warehouse[is_two_way]=FALSE))"

    for i in range(1, num_roster_rows + 1):
        # Nth largest selected-year, mode-aware amount for SelectedTeam (non-two-way)
        amount_value_expr = f"AGGREGATE(14,6,({amount_sel})/({criteria}),{i})"
        match_expr = f"MATCH({amount_value_expr},({amount_sel})/({criteria}),0)"

        name_expr = f'IFERROR(INDEX(tbl_salary_book_warehouse[player_name],{match_expr}),"" )'

        def _lookup_expr(col: str) -> str:
            return f'IFERROR(INDEX(tbl_salary_book_warehouse[{col}],{match_expr}),"" )'

        # Bucket (ROST)
        worksheet.write_formula(
            row,
            COL_BUCKET,
            f'=IF({name_expr}<>"","ROST","")',
            roster_formats["bucket_rost"],
        )

        # CountsTowardTotal: ROST contracts always count toward total (Y)
        worksheet.write_formula(
            row,
            COL_COUNTS_TOTAL,
            f'=IF({name_expr}<>"","Y","")',
            roster_formats["counts_yes"],
        )

        # CountsTowardRoster: ROST contracts always count toward roster (Y)
        worksheet.write_formula(
            row,
            COL_COUNTS_ROSTER,
            f'=IF({name_expr}<>"","Y","")',
            roster_formats["counts_yes"],
        )

        # Player name
        worksheet.write_formula(row, COL_NAME, f"={name_expr}")

        # Option badge (selected year)
        option_expr = f'IFERROR(INDEX({option_sel},{match_expr}),"" )'
        worksheet.write_formula(row, COL_OPTION, f"={option_expr}")

        # Guarantee status (selected year)
        guarantee_expr = (
            f'IFERROR('
            f'IF(INDEX({gtd_full_sel},{match_expr})=TRUE,"GTD",'
            f'IF(INDEX({gtd_part_sel},{match_expr})=TRUE,"PRT",'
            f'IF(INDEX({gtd_non_sel},{match_expr})=TRUE,"NG",""))),'
            f'"" )'
        )
        worksheet.write_formula(row, COL_GUARANTEE, f"={guarantee_expr}")

        # Trade restriction
        trade_expr = (
            f'IFERROR('
            f'IF(INDEX(tbl_salary_book_warehouse[is_no_trade],{match_expr})=TRUE,"NTC",'
            f'IF(INDEX(tbl_salary_book_warehouse[is_trade_bonus],{match_expr})=TRUE,"Kicker",'
            f'IF(INDEX(tbl_salary_book_warehouse[is_trade_restricted_now],{match_expr})=TRUE,"Restricted",""))),'
            f'"" )'
        )
        worksheet.write_formula(row, COL_TRADE, f"={trade_expr}")

        # Minimum contract label
        min_expr = (
            f'IFERROR(IF(INDEX(tbl_salary_book_warehouse[is_min_contract],{match_expr})=TRUE,"MINIMUM",""),"" )'
        )
        worksheet.write_formula(row, COL_MIN_LABEL, f"={min_expr}", roster_formats["min_label"])

        # Salary columns - mode-aware (cap_y*/tax_y*/apron_y* based on SelectedMode)
        for yi in range(6):
            # Build mode-aware column lookup expression
            mode_col_expr = (
                f'IF(SelectedMode="Cap",INDEX(tbl_salary_book_warehouse[cap_y{yi}],{match_expr}),'
                f'IF(SelectedMode="Tax",INDEX(tbl_salary_book_warehouse[tax_y{yi}],{match_expr}),'
                f'INDEX(tbl_salary_book_warehouse[apron_y{yi}],{match_expr})))'
            )
            worksheet.write_formula(
                row,
                COL_CAP_Y0 + yi,
                f'=IFERROR({mode_col_expr},"")',
                roster_formats["money"],
            )

        # % of cap (selected-year mode-aware amount / salary cap for SelectedYear)
        pct_expr = (
            f'IFERROR({amount_value_expr}/'
            f'SUMIFS(tbl_system_values[salary_cap_amount],tbl_system_values[salary_year],SelectedYear),"" )'
        )
        worksheet.write_formula(row, COL_PCT_CAP, f"={pct_expr}", roster_formats["percent"])

        row += 1

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

    # Two-way rows (fewer slots - typically max 3 per team)
    num_twoway_rows = 6

    # Use mode-aware amount for sorting
    amount_sel = _salary_book_choose_mode_aware()
    criteria = "((tbl_salary_book_warehouse[team_code]=SelectedTeam)*(tbl_salary_book_warehouse[is_two_way]=TRUE))"

    for i in range(1, num_twoway_rows + 1):
        amount_value_expr = f"AGGREGATE(14,6,({amount_sel})/({criteria}),{i})"
        match_expr = f"MATCH({amount_value_expr},({amount_sel})/({criteria}),0)"

        name_expr = f'IFERROR(INDEX(tbl_salary_book_warehouse[player_name],{match_expr}),"" )'

        # Bucket (2WAY)
        worksheet.write_formula(
            row,
            COL_BUCKET,
            f'=IF({name_expr}<>"","2WAY","")',
            roster_formats["bucket_2way"],
        )

        # CountsTowardTotal: two-way counts only if CountTwoWayInTotals="Yes"
        counts_total_expr = f'=IF({name_expr}<>"",IF(CountTwoWayInTotals="Yes","Y","N"),"")'
        worksheet.write_formula(row, COL_COUNTS_TOTAL, counts_total_expr, roster_formats["counts_yes"])

        # CountsTowardRoster: two-way counts only if CountTwoWayInRoster="Yes"
        counts_roster_expr = f'=IF({name_expr}<>"",IF(CountTwoWayInRoster="Yes","Y","N"),"")'
        worksheet.write_formula(row, COL_COUNTS_ROSTER, counts_roster_expr, roster_formats["counts_yes"])

        worksheet.write_formula(row, COL_NAME, f"={name_expr}")
        worksheet.write(row, COL_OPTION, "")  # Two-ways don't have options
        worksheet.write(row, COL_GUARANTEE, "")
        worksheet.write(row, COL_TRADE, "")
        worksheet.write(row, COL_MIN_LABEL, "")

        # Salary columns - mode-aware
        for yi in range(6):
            mode_col_expr = (
                f'IF(SelectedMode="Cap",INDEX(tbl_salary_book_warehouse[cap_y{yi}],{match_expr}),'
                f'IF(SelectedMode="Tax",INDEX(tbl_salary_book_warehouse[tax_y{yi}],{match_expr}),'
                f'INDEX(tbl_salary_book_warehouse[apron_y{yi}],{match_expr})))'
            )
            worksheet.write_formula(
                row,
                COL_CAP_Y0 + yi,
                f'=IFERROR({mode_col_expr},"")',
                roster_formats["money"],
            )

        row += 1

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

    Returns next row.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "CAP HOLDS (Free Agent Rights)", section_fmt)
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

    # Cap hold rows
    num_hold_rows = 15

    # Mode-aware amount column expression for cap holds
    amount_col_expr = _cap_holds_amount_col()

    for i in range(1, num_hold_rows + 1):
        criteria = "((tbl_cap_holds_warehouse[team_code]=SelectedTeam)*(tbl_cap_holds_warehouse[salary_year]=SelectedYear))"
        # Use mode-aware amount for sorting
        amount_value_expr = f"AGGREGATE(14,6,({amount_col_expr})/({criteria}),{i})"
        match_expr = f"MATCH({amount_value_expr},({amount_col_expr})/({criteria}),0)"

        name_expr = f'IFERROR(INDEX(tbl_cap_holds_warehouse[player_name],{match_expr}),"" )'

        def _lookup_expr(col: str) -> str:
            return f'IFERROR(INDEX(tbl_cap_holds_warehouse[{col}],{match_expr}),"" )'

        # Bucket (FA)
        worksheet.write_formula(
            row,
            COL_BUCKET,
            f'=IF({name_expr}<>"","FA","")',
            roster_formats["bucket_fa"],
        )

        # CountsTowardTotal: FA/holds always count toward cap total (Y)
        worksheet.write_formula(
            row,
            COL_COUNTS_TOTAL,
            f'=IF({name_expr}<>"","Y","")',
            roster_formats["counts_yes"],
        )

        # CountsTowardRoster: FA/holds do NOT count toward roster count (N)
        worksheet.write_formula(
            row,
            COL_COUNTS_ROSTER,
            f'=IF({name_expr}<>"","N","")',
            roster_formats["counts_no"],
        )

        worksheet.write_formula(row, COL_NAME, f"={name_expr}")

        # FA designation (RFA/UFA/etc.)
        worksheet.write_formula(row, COL_OPTION, f"={_lookup_expr('free_agent_designation_lk')}")
        worksheet.write(row, COL_GUARANTEE, "")

        # FA status
        worksheet.write_formula(row, COL_TRADE, f"={_lookup_expr('free_agent_status_lk')}")
        worksheet.write(row, COL_MIN_LABEL, "")

        # Amount - mode-aware
        mode_amount_expr = (
            f'IF(SelectedMode="Cap",INDEX(tbl_cap_holds_warehouse[cap_amount],{match_expr}),'
            f'IF(SelectedMode="Tax",INDEX(tbl_cap_holds_warehouse[tax_amount],{match_expr}),'
            f'INDEX(tbl_cap_holds_warehouse[apron_amount],{match_expr})))'
        )
        worksheet.write_formula(row, COL_CAP_Y0, f'=IFERROR({mode_amount_expr},"")', roster_formats["money"])

        # % of cap
        pct_expr = (
            f'IFERROR({amount_value_expr}/'
            f'SUMIFS(tbl_system_values[salary_cap_amount],tbl_system_values[salary_year],SelectedYear),"" )'
        )
        worksheet.write_formula(row, COL_PCT_CAP, f"={pct_expr}", roster_formats["percent"])

        row += 1

    # Subtotal for holds - mode-aware
    worksheet.write(row, COL_NAME, "Holds Subtotal:", roster_formats["subtotal_label"])
    subtotal_formula = (
        '=IF(SelectedMode="Cap",'
        'SUMIFS(tbl_cap_holds_warehouse[cap_amount],tbl_cap_holds_warehouse[team_code],SelectedTeam,tbl_cap_holds_warehouse[salary_year],SelectedYear),'
        'IF(SelectedMode="Tax",'
        'SUMIFS(tbl_cap_holds_warehouse[tax_amount],tbl_cap_holds_warehouse[team_code],SelectedTeam,tbl_cap_holds_warehouse[salary_year],SelectedYear),'
        'SUMIFS(tbl_cap_holds_warehouse[apron_amount],tbl_cap_holds_warehouse[team_code],SelectedTeam,tbl_cap_holds_warehouse[salary_year],SelectedYear)))'
    )
    worksheet.write_formula(row, COL_CAP_Y0, subtotal_formula, roster_formats["subtotal"])

    count_formula = (
        "=COUNTIFS(tbl_cap_holds_warehouse[team_code],SelectedTeam,"
        "tbl_cap_holds_warehouse[salary_year],SelectedYear,"
        "tbl_cap_holds_warehouse[cap_amount],\">0\")"
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

    Returns next row.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "DEAD MONEY (Terminated Contracts)", section_fmt)
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

    # Dead money rows
    num_dead_rows = 10

    # Mode-aware amount column expression for dead money
    amount_col_expr = _dead_money_amount_col()

    for i in range(1, num_dead_rows + 1):
        criteria = "((tbl_dead_money_warehouse[team_code]=SelectedTeam)*(tbl_dead_money_warehouse[salary_year]=SelectedYear))"
        # Use mode-aware amount for sorting
        amount_value_expr = f"AGGREGATE(14,6,({amount_col_expr})/({criteria}),{i})"
        match_expr = f"MATCH({amount_value_expr},({amount_col_expr})/({criteria}),0)"

        name_expr = f'IFERROR(INDEX(tbl_dead_money_warehouse[player_name],{match_expr}),"" )'

        def _lookup_expr(col: str) -> str:
            return f'IFERROR(INDEX(tbl_dead_money_warehouse[{col}],{match_expr}),"" )'

        # Bucket (TERM)
        worksheet.write_formula(
            row,
            COL_BUCKET,
            f'=IF({name_expr}<>"","TERM","")',
            roster_formats["bucket_term"],
        )

        # CountsTowardTotal: TERM/dead money always counts toward total (Y)
        worksheet.write_formula(
            row,
            COL_COUNTS_TOTAL,
            f'=IF({name_expr}<>"","Y","")',
            roster_formats["counts_yes"],
        )

        # CountsTowardRoster: TERM/dead money does NOT count toward roster (N)
        worksheet.write_formula(
            row,
            COL_COUNTS_ROSTER,
            f'=IF({name_expr}<>"","N","")',
            roster_formats["counts_no"],
        )

        worksheet.write_formula(row, COL_NAME, f"={name_expr}")
        worksheet.write(row, COL_OPTION, "")
        worksheet.write(row, COL_GUARANTEE, "")

        # Waive date
        worksheet.write_formula(row, COL_TRADE, f"={_lookup_expr('waive_date')}")
        worksheet.write(row, COL_MIN_LABEL, "")

        # Amount - mode-aware
        mode_amount_expr = (
            f'IF(SelectedMode="Cap",INDEX(tbl_dead_money_warehouse[cap_value],{match_expr}),'
            f'IF(SelectedMode="Tax",INDEX(tbl_dead_money_warehouse[tax_value],{match_expr}),'
            f'INDEX(tbl_dead_money_warehouse[apron_value],{match_expr})))'
        )
        worksheet.write_formula(row, COL_CAP_Y0, f'=IFERROR({mode_amount_expr},"")', roster_formats["money"])

        # % of cap
        pct_expr = (
            f'IFERROR({amount_value_expr}/'
            f'SUMIFS(tbl_system_values[salary_cap_amount],tbl_system_values[salary_year],SelectedYear),"" )'
        )
        worksheet.write_formula(row, COL_PCT_CAP, f"={pct_expr}", roster_formats["percent"])

        row += 1

    # Subtotal for dead money - mode-aware
    worksheet.write(row, COL_NAME, "Dead Money Subtotal:", roster_formats["subtotal_label"])
    subtotal_formula = (
        '=IF(SelectedMode="Cap",'
        'SUMIFS(tbl_dead_money_warehouse[cap_value],tbl_dead_money_warehouse[team_code],SelectedTeam,tbl_dead_money_warehouse[salary_year],SelectedYear),'
        'IF(SelectedMode="Tax",'
        'SUMIFS(tbl_dead_money_warehouse[tax_value],tbl_dead_money_warehouse[team_code],SelectedTeam,tbl_dead_money_warehouse[salary_year],SelectedYear),'
        'SUMIFS(tbl_dead_money_warehouse[apron_value],tbl_dead_money_warehouse[team_code],SelectedTeam,tbl_dead_money_warehouse[salary_year],SelectedYear)))'
    )
    worksheet.write_formula(row, COL_CAP_Y0, subtotal_formula, roster_formats["subtotal"])

    count_formula = (
        "=COUNTIFS(tbl_dead_money_warehouse[team_code],SelectedTeam,"
        "tbl_dead_money_warehouse[salary_year],SelectedYear,"
        "tbl_dead_money_warehouse[cap_value],\">0\")"
    )
    worksheet.write_formula(row, COL_BUCKET, count_formula, roster_formats["subtotal_label"])

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
# Import xlsxwriter utility
# =============================================================================

import xlsxwriter.utility


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
    - Reconciliation block proving grid sums match warehouse totals

    Per the blueprint:
    - Every headline total must be reconcilable
    - Detail tables are labeled by bucket
    - MINIMUM label appears for min contracts
    - % of cap displayed for context

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

    # 5. Reconciliation block
    content_row = _write_reconciliation_block(workbook, worksheet, content_row, formats, roster_formats)

    # 6. Apply badge conditional formatting to roster section
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
