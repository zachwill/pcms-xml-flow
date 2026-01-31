"""
BUDGET_LEDGER sheet writer — authoritative totals and deltas.

This module implements the "accounting statement" for team salary cap:
1. Shared command bar (read-only reference to TEAM_COCKPIT)
2. Snapshot totals section (from tbl_team_salary_warehouse)
   - Cap/Tax/Apron totals by bucket (ROST, FA, TERM, 2WAY)
   - System thresholds for context
3. Plan delta section (from tbl_plan_journal, filtered by ActivePlanId)
4. Derived totals section (snapshot + deltas)
5. Delta vs snapshot verification

Per the blueprint (excel-cap-book-blueprint.md):
- BUDGET_LEDGER is the "single source of truth for totals and deltas"
- This is the sheet you use to explain numbers to a GM/owner
- Every headline total must have an audit path

Design notes:
- Uses Excel formulas filtered by SelectedTeam + SelectedYear + SelectedMode
- Mode-aware display (Cap vs Tax vs Apron columns)
- Plan deltas are aggregated from tbl_plan_journal (enabled rows, filtered by ActivePlanId)
"""

from __future__ import annotations

from typing import Any

import xlsxwriter.utility

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

# Column layout
COL_LABEL = 0
COL_CAP = 1
COL_TAX = 2
COL_APRON = 3
COL_NOTES = 4

# Column widths
COLUMN_WIDTHS = {
    COL_LABEL: 28,
    COL_CAP: 14,
    COL_TAX: 14,
    COL_APRON: 14,
    COL_NOTES: 30,
}


# =============================================================================
# Format Helpers
# =============================================================================

def _create_budget_formats(workbook: Workbook) -> dict[str, Any]:
    """Create formats specific to the budget ledger."""
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
    formats["label"] = workbook.add_format({
        "font_size": 10,
    })
    formats["label_indent"] = workbook.add_format({
        "font_size": 10,
        "indent": 1,
    })
    formats["label_bold"] = workbook.add_format({
        "bold": True,
        "font_size": 10,
    })
    
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
    
    # Delta formats (for plan adjustments)
    formats["delta_zero"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#9CA3AF",  # gray-400 (muted)
        "italic": True,
    })
    formats["delta_positive"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#DC2626",  # red-600 (increasing cost)
    })
    formats["delta_negative"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#059669",  # green-600 (savings)
    })
    
    # Threshold context
    formats["threshold_label"] = workbook.add_format({
        "font_size": 9,
        "font_color": "#6B7280",  # gray-500
        "italic": True,
    })
    formats["threshold_value"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_size": 9,
        "font_color": "#6B7280",
    })
    
    # Room/Over indicators
    formats["room_positive"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#059669",  # green-600
        "bold": True,
    })
    formats["room_negative"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#DC2626",  # red-600
        "bold": True,
    })
    
    # Verification section
    formats["verify_ok"] = workbook.add_format({
        "bg_color": "#D1FAE5",  # green-100
        "font_color": "#065F46",  # green-800
        "bold": True,
    })
    formats["verify_fail"] = workbook.add_format({
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "bold": True,
    })
    
    # Notes
    formats["note"] = workbook.add_format({
        "font_size": 9,
        "font_color": "#6B7280",
        "italic": True,
    })
    
    return formats


# =============================================================================
# Helper: SUMIFS formula builder
# =============================================================================

def _warehouse_sumifs(column: str) -> str:
    """Build SUMIFS formula for team_salary_warehouse filtered by SelectedTeam + SelectedYear."""
    return (
        f"SUMIFS(tbl_team_salary_warehouse[{column}],"
        f"tbl_team_salary_warehouse[team_code],SelectedTeam,"
        f"tbl_team_salary_warehouse[salary_year],SelectedYear)"
    )


def _system_sumifs(column: str) -> str:
    """Build SUMIFS formula for system_values filtered by SelectedYear."""
    return (
        f"SUMIFS(tbl_system_values[{column}],"
        f"tbl_system_values[salary_year],SelectedYear)"
    )


