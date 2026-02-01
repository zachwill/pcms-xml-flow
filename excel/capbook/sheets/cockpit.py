"""
TEAM_COCKPIT sheet writer with shared command bar, alerts, and readouts.

This module implements:
1. The editable command bar (using command_bar.write_command_bar_editable)
2. Validation banner (references MetaValidationStatus)
3. Alert stack section (validation, reconciliation, policy alerts)
4. Primary readouts section driven by DATA_team_salary_warehouse
5. Quick drivers panel (top cap hits, top dead money, top holds)
   - Uses Excel 365 dynamic arrays: LET + FILTER + SORTBY + TAKE
   - Single spilling formula per column (replaces per-row AGGREGATE/MATCH)
   - Mode-aware sorting (respects SelectedMode: Cap/Tax/Apron)
6. Minimum contracts count + total (using is_min_contract)
7. Plan comparison panel (ComparePlan A/B/C/D deltas vs Baseline)
8. Sheet protection with unlocked input cells

Per the blueprint (excel-cap-book-blueprint.md), the command bar is the
workbook's "operating context" and should be consistent across all sheets.

Comparison workflow (per mental-models-and-design-principles.md):
- Analysts compare 2-4 deal candidates side-by-side (lane-based branching)
- The PLAN COMPARISON panel shows deltas for each ComparePlan vs Baseline
- Warnings appear if a ComparePlan is blank or equals Baseline
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import FMT_MONEY, COLOR_ALERT_FAIL, COLOR_ALERT_WARN, COLOR_ALERT_OK
from .command_bar import (
    write_command_bar_editable,
    get_content_start_row,
)


# =============================================================================
# Layout Constants
# =============================================================================

# Readouts start after the command bar
def _get_readouts_start_row() -> int:
    return get_content_start_row()


# Column layout for readouts
COL_READOUT_LABEL = 0
COL_READOUT_VALUE = 1
COL_READOUT_DESC = 2

# Drivers panel column layout (right side)
COL_DRIVERS_LABEL = 4
COL_DRIVERS_PLAYER = 5
COL_DRIVERS_VALUE = 6

# Number of top rows to show in drivers
TOP_N_DRIVERS = 5


# =============================================================================
# Formula Helpers
# =============================================================================

def _sumifs_formula(data_col: str) -> str:
    """Build SUMIFS formula to look up a value from tbl_team_salary_warehouse.

    Uses SelectedTeam and SelectedYear to filter.
    SUMIFS works well for numeric values with two-column lookup.
    """
    return (
        f"=SUMIFS(tbl_team_salary_warehouse[{data_col}],"
        f"tbl_team_salary_warehouse[team_code],SelectedTeam,"
        f"tbl_team_salary_warehouse[salary_year],SelectedYear)"
    )


def _salary_book_choose_cap() -> str:
    """Return an Excel CHOOSE() expression selecting the correct cap_y* column for SelectedYear.

    The workbook exports salary_book_warehouse with relative-year columns
    (cap_y0..cap_y5) relative to MetaBaseYear.

    SelectedYear is an absolute salary_year; we map it to a relative offset:
        idx = (SelectedYear - MetaBaseYear) + 1

    Returns an expression (no leading '=') suitable for embedding in AGGREGATE formulas.
    """
    cols = ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
    return f"CHOOSE(SelectedYear-MetaBaseYear+1,{cols})"


def _salary_book_cap_sumproduct_min() -> str:
    """Return a SUMPRODUCT formula for summing min-contract cap amounts for SelectedYear.

    Filters by team_code=SelectedTeam AND is_min_contract=TRUE.
    Uses the SelectedYear-aware CHOOSE expression to pick the correct cap_y* column.

    Returns a formula string (with leading '=').
    """
    amount_expr = _salary_book_choose_cap()
    return (
        f"=SUMPRODUCT("
        f"(tbl_salary_book_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_salary_book_warehouse[is_min_contract]=TRUE)*"
        f"({amount_expr}))"
    )


def _if_formula(data_col: str) -> str:
    """Build INDEX/MATCH formula for boolean/text values from tbl_team_salary_warehouse.

    For booleans like is_repeater_taxpayer, we convert to display text.
    """
    # Use SUMPRODUCT with INDEX to get single value (works for text/bool)
    return (
        f"=IFERROR(INDEX(tbl_team_salary_warehouse[{data_col}],"
        f"MATCH(1,(tbl_team_salary_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_team_salary_warehouse[salary_year]=SelectedYear),0)),\"\")"
    )


def _countifs_formula(table: str, filters: list[tuple[str, str]]) -> str:
    """Build COUNTIFS formula with multiple conditions.
    
    Args:
        table: Table name (without brackets)
        filters: List of (column_name, criteria) tuples
    
    Returns:
        Excel formula string
    """
    parts = []
    for col, criteria in filters:
        parts.append(f"{table}[{col}],{criteria}")
    return f"=COUNTIFS({','.join(parts)})"


def _sumifs_multi_formula(table: str, sum_col: str, filters: list[tuple[str, str]]) -> str:
    """Build SUMIFS formula with multiple conditions.
    
    Args:
        table: Table name (without brackets)
        sum_col: Column to sum
        filters: List of (column_name, criteria) tuples
    
    Returns:
        Excel formula string
    """
    parts = [f"{table}[{sum_col}]"]
    for col, criteria in filters:
        parts.append(f"{table}[{col}],{criteria}")
    return f"=SUMIFS({','.join(parts)})"


def _large_formula(table: str, value_col: str, name_col: str, rank: int, filters: list[tuple[str, str]]) -> tuple[str, str]:
    """Build formulas to get the Nth largest value and corresponding name.
    
    Returns (value_formula, name_formula) tuple.
    Uses AGGREGATE(14,...) which ignores errors.
    """
    # For the value, we use AGGREGATE(14, 6, ..., rank) = LARGE ignoring errors
    # We need to filter by team_code=SelectedTeam
    # This is complex in Excel - we'll use a SUMPRODUCT approach with LARGE on array
    
    # Value formula: Get the Nth largest cap_y0 for the team
    # AGGREGATE(14, 6, array, k) = LARGE(array, k) ignoring errors
    value_formula = (
        f"=IFERROR(AGGREGATE(14,6,"
        f"({table}[{value_col}])/("
        f"({table}[team_code]=SelectedTeam)"
    )
    for col, criteria in filters:
        value_formula += f"*({table}[{col}]={criteria})"
    value_formula += f"),{rank}),0)"
    
    # Name formula: INDEX/MATCH to find the name for this value
    # Use MATCH with SUMPRODUCT for multi-criteria
    name_formula = (
        f"=IFERROR(INDEX({table}[{name_col}],"
        f"MATCH(1,({table}[team_code]=SelectedTeam)"
    )
    for col, criteria in filters:
        name_formula += f"*({table}[{col}]={criteria})"
    name_formula += f"*({table}[{value_col}]=" + value_formula[1:] + f"),0)),\"\")"
    
    return value_formula, name_formula


# =============================================================================
# Write Functions
# =============================================================================

def _write_validation_banner(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the validation status banner.
    
    This banner shows PASS/FAIL based on MetaValidationStatus.
    Uses conditional formatting to highlight failures.
    
    Returns:
        Next available row
    """
    # Create banner format
    banner_fmt = workbook.add_format({
        "bold": True,
        "font_size": 12,
        "align": "left",
        "valign": "vcenter",
    })
    
    # Write the banner cell with formula
    worksheet.write_formula(
        row, COL_READOUT_LABEL,
        '=IF(MetaValidationStatus="PASS","✓ Data Validated","⚠ VALIDATION FAILED")',
        banner_fmt
    )
    worksheet.merge_range(row, COL_READOUT_LABEL, row, COL_READOUT_DESC, "", banner_fmt)
    
    # Re-write after merge with formula
    worksheet.write_formula(
        row, COL_READOUT_LABEL,
        '=IF(MetaValidationStatus="PASS","✓ Data Validated","⚠ VALIDATION FAILED")',
        banner_fmt
    )
    
    # Add conditional formatting
    worksheet.conditional_format(row, COL_READOUT_LABEL, row, COL_READOUT_DESC, {
        "type": "formula",
        "criteria": '=MetaValidationStatus<>"PASS"',
        "format": formats["alert_fail"],
    })
    worksheet.conditional_format(row, COL_READOUT_LABEL, row, COL_READOUT_DESC, {
        "type": "formula",
        "criteria": '=MetaValidationStatus="PASS"',
        "format": formats["alert_ok"],
    })
    
    return row + 1


def _mode_drilldown_sum_formula() -> str:
    """Build formula to sum drilldowns for SelectedMode (Cap/Tax/Apron).
    
    Uses CHOOSE(MATCH(SelectedMode,...)) to select the right column base (cap/tax/apron)
    across salary_book, cap_holds, and dead_money warehouses.
    
    Returns an expression (no leading '=') suitable for use in formulas.
    """
    # For salary_book_warehouse: need CHOOSE for relative-year columns
    # cap_y0..cap_y5, tax_y0..tax_y5, apron_y0..apron_y5
    def salary_book_mode_choose(mode_col: str) -> str:
        """Choose expression for salary_book_warehouse by mode and year."""
        cols = ",".join(f"tbl_salary_book_warehouse[{mode_col}_y{{i}}]" for i in range(6))
        return f"CHOOSE(SelectedYear-MetaBaseYear+1,{cols})"
    
    # Build the SUMPRODUCT for salary_book (both is_two_way=TRUE and FALSE)
    # Mode-aware: CHOOSE(MATCH(SelectedMode,{"Cap","Tax","Apron"},0), cap_expr, tax_expr, apron_expr)
    cap_sb = (
        "SUMPRODUCT((tbl_salary_book_warehouse[team_code]=SelectedTeam)*"
        f"CHOOSE(SelectedYear-MetaBaseYear+1,"
        + ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
        + "))"
    )
    tax_sb = (
        "SUMPRODUCT((tbl_salary_book_warehouse[team_code]=SelectedTeam)*"
        f"CHOOSE(SelectedYear-MetaBaseYear+1,"
        + ",".join(f"tbl_salary_book_warehouse[tax_y{i}]" for i in range(6))
        + "))"
    )
    apron_sb = (
        "SUMPRODUCT((tbl_salary_book_warehouse[team_code]=SelectedTeam)*"
        f"CHOOSE(SelectedYear-MetaBaseYear+1,"
        + ",".join(f"tbl_salary_book_warehouse[apron_y{i}]" for i in range(6))
        + "))"
    )
    salary_book_sum = (
        f'CHOOSE(MATCH(SelectedMode,{{"Cap","Tax","Apron"}},0),'
        f'{cap_sb},{tax_sb},{apron_sb})'
    )
    
    # cap_holds_warehouse: cap_amount, tax_amount, apron_amount
    cap_holds_sum = (
        f'CHOOSE(MATCH(SelectedMode,{{"Cap","Tax","Apron"}},0),'
        "SUMIFS(tbl_cap_holds_warehouse[cap_amount],"
        "tbl_cap_holds_warehouse[team_code],SelectedTeam,"
        "tbl_cap_holds_warehouse[salary_year],SelectedYear),"
        "SUMIFS(tbl_cap_holds_warehouse[tax_amount],"
        "tbl_cap_holds_warehouse[team_code],SelectedTeam,"
        "tbl_cap_holds_warehouse[salary_year],SelectedYear),"
        "SUMIFS(tbl_cap_holds_warehouse[apron_amount],"
        "tbl_cap_holds_warehouse[team_code],SelectedTeam,"
        "tbl_cap_holds_warehouse[salary_year],SelectedYear))"
    )
    
    # dead_money_warehouse: cap_value, tax_value, apron_value
    dead_money_sum = (
        f'CHOOSE(MATCH(SelectedMode,{{"Cap","Tax","Apron"}},0),'
        "SUMIFS(tbl_dead_money_warehouse[cap_value],"
        "tbl_dead_money_warehouse[team_code],SelectedTeam,"
        "tbl_dead_money_warehouse[salary_year],SelectedYear),"
        "SUMIFS(tbl_dead_money_warehouse[tax_value],"
        "tbl_dead_money_warehouse[team_code],SelectedTeam,"
        "tbl_dead_money_warehouse[salary_year],SelectedYear),"
        "SUMIFS(tbl_dead_money_warehouse[apron_value],"
        "tbl_dead_money_warehouse[team_code],SelectedTeam,"
        "tbl_dead_money_warehouse[salary_year],SelectedYear))"
    )
    
    return f"({salary_book_sum}+{cap_holds_sum}+{dead_money_sum})"


def _mode_warehouse_total_formula() -> str:
    """Build formula to get warehouse total for SelectedMode.
    
    Uses CHOOSE(MATCH(SelectedMode,...)) to select cap_total, tax_total, or apron_total.
    
    Returns an expression (no leading '=') suitable for use in formulas.
    """
    return (
        f'CHOOSE(MATCH(SelectedMode,{{"Cap","Tax","Apron"}},0),'
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


def _write_alert_stack(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the alert stack section.
    
    Alerts are formula-driven and show/hide based on conditions:
    - Validation failed
    - Fill rows are enabled (policy toggle)
    - Two-way in totals info
    - Reconciliation delta (mode-aware)
    
    Returns:
        Next available row
    """
    header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    alert_row_fmt = workbook.add_format({
        "font_size": 10,
    })
    
    worksheet.write(row, COL_READOUT_LABEL, "ALERTS", header_fmt)
    row += 1
    
    # Alert 1: Validation failed
    worksheet.write_formula(
        row, COL_READOUT_LABEL,
        '=IF(MetaValidationStatus<>"PASS","⚠ Validation failed — check AUDIT_AND_RECONCILE","")',
        alert_row_fmt
    )
    worksheet.conditional_format(row, COL_READOUT_LABEL, row, COL_READOUT_DESC, {
        "type": "formula",
        "criteria": '=MetaValidationStatus<>"PASS"',
        "format": workbook.add_format({"bg_color": "#FEE2E2", "font_color": "#991B1B"}),  # red-100 / red-800
    })
    row += 1
    
    # Alert 2: Reconciliation delta (mode-aware)
    # Compute: drilldown sum - warehouse total for SelectedMode
    drilldown_sum = _mode_drilldown_sum_formula()
    warehouse_total = _mode_warehouse_total_formula()
    delta_expr = f"({drilldown_sum}-{warehouse_total})"
    
    # Formula: show alert if delta != 0 (with $1 tolerance for floating point)
    reconcile_alert_formula = (
        f'=IF(ABS({delta_expr})>=1,'
        f'"⚠ Unreconciled drilldowns vs warehouse: $"&TEXT(ABS({delta_expr}),"#,##0")&" ("&SelectedMode&") — see AUDIT_AND_RECONCILE",'
        '"")'
    )
    worksheet.write_formula(row, COL_READOUT_LABEL, reconcile_alert_formula, alert_row_fmt)
    worksheet.conditional_format(row, COL_READOUT_LABEL, row, COL_READOUT_DESC, {
        "type": "formula",
        "criteria": f"=ABS({delta_expr})>=1",
        "format": workbook.add_format({"bg_color": "#FEE2E2", "font_color": "#991B1B"}),  # red-100 / red-800
    })
    row += 1
    
    # Alert 3: Roster fill ACTIVE notification
    # When RosterFillTarget > 0, show an informational message that generated rows are included
    worksheet.write_formula(
        row, COL_READOUT_LABEL,
        '=IF(RosterFillTarget>0,"📊 ROSTER FILL ACTIVE — "&RosterFillTarget&" roster target, "&RosterFillType&" amounts. See ROSTER_GRID for generated rows.","")',
        alert_row_fmt
    )
    worksheet.conditional_format(row, COL_READOUT_LABEL, row, COL_READOUT_DESC, {
        "type": "formula",
        "criteria": "=RosterFillTarget>0",
        "format": workbook.add_format({"bg_color": "#FEF3C7", "font_color": "#92400E"}),  # amber-100 / amber-800 (warning)
    })
    row += 1
    
    # Alert 4: ShowExistsOnlyRows info message
    # The EXISTS_ONLY section is now implemented in ROSTER_GRID.
    # When toggle is "Yes", show an informational message pointing to ROSTER_GRID.
    worksheet.write_formula(
        row, COL_READOUT_LABEL,
        '=IF(ShowExistsOnlyRows="Yes","ℹ️ EXISTS_ONLY section visible in ROSTER_GRID — non-counting rows with future-year amounts","")',
        alert_row_fmt
    )
    worksheet.conditional_format(row, COL_READOUT_LABEL, row, COL_READOUT_DESC, {
        "type": "formula",
        "criteria": '=ShowExistsOnlyRows="Yes"',
        "format": workbook.add_format({"bg_color": "#DBEAFE", "font_color": "#1E40AF"}),  # blue-100 / blue-800 (info)
    })
    row += 1
    
    # NOTE: The former "Two-way toggles NOT YET IMPLEMENTED" alert was removed.
    # Two-way counting is a CBA fact (2-way counts toward cap totals, not roster).
    # The COCKPIT now shows informational 2-way readouts in PRIMARY READOUTS section.
    
    # Blank row for spacing
    row += 1
    
    return row


def _write_primary_readouts(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the primary readouts section.
    
    Returns:
        Next available row
    """
    # Create formats
    money_fmt = workbook.add_format({"num_format": FMT_MONEY, "bold": True})
    label_fmt = workbook.add_format({"bold": False})
    bold_fmt = workbook.add_format({"bold": True})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    
    # Section header
    worksheet.write(row, COL_READOUT_LABEL, "PRIMARY READOUTS", section_header_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(values update when Team/Year changes)")
    row += 1
    
    # Cap Position
    worksheet.write(row, COL_READOUT_LABEL, "Cap Position:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("over_cap"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({_sumifs_formula("over_cap")}>0,"over cap","cap room")',
    )
    row += 1
    
    # Tax Position
    worksheet.write(row, COL_READOUT_LABEL, "Tax Position:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("room_under_tax"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({_sumifs_formula("room_under_tax")}>0,"under tax line","over tax line")',
    )
    row += 1
    
    # Room Under Apron 1
    worksheet.write(row, COL_READOUT_LABEL, "Room Under Apron 1:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("room_under_apron1"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({_sumifs_formula("room_under_apron1")}>0,"under 1st apron","at/above 1st apron")',
    )
    row += 1
    
    # Room Under Apron 2
    worksheet.write(row, COL_READOUT_LABEL, "Room Under Apron 2:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("room_under_apron2"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({_sumifs_formula("room_under_apron2")}>0,"under 2nd apron","at/above 2nd apron")',
    )
    row += 1
    
    # Roster Count
    worksheet.write(row, COL_READOUT_LABEL, "Roster Count:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("roster_row_count"), bold_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'="NBA roster + "&{_sumifs_formula("two_way_row_count")}&" two-way"',
    )
    row += 1
    
    # Repeater Status
    worksheet.write(row, COL_READOUT_LABEL, "Repeater Status:", label_fmt)
    worksheet.write_formula(
        row, COL_READOUT_VALUE,
        f'=IF({_if_formula("is_repeater_taxpayer")}=TRUE,"YES","NO")',
        bold_fmt,
    )
    worksheet.write(row, COL_READOUT_DESC, "(repeater taxpayer if TRUE)", label_fmt)
    row += 1
    
    # Cap Total (for reference)
    worksheet.write(row, COL_READOUT_LABEL, "Cap Total:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("cap_total"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'="vs cap of "&TEXT({_sumifs_formula("salary_cap_amount")},"$#,##0")',
    )
    row += 1
    
    # Tax Total (for reference)
    worksheet.write(row, COL_READOUT_LABEL, "Tax Total:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("tax_total"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'="vs tax line of "&TEXT({_sumifs_formula("tax_level_amount")},"$#,##0")',
    )
    row += 1
    
    # =========================================================================
    # Two-Way Informational Readouts
    # =========================================================================
    # NOTE: Two-way counting is a CBA fact, not a user policy toggle.
    # Per CBA: two-way contracts COUNT toward cap/tax/apron totals but do NOT
    # count toward the 15-player NBA roster limit (they have separate 2-slot limit).
    # These readouts provide transparency for analysts who want to see the breakdown.
    
    # Two-Way Count
    worksheet.write(row, COL_READOUT_LABEL, "Two-Way Count:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("two_way_row_count"), bold_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(separate from 15-player roster)", label_fmt)
    row += 1
    
    # Two-Way Cap Amount (mode-aware would require more complexity; show cap for consistency)
    worksheet.write(row, COL_READOUT_LABEL, "Two-Way Cap Amount:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, _sumifs_formula("cap_2way"), money_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(included in Cap Total above)", label_fmt)
    row += 1
    
    # Blank row for spacing
    row += 1
    
    return row


def _write_minimum_contracts_readout(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the minimum contracts count + total readout.
    
    Uses is_min_contract from tbl_salary_book_warehouse.
    
    Returns:
        Next available row
    """
    money_fmt = workbook.add_format({"num_format": FMT_MONEY, "bold": True})
    label_fmt = workbook.add_format({"bold": False})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    
    worksheet.write(row, COL_READOUT_LABEL, "MINIMUM CONTRACTS", section_header_fmt)
    row += 1
    
    # Count of minimum contracts for selected team
    # COUNTIFS on salary_book_warehouse where team_code=SelectedTeam AND is_min_contract=TRUE
    worksheet.write(row, COL_READOUT_LABEL, "Min Contract Count:", label_fmt)
    worksheet.write_formula(
        row, COL_READOUT_VALUE,
        "=COUNTIFS(tbl_salary_book_warehouse[team_code],SelectedTeam,"
        "tbl_salary_book_warehouse[is_min_contract],TRUE)",
    )
    worksheet.write(row, COL_READOUT_DESC, "players on minimum contracts", label_fmt)
    row += 1
    
    # Total salary for minimum contracts (SelectedYear cap amounts)
    worksheet.write(row, COL_READOUT_LABEL, "Min Contract Total:", label_fmt)
    worksheet.write_formula(
        row, COL_READOUT_VALUE,
        _salary_book_cap_sumproduct_min(),
        money_fmt,
    )
    worksheet.write(row, COL_READOUT_DESC, "(SelectedYear cap amounts)", label_fmt)
    row += 1
    
    # Blank row for spacing
    row += 1
    
    return row


def _write_plan_comparison_panel(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the plan comparison panel showing ComparePlan A/B/C/D deltas.
    
    Per the blueprint (mental-models-and-design-principles.md):
    - Comparison is a first-class workflow
    - Analysts compare 2-4 deal candidates side-by-side (lane-based branching)
    
    This panel shows:
    - For each ComparePlan (A/B/C/D): delta vs Baseline (cap/tax/apron)
    - Warning if ComparePlan is blank or equals Baseline
    - Link to PLAN_JOURNAL for details
    
    Plan delta formulas filter by:
    - plan_id = lookup(ComparePlanX -> tbl_plan_manager[plan_id])
    - salary_year = SelectedYear (or blank)
    - enabled = "Yes"
    
    Returns:
        Next available row
    """
    # Formats
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    panel_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "bg_color": "#3B82F6",  # blue-500
        "font_color": "#FFFFFF",
        "border": 1,
    })
    label_fmt = workbook.add_format({"bold": False})
    plan_label_fmt = workbook.add_format({
        "bold": True,
        "font_size": 10,
    })
    money_fmt = workbook.add_format({"num_format": FMT_MONEY})
    money_delta_pos_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#DC2626",  # red-600 (cost increase)
    })
    money_delta_neg_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#059669",  # green-600 (savings)
    })
    note_fmt = workbook.add_format({
        "font_size": 9,
        "font_color": "#6B7280",
        "italic": True,
    })
    warning_fmt = workbook.add_format({
        "font_size": 9,
        "font_color": "#92400E",  # amber-800
        "bg_color": "#FEF3C7",  # amber-100
    })
    
    # Section header
    worksheet.write(row, COL_READOUT_LABEL, "PLAN COMPARISON", section_header_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(ComparePlan A/B/C/D vs Baseline)")
    row += 1
    
    # Column headers
    worksheet.write(row, COL_READOUT_LABEL, "Plan", panel_header_fmt)
    worksheet.write(row, COL_READOUT_VALUE, "Δ Cap", panel_header_fmt)
    worksheet.write(row, COL_READOUT_DESC, "Status / Notes", panel_header_fmt)
    row += 1
    
    # Helper to build plan delta formula for a given compare plan named range
    def _plan_delta_formula(compare_plan_range: str, delta_col: str) -> str:
        """Build SUMPRODUCT formula to get delta for a ComparePlan.
        
        Logic:
        - Lookup plan_id from tbl_plan_manager where plan_name = ComparePlanX
        - Sum deltas from tbl_plan_journal where:
          - plan_id matches
          - salary_year = SelectedYear OR blank
          - enabled = "Yes"
        
        Returns 0 if the compare plan is blank or not found.
        """
        # Lookup plan_id for the ComparePlan
        plan_id_lookup = (
            f'IFERROR(INDEX(tbl_plan_manager[plan_id],'
            f'MATCH({compare_plan_range},tbl_plan_manager[plan_name],0)),"")'
        )
        
        # SUMPRODUCT for deltas matching that plan_id + SelectedYear + enabled
        return (
            f'=IFERROR(IF({compare_plan_range}="",'
            f'0,'  # Return 0 if compare plan is blank
            f'SUMPRODUCT('
            f'(tbl_plan_journal[{delta_col}])*'
            f'(tbl_plan_journal[enabled]="Yes")*'
            f'(tbl_plan_journal[plan_id]={plan_id_lookup})*'
            f'((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]=""))'
            f')),0)'
        )
    
    # Helper to build status formula for a compare plan
    def _plan_status_formula(compare_plan_range: str) -> str:
        """Build formula to show status/warning for a ComparePlan.
        
        Shows:
        - "(blank)" if the compare plan is not selected
        - "(same as Baseline)" if compare plan equals "Baseline"
        - Action count and link to PLAN_JOURNAL otherwise
        """
        # Lookup plan_id
        plan_id_lookup = (
            f'IFERROR(INDEX(tbl_plan_manager[plan_id],'
            f'MATCH({compare_plan_range},tbl_plan_manager[plan_name],0)),"")'
        )
        
        # Action count for this plan + SelectedYear
        action_count = (
            f'SUMPRODUCT('
            f'((tbl_plan_journal[plan_id]={plan_id_lookup})+(tbl_plan_journal[plan_id]=""))>0,'
            f'((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]=""))>0,'
            f'(tbl_plan_journal[enabled]="Yes")*1'
            f')'
        )
        
        return (
            f'=IF({compare_plan_range}="",'
            f'"(not selected)",'
            f'IF({compare_plan_range}="Baseline",'
            f'"(same as Baseline)",'
            f'{action_count}&" actions → see PLAN_JOURNAL"))'
        )
    
    # Write rows for each ComparePlan
    compare_plans = [
        ("ComparePlanA", "Compare A:"),
        ("ComparePlanB", "Compare B:"),
        ("ComparePlanC", "Compare C:"),
        ("ComparePlanD", "Compare D:"),
    ]
    
    for plan_range, label in compare_plans:
        # Plan name label (shows the selected plan name)
        worksheet.write(row, COL_READOUT_LABEL, label, plan_label_fmt)
        
        # Delta Cap (for now, show cap delta; could expand to show tax/apron)
        cap_formula = _plan_delta_formula(plan_range, "delta_cap")
        worksheet.write_formula(row, COL_READOUT_VALUE, cap_formula, money_fmt)
        
        # Status/notes
        status_formula = _plan_status_formula(plan_range)
        worksheet.write_formula(row, COL_READOUT_DESC, status_formula, note_fmt)
        
        # Conditional formatting: delta values
        worksheet.conditional_format(row, COL_READOUT_VALUE, row, COL_READOUT_VALUE, {
            "type": "cell",
            "criteria": ">",
            "value": 0,
            "format": money_delta_pos_fmt,
        })
        worksheet.conditional_format(row, COL_READOUT_VALUE, row, COL_READOUT_VALUE, {
            "type": "cell",
            "criteria": "<",
            "value": 0,
            "format": money_delta_neg_fmt,
        })
        
        # Conditional formatting: warn if blank or Baseline
        worksheet.conditional_format(row, COL_READOUT_DESC, row, COL_READOUT_DESC, {
            "type": "formula",
            "criteria": f'=OR({plan_range}="",{plan_range}="Baseline")',
            "format": warning_fmt,
        })
        
        row += 1
    
    # Blank row
    row += 1
    
    # Link note
    worksheet.write(
        row, COL_READOUT_LABEL,
        "→ Edit plans in PLAN_MANAGER, actions in PLAN_JOURNAL",
        note_fmt
    )
    row += 2
    
    return row


def _write_quick_drivers(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    start_row: int,
) -> int:
    """Write the quick drivers panel (right side).
    
    Shows:
    - Top N cap hits (from salary_book_warehouse)
    - Top N dead money (from dead_money_warehouse)
    - Top N holds (from cap_holds_warehouse)
    
    Uses Excel 365 dynamic array formulas (LET + FILTER + SORTBY + TAKE)
    instead of legacy AGGREGATE/MATCH patterns.
    
    Each panel writes:
    - A spilling name formula at the first data cell
    - A spilling amount formula at the first data cell
    - Both spill down to fill TOP_N_DRIVERS rows
    
    Returns:
        Next available row
    """
    money_fmt = workbook.add_format({"num_format": FMT_MONEY})
    bold_fmt = workbook.add_format({"bold": True})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    player_fmt = workbook.add_format({"align": "left"})
    
    # Column widths for drivers area
    worksheet.set_column(COL_DRIVERS_LABEL, COL_DRIVERS_LABEL, 16)
    worksheet.set_column(COL_DRIVERS_PLAYER, COL_DRIVERS_PLAYER, 20)
    worksheet.set_column(COL_DRIVERS_VALUE, COL_DRIVERS_VALUE, 14)
    
    row = start_row
    n = TOP_N_DRIVERS
    
    # =========================================================================
    # Top Cap Hits (salary_book_warehouse)
    # =========================================================================
    # Uses LET + FILTER + SORTBY + TAKE pattern:
    #   1. mode_amt: mode-aware amount for SelectedYear (cap/tax/apron)
    #   2. filter_cond: team match + non-two-way + amount > 0
    #   3. FILTER columns by filter_cond
    #   4. SORTBY amount (descending)
    #   5. TAKE first N rows
    # =========================================================================
    
    worksheet.write(row, COL_DRIVERS_LABEL, "TOP CAP HITS", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_PLAYER, "Player", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_VALUE, "Amount", section_header_fmt)
    row += 1
    
    # LET prefix for salary_book filtering (SelectedYear-aware, mode-aware)
    # The salary_book_warehouse has relative-year columns: cap_y0..cap_y5, tax_y0..tax_y5, apron_y0..apron_y5
    # We use CHOOSE(SelectedYear-MetaBaseYear+1, ...) to pick the correct year column
    # and IF(SelectedMode=...) to pick the correct mode prefix
    salary_book_let_prefix = (
        'mode_amt,IF(SelectedMode="Cap",'
        'CHOOSE(SelectedYear-MetaBaseYear+1,'
        + ','.join(f'tbl_salary_book_warehouse[cap_y{i}]' for i in range(6))
        + '),'
        'IF(SelectedMode="Tax",'
        'CHOOSE(SelectedYear-MetaBaseYear+1,'
        + ','.join(f'tbl_salary_book_warehouse[tax_y{i}]' for i in range(6))
        + '),'
        'CHOOSE(SelectedYear-MetaBaseYear+1,'
        + ','.join(f'tbl_salary_book_warehouse[apron_y{i}]' for i in range(6))
        + '))),'
        'filter_cond,(tbl_salary_book_warehouse[team_code]=SelectedTeam)*'
        '(tbl_salary_book_warehouse[is_two_way]=FALSE)*(mode_amt>0),'
    )
    
    # Name formula: FILTER player_name, SORTBY mode_amt DESC, TAKE N
    cap_hits_name_formula = (
        "=LET("
        + salary_book_let_prefix
        + "filtered,FILTER(tbl_salary_book_warehouse[player_name],filter_cond,\"\"),"
        + "sorted_amounts,FILTER(mode_amt,filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(filtered,sorted_amounts,-1),{n}),\"\"))"
    )
    worksheet.write_formula(row, COL_DRIVERS_PLAYER, cap_hits_name_formula, player_fmt)
    
    # Amount formula: FILTER mode_amt, SORTBY mode_amt DESC, TAKE N
    cap_hits_amount_formula = (
        "=LET("
        + salary_book_let_prefix
        + "filtered,FILTER(mode_amt,filter_cond,\"\"),"
        + "sorted_amounts,FILTER(mode_amt,filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(filtered,sorted_amounts,-1),{n}),\"\"))"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, cap_hits_amount_formula, money_fmt)
    
    # Row labels (static, don't spill)
    for rank in range(1, n + 1):
        worksheet.write(row + rank - 1, COL_DRIVERS_LABEL, f"#{rank}")
    
    row += n
    
    # Blank row
    row += 1
    
    # =========================================================================
    # Top Dead Money (dead_money_warehouse)
    # =========================================================================
    # dead_money_warehouse has: cap_value, tax_value, apron_value (per salary_year)
    # Filter by team_code + salary_year, sort by mode-aware value (DESC)
    # =========================================================================
    
    worksheet.write(row, COL_DRIVERS_LABEL, "TOP DEAD MONEY", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_PLAYER, "Player", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_VALUE, "Amount", section_header_fmt)
    row += 1
    
    # LET prefix for dead_money filtering (mode-aware)
    dead_money_let_prefix = (
        'mode_amt,IF(SelectedMode="Cap",tbl_dead_money_warehouse[cap_value],'
        'IF(SelectedMode="Tax",tbl_dead_money_warehouse[tax_value],'
        'tbl_dead_money_warehouse[apron_value])),'
        'filter_cond,(tbl_dead_money_warehouse[team_code]=SelectedTeam)*'
        '(tbl_dead_money_warehouse[salary_year]=SelectedYear)*(mode_amt>0),'
    )
    
    # Name formula
    dead_money_name_formula = (
        "=LET("
        + dead_money_let_prefix
        + "filtered,FILTER(tbl_dead_money_warehouse[player_name],filter_cond,\"\"),"
        + "sorted_amounts,FILTER(mode_amt,filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(filtered,sorted_amounts,-1),{n}),\"\"))"
    )
    worksheet.write_formula(row, COL_DRIVERS_PLAYER, dead_money_name_formula, player_fmt)
    
    # Amount formula
    dead_money_amount_formula = (
        "=LET("
        + dead_money_let_prefix
        + "filtered,FILTER(mode_amt,filter_cond,\"\"),"
        + "sorted_amounts,FILTER(mode_amt,filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(filtered,sorted_amounts,-1),{n}),\"\"))"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, dead_money_amount_formula, money_fmt)
    
    # Row labels
    for rank in range(1, n + 1):
        worksheet.write(row + rank - 1, COL_DRIVERS_LABEL, f"#{rank}")
    
    row += n
    
    # Dead money total for the team/year (mode-aware)
    worksheet.write(row, COL_DRIVERS_LABEL, "Total:", bold_fmt)
    dead_money_total_formula = (
        "=LET("
        + dead_money_let_prefix
        + "SUM(FILTER(mode_amt,filter_cond,0)))"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, dead_money_total_formula, money_fmt)
    row += 1
    
    # Blank row
    row += 1
    
    # =========================================================================
    # Top Cap Holds (cap_holds_warehouse)
    # =========================================================================
    # cap_holds_warehouse has: cap_amount, tax_amount, apron_amount (per salary_year)
    # Filter by team_code + salary_year, sort by mode-aware amount (DESC)
    # =========================================================================
    
    worksheet.write(row, COL_DRIVERS_LABEL, "TOP HOLDS", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_PLAYER, "Player", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_VALUE, "Amount", section_header_fmt)
    row += 1
    
    # LET prefix for cap_holds filtering (mode-aware)
    cap_holds_let_prefix = (
        'mode_amt,IF(SelectedMode="Cap",tbl_cap_holds_warehouse[cap_amount],'
        'IF(SelectedMode="Tax",tbl_cap_holds_warehouse[tax_amount],'
        'tbl_cap_holds_warehouse[apron_amount])),'
        'filter_cond,(tbl_cap_holds_warehouse[team_code]=SelectedTeam)*'
        '(tbl_cap_holds_warehouse[salary_year]=SelectedYear)*(mode_amt>0),'
    )
    
    # Name formula
    cap_holds_name_formula = (
        "=LET("
        + cap_holds_let_prefix
        + "filtered,FILTER(tbl_cap_holds_warehouse[player_name],filter_cond,\"\"),"
        + "sorted_amounts,FILTER(mode_amt,filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(filtered,sorted_amounts,-1),{n}),\"\"))"
    )
    worksheet.write_formula(row, COL_DRIVERS_PLAYER, cap_holds_name_formula, player_fmt)
    
    # Amount formula
    cap_holds_amount_formula = (
        "=LET("
        + cap_holds_let_prefix
        + "filtered,FILTER(mode_amt,filter_cond,\"\"),"
        + "sorted_amounts,FILTER(mode_amt,filter_cond,0),"
        + f"IFNA(TAKE(SORTBY(filtered,sorted_amounts,-1),{n}),\"\"))"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, cap_holds_amount_formula, money_fmt)
    
    # Row labels
    for rank in range(1, n + 1):
        worksheet.write(row + rank - 1, COL_DRIVERS_LABEL, f"#{rank}")
    
    row += n
    
    # Holds total for the team/year (mode-aware)
    worksheet.write(row, COL_DRIVERS_LABEL, "Total:", bold_fmt)
    cap_holds_total_formula = (
        "=LET("
        + cap_holds_let_prefix
        + "SUM(FILTER(mode_amt,filter_cond,0)))"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, cap_holds_total_formula, money_fmt)
    row += 1
    
    return row


# =============================================================================
# Main Writer
# =============================================================================

def write_team_cockpit_with_command_bar(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    build_meta: dict[str, Any],
    team_codes: list[str] | None = None,
) -> None:
    """
    Write TEAM_COCKPIT sheet with editable command bar, alerts, and readouts.

    The command bar provides the workbook's operating context:
    - SelectedTeam, SelectedYear, AsOfDate, SelectedMode
    - Policy toggles (roster fill, etc.)
    - Plan selectors (ActivePlan, ComparePlanA/B/C/D)

    The cockpit includes:
    - Validation banner (PASS/FAIL status)
    - Alert stack (validation, policy alerts)
    - Primary readouts (cap/tax/apron positions, roster counts)
    - Minimum contracts count + total
    - Plan comparison panel (ComparePlan A/B/C/D deltas vs Baseline)
    - Quick drivers panel (top cap hits, dead money, holds)

    Args:
        workbook: The XlsxWriter Workbook (needed for define_name and formats)
        worksheet: The TEAM_COCKPIT worksheet
        formats: Standard format dict from create_standard_formats
        build_meta: Build metadata (base_year, as_of_date, etc.)
        team_codes: Optional list of team codes for validation dropdown
    """
    # Sheet title (row 0-1)
    worksheet.write(0, 0, "TEAM COCKPIT", formats["header"])
    worksheet.write(1, 0, "Primary flight display for team cap position")
    
    # Write the editable command bar
    write_command_bar_editable(
        workbook,
        worksheet,
        formats,
        build_meta,
        team_codes=team_codes,
        plan_names=None,  # Will be populated when PLAN_MANAGER is implemented
    )
    
    # =========================================================================
    # Content Sections (after command bar)
    # =========================================================================
    
    content_row = _get_readouts_start_row()
    
    # Column widths for readouts area
    worksheet.set_column(COL_READOUT_LABEL, COL_READOUT_LABEL, 18)
    worksheet.set_column(COL_READOUT_VALUE, COL_READOUT_VALUE, 14)
    worksheet.set_column(COL_READOUT_DESC, COL_READOUT_DESC, 30)
    
    # 1. Validation banner
    content_row = _write_validation_banner(workbook, worksheet, formats, content_row)
    
    # Blank row
    content_row += 1
    
    # 2. Alert stack
    content_row = _write_alert_stack(workbook, worksheet, formats, content_row)
    
    # 3. Primary readouts
    content_row = _write_primary_readouts(workbook, worksheet, formats, content_row)
    
    # 4. Minimum contracts readout
    content_row = _write_minimum_contracts_readout(workbook, worksheet, formats, content_row)
    
    # 5. Plan comparison panel (ComparePlan A/B/C/D deltas)
    content_row = _write_plan_comparison_panel(workbook, worksheet, formats, content_row)
    
    # 6. Quick drivers panel (starts at same row as validation banner, on right side)
    drivers_start_row = _get_readouts_start_row()
    _write_quick_drivers(workbook, worksheet, formats, drivers_start_row)
    
    # =========================================================================
    # Sheet Protection
    # =========================================================================
    # Protect the sheet but allow editing of unlocked (input) cells
    # Input cells are marked with locked=False in command_bar.py
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,  # Allow format changes
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })


def get_command_bar_cell_refs() -> dict[str, tuple[int, int]]:
    """Return cell positions (row, col) for command bar inputs.

    Useful for other sheets that need to reference these cells.
    
    Deprecated: Use the named ranges (SelectedTeam, etc.) instead of cell refs.
    """
    from .command_bar import NAMED_RANGES
    return NAMED_RANGES.copy()
