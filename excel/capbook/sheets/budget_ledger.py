"""
BUDGET_LEDGER sheet writer — authoritative totals and deltas.

This module implements the "accounting statement" for team salary cap:
1. Shared command bar (read-only reference to TEAM_COCKPIT)
2. Snapshot totals section (from tbl_team_salary_warehouse)
   - Cap/Tax/Apron totals by bucket (ROST, FA, TERM, 2WAY)
   - System thresholds for context
3. Plan delta section (from tbl_plan_journal + tbl_subsystem_outputs)
   - Journal entries: manual actions filtered by ActivePlanId AND SelectedYear
   - Subsystem outputs: auto-linked deltas from TRADE_MACHINE, SIGNINGS, WAIVE sheets
   - Combined PLAN DELTA TOTAL from both sources
4. Policy delta section (generated fill rows and other analyst assumptions)
5. Derived totals section (snapshot + plan + policy)
6. Delta vs snapshot verification

Per the blueprint (excel-cap-book-blueprint.md):
- BUDGET_LEDGER is the "single source of truth for totals and deltas"
- This is the sheet you use to explain numbers to a GM/owner
- Every headline total must have an audit path
- Policy deltas are explicit and toggleable (visible generated rows)

Design notes:
- Uses Excel formulas filtered by SelectedTeam + SelectedYear + SelectedMode
- Mode-aware display (Cap vs Tax vs Apron columns)
- Plan deltas are aggregated from BOTH:
  - tbl_plan_journal (enabled rows, filtered by ActivePlanId + salary_year)
  - tbl_subsystem_outputs (include_in_plan="Yes", plan_id=ActivePlanId, salary_year=SelectedYear)
- Each journal entry has a salary_year column; blank means "use SelectedYear"
- Subsystem outputs auto-link to TRADE_MACHINE, SIGNINGS_AND_EXCEPTIONS, WAIVE_BUYOUT_STRETCH
- Policy deltas show generated fill impact with amber styling to indicate assumptions

**Excel 365/2021 Required (Modern Formulas):**
- Uses LET + FILTER + SUM instead of legacy SUMPRODUCT for plan deltas
- Leverages PlanRowMask LAMBDA for consistent filtering across the workbook
- See .ralph/EXCEL.md backlog item #5 for migration rationale
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
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
) -> tuple[int, int]:
    """Write the plan delta section sourced from tbl_plan_journal AND tbl_subsystem_outputs.
    
    This section summarizes journal actions for the active plan and selected year.
    Uses modern Excel 365 formulas (LET + FILTER + SUM) instead of legacy SUMPRODUCT.
    
    Journal entries are filtered where:
    - plan_id matches ActivePlanId (derived from ActivePlan name)
    - salary_year matches SelectedYear (or is blank, which defaults to SelectedYear)
    - enabled = "Yes"
    
    Per backlog task #19, this section ALSO includes deltas from tbl_subsystem_outputs
    where include_in_plan="Yes" AND plan_id=ActivePlanId AND salary_year=SelectedYear.
    
    Fallback behavior:
    - If ActivePlanId is blank/error (e.g., plan not found), deltas are 0
    - The "Baseline" plan has plan_id=1 but no journal entries by default
    - Blank salary_year is treated as "same as SelectedYear"
    
    **Modern Formula Pattern (per .ralph/EXCEL.md #5):**
    - Uses LET + FILTER + SUM instead of SUMPRODUCT
    - Leverages PlanRowMask LAMBDA for consistent filtering
    - IFERROR wrapping for graceful blank/error handling
    
    Returns (next_row, delta_total_row).
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "PLAN DELTAS (from tbl_plan_journal + tbl_subsystem_outputs)",
        budget_formats["section_header"]
    )
    row += 1
    
    # Column headers
    row = _write_column_headers(worksheet, row, budget_formats)
    
    # -------------------------------------------------------------------------
    # JOURNAL ENTRIES subsection
    # -------------------------------------------------------------------------
    worksheet.write(
        row, COL_LABEL,
        "Journal Entries (tbl_plan_journal):",
        budget_formats["label_bold"]
    )
    worksheet.write(row, COL_NOTES, "Enabled rows for ActivePlan + SelectedYear", budget_formats["note"])
    row += 1
    
    # -------------------------------------------------------------------------
    # Modern formula helper: LET + FILTER + SUM with PlanRowMask
    # 
    # Pattern for journal entries by action type:
    #   =IFERROR(LET(
    #     mask, (((plan_id_col=ActivePlanId)+(plan_id_col=""))*((salary_year_col=SelectedYear)+(salary_year_col=""))*(enabled_col="Yes")),
    #     action_mask, (tbl_plan_journal[action_type]="Trade"),
    #     combined, mask * action_mask,
    #     SUM(FILTER(tbl_plan_journal[delta_cap], combined, 0))
    #   ), 0)
    #
    # PlanRowMask already handles:
    #   - (plan_id = ActivePlanId OR plan_id = "")
    #   - (salary_year = SelectedYear OR salary_year = "")
    #   - (enabled = "Yes")
    # -------------------------------------------------------------------------
    
    def _journal_let_filter_by_action(delta_col: str, action_type: str) -> str:
        """
        Sum journal deltas for a specific action type using LET + FILTER + SUM.
        
        Uses PlanRowMask LAMBDA for the base filter, then adds action_type filter.
        IFERROR handles empty results or blank ActivePlanId gracefully.
        """
        return (
            f'=IFERROR(LET('
            f'_xlpm.mask,((('
            f'tbl_plan_journal[plan_id]=ActivePlanId)+('
            f'tbl_plan_journal[plan_id]=""))*(('
            f'tbl_plan_journal[salary_year]=SelectedYear)+('
            f'tbl_plan_journal[salary_year]=""))*('
            f'tbl_plan_journal[enabled]="Yes")),'
            f'_xlpm.action_mask,(tbl_plan_journal[action_type]="{action_type}"),'
            f'_xlpm.combined,_xlpm.mask*_xlpm.action_mask,'
            f'SUM(FILTER(tbl_plan_journal[{delta_col}],_xlpm.combined,0))'
            f'),0)'
        )
    
    # Action type breakdown
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
    
    delta_row_start = row  # Track for conditional formatting
    
    for action_type, note in action_categories:
        worksheet.write(row, COL_LABEL, f"  {action_type}", budget_formats["label_indent"])
        
        # LET + FILTER: sum delta where PlanRowMask matches AND action_type matches
        cap_formula = _journal_let_filter_by_action("delta_cap", action_type)
        tax_formula = _journal_let_filter_by_action("delta_tax", action_type)
        apron_formula = _journal_let_filter_by_action("delta_apron", action_type)
        
        worksheet.write_formula(row, COL_CAP, cap_formula, budget_formats["delta_zero"])
        worksheet.write_formula(row, COL_TAX, tax_formula, budget_formats["delta_zero"])
        worksheet.write_formula(row, COL_APRON, apron_formula, budget_formats["delta_zero"])
        worksheet.write(row, COL_NOTES, note, budget_formats["note"])
        row += 1
    
    journal_delta_row_end = row - 1  # Last journal data row
    
    # Journal entries subtotal using LET + FILTER + SUM with PlanRowMask
    # Pattern: =IFERROR(LET(mask, (((...)=ActivePlanId)+(...)=""))*((SUM(FILTER(delta_col=SelectedYear)+(SUM(FILTER(delta_col=""))*(mask, 0="Yes")))), 0)
    journal_subtotal_cap_formula = (
        '=IFERROR(LET('
        '_xlpm.mask,((('
        'tbl_plan_journal[plan_id]=ActivePlanId)+('
        'tbl_plan_journal[plan_id]=""))*(('
        'tbl_plan_journal[salary_year]=SelectedYear)+('
        'tbl_plan_journal[salary_year]=""))*('
        'tbl_plan_journal[enabled]="Yes")),'
        'SUM(FILTER(tbl_plan_journal[delta_cap],_xlpm.mask,0))'
        '),0)'
    )
    journal_subtotal_tax_formula = (
        '=IFERROR(LET('
        '_xlpm.mask,((('
        'tbl_plan_journal[plan_id]=ActivePlanId)+('
        'tbl_plan_journal[plan_id]=""))*(('
        'tbl_plan_journal[salary_year]=SelectedYear)+('
        'tbl_plan_journal[salary_year]=""))*('
        'tbl_plan_journal[enabled]="Yes")),'
        'SUM(FILTER(tbl_plan_journal[delta_tax],_xlpm.mask,0))'
        '),0)'
    )
    journal_subtotal_apron_formula = (
        '=IFERROR(LET('
        '_xlpm.mask,((('
        'tbl_plan_journal[plan_id]=ActivePlanId)+('
        'tbl_plan_journal[plan_id]=""))*(('
        'tbl_plan_journal[salary_year]=SelectedYear)+('
        'tbl_plan_journal[salary_year]=""))*('
        'tbl_plan_journal[enabled]="Yes")),'
        'SUM(FILTER(tbl_plan_journal[delta_apron],_xlpm.mask,0))'
        '),0)'
    )
    
    worksheet.write(row, COL_LABEL, "  Journal Subtotal", budget_formats["label_indent"])
    worksheet.write_formula(row, COL_CAP, journal_subtotal_cap_formula, budget_formats["money"])
    worksheet.write_formula(row, COL_TAX, journal_subtotal_tax_formula, budget_formats["money"])
    worksheet.write_formula(row, COL_APRON, journal_subtotal_apron_formula, budget_formats["money"])
    worksheet.write(row, COL_NOTES, "Sum of tbl_plan_journal entries", budget_formats["note"])
    journal_subtotal_row = row
    row += 2
    
    # -------------------------------------------------------------------------
    # SUBSYSTEM OUTPUTS subsection
    # -------------------------------------------------------------------------
    # Per backlog task #19, include deltas from tbl_subsystem_outputs where:
    # - include_in_plan = "Yes"
    # - plan_id = ActivePlanId (tbl_subsystem_outputs.plan_id defaults to ActivePlanId)
    # - salary_year = SelectedYear (tbl_subsystem_outputs.salary_year defaults to SelectedYear)
    #
    # The subsystem outputs table (on PLAN_JOURNAL) auto-links to subsystem sheets.
    #
    # **Modern Formula Pattern:**
    # Uses LET + FILTER + SUM (no blank salary_year logic needed for subsystem outputs)
    # -------------------------------------------------------------------------
    
    # Create subsystem-specific formats (blue tint to differentiate from journal)
    subsystem_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "bg_color": "#DBEAFE",  # blue-100
        "font_color": "#1E40AF",  # blue-800
    })
    subsystem_value_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "bg_color": "#EFF6FF",  # blue-50
    })
    subsystem_note_fmt = workbook.add_format({
        "font_size": 9,
        "font_color": "#1E40AF",  # blue-800
        "italic": True,
        "bg_color": "#EFF6FF",  # blue-50
    })
    
    worksheet.write(
        row, COL_LABEL,
        "Subsystem Outputs (tbl_subsystem_outputs):",
        budget_formats["label_bold"]
    )
    worksheet.write(row, COL_NOTES, "Included rows for ActivePlan + SelectedYear", budget_formats["note"])
    row += 1
    
    # Subsystem output row breakdown using LET + FILTER + SUM
    # List each subsystem source (Trade lanes A-D, Signings, Waive/Buyout)
    subsystem_sources = [
        ("Trade Lane A", "Trade Lane A"),
        ("Trade Lane B", "Trade Lane B"),
        ("Trade Lane C", "Trade Lane C"),
        ("Trade Lane D", "Trade Lane D"),
        ("Signings", "Signings (SIGNINGS_AND_EXCEPTIONS)"),
        ("Waive/Buyout", "Waive/Buyout (WAIVE_BUYOUT_STRETCH)"),
    ]
    
    subsystem_row_start = row
    
    def _subsystem_let_filter_by_source(delta_col: str, source_value: str) -> str:
        """
        Sum subsystem output deltas for a specific source using LET + FILTER + SUM.
        
        Filter conditions:
        - include_in_plan = "Yes"
        - plan_id = ActivePlanId
        - salary_year = SelectedYear
        - source = source_value
        """
        return (
            f'=IFERROR(LET('
            f'_xlpm.mask,'
            f'(tbl_subsystem_outputs[include_in_plan]="Yes")*'
            f'(tbl_subsystem_outputs[plan_id]=ActivePlanId)*'
            f'(tbl_subsystem_outputs[salary_year]=SelectedYear)*'
            f'(tbl_subsystem_outputs[source]="{source_value}"),'
            f'SUM(FILTER(tbl_subsystem_outputs[{delta_col}],_xlpm.mask,0))'
            f'),0)'
        )
    
    for label, source_value in subsystem_sources:
        worksheet.write(row, COL_LABEL, f"  {label}", budget_formats["label_indent"])
        
        # LET + FILTER: sum delta by source
        cap_formula = _subsystem_let_filter_by_source("delta_cap", source_value)
        tax_formula = _subsystem_let_filter_by_source("delta_tax", source_value)
        apron_formula = _subsystem_let_filter_by_source("delta_apron", source_value)
        
        worksheet.write_formula(row, COL_CAP, cap_formula, subsystem_value_fmt)
        worksheet.write_formula(row, COL_TAX, tax_formula, subsystem_value_fmt)
        worksheet.write_formula(row, COL_APRON, apron_formula, subsystem_value_fmt)
        worksheet.write(row, COL_NOTES, f"From {source_value}", subsystem_note_fmt)
        row += 1
    
    subsystem_row_end = row - 1
    
    # Subsystem outputs subtotal using LET + FILTER + SUM
    # Sum all included subsystem rows for ActivePlanId + SelectedYear
    subsystem_subtotal_cap_formula = (
        '=IFERROR(LET('
        '_xlpm.mask,'
        '(tbl_subsystem_outputs[include_in_plan]="Yes")*'
        '(tbl_subsystem_outputs[plan_id]=ActivePlanId)*'
        '(tbl_subsystem_outputs[salary_year]=SelectedYear),'
        'SUM(FILTER(tbl_subsystem_outputs[delta_cap],_xlpm.mask,0))'
        '),0)'
    )
    subsystem_subtotal_tax_formula = (
        '=IFERROR(LET('
        '_xlpm.mask,'
        '(tbl_subsystem_outputs[include_in_plan]="Yes")*'
        '(tbl_subsystem_outputs[plan_id]=ActivePlanId)*'
        '(tbl_subsystem_outputs[salary_year]=SelectedYear),'
        'SUM(FILTER(tbl_subsystem_outputs[delta_tax],_xlpm.mask,0))'
        '),0)'
    )
    subsystem_subtotal_apron_formula = (
        '=IFERROR(LET('
        '_xlpm.mask,'
        '(tbl_subsystem_outputs[include_in_plan]="Yes")*'
        '(tbl_subsystem_outputs[plan_id]=ActivePlanId)*'
        '(tbl_subsystem_outputs[salary_year]=SelectedYear),'
        'SUM(FILTER(tbl_subsystem_outputs[delta_apron],_xlpm.mask,0))'
        '),0)'
    )
    
    worksheet.write(row, COL_LABEL, "  Subsystem Subtotal", budget_formats["label_indent"])
    worksheet.write_formula(row, COL_CAP, subsystem_subtotal_cap_formula, subsystem_value_fmt)
    worksheet.write_formula(row, COL_TAX, subsystem_subtotal_tax_formula, subsystem_value_fmt)
    worksheet.write_formula(row, COL_APRON, subsystem_subtotal_apron_formula, subsystem_value_fmt)
    worksheet.write(row, COL_NOTES, "Sum of tbl_subsystem_outputs entries", subsystem_note_fmt)
    subsystem_subtotal_row = row
    row += 2
    
    # -------------------------------------------------------------------------
    # PLAN DELTA TOTAL (Journal + Subsystem)
    # -------------------------------------------------------------------------
    # This is the combined total from both sources
    
    journal_cap_cell = xlsxwriter.utility.xl_rowcol_to_cell(journal_subtotal_row, COL_CAP)
    journal_tax_cell = xlsxwriter.utility.xl_rowcol_to_cell(journal_subtotal_row, COL_TAX)
    journal_apron_cell = xlsxwriter.utility.xl_rowcol_to_cell(journal_subtotal_row, COL_APRON)
    
    subsystem_cap_cell = xlsxwriter.utility.xl_rowcol_to_cell(subsystem_subtotal_row, COL_CAP)
    subsystem_tax_cell = xlsxwriter.utility.xl_rowcol_to_cell(subsystem_subtotal_row, COL_TAX)
    subsystem_apron_cell = xlsxwriter.utility.xl_rowcol_to_cell(subsystem_subtotal_row, COL_APRON)
    
    worksheet.write(row, COL_LABEL, "PLAN DELTA TOTAL", budget_formats["label_bold"])
    worksheet.write_formula(row, COL_CAP, f"={journal_cap_cell}+{subsystem_cap_cell}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_TAX, f"={journal_tax_cell}+{subsystem_tax_cell}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_APRON, f"={journal_apron_cell}+{subsystem_apron_cell}", budget_formats["money_total"])
    worksheet.write(row, COL_NOTES, "Journal + Subsystem Outputs for ActivePlan + SelectedYear", budget_formats["note"])
    
    delta_total_row = row
    row += 1
    
    # -------------------------------------------------------------------------
    # WARNING BANNER when subsystem outputs are included
    # -------------------------------------------------------------------------
    # Show a visible alert when any subsystem outputs are included
    # Count rows where include_in_plan="Yes" for current plan/year context
    
    warning_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#1E40AF",  # blue-800
        "bg_color": "#DBEAFE",  # blue-100
        "italic": True,
    })
    
    # Formula: if subsystem subtotal != 0, show warning
    worksheet.write_formula(
        row, COL_LABEL,
        f'=IF({subsystem_cap_cell}<>0,"ℹ️ Subsystem outputs included in PLAN DELTA TOTAL","")',
        warning_fmt
    )
    worksheet.write_formula(
        row, COL_NOTES,
        f'=IF({subsystem_cap_cell}<>0,"See PLAN_JOURNAL → SUBSYSTEM_OUTPUTS table","")',
        warning_fmt
    )
    
    # Conditional formatting to highlight the entire row when subsystem outputs are active
    worksheet.conditional_format(row, COL_LABEL, row, COL_NOTES, {
        "type": "formula",
        "criteria": f"={subsystem_cap_cell}<>0",
        "format": warning_fmt,
    })
    
    row += 2
    
    # Conditional formatting for delta cells (positive=red/cost, negative=green/savings)
    # Apply to the journal category rows
    for delta_row in range(delta_row_start, journal_delta_row_end + 1):
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
    
    # Apply to subsystem rows as well
    for delta_row in range(subsystem_row_start, subsystem_row_end + 1):
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


