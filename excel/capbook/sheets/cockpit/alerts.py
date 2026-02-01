"""
Validation banner and alert stack for TEAM_COCKPIT sheet.

Implements:
- Validation status banner (PASS/FAIL based on MetaValidationStatus)
- Alert stack section (validation, reconciliation, policy alerts)
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .constants import COL_READOUT_LABEL, COL_READOUT_DESC
from .helpers import mode_drilldown_sum_formula, mode_warehouse_total_formula


# =============================================================================
# Validation Banner
# =============================================================================


def write_validation_banner(
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


# =============================================================================
# Alert Stack
# =============================================================================


def write_alert_stack(
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
    drilldown_sum = mode_drilldown_sum_formula()
    warehouse_total = mode_warehouse_total_formula()
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