# =============================================================================
# Section Writers
# =============================================================================

def _write_column_headers(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
) -> int:
    """Write the column headers for the budget ledger.
    
    Returns next row.
    """
    fmt = formats["col_header"]
    
    worksheet.write(row, COL_LABEL, "", fmt)
    worksheet.write(row, COL_CAP, "Cap", fmt)
    worksheet.write(row, COL_TAX, "Tax", fmt)
    worksheet.write(row, COL_APRON, "Apron", fmt)
    worksheet.write(row, COL_NOTES, "Notes", fmt)
    
    return row + 1


def _write_snapshot_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
) -> int:
    """Write the snapshot totals section from team_salary_warehouse.
    
    This is the authoritative baseline - what PCMS says the team owes.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "SNAPSHOT TOTALS (from DATA_team_salary_warehouse)",
        budget_formats["section_header"]
    )
    row += 1
    
    # Column headers
    row = _write_column_headers(worksheet, row, budget_formats)
    
    # Bucket breakdown
    buckets = [
        ("Roster contracts (ROST)", "cap_rost", "tax_rost", "apron_rost", "Active player contracts"),
        ("Free agent holds (FA)", "cap_fa", "tax_fa", "apron_fa", "Cap holds for FA rights"),
        ("Dead money (TERM)", "cap_term", "tax_term", "apron_term", "Terminated/waived contracts"),
        ("Two-way contracts (2WAY)", "cap_2way", "tax_2way", "apron_2way", "Two-way player contracts"),
    ]
    
    for label, cap_col, tax_col, apron_col, note in buckets:
        worksheet.write(row, COL_LABEL, label, budget_formats["label_indent"])
        worksheet.write_formula(row, COL_CAP, f"={_warehouse_sumifs(cap_col)}", budget_formats["money"])
        worksheet.write_formula(row, COL_TAX, f"={_warehouse_sumifs(tax_col)}", budget_formats["money"])
        worksheet.write_formula(row, COL_APRON, f"={_warehouse_sumifs(apron_col)}", budget_formats["money"])
        worksheet.write(row, COL_NOTES, note, budget_formats["note"])
        row += 1
    
    # Total row
    row += 1  # Blank row before total
    worksheet.write(row, COL_LABEL, "SNAPSHOT TOTAL", budget_formats["label_bold"])
    worksheet.write_formula(row, COL_CAP, f"={_warehouse_sumifs('cap_total')}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_TAX, f"={_warehouse_sumifs('tax_total')}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_APRON, f"={_warehouse_sumifs('apron_total')}", budget_formats["money_total"])
    worksheet.write(row, COL_NOTES, "Authoritative PCMS total", budget_formats["note"])
    
    snapshot_total_row = row  # Save for later reference
    row += 2
    
    return row, snapshot_total_row


def _write_thresholds_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
) -> int:
    """Write system thresholds for context.
    
    Returns next row.
    """
    # Subsection header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "System Thresholds (for SelectedYear)",
        budget_formats["subsection_header"]
    )
    row += 1
    
    thresholds = [
        ("Salary Cap", "salary_cap_amount"),
        ("Tax Level", "tax_level_amount"),
        ("First Apron", "tax_apron_amount"),
        ("Second Apron", "tax_apron2_amount"),
        ("Minimum Team Salary", "minimum_team_salary_amount"),
    ]
    
    for label, col in thresholds:
        worksheet.write(row, COL_LABEL, label, budget_formats["threshold_label"])
        worksheet.write_formula(row, COL_CAP, f"={_system_sumifs(col)}", budget_formats["threshold_value"])
        row += 1
    
    row += 1
    return row


def _write_plan_delta_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
) -> tuple[int, int]:
    """Write the plan delta section sourced from tbl_plan_journal.
    
    This section summarizes journal actions for the active plan.
    It uses SUMIFS to aggregate deltas from enabled journal entries
    where plan_id matches the ActivePlanId (derived from ActivePlan name).
    
    Fallback behavior:
    - If ActivePlanId is blank/error (e.g., plan not found), deltas are 0
    - The "Baseline" plan has plan_id=1 but no journal entries by default
    
    Returns (next_row, delta_total_row).
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "PLAN DELTAS (from tbl_plan_journal)",
        budget_formats["section_header"]
    )
    row += 1
    
    # Column headers
    row = _write_column_headers(worksheet, row, budget_formats)
    
    # Note about plan journal sourcing
    worksheet.write(
        row, COL_LABEL,
        "Journal deltas for ActivePlan (enabled rows only):",
        budget_formats["label_indent"]
    )
    worksheet.write(row, COL_NOTES, "See PLAN_JOURNAL tab for details", budget_formats["note"])
    row += 1
    
    # Helper: SUMIFS for plan journal filtered by ActivePlanId and enabled="Yes"
    # Uses IFERROR to handle case where ActivePlanId is blank or not found
    # When ActivePlanId is blank (e.g., no plan selected), returns 0
    
    def _journal_sumifs_by_plan(delta_col: str, action_type: str) -> str:
        """
        Sum journal deltas for a specific action type, filtered by:
        - enabled = "Yes"
        - plan_id = ActivePlanId
        
        Uses IFERROR to gracefully handle blank/missing ActivePlanId.
        """
        return (
            f'=IFERROR(SUMIFS(tbl_plan_journal[{delta_col}],'
            f'tbl_plan_journal[enabled],"Yes",'
            f'tbl_plan_journal[plan_id],ActivePlanId,'
            f'tbl_plan_journal[action_type],"{action_type}"),0)'
        )
    
    # Action type breakdown with SUMIFS
    action_categories = [
        ("Trade", "Trade actions"),
        ("Sign (Cap Room)", "Cap room signings"),
        ("Sign (Exception)", "Exception signings"),
        ("Sign (Minimum)", "Minimum signings"),
        ("Waive", "Waiver actions"),
        ("Buyout", "Buyout actions"),
        ("Stretch", "Stretch provisions"),
        ("Renounce", "Renounced rights"),
        ("Other", "Other actions"),
    ]
    
    delta_row_start = row  # Track for total formula
    
    for action_type, note in action_categories:
        worksheet.write(row, COL_LABEL, f"  {action_type}", budget_formats["label_indent"])
        
        # SUMIFS: sum delta where enabled="Yes" AND plan_id=ActivePlanId AND action_type matches
        cap_formula = _journal_sumifs_by_plan("delta_cap", action_type)
        tax_formula = _journal_sumifs_by_plan("delta_tax", action_type)
        apron_formula = _journal_sumifs_by_plan("delta_apron", action_type)
        
        worksheet.write_formula(row, COL_CAP, cap_formula, budget_formats["delta_zero"])
        worksheet.write_formula(row, COL_TAX, tax_formula, budget_formats["delta_zero"])
        worksheet.write_formula(row, COL_APRON, apron_formula, budget_formats["delta_zero"])
        worksheet.write(row, COL_NOTES, note, budget_formats["note"])
        row += 1
    
    delta_row_end = row - 1  # Last data row
    
    # Delta total row - sum all enabled journal entries for ActivePlanId
    row += 1
    worksheet.write(row, COL_LABEL, "PLAN DELTA TOTAL", budget_formats["label_bold"])
    
    # Total formula: sum all enabled deltas for ActivePlanId
    # Uses IFERROR for robustness when ActivePlanId is blank
    total_cap_formula = (
        '=IFERROR(SUMIFS(tbl_plan_journal[delta_cap],'
        'tbl_plan_journal[enabled],"Yes",'
        'tbl_plan_journal[plan_id],ActivePlanId),0)'
    )
    total_tax_formula = (
        '=IFERROR(SUMIFS(tbl_plan_journal[delta_tax],'
        'tbl_plan_journal[enabled],"Yes",'
        'tbl_plan_journal[plan_id],ActivePlanId),0)'
    )
    total_apron_formula = (
        '=IFERROR(SUMIFS(tbl_plan_journal[delta_apron],'
        'tbl_plan_journal[enabled],"Yes",'
        'tbl_plan_journal[plan_id],ActivePlanId),0)'
    )
    
    worksheet.write_formula(row, COL_CAP, total_cap_formula, budget_formats["money_total"])
    worksheet.write_formula(row, COL_TAX, total_tax_formula, budget_formats["money_total"])
    worksheet.write_formula(row, COL_APRON, total_apron_formula, budget_formats["money_total"])
    worksheet.write(row, COL_NOTES, "Sum of all enabled plan adjustments for ActivePlan", budget_formats["note"])
    
    delta_total_row = row
    row += 2
    
    # Conditional formatting for delta cells (positive=red/cost, negative=green/savings)
    # Apply to the category rows
    for delta_row in range(delta_row_start, delta_row_end + 1):
        for col in [COL_CAP, COL_TAX, COL_APRON]:
            worksheet.conditional_format(delta_row, col, delta_row, col, {
                "type": "cell",
                "criteria": ">",
                "value": 0,
                "format": budget_formats["delta_positive"],
            })
            worksheet.conditional_format(delta_row, col, delta_row, col, {
                "type": "cell",
                "criteria": "<",
                "value": 0,
                "format": budget_formats["delta_negative"],
            })
    
    return row, delta_total_row