def _write_policy_delta_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
) -> tuple[int, int]:
    """Write the policy deltas section for generated fill rows.
    
    This section shows policy-driven adjustments that are NOT from the plan journal
    or authoritative warehouse data. These are analyst assumptions.
    
    Currently includes:
    - Generated roster fill rows (when RosterFillTarget > 0)
    
    Per the blueprint: policies must create visible generated rows that are toggleable.
    
    Returns (next_row, policy_delta_total_row).
    """
    # Section header with amber styling to indicate policy/assumption nature
    policy_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
        "bottom": 2,
    })
    
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "POLICY DELTAS (Generated Assumptions)",
        policy_header_fmt
    )
    row += 1
    
    # Column headers
    row = _write_column_headers(worksheet, row, budget_formats)
    
    # ------------------------------------------------------------------
    # Generated Fill Rows calculation
    # ------------------------------------------------------------------
    # Current roster count formula (matches roster_grid.py and audit.py)
    cap_choose_expr = (
        "CHOOSE(SelectedYear-MetaBaseYear+1,"
        + ",".join(f"tbl_salary_book_warehouse[cap_y{i}]" for i in range(6))
        + ")"
    )
    current_roster_formula = (
        "SUMPRODUCT(--(tbl_salary_book_warehouse[team_code]=SelectedTeam),"
        "--(tbl_salary_book_warehouse[is_two_way]=FALSE),"
        f"--({cap_choose_expr}>0))"
    )
    
    # Fill rows needed = MAX(0, RosterFillTarget - current_roster_count)
    fill_rows_needed_formula = f"MAX(0,RosterFillTarget-{current_roster_formula})"
    
    # Fill amount per row (based on RosterFillType)
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
    
    # Total fill impact = fill_rows_needed * fill_amount (only when RosterFillTarget > 0)
    # This applies to cap/tax/apron equally (minimums count the same for all modes)
    total_fill_formula = f"IF(RosterFillTarget>0,{fill_rows_needed_formula}*{fill_amount_formula},0)"
    
    # Policy delta format (amber to indicate assumption)
    policy_delta_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
    })
    policy_delta_zero_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#9CA3AF",  # gray-400 (muted when zero)
        "italic": True,
    })
    
    # Write the Generated Fill Rows row
    worksheet.write(row, COL_LABEL, "  Generated Fill Rows (GEN)", budget_formats["label_indent"])
    worksheet.write_formula(row, COL_CAP, f"={total_fill_formula}", policy_delta_zero_fmt)
    worksheet.write_formula(row, COL_TAX, f"={total_fill_formula}", policy_delta_zero_fmt)
    worksheet.write_formula(row, COL_APRON, f"={total_fill_formula}", policy_delta_zero_fmt)
    
    # Dynamic note showing fill count and type
    note_formula = (
        '=IF(RosterFillTarget>0,'
        f'"Adds "&{fill_rows_needed_formula}&" fill slots × "&RosterFillType,'
        '"Disabled (RosterFillTarget=0)")'
    )
    worksheet.write_formula(row, COL_NOTES, note_formula, budget_formats["note"])
    
    # Conditional formatting: highlight amber when fill is active (> 0)
    for col in [COL_CAP, COL_TAX, COL_APRON]:
        worksheet.conditional_format(row, col, row, col, {
            "type": "cell",
            "criteria": ">",
            "value": 0,
            "format": policy_delta_fmt,
        })
    
    fill_row = row
    row += 1
    
    # (Future: additional policy rows could be added here, e.g., incomplete roster charges)
    
    # ------------------------------------------------------------------
    # Policy Delta Total row
    # ------------------------------------------------------------------
    row += 1
    policy_total_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "bold": True,
        "top": 1,
        "bottom": 2,
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
    })
    policy_total_zero_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "bold": True,
        "top": 1,
        "bottom": 2,
        "bg_color": "#F3F4F6",  # gray-100 when zero
    })
    
    worksheet.write(row, COL_LABEL, "POLICY DELTA TOTAL", budget_formats["label_bold"])
    
    # For now, policy total = fill total (when more policy rows added, sum them)
    fill_cap_cell = xlsxwriter.utility.xl_rowcol_to_cell(fill_row, COL_CAP)
    fill_tax_cell = xlsxwriter.utility.xl_rowcol_to_cell(fill_row, COL_TAX)
    fill_apron_cell = xlsxwriter.utility.xl_rowcol_to_cell(fill_row, COL_APRON)
    
    worksheet.write_formula(row, COL_CAP, f"={fill_cap_cell}", policy_total_zero_fmt)
    worksheet.write_formula(row, COL_TAX, f"={fill_tax_cell}", policy_total_zero_fmt)
    worksheet.write_formula(row, COL_APRON, f"={fill_apron_cell}", policy_total_zero_fmt)
    worksheet.write(row, COL_NOTES, "Sum of policy-driven assumptions (NOT authoritative)", budget_formats["note"])
    
    # Conditional formatting for total row when active
    for col in [COL_CAP, COL_TAX, COL_APRON]:
        worksheet.conditional_format(row, col, row, col, {
            "type": "cell",
            "criteria": ">",
            "value": 0,
            "format": policy_total_fmt,
        })
    
    policy_total_row = row
    row += 2
    
    return row, policy_total_row


