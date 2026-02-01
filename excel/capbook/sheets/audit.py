"""
AUDIT_AND_RECONCILE sheet writer.

This sheet is the "prevent 'your number is wrong' fights" layer.
Per the blueprint (excel-cap-book-blueprint.md), it must include:
- Totals reconciliation (snapshot vs counting rows vs derived totals)
- Contributing rows drilldowns for each headline readout
- Assumptions applied (fill rows, toggles, overrides)
- Plan diff (baseline vs ActivePlan) and journal action summary

This implementation provides:
1. Shared command bar (read-only reference to TEAM_COCKPIT)
2. Summary banner (at-a-glance reconciliation status for cap/tax/apron)
3. Authoritative totals from DATA_team_salary_warehouse (by bucket)
4. Drilldown table sums (salary_book, cap_holds, dead_money)
5. Visible deltas with conditional formatting
6. Row counts + counts-vs-exists summary
7. Policy assumptions summary (fill rows, toggles)
8. Plan diff section (Baseline vs ActivePlan delta totals + action counts)
9. Notes section with drilldown links

Design notes:
- Uses Excel formulas filtered by SelectedTeam + SelectedYear
- **Uses LET + FILTER + SUM patterns instead of legacy SUMPRODUCT** (Excel 365/2021+)
- Salary book drilldowns use LET + CHOOSECOLS + FILTER for year-column selection
- Plan diff uses shared PlanRowMask LAMBDA helper for consistent filtering
- Conditional formatting highlights any non-zero deltas as red (reconciliation failures)
- Row count comparison shows if drilldown tables have expected number of rows
"""

from __future__ import annotations

from typing import Any

import xlsxwriter.utility

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import FMT_MONEY
from .command_bar import (
    write_command_bar_readonly,
    get_content_start_row,
)


# =============================================================================
# Layout Constants
# =============================================================================

COL_LABEL = 0
COL_WAREHOUSE = 1  # Authoritative (warehouse) value
COL_DRILLDOWN = 2  # Calculated from drilldown tables
COL_DELTA = 3      # Difference
COL_STATUS = 4     # Status indicator (✓ / ✗)
COL_NOTES = 5      # Notes/context

# Column widths
COLUMN_WIDTHS = {
    COL_LABEL: 32,
    COL_WAREHOUSE: 16,
    COL_DRILLDOWN: 16,
    COL_DELTA: 14,
    COL_STATUS: 10,
    COL_NOTES: 40,
}


# =============================================================================
# Format Helpers
# =============================================================================

def _create_audit_formats(workbook: Workbook) -> dict[str, Any]:
    """Create formats specific to the audit sheet."""
    formats = {}
    
    # Section headers
    formats["section_header"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#1E3A5F",  # Dark blue
        "font_color": "#FFFFFF",
        "bottom": 2,
    })
    
    # Subsection headers
    formats["subsection_header"] = workbook.add_format({
        "bold": True,
        "font_size": 10,
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
    
    # Row labels
    formats["label"] = workbook.add_format({"font_size": 10})
    formats["label_indent"] = workbook.add_format({"font_size": 10, "indent": 1})
    formats["label_bold"] = workbook.add_format({"bold": True, "font_size": 10})
    
    # Money formats
    formats["money"] = workbook.add_format({"num_format": FMT_MONEY})
    formats["money_bold"] = workbook.add_format({"num_format": FMT_MONEY, "bold": True})
    formats["money_total"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "bold": True,
        "top": 1,
        "bottom": 2,
        "bg_color": "#F3F4F6",
    })
    
    # Count format (for row counts)
    formats["count"] = workbook.add_format({"align": "center"})
    formats["count_bold"] = workbook.add_format({"align": "center", "bold": True})
    
    # Delta formats
    formats["delta_ok"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "bg_color": "#D1FAE5",  # green-100
        "font_color": "#065F46",  # green-800
    })
    formats["delta_fail"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "bold": True,
    })
    
    # Status indicators
    formats["status_ok"] = workbook.add_format({
        "align": "center",
        "font_color": "#065F46",
        "bold": True,
    })
    formats["status_fail"] = workbook.add_format({
        "align": "center",
        "font_color": "#991B1B",
        "bold": True,
    })
    
    # Notes
    formats["note"] = workbook.add_format({
        "font_size": 9,
        "font_color": "#6B7280",
        "italic": True,
    })
    
    # Summary box formats
    formats["summary_pass"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#D1FAE5",
        "font_color": "#065F46",
        "align": "center",
        "valign": "vcenter",
        "border": 2,
        "border_color": "#065F46",
    })
    formats["summary_fail"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#FEE2E2",
        "font_color": "#991B1B",
        "align": "center",
        "valign": "vcenter",
        "border": 2,
        "border_color": "#991B1B",
    })
    
    return formats


# =============================================================================
# Helper: SUMIFS/COUNTIFS formula builders (using LET + FILTER + SUM patterns)
# =============================================================================

def _warehouse_sumifs(column: str) -> str:
    """Build SUMIFS formula for team_salary_warehouse filtered by SelectedTeam + SelectedYear."""
    return (
        f"SUMIFS(tbl_team_salary_warehouse[{column}],"
        f"tbl_team_salary_warehouse[team_code],SelectedTeam,"
        f"tbl_team_salary_warehouse[salary_year],SelectedYear)"
    )


def _salary_book_filter_sum(col_base: str, *, is_two_way: bool) -> str:
    """Sum selected-year amounts from salary_book_warehouse using LET + FILTER + SUM.

    Replaces the legacy SUMPRODUCT pattern with modern dynamic arrays.

    salary_book_warehouse exports relative-year columns (cap_y0..cap_y5, etc.)
    relative to MetaBaseYear. We use CHOOSECOLS to extract the correct year column.

    Args:
        col_base: Column prefix (cap, tax, apron)
        is_two_way: Filter to two-way (True) or non-two-way (False) rows

    Returns:
        Formula string (no leading '=') using LET + FILTER + SUM
    """
    two_way_val = "TRUE" if is_two_way else "FALSE"

    # Build the year column selector using CHOOSECOLS
    year_cols = ",".join(f"tbl_salary_book_warehouse[{col_base}_y{i}]" for i in range(6))
    year_col_expr = f"CHOOSECOLS({year_cols},(SelectedYear-MetaBaseYear+1))"

    return (
        "LET("
        "_xlpm.tbl,tbl_salary_book_warehouse,"
        "_xlpm.team_mask,_xlpm.tbl[team_code]=SelectedTeam,"
        f"_xlpm.twoway_mask,_xlpm.tbl[is_two_way]={two_way_val},"
        f"_xlpm.year_col,{year_col_expr},"
        "_xlpm.mask,_xlpm.team_mask*_xlpm.twoway_mask,"
        "IFERROR(SUM(FILTER(_xlpm.year_col,_xlpm.mask,0)),0)"
        ")"
    )