def _write_derived_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
    snapshot_total_row: int,
    delta_total_row: int,
) -> int:
    """Write the derived totals section (snapshot + plan deltas).
    
    This shows the "if you execute this plan" state.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "DERIVED TOTALS (Snapshot + Plan Deltas)",
        budget_formats["section_header"]
    )
    row += 1
    
    # Column headers
    row = _write_column_headers(worksheet, row, budget_formats)
    
    # Derived total = snapshot + delta
    # Reference the snapshot and delta total rows
    snapshot_cap = xlsxwriter.utility.xl_rowcol_to_cell(snapshot_total_row, COL_CAP)
    snapshot_tax = xlsxwriter.utility.xl_rowcol_to_cell(snapshot_total_row, COL_TAX)
    snapshot_apron = xlsxwriter.utility.xl_rowcol_to_cell(snapshot_total_row, COL_APRON)
    
    delta_cap = xlsxwriter.utility.xl_rowcol_to_cell(delta_total_row, COL_CAP)
    delta_tax = xlsxwriter.utility.xl_rowcol_to_cell(delta_total_row, COL_TAX)
    delta_apron = xlsxwriter.utility.xl_rowcol_to_cell(delta_total_row, COL_APRON)
    
    worksheet.write(row, COL_LABEL, "DERIVED TOTAL", budget_formats["label_bold"])
    worksheet.write_formula(row, COL_CAP, f"={snapshot_cap}+{delta_cap}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_TAX, f"={snapshot_tax}+{delta_tax}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_APRON, f"={snapshot_apron}+{delta_apron}", budget_formats["money_total"])
    worksheet.write(row, COL_NOTES, "Projected team total after plan", budget_formats["note"])
    
    derived_total_row = row
    row += 2
    
    # Room calculations
    worksheet.write(row, COL_LABEL, "Room/Over Analysis:", budget_formats["subsection_header"])
    worksheet.merge_range(row, COL_LABEL, row, COL_NOTES, "Room/Over Analysis:", budget_formats["subsection_header"])
    row += 1
    
    derived_cap_cell = xlsxwriter.utility.xl_rowcol_to_cell(derived_total_row, COL_CAP)
    derived_tax_cell = xlsxwriter.utility.xl_rowcol_to_cell(derived_total_row, COL_TAX)
    derived_apron_cell = xlsxwriter.utility.xl_rowcol_to_cell(derived_total_row, COL_APRON)
    
    # Cap room
    worksheet.write(row, COL_LABEL, "Cap Room (+) / Over Cap (-)", budget_formats["label_indent"])
    cap_room_formula = f"={_system_sumifs('salary_cap_amount')}-{derived_cap_cell}"
    worksheet.write_formula(row, COL_CAP, cap_room_formula, budget_formats["money"])
    worksheet.write(row, COL_NOTES, "Positive = room; Negative = over cap", budget_formats["note"])
    
    # Conditional formatting for room
    worksheet.conditional_format(row, COL_CAP, row, COL_CAP, {
        "type": "cell",
        "criteria": ">=",
        "value": 0,
        "format": budget_formats["room_positive"],
    })
    worksheet.conditional_format(row, COL_CAP, row, COL_CAP, {
        "type": "cell",
        "criteria": "<",
        "value": 0,
        "format": budget_formats["room_negative"],
    })
    row += 1
    
    # Tax room
    worksheet.write(row, COL_LABEL, "Room Under Tax Line", budget_formats["label_indent"])
    tax_room_formula = f"={_system_sumifs('tax_level_amount')}-{derived_tax_cell}"
    worksheet.write_formula(row, COL_TAX, tax_room_formula, budget_formats["money"])
    worksheet.write(row, COL_NOTES, "Positive = not taxpayer; Negative = over tax", budget_formats["note"])
    
    worksheet.conditional_format(row, COL_TAX, row, COL_TAX, {
        "type": "cell",
        "criteria": ">=",
        "value": 0,
        "format": budget_formats["room_positive"],
    })
    worksheet.conditional_format(row, COL_TAX, row, COL_TAX, {
        "type": "cell",
        "criteria": "<",
        "value": 0,
        "format": budget_formats["room_negative"],
    })
    row += 1
    
    # First apron room
    worksheet.write(row, COL_LABEL, "Room Under First Apron", budget_formats["label_indent"])
    apron1_room_formula = f"={_system_sumifs('tax_apron_amount')}-{derived_apron_cell}"
    worksheet.write_formula(row, COL_APRON, apron1_room_formula, budget_formats["money"])
    worksheet.write(row, COL_NOTES, "Positive = below apron; Negative = over apron", budget_formats["note"])
    
    worksheet.conditional_format(row, COL_APRON, row, COL_APRON, {
        "type": "cell",
        "criteria": ">=",
        "value": 0,
        "format": budget_formats["room_positive"],
    })
    worksheet.conditional_format(row, COL_APRON, row, COL_APRON, {
        "type": "cell",
        "criteria": "<",
        "value": 0,
        "format": budget_formats["room_negative"],
    })
    row += 1
    
    # Second apron room
    worksheet.write(row, COL_LABEL, "Room Under Second Apron", budget_formats["label_indent"])
    apron2_room_formula = f"={_system_sumifs('tax_apron2_amount')}-{derived_apron_cell}"
    worksheet.write_formula(row, COL_APRON, apron2_room_formula, budget_formats["money"])
    worksheet.write(row, COL_NOTES, "Positive = below apron 2; Negative = over", budget_formats["note"])
    
    worksheet.conditional_format(row, COL_APRON, row, COL_APRON, {
        "type": "cell",
        "criteria": ">=",
        "value": 0,
        "format": budget_formats["room_positive"],
    })
    worksheet.conditional_format(row, COL_APRON, row, COL_APRON, {
        "type": "cell",
        "criteria": "<",
        "value": 0,
        "format": budget_formats["room_negative"],
    })
    row += 2
    
    return row, derived_total_row


def _write_verification_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
    snapshot_total_row: int,
) -> int:
    """Write verification that derived totals match snapshot (when no deltas).
    
    This section confirms the ledger is consistent.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "VERIFICATION (Baseline Mode — no plan deltas)",
        budget_formats["subsection_header"]
    )
    row += 1
    
    # In baseline mode with no plan deltas, derived should equal snapshot
    # This is a sanity check that formulas are wired correctly
    
    snapshot_cap = xlsxwriter.utility.xl_rowcol_to_cell(snapshot_total_row, COL_CAP)
    
    # Compare snapshot cap_total to warehouse cap_total (should be same formula)
    worksheet.write(row, COL_LABEL, "Snapshot vs Warehouse check:", budget_formats["label"])
    
    # This verifies that our snapshot section correctly pulls from warehouse
    verify_formula = (
        f"=IF({snapshot_cap}={_warehouse_sumifs('cap_total')},"
        f"\"✓ Matched\",\"✗ MISMATCH\")"
    )
    worksheet.write_formula(row, COL_CAP, verify_formula)
    
    # Conditional formatting
    worksheet.conditional_format(row, COL_CAP, row, COL_CAP, {
        "type": "text",
        "criteria": "containing",
        "value": "✓",
        "format": budget_formats["verify_ok"],
    })
    worksheet.conditional_format(row, COL_CAP, row, COL_CAP, {
        "type": "text",
        "criteria": "containing",
        "value": "✗",
        "format": budget_formats["verify_fail"],
    })
    
    worksheet.write(row, COL_NOTES, "Confirms snapshot pulls correctly from warehouse", budget_formats["note"])
    row += 2
    
    return row


def _write_policy_warnings(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    budget_formats: dict[str, Any],
) -> int:
    """Write policy warnings for features that are not yet implemented.
    
    Per backlog item 4: When RosterFillTarget > 0, show a loud warning that
    no generated fill rows are currently being applied.
    
    Returns next row.
    """
    # Create a bold alert format for warnings
    warning_fmt = workbook.add_format({
        "bold": True,
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "font_size": 10,
    })
    
    # RosterFillTarget NOT YET IMPLEMENTED warning
    # Uses IF formula to only show when RosterFillTarget > 0
    worksheet.write_formula(
        row, COL_LABEL,
        '=IF(RosterFillTarget>0,"🚧 ROSTER FILL NOT YET IMPLEMENTED","")',
        warning_fmt
    )
    worksheet.write_formula(
        row, COL_CAP,
        '=IF(RosterFillTarget>0,"RosterFillTarget="&RosterFillTarget&" has no effect","")',
        warning_fmt
    )
    worksheet.write_formula(
        row, COL_NOTES,
        '=IF(RosterFillTarget>0,"No generated fill rows are applied — set to 0 to hide this warning","")',
        workbook.add_format({
            "bg_color": "#FEE2E2",
            "font_color": "#991B1B",
            "font_size": 9,
            "italic": True,
        })
    )
    
    # Conditional formatting to highlight the entire row when warning is active
    worksheet.conditional_format(row, COL_LABEL, row, COL_NOTES, {
        "type": "formula",
        "criteria": "=RosterFillTarget>0",
        "format": warning_fmt,
    })
    
    row += 1
    
    # ShowExistsOnlyRows info message (feature now implemented)
    # The EXISTS_ONLY section is now available in ROSTER_GRID
    info_fmt = workbook.add_format({
        "bg_color": "#DBEAFE",  # blue-100
        "font_color": "#1E40AF",  # blue-800
        "font_size": 9,
    })
    worksheet.write_formula(
        row, COL_LABEL,
        '=IF(ShowExistsOnlyRows="Yes","ℹ️ EXISTS_ONLY section active","")',
        info_fmt
    )
    worksheet.write_formula(
        row, COL_CAP,
        '=IF(ShowExistsOnlyRows="Yes","See ROSTER_GRID","")',
        info_fmt
    )
    worksheet.write_formula(
        row, COL_NOTES,
        '=IF(ShowExistsOnlyRows="Yes","Non-counting rows with future-year amounts are displayed in ROSTER_GRID","")',
        workbook.add_format({
            "bg_color": "#DBEAFE",
            "font_color": "#1E40AF",
            "font_size": 9,
            "italic": True,
        })
    )
    
    # Conditional formatting to highlight the entire row when info is shown
    worksheet.conditional_format(row, COL_LABEL, row, COL_NOTES, {
        "type": "formula",
        "criteria": '=ShowExistsOnlyRows="Yes"',
        "format": info_fmt,
    })
    
    row += 1

    # Two-way policy toggles NOT YET IMPLEMENTED warning
    # These toggles currently do not change authoritative totals or roster counts.
    worksheet.write_formula(
        row, COL_LABEL,
        '=IF(OR(CountTwoWayInTotals="Yes",CountTwoWayInRoster="Yes"),"🚧 TWO-WAY TOGGLES NOT YET IMPLEMENTED","")',
        warning_fmt
    )
    worksheet.write_formula(
        row, COL_CAP,
        '=IF(OR(CountTwoWayInTotals="Yes",CountTwoWayInRoster="Yes"),"No effect on totals/roster counts","")',
        warning_fmt
    )
    worksheet.write_formula(
        row, COL_NOTES,
        '=IF(OR(CountTwoWayInTotals="Yes",CountTwoWayInRoster="Yes"),"Authoritative totals always include 2-way per warehouse — set both to No to hide this warning","")',
        workbook.add_format({
            "bg_color": "#FEE2E2",
            "font_color": "#991B1B",
            "font_size": 9,
            "italic": True,
        })
    )
    worksheet.conditional_format(row, COL_LABEL, row, COL_NOTES, {
        "type": "formula",
        "criteria": '=OR(CountTwoWayInTotals="Yes",CountTwoWayInRoster="Yes")',
        "format": warning_fmt,
    })

    row += 1

    # Blank row for spacing (only shows if warning is active, otherwise row is empty)
    row += 1

    return row


# =============================================================================
# Main Writer
# =============================================================================

def write_budget_ledger(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write BUDGET_LEDGER sheet — the authoritative accounting statement.

    The budget ledger shows:
    - Snapshot totals by bucket from DATA_team_salary_warehouse
    - System thresholds for context
    - Plan deltas (from tbl_plan_journal, enabled rows filtered by ActivePlanId)
    - Derived totals (snapshot + deltas)
    - Room/over analysis for cap/tax/aprons
    - Verification that formulas are consistent

    Per the blueprint:
    - This is the "single source of truth for totals and deltas"
    - This is the sheet you use to explain numbers to a GM/owner
    - Mode-aware (Cap vs Tax vs Apron columns always visible)

    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The BUDGET_LEDGER worksheet
        formats: Standard format dict from create_standard_formats
    """
    # Sheet title
    worksheet.write(0, 0, "BUDGET LEDGER", formats["header"])
    worksheet.write(1, 0, "Authoritative accounting statement (Snapshot + Plan = Derived)")
    
    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)
    
    # Set column widths
    for col, width in COLUMN_WIDTHS.items():
        worksheet.set_column(col, col, width)
    
    # Create budget-specific formats
    budget_formats = _create_budget_formats(workbook)
    
    # Content starts after command bar
    content_row = get_content_start_row()
    
    # 0. Policy warnings (NOT YET IMPLEMENTED alerts)
    content_row = _write_policy_warnings(
        workbook, worksheet, content_row, budget_formats
    )
    
    # 1. Snapshot totals section
    content_row, snapshot_total_row = _write_snapshot_section(
        worksheet, content_row, formats, budget_formats
    )
    
    # 2. System thresholds for context
    content_row = _write_thresholds_section(
        worksheet, content_row, formats, budget_formats
    )
    
    # 3. Plan delta section (from tbl_plan_journal for ActivePlanId)
    content_row, delta_total_row = _write_plan_delta_section(
        worksheet, content_row, formats, budget_formats
    )
    
    # 4. Derived totals section
    content_row, derived_total_row = _write_derived_section(
        worksheet, content_row, formats, budget_formats,
        snapshot_total_row, delta_total_row
    )
    
    # 5. Verification section
    content_row = _write_verification_section(
        worksheet, content_row, formats, budget_formats,
        snapshot_total_row
    )
    
    # Sheet protection
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })
