"""
HOME sheet writer — workbook landing page.

The HOME sheet provides:
1. Workbook title + data health banner (validation + reconciliation status)
2. Current context summary (Team/Year/Mode/As-of/ActivePlan from named ranges)
3. Top-line readouts (cap/tax/apron room, roster count) from warehouse
4. Navigation hyperlinks to all major sheets
5. Build metadata (refresh time, data contract, git SHA)

HOME does not have the command bar (it's a landing/overview page).
Users should go to TEAM_COCKPIT to edit context or view detailed readouts.

Per excel-cap-book-blueprint.md:
- HOME shows Active Team/Year/As-of Date/Plan
- "Data health" indicator (Reconciled ✓ / Not reconciled ✗)
- Links to all major tools
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import FMT_MONEY, COLOR_ALERT_FAIL, COLOR_ALERT_WARN, COLOR_ALERT_OK


# =============================================================================
# Layout Constants
# =============================================================================

# Column layout
COL_A = 0  # Labels / section headers
COL_B = 1  # Values / primary data
COL_C = 2  # Secondary data / descriptions
COL_D = 3  # Tertiary / units

# Column widths
WIDTH_COL_A = 20
WIDTH_COL_B = 18
WIDTH_COL_C = 45
WIDTH_COL_D = 12

# Navigation sheet list (in display order)
# Each tuple: (sheet_name, description, is_primary)
NAVIGATION_SHEETS = [
    ("TEAM_COCKPIT", "Primary readouts, alerts, quick drivers", True),
    ("ROSTER_GRID", "Full roster/ledger view with bucket classification", True),
    ("BUDGET_LEDGER", "Authoritative totals + plan deltas", True),
    ("PLAN_MANAGER", "Manage plans and scenarios", False),
    ("PLAN_JOURNAL", "Ordered actions for scenario modeling", False),
    ("TRADE_MACHINE", "Lane-based trade iteration", False),
    ("SIGNINGS_AND_EXCEPTIONS", "Signings, minimums, exception usage", False),
    ("WAIVE_BUYOUT_STRETCH", "Dead money modeling (waive/buyout/stretch)", False),
    ("ASSETS", "Exception/TPE + draft pick inventory", False),
    ("AUDIT_AND_RECONCILE", "Reconciliation + drilldowns", True),
    ("RULES_REFERENCE", "Quick reference tables (tax rates, scales)", False),
    ("META", "Build metadata + validation details", False),
]


# =============================================================================
# Helpers
# =============================================================================

def _protect_sheet(worksheet: Worksheet) -> None:
    """Apply standard sheet protection."""
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })


def _sumifs_formula(data_col: str) -> str:
    """Build SUMIFS formula to look up a value from tbl_team_salary_warehouse.
    
    Uses SelectedTeam and SelectedYear to filter.
    """
    return (
        f"=SUMIFS(tbl_team_salary_warehouse[{data_col}],"
        f"tbl_team_salary_warehouse[team_code],SelectedTeam,"
        f"tbl_team_salary_warehouse[salary_year],SelectedYear)"
    )


def _if_formula(data_col: str) -> str:
    """Build INDEX/MATCH formula for boolean/text values from tbl_team_salary_warehouse."""
    return (
        f"=IFERROR(INDEX(tbl_team_salary_warehouse[{data_col}],"
        f"MATCH(1,(tbl_team_salary_warehouse[team_code]=SelectedTeam)*"
        f"(tbl_team_salary_warehouse[salary_year]=SelectedYear),0)),\"\")"
    )


# =============================================================================
# Main Writer
# =============================================================================

def write_home_sheet(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    build_meta: dict[str, Any],
) -> None:
    """
    Write the HOME sheet — workbook landing page.
    
    Args:
        workbook: The XlsxWriter Workbook (for hyperlinks and formats)
        worksheet: The HOME worksheet
        formats: Standard format dict from xlsx.create_standard_formats()
        build_meta: Build metadata dict containing:
            - refreshed_at (str): ISO timestamp
            - base_year (int): Base salary year
            - as_of_date (str): ISO date
            - league_lk (str): League code (e.g., "NBA")
            - data_contract_version (str): Data contract version string
            - exporter_git_sha (str): Git commit SHA
            - validation_status (str): "PASS" or "FAILED"
            - reconcile_passed (bool): Reconciliation status
    """
    # Set column widths
    worksheet.set_column(COL_A, COL_A, WIDTH_COL_A)
    worksheet.set_column(COL_B, COL_B, WIDTH_COL_B)
    worksheet.set_column(COL_C, COL_C, WIDTH_COL_C)
    worksheet.set_column(COL_D, COL_D, WIDTH_COL_D)

    # Create additional formats for HOME
    title_fmt = workbook.add_format({
        "bold": True,
        "font_size": 18,
        "font_color": "#1F2937",
    })
    subtitle_fmt = workbook.add_format({
        "italic": True,
        "font_size": 11,
        "font_color": "#6B7280",
    })
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "font_color": "#374151",
        "bottom": 1,
        "bottom_color": "#D1D5DB",
    })
    label_fmt = workbook.add_format({
        "font_color": "#6B7280",
    })
    value_fmt = workbook.add_format({
        "bold": True,
        "font_color": "#111827",
    })
    value_money_fmt = workbook.add_format({
        "bold": True,
        "font_color": "#111827",
        "num_format": FMT_MONEY,
    })
    link_fmt = workbook.add_format({
        "font_color": "#2563EB",
        "underline": 1,
    })
    link_primary_fmt = workbook.add_format({
        "bold": True,
        "font_color": "#2563EB",
        "underline": 1,
    })
    desc_fmt = workbook.add_format({
        "font_color": "#6B7280",
        "italic": True,
    })
    muted_fmt = workbook.add_format({
        "font_size": 9,
        "font_color": "#9CA3AF",
    })

    row = 0

    # =========================================================================
    # Section 1: Title + Status Banner
    # =========================================================================
    worksheet.write(row, COL_A, "NBA Cap Workbook", title_fmt)
    row += 1
    worksheet.write(row, COL_A, "Sean-style salary cap analysis — generated from Postgres", subtitle_fmt)
    row += 2

    # Validation + Reconciliation status banner
    validation_status = build_meta.get("validation_status", "UNKNOWN")
    reconcile_passed = build_meta.get("reconcile_passed")

    # Determine overall health status
    if validation_status == "PASS" and reconcile_passed is True:
        worksheet.write(row, COL_A, "Data Health:", formats["alert_ok"])
        worksheet.write(row, COL_B, "✓ PASS", formats["alert_ok"])
        worksheet.write(row, COL_C, "Validation passed, reconciliation OK", formats["alert_ok"])
    elif validation_status == "PASS" and reconcile_passed is False:
        worksheet.write(row, COL_A, "Data Health:", formats["alert_warn"])
        worksheet.write(row, COL_B, "⚠ RECONCILE FAILED", formats["alert_warn"])
        worksheet.write(row, COL_C, "Validation passed but reconciliation failed — see AUDIT_AND_RECONCILE", formats["alert_warn"])
    elif validation_status != "PASS":
        worksheet.write(row, COL_A, "Data Health:", formats["alert_fail"])
        worksheet.write(row, COL_B, "✗ FAILED", formats["alert_fail"])
        worksheet.write(row, COL_C, "Do not trust these numbers — see META for details", formats["alert_fail"])
    else:
        worksheet.write(row, COL_A, "Data Health:", formats["alert_warn"])
        worksheet.write(row, COL_B, "⚠ UNKNOWN", formats["alert_warn"])
        worksheet.write(row, COL_C, "Reconciliation status unknown", formats["alert_warn"])
    row += 2

    # =========================================================================
    # Section 2: Current Context (from named ranges)
    # =========================================================================
    worksheet.write(row, COL_A, "CURRENT CONTEXT", section_header_fmt)
    worksheet.write(row, COL_B, "", section_header_fmt)
    worksheet.write(row, COL_C, "(edit on TEAM_COCKPIT)", muted_fmt)
    row += 1

    # Team
    worksheet.write(row, COL_A, "Team:", label_fmt)
    worksheet.write_formula(row, COL_B, "=SelectedTeam", value_fmt)
    row += 1

    # Year
    worksheet.write(row, COL_A, "Salary Year:", label_fmt)
    worksheet.write_formula(row, COL_B, "=SelectedYear", value_fmt)
    row += 1

    # Mode
    worksheet.write(row, COL_A, "Mode:", label_fmt)
    worksheet.write_formula(row, COL_B, "=SelectedMode", value_fmt)
    row += 1

    # As-Of Date
    worksheet.write(row, COL_A, "As-Of Date:", label_fmt)
    worksheet.write_formula(row, COL_B, "=AsOfDate", value_fmt)
    row += 1

    # Active Plan
    worksheet.write(row, COL_A, "Active Plan:", label_fmt)
    worksheet.write_formula(row, COL_B, "=ActivePlan", value_fmt)
    row += 1

    # Compare Plans (show if any are set)
    compare_formula = (
        '=IF(COUNTA(ComparePlanA,ComparePlanB,ComparePlanC,ComparePlanD)=0,'
        '"(none)",'
        'TEXTJOIN(", ",TRUE,ComparePlanA,ComparePlanB,ComparePlanC,ComparePlanD))'
    )
    worksheet.write(row, COL_A, "Compare Plans:", label_fmt)
    worksheet.write_formula(row, COL_B, compare_formula, value_fmt)
    row += 2

    # =========================================================================
    # Section 3: Top-Line Readouts (from warehouse)
    # =========================================================================
    worksheet.write(row, COL_A, "TOP-LINE READOUTS", section_header_fmt)
    worksheet.write(row, COL_B, "", section_header_fmt)
    worksheet.write(row, COL_C, "(for SelectedTeam + SelectedYear)", muted_fmt)
    row += 1

    # Cap Room / Over Cap
    worksheet.write(row, COL_A, "Cap Position:", label_fmt)
    # Formula: if over_cap > 0, show "(Over by $X)", else show "Room: $X"
    cap_position_formula = (
        f"=IF({_sumifs_formula('over_cap')[1:]}>0,"
        f'"Over Cap by "&TEXT({_sumifs_formula("over_cap")[1:]},"$#,##0"),'
        f'"Room: "&TEXT(-{_sumifs_formula("over_cap")[1:]},"$#,##0"))'
    )
    worksheet.write_formula(row, COL_B, cap_position_formula, value_fmt)
    worksheet.write(row, COL_C, "=Salary Cap - Cap Total", desc_fmt)
    row += 1

    # Room Under Tax
    worksheet.write(row, COL_A, "Tax Room:", label_fmt)
    worksheet.write_formula(row, COL_B, _sumifs_formula("room_under_tax"), value_money_fmt)
    worksheet.write(row, COL_C, "=Tax Level - Tax Total", desc_fmt)
    row += 1

    # Room Under Apron 1
    worksheet.write(row, COL_A, "Apron 1 Room:", label_fmt)
    worksheet.write_formula(row, COL_B, _sumifs_formula("room_under_apron1"), value_money_fmt)
    worksheet.write(row, COL_C, "=First Apron - Apron Total", desc_fmt)
    row += 1

    # Room Under Apron 2
    worksheet.write(row, COL_A, "Apron 2 Room:", label_fmt)
    worksheet.write_formula(row, COL_B, _sumifs_formula("room_under_apron2"), value_money_fmt)
    worksheet.write(row, COL_C, "=Second Apron - Apron Total", desc_fmt)
    row += 1

    # Roster Count (NBA roster + two-way)
    worksheet.write(row, COL_A, "Roster Count:", label_fmt)
    roster_formula = (
        f'={_sumifs_formula("roster_row_count")[1:]}&" NBA + "'
        f'&{_sumifs_formula("two_way_row_count")[1:]}&" two-way"'
    )
    worksheet.write_formula(row, COL_B, roster_formula, value_fmt)
    row += 1

    # Taxpayer Status
    worksheet.write(row, COL_A, "Taxpayer Status:", label_fmt)
    # Show is_taxpayer and is_repeater
    taxpayer_formula = (
        f'=IF({_if_formula("is_taxpayer")[1:]},'
        f'IF({_if_formula("is_repeater_taxpayer")[1:]},"Repeater Taxpayer","Taxpayer"),'
        f'"Below Tax")'
    )
    worksheet.write_formula(row, COL_B, taxpayer_formula, value_fmt)
    row += 1

    # Apron Level
    worksheet.write(row, COL_A, "Apron Level:", label_fmt)
    worksheet.write_formula(row, COL_B, _if_formula("apron_level_lk"), value_fmt)
    row += 2

    # =========================================================================
    # Section 4: Navigation
    # =========================================================================
    worksheet.write(row, COL_A, "NAVIGATION", section_header_fmt)
    worksheet.write(row, COL_B, "", section_header_fmt)
    worksheet.write(row, COL_C, "", section_header_fmt)
    row += 1

    for sheet_name, description, is_primary in NAVIGATION_SHEETS:
        # Create internal hyperlink to the sheet
        link_target = f"'{sheet_name}'!A1"
        link_format = link_primary_fmt if is_primary else link_fmt
        
        worksheet.write_url(row, COL_A, f"internal:{link_target}", link_format, sheet_name)
        worksheet.write(row, COL_B, description, desc_fmt)
        row += 1

    row += 1

    # =========================================================================
    # Section 5: Build Metadata
    # =========================================================================
    worksheet.write(row, COL_A, "BUILD INFO", section_header_fmt)
    worksheet.write(row, COL_B, "", section_header_fmt)
    row += 1

    worksheet.write(row, COL_A, "League:", muted_fmt)
    worksheet.write(row, COL_B, build_meta.get("league_lk", ""), muted_fmt)
    row += 1

    worksheet.write(row, COL_A, "Data Contract:", muted_fmt)
    worksheet.write(row, COL_B, build_meta.get("data_contract_version", ""), muted_fmt)
    row += 1

    worksheet.write(row, COL_A, "Base Year:", muted_fmt)
    worksheet.write(row, COL_B, build_meta.get("base_year", ""), muted_fmt)
    row += 1

    worksheet.write(row, COL_A, "As-Of Date:", muted_fmt)
    worksheet.write(row, COL_B, build_meta.get("as_of_date", ""), muted_fmt)
    row += 1

    worksheet.write(row, COL_A, "Refreshed:", muted_fmt)
    worksheet.write(row, COL_B, build_meta.get("refreshed_at", ""), muted_fmt)
    row += 1

    worksheet.write(row, COL_A, "Git SHA:", muted_fmt)
    worksheet.write(row, COL_B, build_meta.get("exporter_git_sha", "")[:12], muted_fmt)
    row += 1

    # =========================================================================
    # Section 6: Quick Start Guide
    # =========================================================================
    row += 1
    worksheet.write(row, COL_A, "QUICK START", section_header_fmt)
    worksheet.write(row, COL_B, "", section_header_fmt)
    row += 1

    quick_start_steps = [
        "1. Go to TEAM_COCKPIT to select a team, year, and mode",
        "2. Review cap position, alerts, and quick drivers",
        "3. See full roster breakdown on ROSTER_GRID",
        "4. Model scenarios via PLAN_JOURNAL or subsystem tools",
        "5. Check AUDIT_AND_RECONCILE to verify totals match warehouse",
    ]
    for step in quick_start_steps:
        worksheet.write(row, COL_A, step, desc_fmt)
        row += 1

    # Apply sheet protection
    _protect_sheet(worksheet)