def _salary_book_filter_count(*, is_two_way: bool) -> str:
    """Count salary_book rows with selected-year cap > 0 using LET + FILTER + ROWS.

    Replaces the legacy SUMPRODUCT(--, --, --) pattern with modern dynamic arrays.

    Args:
        is_two_way: Filter to two-way (True) or non-two-way (False) rows

    Returns:
        Formula string (no leading '=') using LET + FILTER + ROWS
    """
    two_way_val = "TRUE" if is_two_way else "FALSE"

    # Build the year column selector for cap using CHOOSECOLS
    cap_year_cols = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
    cap_year_col_expr = f"CHOOSECOLS({cap_year_cols},(SelectedYear-MetaBaseYear+1))"

    return (
        "LET("
        "_xlpm.tbl,tbl_salary_book_warehouse,"
        "_xlpm.team_mask,_xlpm.tbl[team_code]=SelectedTeam,"
        f"_xlpm.twoway_mask,_xlpm.tbl[is_two_way]={two_way_val},"
        f"_xlpm.cap_col,{cap_year_col_expr},"
        "_xlpm.cap_mask,_xlpm.cap_col>0,"
        "_xlpm.mask,_xlpm.team_mask*_xlpm.twoway_mask*_xlpm.cap_mask,"
        "_xlpm.filtered,FILTER(_xlpm.tbl[player_id],_xlpm.mask,\"\"),"
        "IF(ISTEXT(_xlpm.filtered),0,ROWS(_xlpm.filtered))"
        ")"
    )


def _cap_holds_sumifs(column: str) -> str:
    """Build SUMIFS formula for cap_holds_warehouse."""
    return (
        f"SUMIFS(tbl_cap_holds_warehouse[{column}],"
        f"tbl_cap_holds_warehouse[team_code],SelectedTeam,"
        f"tbl_cap_holds_warehouse[salary_year],SelectedYear)"
    )


def _cap_holds_countifs() -> str:
    """Build COUNTIFS formula for cap_holds_warehouse."""
    return (
        f"COUNTIFS(tbl_cap_holds_warehouse[team_code],SelectedTeam,"
        f"tbl_cap_holds_warehouse[salary_year],SelectedYear,"
        f'tbl_cap_holds_warehouse[cap_amount],">0")'
    )


def _dead_money_sumifs(column: str) -> str:
    """Build SUMIFS formula for dead_money_warehouse."""
    return (
        f"SUMIFS(tbl_dead_money_warehouse[{column}],"
        f"tbl_dead_money_warehouse[team_code],SelectedTeam,"
        f"tbl_dead_money_warehouse[salary_year],SelectedYear)"
    )


def _dead_money_countifs() -> str:
    """Build COUNTIFS formula for dead_money_warehouse."""
    return (
        f"COUNTIFS(tbl_dead_money_warehouse[team_code],SelectedTeam,"
        f"tbl_dead_money_warehouse[salary_year],SelectedYear,"
        f'tbl_dead_money_warehouse[cap_value],">0")'
    )


# =============================================================================
# Section Writers
# =============================================================================

def _write_column_headers(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    headers: list[str],
) -> int:
    """Write column headers.
    
    Returns next row.
    """
    fmt = formats["col_header"]
    for col, header in enumerate(headers):
        worksheet.write(row, col, header, fmt)
    return row + 1


def _write_summary_banner(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the top-level reconciliation summary banner.
    
    This shows at-a-glance whether the workbook is reconciled.
    
    PASS iff all three total deltas (cap/tax/apron) are zero (tolerance < 1).
    FAIL message names which totals are mismatched and shows deltas.
    
    Returns next row.
    """
    # We'll create a merged cell that shows overall status
    # The formula checks if ALL three (cap/tax/apron) bucket deltas are zero
    
    # Calculate CAP delta = drilldown - warehouse
    cap_drilldown = (
        f"({_salary_book_filter_sum('cap', is_two_way=False)})"
        f"+({_salary_book_filter_sum('cap', is_two_way=True)})"
        f"+({_cap_holds_sumifs('cap_amount')})"
        f"+({_dead_money_sumifs('cap_value')})"
    )
    cap_warehouse = _warehouse_sumifs('cap_total')
    cap_delta = f"({cap_drilldown}-{cap_warehouse})"
    
    # Calculate TAX delta = drilldown - warehouse
    tax_drilldown = (
        f"({_salary_book_filter_sum('tax', is_two_way=False)})"
        f"+({_salary_book_filter_sum('tax', is_two_way=True)})"
        f"+({_cap_holds_sumifs('tax_amount')})"
        f"+({_dead_money_sumifs('tax_value')})"
    )
    tax_warehouse = _warehouse_sumifs('tax_total')
    tax_delta = f"({tax_drilldown}-{tax_warehouse})"
    
    # Calculate APRON delta = drilldown - warehouse
    apron_drilldown = (
        f"({_salary_book_filter_sum('apron', is_two_way=False)})"
        f"+({_salary_book_filter_sum('apron', is_two_way=True)})"
        f"+({_cap_holds_sumifs('apron_amount')})"
        f"+({_dead_money_sumifs('apron_value')})"
    )
    apron_warehouse = _warehouse_sumifs('apron_total')
    apron_delta = f"({apron_drilldown}-{apron_warehouse})"
    
    # Check if each is within tolerance
    cap_ok = f"(ABS{cap_delta}<1)"
    tax_ok = f"(ABS{tax_delta}<1)"
    apron_ok = f"(ABS{apron_delta}<1)"
    all_ok = f"AND({cap_ok},{tax_ok},{apron_ok})"
    
    # Build mismatch detail string showing which sections failed and their deltas
    # Format: "Cap: $X, Tax: $Y, Apron: $Z" for any that mismatch
    mismatch_parts = (
        f'IF(NOT({cap_ok}),"Cap: $"&TEXT(ABS{cap_delta},"#,##0")&" ","")'
        f'&IF(NOT({tax_ok}),"Tax: $"&TEXT(ABS{tax_delta},"#,##0")&" ","")'
        f'&IF(NOT({apron_ok}),"Apron: $"&TEXT(ABS{apron_delta},"#,##0"),"")'
    )
    
    status_formula = (
        f'=IF({all_ok},'
        f'"✓ RECONCILED — All drilldown sums match warehouse totals (Cap/Tax/Apron)",'
        f'"✗ MISMATCH — "&TRIM({mismatch_parts}))'
    )
    
    worksheet.merge_range(row, COL_LABEL, row, COL_NOTES, "", audit_formats["summary_pass"])
    worksheet.write_formula(row, COL_LABEL, status_formula, audit_formats["summary_pass"])
    
    # Conditional formatting for the banner
    worksheet.conditional_format(row, COL_LABEL, row, COL_NOTES, {
        "type": "text",
        "criteria": "containing",
        "value": "✓",
        "format": audit_formats["summary_pass"],
    })
    worksheet.conditional_format(row, COL_LABEL, row, COL_NOTES, {
        "type": "text",
        "criteria": "containing",
        "value": "✗",
        "format": audit_formats["summary_fail"],
    })
    
    return row + 2


def _write_cap_reconciliation_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the cap amount reconciliation section.
    
    Compares warehouse bucket totals against drilldown table sums.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "CAP AMOUNT RECONCILIATION",
        audit_formats["section_header"]
    )
    row += 1
    
    # Column headers
    headers = ["Bucket", "Warehouse", "Drilldown", "Delta", "Status", "Source Tables"]
    row = _write_column_headers(worksheet, row, audit_formats, headers)
    
    # Bucket reconciliation rows
    buckets = [
        ("Roster (ROST)", "cap_rost", _salary_book_filter_sum("cap", is_two_way=False),
         "tbl_salary_book_warehouse (selected-year cap; is_two_way=FALSE)"),
        ("Two-Way (2WAY)", "cap_2way", _salary_book_filter_sum("cap", is_two_way=True),
         "tbl_salary_book_warehouse (selected-year cap; is_two_way=TRUE)"),
        ("FA Holds (FA)", "cap_fa", _cap_holds_sumifs("cap_amount"),
         "tbl_cap_holds_warehouse"),
        ("Dead Money (TERM)", "cap_term", _dead_money_sumifs("cap_value"),
         "tbl_dead_money_warehouse"),
    ]
    
    for label, warehouse_col, drilldown_formula, source_note in buckets:
        worksheet.write(row, COL_LABEL, label, audit_formats["label_indent"])
        
        # Warehouse value
        warehouse_formula = f"={_warehouse_sumifs(warehouse_col)}"
        worksheet.write_formula(row, COL_WAREHOUSE, warehouse_formula, audit_formats["money"])
        
        # Drilldown sum
        worksheet.write_formula(row, COL_DRILLDOWN, f"={drilldown_formula}", audit_formats["money"])
        
        # Delta = drilldown - warehouse
        warehouse_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_WAREHOUSE)
        drilldown_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DRILLDOWN)
        delta_formula = f"={drilldown_cell}-{warehouse_cell}"
        worksheet.write_formula(row, COL_DELTA, delta_formula, audit_formats["money"])
        
        # Status
        delta_ref = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DELTA)
        status_formula = f'=IF(ABS({delta_ref})<1,"✓","✗")'
        worksheet.write_formula(row, COL_STATUS, status_formula)
        
        # Conditional formatting for delta
        worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
            "type": "cell", "criteria": "==", "value": 0, "format": audit_formats["delta_ok"],
        })
        worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
            "type": "cell", "criteria": "!=", "value": 0, "format": audit_formats["delta_fail"],
        })
        
        # Conditional formatting for status
        worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
            "type": "text", "criteria": "containing", "value": "✓", "format": audit_formats["status_ok"],
        })
        worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
            "type": "text", "criteria": "containing", "value": "✗", "format": audit_formats["status_fail"],
        })
        
        worksheet.write(row, COL_NOTES, source_note, audit_formats["note"])
        row += 1
    
    # Total row
    row += 1
    worksheet.write(row, COL_LABEL, "CAP TOTAL", audit_formats["label_bold"])
    
    # Warehouse total
    worksheet.write_formula(
        row, COL_WAREHOUSE, f"={_warehouse_sumifs('cap_total')}", 
        audit_formats["money_total"]
    )
    
    # Drilldown total (sum of all buckets)
    drilldown_total = (
        f"={_salary_book_filter_sum('cap', is_two_way=False)}"
        f"+{_salary_book_filter_sum('cap', is_two_way=True)}"
        f"+{_cap_holds_sumifs('cap_amount')}"
        f"+{_dead_money_sumifs('cap_value')}"
    )
    worksheet.write_formula(row, COL_DRILLDOWN, drilldown_total, audit_formats["money_total"])
    
    # Total delta
    warehouse_total_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_WAREHOUSE)
    drilldown_total_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DRILLDOWN)
    total_delta_formula = f"={drilldown_total_cell}-{warehouse_total_cell}"
    worksheet.write_formula(row, COL_DELTA, total_delta_formula, audit_formats["money_total"])
    
    # Total status
    total_delta_ref = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DELTA)
    worksheet.write_formula(row, COL_STATUS, f'=IF(ABS({total_delta_ref})<1,"✓","✗")')
    
    worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
        "type": "cell", "criteria": "==", "value": 0, "format": audit_formats["delta_ok"],
    })
    worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
        "type": "cell", "criteria": "!=", "value": 0, "format": audit_formats["delta_fail"],
    })
    worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
        "type": "text", "criteria": "containing", "value": "✓", "format": audit_formats["status_ok"],
    })
    worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
        "type": "text", "criteria": "containing", "value": "✗", "format": audit_formats["status_fail"],
    })
    
    return row + 2


def _write_tax_reconciliation_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the tax amount reconciliation section.
    
    Similar to cap but uses tax columns.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "TAX AMOUNT RECONCILIATION",
        audit_formats["section_header"]
    )
    row += 1
    
    # Column headers
    headers = ["Bucket", "Warehouse", "Drilldown", "Delta", "Status", "Notes"]
    row = _write_column_headers(worksheet, row, audit_formats, headers)
    
    # Tax bucket rows. salary_book_warehouse provides tax_y*, cap_holds_warehouse provides tax_amount,
    # and dead_money_warehouse provides tax_value.
    buckets = [
        ("Roster (ROST)", "tax_rost", _salary_book_filter_sum("tax", is_two_way=False)),
        ("Two-Way (2WAY)", "tax_2way", _salary_book_filter_sum("tax", is_two_way=True)),
        ("FA Holds (FA)", "tax_fa", _cap_holds_sumifs("tax_amount")),
        ("Dead Money (TERM)", "tax_term", _dead_money_sumifs("tax_value")),
    ]
    
    for label, warehouse_col, drilldown_formula in buckets:
        worksheet.write(row, COL_LABEL, label, audit_formats["label_indent"])
        worksheet.write_formula(row, COL_WAREHOUSE, f"={_warehouse_sumifs(warehouse_col)}", audit_formats["money"])
        worksheet.write_formula(row, COL_DRILLDOWN, f"={drilldown_formula}", audit_formats["money"])
        
        warehouse_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_WAREHOUSE)
        drilldown_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DRILLDOWN)
        worksheet.write_formula(row, COL_DELTA, f"={drilldown_cell}-{warehouse_cell}", audit_formats["money"])
        
        delta_ref = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DELTA)
        worksheet.write_formula(row, COL_STATUS, f'=IF(ABS({delta_ref})<1,"✓","✗")')
        
        worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
            "type": "cell", "criteria": "==", "value": 0, "format": audit_formats["delta_ok"],
        })
        worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
            "type": "cell", "criteria": "!=", "value": 0, "format": audit_formats["delta_fail"],
        })
        worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
            "type": "text", "criteria": "containing", "value": "✓", "format": audit_formats["status_ok"],
        })
        worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
            "type": "text", "criteria": "containing", "value": "✗", "format": audit_formats["status_fail"],
        })
        
        row += 1
    
    # Total row
    row += 1
    worksheet.write(row, COL_LABEL, "TAX TOTAL", audit_formats["label_bold"])
    worksheet.write_formula(row, COL_WAREHOUSE, f"={_warehouse_sumifs('tax_total')}", audit_formats["money_total"])
    
    drilldown_total = (
        f"={_salary_book_filter_sum('tax', is_two_way=False)}"
        f"+{_salary_book_filter_sum('tax', is_two_way=True)}"
        f"+{_cap_holds_sumifs('tax_amount')}"
        f"+{_dead_money_sumifs('tax_value')}"
    )
    worksheet.write_formula(row, COL_DRILLDOWN, drilldown_total, audit_formats["money_total"])
    
    warehouse_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_WAREHOUSE)
    drilldown_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DRILLDOWN)
    worksheet.write_formula(row, COL_DELTA, f"={drilldown_cell}-{warehouse_cell}", audit_formats["money_total"])
    
    delta_ref = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DELTA)
    worksheet.write_formula(row, COL_STATUS, f'=IF(ABS({delta_ref})<1,"✓","✗")')
    
    worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
        "type": "cell", "criteria": "==", "value": 0, "format": audit_formats["delta_ok"],
    })
    worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
        "type": "cell", "criteria": "!=", "value": 0, "format": audit_formats["delta_fail"],
    })
    worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
        "type": "text", "criteria": "containing", "value": "✓", "format": audit_formats["status_ok"],
    })
    worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
        "type": "text", "criteria": "containing", "value": "✗", "format": audit_formats["status_fail"],
    })
    
    return row + 2


def _write_apron_reconciliation_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the apron amount reconciliation section.
    
    Similar to cap/tax but uses apron columns.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "APRON AMOUNT RECONCILIATION",
        audit_formats["section_header"]
    )
    row += 1
    
    # Column headers
    headers = ["Bucket", "Warehouse", "Drilldown", "Delta", "Status", "Source Tables"]
    row = _write_column_headers(worksheet, row, audit_formats, headers)
    
    # Apron bucket rows. salary_book_warehouse provides apron_y*, cap_holds_warehouse provides apron_amount,
    # and dead_money_warehouse provides apron_value.
    buckets = [
        ("Roster (ROST)", "apron_rost", _salary_book_filter_sum("apron", is_two_way=False),
         "tbl_salary_book_warehouse (selected-year apron; is_two_way=FALSE)"),
        ("Two-Way (2WAY)", "apron_2way", _salary_book_filter_sum("apron", is_two_way=True),
         "tbl_salary_book_warehouse (selected-year apron; is_two_way=TRUE)"),
        ("FA Holds (FA)", "apron_fa", _cap_holds_sumifs("apron_amount"),
         "tbl_cap_holds_warehouse"),
        ("Dead Money (TERM)", "apron_term", _dead_money_sumifs("apron_value"),
         "tbl_dead_money_warehouse"),
    ]
    
    for label, warehouse_col, drilldown_formula, source_note in buckets:
        worksheet.write(row, COL_LABEL, label, audit_formats["label_indent"])
        
        # Warehouse value
        warehouse_formula = f"={_warehouse_sumifs(warehouse_col)}"
        worksheet.write_formula(row, COL_WAREHOUSE, warehouse_formula, audit_formats["money"])
        
        # Drilldown sum
        worksheet.write_formula(row, COL_DRILLDOWN, f"={drilldown_formula}", audit_formats["money"])
        
        # Delta = drilldown - warehouse
        warehouse_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_WAREHOUSE)
        drilldown_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DRILLDOWN)
        delta_formula = f"={drilldown_cell}-{warehouse_cell}"
        worksheet.write_formula(row, COL_DELTA, delta_formula, audit_formats["money"])
        
        # Status
        delta_ref = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DELTA)
        status_formula = f'=IF(ABS({delta_ref})<1,"✓","✗")'
        worksheet.write_formula(row, COL_STATUS, status_formula)
        
        # Conditional formatting for delta
        worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
            "type": "cell", "criteria": "==", "value": 0, "format": audit_formats["delta_ok"],
        })
        worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
            "type": "cell", "criteria": "!=", "value": 0, "format": audit_formats["delta_fail"],
        })
        
        # Conditional formatting for status
        worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
            "type": "text", "criteria": "containing", "value": "✓", "format": audit_formats["status_ok"],
        })
        worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
            "type": "text", "criteria": "containing", "value": "✗", "format": audit_formats["status_fail"],
        })
        
        worksheet.write(row, COL_NOTES, source_note, audit_formats["note"])
        row += 1
    
    # Total row
    row += 1
    worksheet.write(row, COL_LABEL, "APRON TOTAL", audit_formats["label_bold"])
    worksheet.write_formula(row, COL_WAREHOUSE, f"={_warehouse_sumifs('apron_total')}", audit_formats["money_total"])
    
    drilldown_total = (
        f"={_salary_book_filter_sum('apron', is_two_way=False)}"
        f"+{_salary_book_filter_sum('apron', is_two_way=True)}"
        f"+{_cap_holds_sumifs('apron_amount')}"
        f"+{_dead_money_sumifs('apron_value')}"
    )
    worksheet.write_formula(row, COL_DRILLDOWN, drilldown_total, audit_formats["money_total"])
    
    warehouse_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_WAREHOUSE)
    drilldown_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DRILLDOWN)
    worksheet.write_formula(row, COL_DELTA, f"={drilldown_cell}-{warehouse_cell}", audit_formats["money_total"])
    
    delta_ref = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DELTA)
    worksheet.write_formula(row, COL_STATUS, f'=IF(ABS({delta_ref})<1,"✓","✗")')
    
    worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
        "type": "cell", "criteria": "==", "value": 0, "format": audit_formats["delta_ok"],
    })
    worksheet.conditional_format(row, COL_DELTA, row, COL_DELTA, {
        "type": "cell", "criteria": "!=", "value": 0, "format": audit_formats["delta_fail"],
    })
    worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
        "type": "text", "criteria": "containing", "value": "✓", "format": audit_formats["status_ok"],
    })
    worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
        "type": "text", "criteria": "containing", "value": "✗", "format": audit_formats["status_fail"],
    })
    
    return row + 2


def _write_row_counts_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the row counts reconciliation section.
    
    Compares warehouse row counts against drilldown table counts.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "ROW COUNTS",
        audit_formats["section_header"]
    )
    row += 1
    
    # Column headers
    headers = ["Category", "Warehouse", "Drilldown", "Delta", "Status", "Notes"]
    row = _write_column_headers(worksheet, row, audit_formats, headers)
    
    # Row count comparisons
    counts = [
        ("Roster contracts", "roster_row_count", _salary_book_filter_count(is_two_way=False),
         "Players with selected-year cap > 0, is_two_way=FALSE"),
        ("Two-way contracts", "two_way_row_count", _salary_book_filter_count(is_two_way=True),
         "Players with selected-year cap > 0, is_two_way=TRUE"),
        ("FA holds", None, _cap_holds_countifs(), "cap_holds_warehouse for year"),
        ("Dead money entries", None, _dead_money_countifs(), "dead_money_warehouse for year"),
    ]
    
    for label, warehouse_col, drilldown_formula, note in counts:
        worksheet.write(row, COL_LABEL, label, audit_formats["label_indent"])
        
        # Warehouse value (if available)
        if warehouse_col:
            worksheet.write_formula(
                row, COL_WAREHOUSE, f"={_warehouse_sumifs(warehouse_col)}", 
                audit_formats["count"]
            )
        else:
            worksheet.write(row, COL_WAREHOUSE, "—", audit_formats["count"])
        
        # Drilldown count
        worksheet.write_formula(row, COL_DRILLDOWN, f"={drilldown_formula}", audit_formats["count"])
        
        # Delta (only if warehouse column exists)
        if warehouse_col:
            warehouse_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_WAREHOUSE)
            drilldown_cell = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DRILLDOWN)
            worksheet.write_formula(row, COL_DELTA, f"={drilldown_cell}-{warehouse_cell}", audit_formats["count"])
            
            delta_ref = xlsxwriter.utility.xl_rowcol_to_cell(row, COL_DELTA)
            worksheet.write_formula(row, COL_STATUS, f'=IF({delta_ref}=0,"✓","✗")')
            
            worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
                "type": "text", "criteria": "containing", "value": "✓", "format": audit_formats["status_ok"],
            })
            worksheet.conditional_format(row, COL_STATUS, row, COL_STATUS, {
                "type": "text", "criteria": "containing", "value": "✗", "format": audit_formats["status_fail"],
            })
        else:
            worksheet.write(row, COL_DELTA, "—", audit_formats["count"])
            worksheet.write(row, COL_STATUS, "—", audit_formats["count"])
        
        worksheet.write(row, COL_NOTES, note, audit_formats["note"])
        row += 1
    
    return row + 2


def _write_policy_assumptions_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the policy assumptions section.
    
    Shows current values of policy toggles that affect totals,
    including generated fill row impacts.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "POLICY ASSUMPTIONS (Current Settings)",
        audit_formats["subsection_header"]
    )
    row += 1
    
    # Policy toggles (read from named ranges)
    # NOTE: CountTwoWayInRoster/CountTwoWayInTotals were removed.
    # Two-way counting is a CBA fact (2-way counts toward cap totals, not roster).
    # The COCKPIT now shows informational 2-way readouts in PRIMARY READOUTS section.
    policies = [
        ("Roster Fill Target", "RosterFillTarget", "Generated fill rows target count"),
        ("Roster Fill Type", "RosterFillType", "Minimum salary type for fills"),
        ("Show Exists-Only Rows", "ShowExistsOnlyRows", "Display non-counting rows"),
        ("Active Plan", "ActivePlan", "Currently selected scenario"),
    ]
    
    for label, named_range, note in policies:
        worksheet.write(row, COL_LABEL, label, audit_formats["label_indent"])
        worksheet.write_formula(row, COL_WAREHOUSE, f"={named_range}", audit_formats["label"])
        worksheet.write(row, COL_NOTES, note, audit_formats["note"])
        row += 1
    
    row += 1
    
    # =========================================================================
    # Generated Fill Rows Impact (when RosterFillTarget > 0)
    # =========================================================================
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "GENERATED FILL ROWS IMPACT",
        audit_formats["subsection_header"]
    )
    row += 1
    
    # Explanation
    # NOTE: Fill amounts are mode-independent (same for Cap/Tax/Apron) because
    # minimum salary contracts count identically toward all thresholds per CBA.
    worksheet.write(
        row, COL_LABEL,
        "When RosterFillTarget > 0, generated fill rows add to totals (mode-independent):",
        audit_formats["note"]
    )
    row += 1
    
    # Current roster count (non-two-way with selected-year cap > 0)
    # Uses LET + FILTER + ROWS to match the modern formula pattern
    current_roster_formula = _salary_book_filter_count(is_two_way=False)
    
    worksheet.write(row, COL_LABEL, "  Current Roster Count:", audit_formats["label_indent"])
    worksheet.write_formula(row, COL_WAREHOUSE, f"={current_roster_formula}", audit_formats["count"])
    worksheet.write(row, COL_NOTES, "Non-two-way players with SelectedYear cap > 0", audit_formats["note"])
    row += 1
    
    # Fill rows needed = MAX(0, RosterFillTarget - current_roster_count)
    fill_rows_needed_formula = f"MAX(0,RosterFillTarget-{current_roster_formula})"
    
    worksheet.write(row, COL_LABEL, "  Fill Rows Needed:", audit_formats["label_indent"])
    worksheet.write_formula(row, COL_WAREHOUSE, f"={fill_rows_needed_formula}", audit_formats["count"])
    worksheet.write(row, COL_NOTES, "= MAX(0, RosterFillTarget - Current Roster)", audit_formats["note"])
    row += 1
    
    # Fill amount per row (based on RosterFillType)
    # Mode-independent: minimum salaries count the same for cap/tax/apron thresholds
    rookie_min_formula = (
        "SUMIFS(tbl_rookie_scale[salary_year_1],"
        "tbl_rookie_scale[salary_year],SelectedYear,"
        "tbl_rookie_scale[pick_number],30)"
    )
    vet_min_formula = (
        "SUMIFS(tbl_minimum_scale[minimum_salary_amount],"
        "tbl_minimum_scale[salary_year],SelectedYear,"
        "tbl_minimum_scale[years_of_service],0)"
    )
    fill_amount_formula = (
        f'IF(RosterFillType="Rookie Min",{rookie_min_formula},'
        f'IF(RosterFillType="Vet Min",{vet_min_formula},'
        f'MIN({rookie_min_formula},{vet_min_formula})))'
    )
    
    worksheet.write(row, COL_LABEL, "  Fill Amount (per row):", audit_formats["label_indent"])
    worksheet.write_formula(row, COL_WAREHOUSE, f"={fill_amount_formula}", audit_formats["money"])
    worksheet.write_formula(
        row, COL_NOTES,
        '="Based on RosterFillType = "&RosterFillType',
        audit_formats["note"]
    )
    row += 1
    
    # Total fill impact = fill_rows_needed * fill_amount
    total_fill_formula = f"IF(RosterFillTarget>0,{fill_rows_needed_formula}*{fill_amount_formula},0)"
    
    worksheet.write(row, COL_LABEL, "  Total Fill Impact:", audit_formats["label_bold"])
    worksheet.write_formula(row, COL_WAREHOUSE, f"={total_fill_formula}", audit_formats["money_bold"])
    worksheet.write(
        row, COL_NOTES,
        "GENERATED rows add this amount to totals (policy delta, not authoritative)",
        audit_formats["note"]
    )
    
    # Conditional formatting to highlight when fill is active
    worksheet.conditional_format(row, COL_WAREHOUSE, row, COL_WAREHOUSE, {
        "type": "cell",
        "criteria": ">",
        "value": 0,
        "format": audit_formats["delta_fail"],  # Use warning format when active
    })
    row += 1
    
    # Warning note about reconciliation
    row += 1
    worksheet.write(
        row, COL_LABEL,
        "⚠ IMPORTANT: Generated fill rows are POLICY ASSUMPTIONS, not authoritative data.",
        audit_formats["note"]
    )
    row += 1
    worksheet.write(
        row, COL_LABEL,
        "  They are NOT included in the reconciliation sections above (which compare warehouse vs drilldowns).",
        audit_formats["note"]
    )
    row += 1
    worksheet.write(
        row, COL_LABEL,
        "  To disable: set RosterFillTarget = 0 in the command bar.",
        audit_formats["note"]
    )
    row += 1
    
    row += 1  # Blank row before next subsection
    
    # =========================================================================
    # Incomplete Roster Charges (explicitly excluded)
    # =========================================================================
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "INCOMPLETE ROSTER CHARGES (Not Implemented)",
        audit_formats["subsection_header"]
    )
    row += 1
    
    # Explanation of what incomplete roster charges are and why they're excluded
    incomplete_roster_notes = [
        "Per CBA: teams with fewer than 12 players (or 14 in off-season) incur a charge for each",
        "\"missing\" roster spot, equal to the minimum salary pro-rated by days (/174 in-season).",
        "",
        "❌ THIS WORKBOOK DOES NOT MODEL INCOMPLETE ROSTER CHARGES. Reasons:",
        "",
        "  1. PCMS authoritative data: If PCMS includes these charges in team_budget_snapshots,",
        "     they are already reflected in warehouse totals. Adding them again would double-count.",
        "",
        "  2. Scenario modeling covered: The Roster Fill feature (above) addresses the common",
        "     analyst use case of projecting totals with fill-to-12/14/15 assumptions.",
        "",
        "  3. Proration complexity: Incomplete roster charges depend on specific dates and days",
        "     remaining in season — information not reliably available in the current data model.",
        "",
        "  4. Rare in practice: Most teams maintain at least 12 players during the season.",
        "",
        "If incomplete roster charges are critical for your analysis:",
        "  • Check if PCMS already includes them in cap_total (compare to official league sources)",
        "  • Use Roster Fill (RosterFillTarget=12) as a proxy for scenario modeling",
        "  • For precise calculations, consult official league cap sheets",
    ]
    
    for note in incomplete_roster_notes:
        worksheet.write(row, COL_LABEL, note, audit_formats["note"])
        row += 1
    
    return row + 2


def _write_plan_diff_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the Plan Diff section showing Baseline vs ActivePlan comparison.
    
    This section provides:
    - Active Plan and Selected Year context display
    - Total plan deltas (cap/tax/apron) for ActivePlan + SelectedYear
    - Journal action counts (total rows vs enabled rows)
    - Link to PLAN_JOURNAL for detailed drilldown
    
    The formulas use LET + FILTER + SUM (dynamic arrays) to aggregate from
    tbl_plan_journal where:
    - plan_id matches ActivePlanId (or plan_id is blank)
    - salary_year matches SelectedYear (or is blank, defaulting to SelectedYear)
    - enabled = "Yes" for counting/summing active actions
    
    Uses the shared PlanRowMask LAMBDA helper for consistent filtering logic.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "PLAN DIFF (Baseline vs ActivePlan)",
        audit_formats["section_header"]
    )
    row += 1
    
    # Context display: Active Plan and Selected Year
    worksheet.write(row, COL_LABEL, "Active Plan:", audit_formats["label_indent"])
    worksheet.write_formula(row, COL_WAREHOUSE, "=ActivePlan", audit_formats["label"])
    worksheet.write(row, COL_NOTES, "Selected scenario from command bar", audit_formats["note"])
    row += 1
    
    worksheet.write(row, COL_LABEL, "Selected Year:", audit_formats["label_indent"])
    worksheet.write_formula(row, COL_WAREHOUSE, "=SelectedYear", audit_formats["count"])
    worksheet.write(row, COL_NOTES, "Year context for plan deltas", audit_formats["note"])
    row += 1
    
    row += 1  # Blank row
    
    # =========================================================================
    # Journal Action Counts
    # =========================================================================
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "Journal Action Counts (for ActivePlan + SelectedYear)",
        audit_formats["subsection_header"]
    )
    row += 1
    
    # Total rows for ActivePlan (regardless of enabled status)
    # Count rows where plan_id matches ActivePlanId AND salary_year matches SelectedYear (or blank)
    # Uses LET + FILTER + ROWS pattern instead of SUMPRODUCT
    total_rows_formula = (
        '=LET('
        '_xlpm.tbl,tbl_plan_journal,'
        '_xlpm.plan_mask,(_xlpm.tbl[plan_id]=ActivePlanId)+(_xlpm.tbl[plan_id]=""),'
        '_xlpm.year_mask,(_xlpm.tbl[salary_year]=SelectedYear)+(_xlpm.tbl[salary_year]=""),'
        '_xlpm.action_mask,_xlpm.tbl[action_type]<>"",'
        '_xlpm.mask,(_xlpm.plan_mask>0)*(_xlpm.year_mask>0)*_xlpm.action_mask,'
        '_xlpm.filtered,FILTER(_xlpm.tbl[action_type],_xlpm.mask,""),'
        'IF(ISTEXT(_xlpm.filtered),0,ROWS(_xlpm.filtered))'
        ')'
    )
    worksheet.write(row, COL_LABEL, "Total Journal Rows:", audit_formats["label_indent"])
    worksheet.write_formula(row, COL_WAREHOUSE, total_rows_formula, audit_formats["count"])
    worksheet.write(row, COL_NOTES, "Rows with action_type for ActivePlan + SelectedYear", audit_formats["note"])
    row += 1
    
    # Enabled rows count
    # Uses LET + FILTER + ROWS with PlanRowMask for consistent filtering
    enabled_rows_formula = (
        '=LET('
        '_xlpm.mask,(((tbl_plan_journal[plan_id]=ActivePlanId)+(tbl_plan_journal[plan_id]=""))*((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]=""))*(tbl_plan_journal[enabled]="Yes")),'
        '_xlpm.filtered,FILTER(tbl_plan_journal[enabled],_xlpm.mask,""),'
        'IF(ISTEXT(_xlpm.filtered),0,ROWS(_xlpm.filtered))'
        ')'
    )
    worksheet.write(row, COL_LABEL, "Enabled Actions:", audit_formats["label_indent"])
    worksheet.write_formula(row, COL_WAREHOUSE, enabled_rows_formula, audit_formats["count"])
    worksheet.write(row, COL_NOTES, "Only enabled actions count toward plan deltas", audit_formats["note"])
    row += 1
    
    # Disabled/pending rows (for awareness)
    worksheet.write(row, COL_LABEL, "Disabled/Pending:", audit_formats["label_indent"])
    disabled_formula = f"={xlsxwriter.utility.xl_rowcol_to_cell(row-2, COL_WAREHOUSE)}-{xlsxwriter.utility.xl_rowcol_to_cell(row-1, COL_WAREHOUSE)}"
    worksheet.write_formula(row, COL_WAREHOUSE, disabled_formula, audit_formats["count"])
    worksheet.write(row, COL_NOTES, "Rows with enabled≠Yes (excluded from deltas)", audit_formats["note"])
    row += 1
    
    row += 1  # Blank row
    
    # =========================================================================
    # Plan Delta Totals
    # =========================================================================
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "Plan Delta Totals (Enabled Actions Only)",
        audit_formats["subsection_header"]
    )
    row += 1
    
    # Column headers for delta display
    headers = ["", "Cap Δ", "Tax Δ", "Apron Δ", "Notes"]
    for col, header in enumerate(headers[:5]):
        worksheet.write(row, col, header, audit_formats["col_header"])
    row += 1
    
    # Delta Cap Total - uses LET + FILTER + SUM with PlanRowMask
    delta_cap_formula = (
        '=LET('
        '_xlpm.mask,(((tbl_plan_journal[plan_id]=ActivePlanId)+(tbl_plan_journal[plan_id]=""))*((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]=""))*(tbl_plan_journal[enabled]="Yes")),'
        'IFERROR(SUM(FILTER(tbl_plan_journal[delta_cap],_xlpm.mask,0)),0)'
        ')'
    )
    delta_tax_formula = (
        '=LET('
        '_xlpm.mask,(((tbl_plan_journal[plan_id]=ActivePlanId)+(tbl_plan_journal[plan_id]=""))*((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]=""))*(tbl_plan_journal[enabled]="Yes")),'
        'IFERROR(SUM(FILTER(tbl_plan_journal[delta_tax],_xlpm.mask,0)),0)'
        ')'
    )
    delta_apron_formula = (
        '=LET('
        '_xlpm.mask,(((tbl_plan_journal[plan_id]=ActivePlanId)+(tbl_plan_journal[plan_id]=""))*((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]=""))*(tbl_plan_journal[enabled]="Yes")),'
        'IFERROR(SUM(FILTER(tbl_plan_journal[delta_apron],_xlpm.mask,0)),0)'
        ')'
    )
    
    worksheet.write(row, COL_LABEL, "PLAN DELTA TOTAL", audit_formats["label_bold"])
    worksheet.write_formula(row, COL_WAREHOUSE, delta_cap_formula, audit_formats["money_bold"])
    worksheet.write_formula(row, COL_DRILLDOWN, delta_tax_formula, audit_formats["money_bold"])
    worksheet.write_formula(row, COL_DELTA, delta_apron_formula, audit_formats["money_bold"])
    worksheet.write(row, COL_NOTES, "Sum of enabled actions for ActivePlan + SelectedYear", audit_formats["note"])
    
    # Conditional formatting for delta totals (highlight non-zero)
    for col in [COL_WAREHOUSE, COL_DRILLDOWN, COL_DELTA]:
        worksheet.conditional_format(row, col, row, col, {
            "type": "cell",
            "criteria": ">",
            "value": 0,
            "format": audit_formats["delta_fail"],  # Red for increasing costs
        })
        worksheet.conditional_format(row, col, row, col, {
            "type": "cell",
            "criteria": "<",
            "value": 0,
            "format": audit_formats["delta_ok"],  # Green for savings
        })
    row += 1
    
    row += 1  # Blank row
    
    # =========================================================================
    # Drilldown Link
    # =========================================================================
    worksheet.write(
        row, COL_LABEL,
        "➤ For full journal drilldown, see PLAN_JOURNAL sheet",
        audit_formats["note"]
    )
    row += 1
    worksheet.write(
        row, COL_LABEL,
        "  PLAN_JOURNAL shows per-action details + cumulative running totals",
        audit_formats["note"]
    )
    row += 1
    worksheet.write(
        row, COL_LABEL,
        "  BUDGET_LEDGER shows plan deltas by action type with derived totals",
        audit_formats["note"]
    )
    row += 1
    
    # Note about Baseline behavior
    row += 1
    worksheet.write(
        row, COL_LABEL,
        "ℹ When ActivePlan = 'Baseline', deltas should be $0 (no journal entries).",
        audit_formats["note"]
    )
    row += 1
    
    return row + 2


def _write_notes_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    audit_formats: dict[str, Any],
) -> int:
    """Write the notes and guidance section.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "NOTES",
        audit_formats["subsection_header"]
    )
    row += 1
    
    notes = [
        "• This sheet validates that drilldown table sums match warehouse totals",
        "• Any non-zero delta indicates a reconciliation issue that needs investigation",
        "• Row counts help verify that all expected rows are included",
        "• Plan Diff section shows ActivePlan impact vs Baseline (above)",
        "• See META sheet for validation status, timestamps, and any build errors",
        "• See BUDGET_LEDGER for the authoritative totals statement",
        "• See ROSTER_GRID for per-row drilldowns by bucket",
    ]
    
    for note in notes:
        worksheet.write(row, COL_LABEL, note, audit_formats["note"])
        row += 1
    
    return row