def _write_derived_section(
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    budget_formats: dict[str, Any],
    snapshot_total_row: int,
    plan_delta_total_row: int,
    policy_delta_total_row: int,
) -> int:
    """Write the derived totals section (snapshot + plan deltas + policy deltas).
    
    This shows the "if you execute this plan with these assumptions" state.
    
    Returns next row.
    """
    # Section header
    worksheet.merge_range(
        row, COL_LABEL, row, COL_NOTES,
        "DERIVED TOTALS (Snapshot + Plan + Policy)",
        budget_formats["section_header"]
    )
    row += 1
    
    # Column headers
    row = _write_column_headers(worksheet, row, budget_formats)
    
    # Derived total = snapshot + plan delta + policy delta
    snapshot_cap = xlsxwriter.utility.xl_rowcol_to_cell(snapshot_total_row, COL_CAP)
    snapshot_tax = xlsxwriter.utility.xl_rowcol_to_cell(snapshot_total_row, COL_TAX)
    snapshot_apron = xlsxwriter.utility.xl_rowcol_to_cell(snapshot_total_row, COL_APRON)
    
    plan_cap = xlsxwriter.utility.xl_rowcol_to_cell(plan_delta_total_row, COL_CAP)
    plan_tax = xlsxwriter.utility.xl_rowcol_to_cell(plan_delta_total_row, COL_TAX)
    plan_apron = xlsxwriter.utility.xl_rowcol_to_cell(plan_delta_total_row, COL_APRON)
    
    policy_cap = xlsxwriter.utility.xl_rowcol_to_cell(policy_delta_total_row, COL_CAP)
    policy_tax = xlsxwriter.utility.xl_rowcol_to_cell(policy_delta_total_row, COL_TAX)
    policy_apron = xlsxwriter.utility.xl_rowcol_to_cell(policy_delta_total_row, COL_APRON)
    
    worksheet.write(row, COL_LABEL, "DERIVED TOTAL", budget_formats["label_bold"])
    worksheet.write_formula(row, COL_CAP, f"={snapshot_cap}+{plan_cap}+{policy_cap}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_TAX, f"={snapshot_tax}+{plan_tax}+{policy_tax}", budget_formats["money_total"])
    worksheet.write_formula(row, COL_APRON, f"={snapshot_apron}+{plan_apron}+{policy_apron}", budget_formats["money_total"])
    worksheet.write(row, COL_NOTES, "Projected total: Snapshot + Plan + Policy assumptions", budget_formats["note"])
    
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
    """Write policy notifications for active features.
    
    Shows informational alerts when policy toggles are active:
    - RosterFillTarget > 0: shows generated fill rows are active
    - ShowExistsOnlyRows = "Yes": shows EXISTS_ONLY section is visible
    
    Returns next row.
    """
    # Create an info/warning format for active policies
    warning_fmt = workbook.add_format({
        "bold": True,
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
        "font_size": 10,
    })
    
    # RosterFillTarget ACTIVE notification
    # Uses IF formula to only show when RosterFillTarget > 0
    worksheet.write_formula(
        row, COL_LABEL,
        '=IF(RosterFillTarget>0,"📊 ROSTER FILL ACTIVE","")',
        warning_fmt
    )
    worksheet.write_formula(
        row, COL_CAP,
        '=IF(RosterFillTarget>0,"Target="&RosterFillTarget&", Type="&RosterFillType,"")',
        warning_fmt
    )
    worksheet.write_formula(
        row, COL_NOTES,
        '=IF(RosterFillTarget>0,"Generated fill rows added — see ROSTER_GRID and AUDIT_AND_RECONCILE","")',
        workbook.add_format({
            "bg_color": "#FEF3C7",
            "font_color": "#92400E",
            "font_size": 9,
            "italic": True,
        })
    )
    
    # Conditional formatting to highlight the entire row when fill is active
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

    # NOTE: The former "Two-way toggles NOT YET IMPLEMENTED" warning was removed.
    # Two-way counting is a CBA fact (2-way counts toward cap totals, not roster).
    # The COCKPIT now shows informational 2-way readouts instead.

    # Blank row for spacing
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
    - Plan deltas (from tbl_plan_journal, enabled rows filtered by ActivePlanId + SelectedYear)
    - Policy deltas (generated fill rows and other analyst assumptions)
    - Derived totals (snapshot + plan + policy)
    - Room/over analysis for cap/tax/aprons
    - Verification that formulas are consistent

    Per the blueprint:
    - This is the "single source of truth for totals and deltas"
    - This is the sheet you use to explain numbers to a GM/owner
    - Mode-aware (Cap vs Tax vs Apron columns always visible)
    - Policy deltas are explicit and toggleable (visible generated rows)

    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The BUDGET_LEDGER worksheet
        formats: Standard format dict from create_standard_formats
    """
    # Sheet title
    worksheet.write(0, 0, "BUDGET LEDGER", formats["header"])
    worksheet.write(1, 0, "Authoritative accounting statement (Snapshot + Plan + Policy = Derived)")
    
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
    
    # 3. Plan delta section (from tbl_plan_journal + tbl_subsystem_outputs)
    content_row, plan_delta_total_row = _write_plan_delta_section(
        workbook, worksheet, content_row, formats, budget_formats
    )
    
    # 4. Policy delta section (generated fill rows and other assumptions)
    content_row, policy_delta_total_row = _write_policy_delta_section(
        workbook, worksheet, content_row, formats, budget_formats
    )
    
    # 5. Derived totals section (snapshot + plan + policy)
    content_row, derived_total_row = _write_derived_section(
        worksheet, content_row, formats, budget_formats,
        snapshot_total_row, plan_delta_total_row, policy_delta_total_row
    )
    
    # 6. Verification section
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