# =============================================================================
# Main Writer
# =============================================================================

def write_audit_and_reconcile(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    build_meta: dict[str, Any],
) -> None:
    """
    Write AUDIT_AND_RECONCILE sheet — the explainability and verification layer.

    The audit sheet shows:
    - Summary banner (at-a-glance reconciliation status)
    - Cap amount reconciliation (warehouse vs drilldown by bucket)
    - Tax amount reconciliation (warehouse vs drilldown by bucket)
    - Apron amount reconciliation (warehouse vs drilldown by bucket)
    - Row counts comparison
    - Policy assumptions summary (fill rows, toggles)
    - Plan diff (Baseline vs ActivePlan delta totals + action counts)
    - Notes and guidance

    Per the blueprint:
    - Prevent "your number is wrong" fights
    - Every headline total must have a contributing-rows drilldown
    - Visible deltas with conditional formatting (green=OK, red=mismatch)

    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The AUDIT_AND_RECONCILE worksheet
        formats: Standard format dict from create_standard_formats
        build_meta: Build metadata (used for context, not directly displayed here)
    """
    # Sheet title
    worksheet.write(0, 0, "AUDIT & RECONCILE", formats["header"])
    worksheet.write(1, 0, "Reconciliation and explainability layer — verifies drilldown tables match warehouse totals")
    
    # Write read-only command bar (consistent with other UI sheets)
    write_command_bar_readonly(workbook, worksheet, formats)
    
    # Set column widths
    for col, width in COLUMN_WIDTHS.items():
        worksheet.set_column(col, col, width)
    
    # Create audit-specific formats
    audit_formats = _create_audit_formats(workbook)
    
    # Content starts after command bar
    content_row = get_content_start_row()
    
    # 1. Summary banner (at-a-glance status)
    content_row = _write_summary_banner(worksheet, content_row, formats, audit_formats)
    
    # 2. Cap amount reconciliation
    content_row = _write_cap_reconciliation_section(worksheet, content_row, formats, audit_formats)
    
    # 3. Tax amount reconciliation
    content_row = _write_tax_reconciliation_section(worksheet, content_row, formats, audit_formats)
    
    # 4. Apron amount reconciliation
    content_row = _write_apron_reconciliation_section(worksheet, content_row, formats, audit_formats)
    
    # 5. Row counts
    content_row = _write_row_counts_section(worksheet, content_row, formats, audit_formats)
    
    # 6. Policy assumptions
    content_row = _write_policy_assumptions_section(worksheet, content_row, formats, audit_formats)
    
    # 7. Plan diff (Baseline vs ActivePlan)
    content_row = _write_plan_diff_section(worksheet, content_row, formats, audit_formats)
    
    # 8. Notes
    content_row = _write_notes_section(worksheet, content_row, formats, audit_formats)
    
    # Sheet protection
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })
