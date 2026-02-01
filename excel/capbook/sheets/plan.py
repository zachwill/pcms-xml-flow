"""
PLAN_MANAGER and PLAN_JOURNAL sheet writers — scenario engine foundation.

This module implements:
1. PLAN_MANAGER — manages scenarios (plans) with an editable table
2. PLAN_JOURNAL — ordered action journal for scenario modeling
   - Includes a running-state panel showing ActivePlan + SelectedYear summary
   - Cumulative running totals by step for the active plan/year
   - Conditional formatting to gray out rows not in ActivePlan/SelectedYear

Per the blueprint (excel-cap-book-blueprint.md):
- A "scenario" is: Baseline state + Plan journal + Derived state
- Analysts work by transformations, not edits
- Comparison is a first-class workflow (A/B/C/D lanes)
- Next to the journal: a running-state panel with totals after each step

Design notes:
- PLAN_MANAGER provides the list of plans for ActivePlan dropdown validation
- PLAN_JOURNAL holds ordered actions that modify the baseline
- Both tables are INPUT zones (unlocked for editing, yellow background)
- The tables must be actual Excel Tables for formula references
- The running-state panel is positioned to the right of the journal table

**Excel 365/2021 Required (Modern Formulas):**
- Running-state panel uses LET + FILTER + SUM instead of SUMPRODUCT
- Cumulative totals use SCAN for efficient running sums (single spilling formula)
- Leverages PlanRowMask LAMBDA for consistent filtering across the workbook
- See .ralph/EXCEL.md backlog item #4 for migration rationale

Named table conventions:
- tbl_plan_manager: Plan definitions (user-editable)
- tbl_plan_journal: Ordered actions (user-editable)
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import xlsxwriter.utility

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import FMT_MONEY
from .command_bar import (
    write_command_bar_readonly,
    get_content_start_row,
    NAMED_RANGES,
    ROW_ACTIVE_PLAN,
    COL_INPUT_3,
    COCKPIT_SHEET_NAME,
)


# =============================================================================
# Action Type Taxonomy
# =============================================================================

# Per the blueprint (mental-models-and-design-principles.md Section 7.2)
# These are the valid action types for the plan journal.
ACTION_TYPES = [
    "Trade",
    "Sign (Cap Room)",
    "Sign (Exception)",
    "Sign (Minimum)",
    "Waive",
    "Buyout",
    "Stretch",
    "Renounce",
    "Option Exercise",
    "Option Decline",
    "Convert 2-Way",
    "Sign 2-Way",
    "Use TPE",
    "Other",
]


# =============================================================================
# Layout Constants
# =============================================================================

# PLAN_MANAGER layout
PM_COL_PLAN_ID = 0
PM_COL_PLAN_NAME = 1
PM_COL_NOTES = 2
PM_COL_CREATED_AT = 3
PM_COL_IS_ACTIVE = 4  # Helper for filtering

# PLAN_JOURNAL layout
PJ_COL_STEP = 0
PJ_COL_PLAN_ID = 1
PJ_COL_ENABLED = 2
PJ_COL_SALARY_YEAR = 3  # NEW: which salary year the delta applies to
PJ_COL_EFFECTIVE_DATE = 4
PJ_COL_ACTION_TYPE = 5
PJ_COL_TARGET_PLAYER = 6
PJ_COL_TARGET_TEAM = 7
PJ_COL_NOTES = 8
PJ_COL_DELTA_CAP = 9
PJ_COL_DELTA_TAX = 10
PJ_COL_DELTA_APRON = 11
PJ_COL_VALIDATION = 12
PJ_COL_SOURCE = 13

# Running-state panel layout (positioned to the right of journal table)
# Gap of 1 column after PJ_COL_SOURCE, then the panel starts
PJ_RUNNING_PANEL_GAP = 2  # Columns between journal table and running panel
PJ_RUNNING_COL_START = PJ_COL_SOURCE + PJ_RUNNING_PANEL_GAP  # Column 15
PJ_RUNNING_COL_LABEL = PJ_RUNNING_COL_START  # Column for labels
PJ_RUNNING_COL_VALUE = PJ_RUNNING_COL_START + 1  # Column for values

# Running totals columns (to the right of the summary box)
PJ_CUMULATIVE_COL_START = PJ_RUNNING_COL_VALUE + 2  # Start of cumulative table


# =============================================================================
# Format Helpers
# =============================================================================

def _create_plan_formats(workbook: Workbook) -> dict[str, Any]:
    """Create formats specific to plan sheets."""
    formats = {}
    
    # Section headers
    formats["section_header"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#1E3A5F",  # Dark blue
        "font_color": "#FFFFFF",
        "bottom": 2,
    })
    
    # Input cell format (editable zone)
    formats["input"] = workbook.add_format({
        "bg_color": "#FFFDE7",  # Light yellow
        "border": 1,
        "border_color": "#FBC02D",  # Amber
        "locked": False,
    })
    
    formats["input_date"] = workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "num_format": "yyyy-mm-dd",
    })
    
    formats["input_money"] = workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "num_format": FMT_MONEY,
    })
    
    formats["input_center"] = workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "align": "center",
    })
    
    # Table headers
    formats["table_header"] = workbook.add_format({
        "bold": True,
        "bg_color": "#E5E7EB",  # gray-200
        "border": 1,
    })
    
    # Labels
    formats["label"] = workbook.add_format({
        "font_size": 10,
    })
    
    # Notes
    formats["note"] = workbook.add_format({
        "font_size": 9,
        "font_color": "#6B7280",
        "italic": True,
    })
    
    # Validation indicators
    formats["valid_ok"] = workbook.add_format({
        "font_color": "#059669",  # green-600
        "align": "center",
    })
    formats["valid_warn"] = workbook.add_format({
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
        "align": "center",
    })
    formats["valid_error"] = workbook.add_format({
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "align": "center",
    })
    
    # -------------------------------------------------------------------------
    # Running-state panel formats
    # -------------------------------------------------------------------------
    
    # Panel header (dark blue, similar to section header)
    formats["panel_header"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#1E3A5F",  # Dark blue
        "font_color": "#FFFFFF",
        "border": 1,
        "align": "center",
    })
    
    # Panel sub-header (lighter blue)
    formats["panel_subheader"] = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "bg_color": "#3B82F6",  # blue-500
        "font_color": "#FFFFFF",
        "border": 1,
    })
    
    # Panel label (left-aligned, light bg)
    formats["panel_label"] = workbook.add_format({
        "font_size": 10,
        "bg_color": "#F3F4F6",  # gray-100
        "border": 1,
    })
    
    # Panel value (right-aligned, light bg)
    formats["panel_value"] = workbook.add_format({
        "font_size": 10,
        "bg_color": "#F3F4F6",  # gray-100
        "border": 1,
        "align": "right",
    })
    
    # Panel value - money format
    formats["panel_value_money"] = workbook.add_format({
        "font_size": 10,
        "bg_color": "#F3F4F6",  # gray-100
        "border": 1,
        "align": "right",
        "num_format": FMT_MONEY,
    })
    
    # Grayed-out format for rows not in ActivePlan/SelectedYear
    # Used via conditional formatting
    formats["grayed_out"] = workbook.add_format({
        "font_color": "#9CA3AF",  # gray-400
        "bg_color": "#F9FAFB",  # gray-50
    })
    
    return formats


# =============================================================================
# PLAN_MANAGER Sheet Writer
# =============================================================================

def write_plan_manager(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write PLAN_MANAGER sheet with plan definitions table.
    
    The plan manager provides:
    - A table of plan definitions (ID, name, notes, created_at)
    - The "Baseline" plan is pre-populated and always first
    - Users can add new plans by extending the table
    - The plan names feed the ActivePlan dropdown on TEAM_COCKPIT
    
    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The PLAN_MANAGER worksheet
        formats: Standard format dict from create_standard_formats
    """
    plan_formats = _create_plan_formats(workbook)
    
    # Sheet title
    worksheet.write(0, 0, "PLAN MANAGER", formats["header"])
    worksheet.write(1, 0, "Manage scenarios — plans feed ActivePlan dropdown on TEAM_COCKPIT")
    
    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)
    
    # Column widths
    worksheet.set_column(PM_COL_PLAN_ID, PM_COL_PLAN_ID, 10)
    worksheet.set_column(PM_COL_PLAN_NAME, PM_COL_PLAN_NAME, 20)
    worksheet.set_column(PM_COL_NOTES, PM_COL_NOTES, 40)
    worksheet.set_column(PM_COL_CREATED_AT, PM_COL_CREATED_AT, 20)
    worksheet.set_column(PM_COL_IS_ACTIVE, PM_COL_IS_ACTIVE, 12)
    
    content_row = get_content_start_row()
    
    # Section header
    worksheet.merge_range(
        content_row, PM_COL_PLAN_ID,
        content_row, PM_COL_IS_ACTIVE,
        "PLAN DEFINITIONS (tbl_plan_manager)",
        plan_formats["section_header"],
    )
    content_row += 1
    
    # Instructions
    worksheet.write(
        content_row, PM_COL_PLAN_ID,
        "Add rows to create new plans. Plan names appear in ActivePlan dropdown.",
        plan_formats["note"],
    )
    content_row += 2
    
    # Pre-populate with Baseline plan
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
    
    # Define table columns
    columns = ["plan_id", "plan_name", "notes", "created_at", "is_active"]
    
    # Initial data: Baseline plan + 4 empty slots for user plans
    initial_data = [
        {
            "plan_id": 1,
            "plan_name": "Baseline",
            "notes": "Original snapshot — no modifications",
            "created_at": now_str,
            "is_active": "Yes",
        },
        # Empty slots for user to add plans
        {"plan_id": 2, "plan_name": "", "notes": "", "created_at": "", "is_active": ""},
        {"plan_id": 3, "plan_name": "", "notes": "", "created_at": "", "is_active": ""},
        {"plan_id": 4, "plan_name": "", "notes": "", "created_at": "", "is_active": ""},
        {"plan_id": 5, "plan_name": "", "notes": "", "created_at": "", "is_active": ""},
    ]
    
    # Write the table
    table_start_row = content_row
    table_end_row = table_start_row + len(initial_data)
    table_end_col = len(columns) - 1
    
    # Build data matrix
    data_matrix = []
    for row_dict in initial_data:
        data_matrix.append([row_dict.get(col, "") for col in columns])
    
    # Column definitions with unlocked formats for editing on protected sheet
    # All columns in tbl_plan_manager are user-editable inputs
    column_defs = [
        {"header": "plan_id", "format": formats["input_int"]},
        {"header": "plan_name", "format": formats["input"]},
        {"header": "notes", "format": formats["input"]},
        {"header": "created_at", "format": formats["input"]},
        {"header": "is_active", "format": formats["input"]},
    ]
    
    worksheet.add_table(
        table_start_row,
        PM_COL_PLAN_ID,
        table_end_row,
        table_end_col,
        {
            "name": "tbl_plan_manager",
            "columns": column_defs,
            "data": data_matrix,
            "style": "Table Style Light 9",  # Yellow-ish to indicate input
        },
    )
    
    # Data validation for is_active column
    worksheet.data_validation(
        table_start_row + 1,  # First data row
        PM_COL_IS_ACTIVE,
        table_end_row,
        PM_COL_IS_ACTIVE,
        {
            "validate": "list",
            "source": ["Yes", "No", ""],
            "input_title": "Plan Active?",
            "input_message": "Is this plan active for selection?",
        },
    )
    
    content_row = table_end_row + 3
    
    # Editable zone note
    worksheet.write(
        content_row, PM_COL_PLAN_ID,
        "📝 EDITABLE ZONE: The table above (yellow cells) is unlocked for editing. "
        "Formulas and sheet structure are protected.",
        plan_formats["note"],
    )
    content_row += 2
    
    # Usage notes
    worksheet.write(content_row, PM_COL_PLAN_ID, "Usage Notes:", formats["header"])
    content_row += 1
    
    notes = [
        "• 'Baseline' is the default plan showing unmodified snapshot data",
        "• Add a plan_name to create a new scenario",
        "• Set is_active='Yes' for plans to appear in ActivePlan dropdown",
        "• Plan actions are recorded in PLAN_JOURNAL tab",
        "• Compare plans using ComparePlanA/B/C/D dropdowns on TEAM_COCKPIT",
    ]
    for note in notes:
        worksheet.write(content_row, PM_COL_PLAN_ID, note, plan_formats["note"])
        content_row += 1
    
    # Sheet protection (allows editing table cells)
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })


# =============================================================================
# PLAN_JOURNAL Sheet Writer
# =============================================================================

def write_plan_journal(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write PLAN_JOURNAL sheet with ordered action journal and running-state panel.
    
    The plan journal provides:
    - An input table for recording scenario actions
    - Action Type validation from the taxonomy
    - Delta columns for cap/tax/apron effects
    - Validation status column
    - Source column (e.g., "Generated by Trade Lane A")
    - **Running-state panel** showing ActivePlan + SelectedYear summary
    - **Cumulative running totals** by step for the active plan/year
    - Conditional formatting to gray out rows not in ActivePlan/SelectedYear
    
    Per the blueprint (excel-cap-book-blueprint.md):
    - Journal table columns: Step#, Enabled?, EffectiveDate, ActionType,
      Targets, Parameters, ComputedDeltas, RosterAdds/Drops, ValidationStatus, Source
    - Next to the journal: a running-state panel with totals after each step
    
    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The PLAN_JOURNAL worksheet
        formats: Standard format dict from create_standard_formats
    """
    plan_formats = _create_plan_formats(workbook)
    
    # Sheet title
    worksheet.write(0, 0, "PLAN JOURNAL", formats["header"])
    worksheet.write(1, 0, "Ordered scenario actions — each row is a step in the plan")
    
    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)
    
    # Column widths for journal table
    worksheet.set_column(PJ_COL_STEP, PJ_COL_STEP, 6)
    worksheet.set_column(PJ_COL_PLAN_ID, PJ_COL_PLAN_ID, 8)
    worksheet.set_column(PJ_COL_ENABLED, PJ_COL_ENABLED, 9)
    worksheet.set_column(PJ_COL_SALARY_YEAR, PJ_COL_SALARY_YEAR, 11)
    worksheet.set_column(PJ_COL_EFFECTIVE_DATE, PJ_COL_EFFECTIVE_DATE, 14)
    worksheet.set_column(PJ_COL_ACTION_TYPE, PJ_COL_ACTION_TYPE, 16)
    worksheet.set_column(PJ_COL_TARGET_PLAYER, PJ_COL_TARGET_PLAYER, 20)
    worksheet.set_column(PJ_COL_TARGET_TEAM, PJ_COL_TARGET_TEAM, 10)
    worksheet.set_column(PJ_COL_NOTES, PJ_COL_NOTES, 25)
    worksheet.set_column(PJ_COL_DELTA_CAP, PJ_COL_DELTA_CAP, 12)
    worksheet.set_column(PJ_COL_DELTA_TAX, PJ_COL_DELTA_TAX, 12)
    worksheet.set_column(PJ_COL_DELTA_APRON, PJ_COL_DELTA_APRON, 12)
    worksheet.set_column(PJ_COL_VALIDATION, PJ_COL_VALIDATION, 12)
    worksheet.set_column(PJ_COL_SOURCE, PJ_COL_SOURCE, 20)
    
    # Column widths for running-state panel (to the right of journal)
    worksheet.set_column(PJ_RUNNING_COL_LABEL, PJ_RUNNING_COL_LABEL, 18)
    worksheet.set_column(PJ_RUNNING_COL_VALUE, PJ_RUNNING_COL_VALUE, 14)
    
    content_row = get_content_start_row()
    
    # Section header for journal table
    worksheet.merge_range(
        content_row, PJ_COL_STEP,
        content_row, PJ_COL_SOURCE,
        "PLAN JOURNAL (tbl_plan_journal) — Record scenario actions",
        plan_formats["section_header"],
    )
    content_row += 1
    
    # Instructions
    worksheet.write(
        content_row, PJ_COL_STEP,
        "Enter actions in order. Each action has a salary_year (defaults to SelectedYear). "
        "Delta columns show cap/tax/apron effect (positive = cost increase, negative = savings).",
        plan_formats["note"],
    )
    content_row += 2
    
    # Define table columns (now includes salary_year)
    columns = [
        "step",
        "plan_id",
        "enabled",
        "salary_year",  # NEW: which year the delta applies to
        "effective_date",
        "action_type",
        "target_player",
        "target_team",
        "notes",
        "delta_cap",
        "delta_tax",
        "delta_apron",
        "validation",
        "source",
    ]
    
    # Initial empty rows for user input
    # salary_year defaults to "" which means the BUDGET_LEDGER formulas will filter by SelectedYear
    # Users can override to apply deltas to different years (e.g., multi-year contracts)
    num_empty_rows = 20
    initial_data = []
    for i in range(num_empty_rows):
        initial_data.append({
            "step": i + 1,
            "plan_id": "",
            "enabled": "",
            "salary_year": "",  # Blank defaults to SelectedYear in formulas
            "effective_date": "",
            "action_type": "",
            "target_player": "",
            "target_team": "",
            "notes": "",
            "delta_cap": 0,
            "delta_tax": 0,
            "delta_apron": 0,
            "validation": "",
            "source": "",
        })
    
    # Write the table
    table_start_row = content_row
    table_end_row = table_start_row + len(initial_data)
    table_end_col = len(columns) - 1
    
    # Build data matrix
    data_matrix = []
    for row_dict in initial_data:
        data_matrix.append([row_dict.get(col, "") for col in columns])
    
    # Column definitions with unlocked formats for editing on protected sheet
    # Most columns are user-editable; delta and validation may be formula-driven in future
    column_defs = [
        {"header": "step", "format": formats["input_int"]},
        {"header": "plan_id", "format": formats["input_int"]},
        {"header": "enabled", "format": formats["input"]},
        {"header": "salary_year", "format": formats["input_int"]},  # NEW: year context
        {"header": "effective_date", "format": formats["input_date"]},
        {"header": "action_type", "format": formats["input"]},
        {"header": "target_player", "format": formats["input"]},
        {"header": "target_team", "format": formats["input"]},
        {"header": "notes", "format": formats["input"]},
        {"header": "delta_cap", "format": formats["input_money"]},
        {"header": "delta_tax", "format": formats["input_money"]},
        {"header": "delta_apron", "format": formats["input_money"]},
        {"header": "validation", "format": formats["input"]},
        {"header": "source", "format": formats["input"]},
    ]
    
    worksheet.add_table(
        table_start_row,
        PJ_COL_STEP,
        table_end_row,
        table_end_col,
        {
            "name": "tbl_plan_journal",
            "columns": column_defs,
            "data": data_matrix,
            "style": "Table Style Light 9",  # Yellow-ish to indicate input
        },
    )
    
    # Data validation: enabled column
    worksheet.data_validation(
        table_start_row + 1,
        PJ_COL_ENABLED,
        table_end_row,
        PJ_COL_ENABLED,
        {
            "validate": "list",
            "source": ["Yes", "No", ""],
            "input_title": "Enabled?",
            "input_message": "Is this action enabled?",
        },
    )
    
    # Data validation: salary_year column
    # Allow blank (defaults to SelectedYear) or valid years (base_year through base_year+5)
    # Since we don't know base_year at generation time, use a reasonable range
    worksheet.data_validation(
        table_start_row + 1,
        PJ_COL_SALARY_YEAR,
        table_end_row,
        PJ_COL_SALARY_YEAR,
        {
            "validate": "integer",
            "criteria": "between",
            "minimum": 2024,
            "maximum": 2035,
            "ignore_blank": True,
            "input_title": "Salary Year",
            "input_message": "Which year does this delta apply to? Leave blank for SelectedYear.",
        },
    )
    
    # Data validation: action_type column (from taxonomy)
    worksheet.data_validation(
        table_start_row + 1,
        PJ_COL_ACTION_TYPE,
        table_end_row,
        PJ_COL_ACTION_TYPE,
        {
            "validate": "list",
            "source": ACTION_TYPES,
            "input_title": "Action Type",
            "input_message": "Select the type of action",
            "error_title": "Invalid Action",
            "error_message": "Please select a valid action type from the list",
        },
    )
    
    # Data validation: validation status
    worksheet.data_validation(
        table_start_row + 1,
        PJ_COL_VALIDATION,
        table_end_row,
        PJ_COL_VALIDATION,
        {
            "validate": "list",
            "source": ["OK", "Warning", "Error", ""],
            "input_title": "Validation Status",
            "input_message": "Status of this action",
        },
    )
    
    # Conditional formatting for validation column
    worksheet.conditional_format(
        table_start_row + 1,
        PJ_COL_VALIDATION,
        table_end_row,
        PJ_COL_VALIDATION,
        {
            "type": "text",
            "criteria": "containing",
            "value": "OK",
            "format": plan_formats["valid_ok"],
        },
    )
    worksheet.conditional_format(
        table_start_row + 1,
        PJ_COL_VALIDATION,
        table_end_row,
        PJ_COL_VALIDATION,
        {
            "type": "text",
            "criteria": "containing",
            "value": "Warning",
            "format": plan_formats["valid_warn"],
        },
    )
    worksheet.conditional_format(
        table_start_row + 1,
        PJ_COL_VALIDATION,
        table_end_row,
        PJ_COL_VALIDATION,
        {
            "type": "text",
            "criteria": "containing",
            "value": "Error",
            "format": plan_formats["valid_error"],
        },
    )
    
    # =========================================================================
    # Conditional formatting: gray out rows NOT in ActivePlan/SelectedYear
    # =========================================================================
    # A row "counts" for the current context if:
    #   - plan_id matches ActivePlanId (or plan_id is blank)
    #   - AND salary_year matches SelectedYear (or salary_year is blank)
    #
    # Rows that do NOT match the current (ActivePlanId, SelectedYear) context
    # are grayed out to reduce visual noise.
    #
    # Row reference: $B{row} = plan_id, $D{row} = salary_year
    # =========================================================================
    
    # Build the conditional format formula.
    # The formula is applied to each row and uses relative row references.
    first_data_row = table_start_row + 2  # 1-indexed for Excel formula
    
    # Gray out if NOT( plan matches AND year matches )
    gray_out_formula = (
        f'=NOT(AND('
        f'OR($B{first_data_row}=ActivePlanId,$B{first_data_row}=""),'
        f'OR($D{first_data_row}=SelectedYear,$D{first_data_row}="")'
        f'))'
    )
    
    # Apply to entire journal table data rows (all columns)
    worksheet.conditional_format(
        table_start_row + 1,
        PJ_COL_STEP,
        table_end_row,
        PJ_COL_SOURCE,
        {
            "type": "formula",
            "criteria": gray_out_formula,
            "format": plan_formats["grayed_out"],
        },
    )
    
    # =========================================================================
    # RUNNING-STATE PANEL (to the right of the journal table)
    # =========================================================================
    _write_running_state_panel(
        workbook,
        worksheet,
        formats,
        plan_formats,
        panel_start_row=table_start_row,
        table_start_row=table_start_row,
        table_end_row=table_end_row,
        num_data_rows=num_empty_rows,
    )
    
    content_row = table_end_row + 3
    
    # Editable zone note
    worksheet.write(
        content_row, PJ_COL_STEP,
        "📝 EDITABLE ZONE: The table above (yellow cells) is unlocked for editing. "
        "Formulas and sheet structure are protected.",
        plan_formats["note"],
    )
    content_row += 2
    
    # =========================================================================
    # SUBSYSTEM OUTPUTS TABLE (tbl_subsystem_outputs)
    # =========================================================================
    # This is a staging table that aggregates deltas from subsystem sheets
    # (TRADE_MACHINE lanes, SIGNINGS_AND_EXCEPTIONS, WAIVE_BUYOUT_STRETCH).
    #
    # Each row corresponds to one subsystem's Journal Output block.
    # Delta columns are formula-linked to the subsystem sheets.
    # The include_in_plan toggle controls whether the row is counted.
    #
    # Per backlog task #18, this replaces the manual copy/paste workflow.
    # =========================================================================
    
    content_row = _write_subsystem_outputs_table(
        workbook, worksheet, formats, plan_formats, content_row
    )
    content_row += 2
    
    # Action type reference
    worksheet.write(content_row, PJ_COL_STEP, "Action Types (Reference):", formats["header"])
    content_row += 1
    
    for action_type in ACTION_TYPES:
        worksheet.write(content_row, PJ_COL_STEP, f"  • {action_type}", plan_formats["note"])
        content_row += 1
    
    content_row += 1
    
    # Usage notes
    worksheet.write(content_row, PJ_COL_STEP, "Usage Notes:", formats["header"])
    content_row += 1
    
    notes = [
        "• Each row is one action in the plan",
        "• Use plan_id to associate actions with plans from PLAN_MANAGER",
        "• Set enabled='Yes' to include action in plan calculations",
        "• salary_year: which year this delta applies to (leave blank for SelectedYear)",
        "• Delta columns: + = cost increase, - = savings",
        "• BUDGET_LEDGER aggregates deltas from tbl_plan_journal AND tbl_subsystem_outputs",
        "• ⚠️ Do NOT manually copy subsystem rows into tbl_plan_journal (double-counting!)",
        "• The RUNNING STATE panel shows cumulative totals for ActivePlan + SelectedYear",
        "• Grayed-out rows do not match the current ActivePlan/SelectedYear context",
    ]
    for note in notes:
        worksheet.write(content_row, PJ_COL_STEP, note, plan_formats["note"])
        content_row += 1
    
    # Sheet protection (allows editing table cells)
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })


# =============================================================================
# SUBSYSTEM_OUTPUTS Table Writer
# =============================================================================

# Subsystem outputs table column layout
SO_COL_INCLUDE = 0  # include_in_plan (Yes/No)
SO_COL_PLAN_ID = 1  # plan_id (defaults to ActivePlanId via formula)
SO_COL_SALARY_YEAR = 2  # salary_year (defaults to SelectedYear via formula)
SO_COL_DELTA_CAP = 3  # delta_cap (formula-linked to subsystem)
SO_COL_DELTA_TAX = 4  # delta_tax (formula-linked to subsystem)
SO_COL_DELTA_APRON = 5  # delta_apron (formula-linked to subsystem)
SO_COL_SOURCE = 6  # source (fixed label per row)
SO_COL_NOTES = 7  # notes (user-editable)

# Fixed subsystem row definitions
# Each tuple: (source_label, delta_formula_template, notes)
# The delta_formula_template is a sheet + cell reference pattern that will be used
# to look up the corresponding Journal Output delta from each subsystem.
#
# For TRADE_MACHINE lanes, the deltas are computed inline in the lane.
# For SIGNINGS and WAIVE, the deltas are in their Journal Output sections.
#
# Since cell references can change with sheet layout updates, we use stable
# INDIRECT patterns or direct sheet references that match the current layout.
SUBSYSTEM_ROWS = [
    ("Trade Lane A", "TRADE_MACHINE"),
    ("Trade Lane B", "TRADE_MACHINE"),
    ("Trade Lane C", "TRADE_MACHINE"),
    ("Trade Lane D", "TRADE_MACHINE"),
    ("Signings (SIGNINGS_AND_EXCEPTIONS)", "SIGNINGS_AND_EXCEPTIONS"),
    ("Waive/Buyout (WAIVE_BUYOUT_STRETCH)", "WAIVE_BUYOUT_STRETCH"),
]


def _write_subsystem_outputs_table(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    plan_formats: dict[str, Any],
    start_row: int,
) -> int:
    """
    Write the SUBSYSTEM_OUTPUTS table as a staging area for subsystem deltas.
    
    This table provides a no-copy-paste way to include subsystem outputs
    (TRADE_MACHINE lanes, SIGNINGS, WAIVE) in plan calculations.
    
    Features:
    - Fixed rows for each subsystem (6 total: 4 trade lanes + signings + waive)
    - include_in_plan toggle to control which subsystems count
    - plan_id defaults to ActivePlanId via formula
    - salary_year defaults to SelectedYear via formula
    - Delta columns are formula-linked to each subsystem's Journal Output block
    - BUDGET_LEDGER sums tbl_subsystem_outputs where include_in_plan="Yes"
    
    Per backlog task #18:
    - This replaces the manual copy/paste workflow from subsystem sheets
    - Includes a loud warning about NOT duplicating into tbl_plan_journal
    
    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The PLAN_JOURNAL worksheet
        formats: Standard formats dict
        plan_formats: Plan-specific formats dict
        start_row: Row where the section starts
        
    Returns:
        The row after the table (for continuing content placement)
    """
    content_row = start_row
    
    # Section header
    worksheet.merge_range(
        content_row, SO_COL_INCLUDE,
        content_row, SO_COL_NOTES,
        "SUBSYSTEM OUTPUTS (tbl_subsystem_outputs) — Auto-linked from subsystem sheets",
        plan_formats["section_header"],
    )
    content_row += 1
    
    # Warning banner (loud, important)
    warning_format = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "font_color": "#7C2D12",  # orange-900
        "bg_color": "#FED7AA",  # orange-200
        "border": 2,
        "border_color": "#EA580C",  # orange-600
        "text_wrap": True,
    })
    worksheet.merge_range(
        content_row, SO_COL_INCLUDE,
        content_row, SO_COL_NOTES,
        "⚠️ WARNING: Do NOT also copy these deltas into tbl_plan_journal — they are already "
        "included via this table. Doing so will DOUBLE-COUNT the amounts!",
        warning_format,
    )
    worksheet.set_row(content_row, 30)  # Taller row for warning
    content_row += 1
    
    # Instructions
    worksheet.write(
        content_row, SO_COL_INCLUDE,
        "Toggle 'include_in_plan' to include/exclude each subsystem. Deltas auto-update from subsystem sheets.",
        plan_formats["note"],
    )
    content_row += 2
    
    # Table columns
    subsystem_columns = [
        "include_in_plan",
        "plan_id",
        "salary_year",
        "delta_cap",
        "delta_tax",
        "delta_apron",
        "source",
        "notes",
    ]
    
    # Build data matrix
    # Each row is pre-filled with defaults; delta columns will have formulas
    table_start_row = content_row
    data_matrix = []
    
    for source_label, sheet_name in SUBSYSTEM_ROWS:
        data_matrix.append([
            "No",  # include_in_plan (default to No)
            "",    # plan_id (formula: =ActivePlanId)
            "",    # salary_year (formula: =SelectedYear)
            0,     # delta_cap (formula-linked)
            0,     # delta_tax (formula-linked)
            0,     # delta_apron (formula-linked)
            source_label,  # source (fixed)
            "",    # notes (user-editable)
        ])
    
    table_end_row = table_start_row + len(data_matrix)
    
    # Build delta formulas for each row
    # These reference the Journal Output sections in subsystem sheets
    #
    # TRADE_MACHINE lanes:
    #   Lanes are laid out in columns 0-5 (lane A), 6-11 (lane B), etc.
    #   Each lane's Journal Output section has Δ Cap/Tax/Apron values.
    #   The exact cell references depend on layout but we can use INDIRECT
    #   or hard-coded references based on known layout.
    #
    # SIGNINGS_AND_EXCEPTIONS:
    #   Has a Journal Output section with aggregated deltas.
    #
    # WAIVE_BUYOUT_STRETCH:
    #   Has a Journal Output section with aggregated deltas.
    #
    # For robustness, we reference SUBTOTAL formulas that sum the table columns.
    # This is more stable than referencing specific cells.
    #
    # Trade lanes: They compute Total In - Total Out inline, no stable table.
    # We'll reference the net delta formula cells directly.
    # Layout: Lane A at col 0-5, Lane B at col 6-11, etc.
    # Net Delta is after Outgoing + Incoming sections.
    # Since these can shift, we use a formula pattern that looks for the
    # computed net from the lane's Total In - Total Out.
    #
    # For now, use SUBTOTAL references for Signings/Waive (stable) and
    # a cross-reference for Trade lanes (matches current layout).
    
    # Define delta formulas per subsystem row
    # Trade lane deltas: reference the inline net delta from each lane
    # These are calculated as Total In - Total Out per lane.
    # We'll use named ranges or direct cell references.
    #
    # Layout analysis from subsystems.py:
    # - Each lane starts at base_col = lane_idx * 6
    # - Lane content starts at content_row (after command bar) ≈ row 15
    # - Net Delta is computed after incoming totals, varies by row
    #
    # For stability, we'll reference the JOURNAL OUTPUT section of each lane.
    # Per the code, the JOURNAL OUTPUT has Δ Cap, Δ Tax, Δ Apron as formulas.
    # The exact rows depend on layout, so we use approximate cell refs.
    #
    # Alternative: Use a formula that SUMs from the lane's incoming/outgoing.
    # But this would duplicate logic. Better to reference the computed delta.
    #
    # For this implementation, we'll use a pattern that can be adjusted:
    # Trade Lane A: references from TRADE_MACHINE sheet, column B (value col)
    # Row numbers will need to be stable or we use a search pattern.
    #
    # SIMPLER APPROACH: Just reference the SUBTOTAL for signings/waive,
    # and for trade lanes, use a formula that computes the net inline.
    # This avoids fragile cell references.
    #
    # Even simpler for trade lanes: reference TradeLane{X}Team to check if
    # a lane is active, then compute from the known table structure.
    # But we don't have trade lane values in a stable table.
    #
    # PRAGMATIC APPROACH:
    # For now, make delta columns user-editable (input format) so users can
    # manually enter or formula-link. The trade lanes don't have stable
    # table references. In future, we could add stable named ranges.
    #
    # BUT: For signings and waive, we CAN use stable SUBTOTAL references!
    # So we'll make those formula-driven and trade lanes manual.
    
    # Delta formula templates (row-specific)
    # Index matches SUBSYSTEM_ROWS order
    delta_formulas = [
        # Trade Lane A-D: manual entry for now (no stable table reference)
        # Users can enter values or we could add named ranges later
        (None, None, None),  # Lane A
        (None, None, None),  # Lane B
        (None, None, None),  # Lane C
        (None, None, None),  # Lane D
        # Signings: use SUBTOTAL from tbl_signings_input[delta_*]
        (
            "=SUBTOTAL(109,tbl_signings_input[delta_cap])",
            "=SUBTOTAL(109,tbl_signings_input[delta_tax])",
            "=SUBTOTAL(109,tbl_signings_input[delta_apron])",
        ),
        # Waive: use SUBTOTAL from tbl_waive_input[delta_*]
        (
            "=SUBTOTAL(109,tbl_waive_input[delta_cap])",
            "=SUBTOTAL(109,tbl_waive_input[delta_tax])",
            "=SUBTOTAL(109,tbl_waive_input[delta_apron])",
        ),
    ]
    
    # Column definitions
    # - include_in_plan: input (Yes/No dropdown)
    # - plan_id: formula (defaults to ActivePlanId)
    # - salary_year: formula (defaults to SelectedYear)
    # - delta_cap/tax/apron: formula where available, input otherwise
    # - source: locked (fixed label)
    # - notes: input
    column_defs = [
        {"header": "include_in_plan", "format": formats["input"]},
        {"header": "plan_id", "format": plan_formats["panel_value"]},
        {"header": "salary_year", "format": plan_formats["panel_value"]},
        {"header": "delta_cap", "format": formats["input_money"]},
        {"header": "delta_tax", "format": formats["input_money"]},
        {"header": "delta_apron", "format": formats["input_money"]},
        {"header": "source"},  # Will apply locked format separately
        {"header": "notes", "format": formats["input"]},
    ]
    
    worksheet.add_table(
        table_start_row,
        SO_COL_INCLUDE,
        table_end_row,
        SO_COL_NOTES,
        {
            "name": "tbl_subsystem_outputs",
            "columns": column_defs,
            "data": data_matrix,
            "style": "Table Style Light 11",  # Blue-ish for mixed input/output
        },
    )
    
    # Now write formulas over the data for specific columns
    # plan_id: defaults to ActivePlanId
    # salary_year: defaults to SelectedYear
    # delta_cap/tax/apron: formula for signings/waive, value for trade lanes
    
    for row_idx, (source_label, sheet_name) in enumerate(SUBSYSTEM_ROWS):
        data_row = table_start_row + 1 + row_idx  # +1 for header
        
        # plan_id formula: =ActivePlanId
        worksheet.write_formula(
            data_row, SO_COL_PLAN_ID,
            "=ActivePlanId",
            plan_formats["panel_value"],
        )
        
        # salary_year formula: =SelectedYear
        worksheet.write_formula(
            data_row, SO_COL_SALARY_YEAR,
            "=SelectedYear",
            plan_formats["panel_value"],
        )
        
        # Delta formulas (if available)
        cap_formula, tax_formula, apron_formula = delta_formulas[row_idx]
        if cap_formula:
            worksheet.write_formula(
                data_row, SO_COL_DELTA_CAP, cap_formula, plan_formats["panel_value_money"]
            )
            worksheet.write_formula(
                data_row, SO_COL_DELTA_TAX, tax_formula, plan_formats["panel_value_money"]
            )
            worksheet.write_formula(
                data_row, SO_COL_DELTA_APRON, apron_formula, plan_formats["panel_value_money"]
            )
    
    content_row = table_end_row + 1
    
    # Data validation: include_in_plan
    worksheet.data_validation(
        table_start_row + 1,
        SO_COL_INCLUDE,
        table_end_row,
        SO_COL_INCLUDE,
        {
            "validate": "list",
            "source": ["Yes", "No"],
            "input_title": "Include in Plan?",
            "input_message": "Include this subsystem's deltas in plan calculations?",
        },
    )
    
    content_row += 1
    
    # Notes about trade lane manual entry
    worksheet.write(
        content_row, SO_COL_INCLUDE,
        "Note: Trade Lane deltas must be entered manually (copy from TRADE_MACHINE Journal Output). "
        "Signings and Waive deltas auto-update from their tables.",
        plan_formats["note"],
    )
    content_row += 2
    
    # Summary section: show total included deltas
    worksheet.write(content_row, SO_COL_INCLUDE, "INCLUDED TOTALS", plan_formats["panel_subheader"])
    worksheet.write(content_row, SO_COL_PLAN_ID, "(where include_in_plan='Yes')", plan_formats["label"])
    content_row += 1
    
    # Total Δ Cap (SUMIF include_in_plan="Yes")
    worksheet.write(content_row, SO_COL_INCLUDE, "Δ Cap:", plan_formats["panel_label"])
    worksheet.write_formula(
        content_row, SO_COL_PLAN_ID,
        '=SUMIF(tbl_subsystem_outputs[include_in_plan],"Yes",tbl_subsystem_outputs[delta_cap])',
        plan_formats["panel_value_money"],
    )
    content_row += 1
    
    # Total Δ Tax
    worksheet.write(content_row, SO_COL_INCLUDE, "Δ Tax:", plan_formats["panel_label"])
    worksheet.write_formula(
        content_row, SO_COL_PLAN_ID,
        '=SUMIF(tbl_subsystem_outputs[include_in_plan],"Yes",tbl_subsystem_outputs[delta_tax])',
        plan_formats["panel_value_money"],
    )
    content_row += 1
    
    # Total Δ Apron
    worksheet.write(content_row, SO_COL_INCLUDE, "Δ Apron:", plan_formats["panel_label"])
    worksheet.write_formula(
        content_row, SO_COL_PLAN_ID,
        '=SUMIF(tbl_subsystem_outputs[include_in_plan],"Yes",tbl_subsystem_outputs[delta_apron])',
        plan_formats["panel_value_money"],
    )
    content_row += 2
    
    return content_row


def _write_running_state_panel(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    plan_formats: dict[str, Any],
    panel_start_row: int,
    table_start_row: int,
    table_end_row: int,
    num_data_rows: int,
) -> None:
    """
    Write the running-state panel to the right of the PLAN_JOURNAL table.
    
    The panel includes:
    1. SUMMARY BOX: Total deltas (cap/tax/apron) + action count for ActivePlan + SelectedYear
    2. CUMULATIVE RUNNING TOTALS: Step-by-step running totals aligned with journal rows
    
    **Modern Formula Implementation (Excel 365/2021 required):**
    - Uses LET + FILTER + SUM instead of SUMPRODUCT for totals
    - Uses SCAN for cumulative running totals instead of per-row SUMPRODUCT
    - Leverages PlanRowMask named formula for consistent filtering
    - Handles blank salary_year as "applies to SelectedYear"
    
    Args:
        workbook: The XlsxWriter Workbook
        worksheet: The PLAN_JOURNAL worksheet
        formats: Standard formats dict
        plan_formats: Plan-specific formats dict
        panel_start_row: Row where the panel header starts (same as table header)
        table_start_row: Row where the journal table starts (header row)
        table_end_row: Row where the journal table ends
        num_data_rows: Number of data rows in the journal table
    """
    # Panel header
    worksheet.merge_range(
        panel_start_row, PJ_RUNNING_COL_LABEL,
        panel_start_row, PJ_RUNNING_COL_VALUE,
        "RUNNING STATE (ActivePlan + SelectedYear)",
        plan_formats["panel_header"],
    )
    
    row = panel_start_row + 2  # Skip a row after header
    
    # -------------------------------------------------------------------------
    # SUMMARY BOX: Aggregate totals for ActivePlan + SelectedYear
    # -------------------------------------------------------------------------
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "PLAN SUMMARY", plan_formats["panel_subheader"])
    worksheet.write(row, PJ_RUNNING_COL_VALUE, "", plan_formats["panel_subheader"])
    row += 1
    
    # Active Plan name (read from command bar)
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Active Plan:", plan_formats["panel_label"])
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, "=ActivePlan", plan_formats["panel_value"])
    row += 1
    
    # Selected Year (read from command bar)
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Selected Year:", plan_formats["panel_label"])
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, "=SelectedYear", plan_formats["panel_value"])
    row += 1
    
    row += 1  # Blank row
    
    # -------------------------------------------------------------------------
    # Action Count: LET + SUM + FILTER (modern formula)
    # Matches if: (plan_id = ActivePlanId OR plan_id is blank) AND 
    #             (salary_year = SelectedYear OR salary_year is blank) AND
    #             (enabled = "Yes")
    #
    # Modern approach: Use PlanRowMask LAMBDA for the mask, then SUM the boolean result
    # PlanRowMask already returns 1 for matching rows, so SUM counts them.
    # Wrapped in IFNA to handle empty table gracefully (returns 0).
    # -------------------------------------------------------------------------
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Actions (Enabled):", plan_formats["panel_label"])
    action_count_formula = (
        '=IFNA('
        'SUM(--((('
        'tbl_plan_journal[plan_id]=ActivePlanId)+('
        'tbl_plan_journal[plan_id]=""))*(('
        'tbl_plan_journal[salary_year]=SelectedYear)+('
        'tbl_plan_journal[salary_year]=""))*('
        'tbl_plan_journal[enabled]'
        '="Yes"))),0)'
    )
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, action_count_formula, plan_formats["panel_value"])
    row += 1
    
    row += 1  # Blank row
    
    # -------------------------------------------------------------------------
    # Total Deltas: LET + SUM + FILTER (modern formula)
    #
    # Uses LET to define the mask once, then filters delta columns.
    # SUM(FILTER(delta_col, mask, 0)) is cleaner than SUMPRODUCT.
    # The 0 in FILTER handles empty results (no matching rows).
    # -------------------------------------------------------------------------
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "TOTAL DELTAS", plan_formats["panel_subheader"])
    worksheet.write(row, PJ_RUNNING_COL_VALUE, "", plan_formats["panel_subheader"])
    row += 1
    
    # Delta Cap Total
    # LET defines the mask once, then SUM(FILTER(...)) extracts matching deltas
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Δ Cap Total:", plan_formats["panel_label"])
    delta_cap_formula = (
        '=LET('
        '_xlpm.mask,((('
        'tbl_plan_journal[plan_id]=ActivePlanId)+('
        'tbl_plan_journal[plan_id]=""))*(('
        'tbl_plan_journal[salary_year]=SelectedYear)+('
        'tbl_plan_journal[salary_year]=""))*('
        'tbl_plan_journal[enabled]="Yes")),'
        'SUM(FILTER(tbl_plan_journal[delta_cap],_xlpm.mask,0)))'
    )
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, delta_cap_formula, plan_formats["panel_value_money"])
    row += 1
    
    # Delta Tax Total
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Δ Tax Total:", plan_formats["panel_label"])
    delta_tax_formula = (
        '=LET('
        '_xlpm.mask,((('
        'tbl_plan_journal[plan_id]=ActivePlanId)+('
        'tbl_plan_journal[plan_id]=""))*(('
        'tbl_plan_journal[salary_year]=SelectedYear)+('
        'tbl_plan_journal[salary_year]=""))*('
        'tbl_plan_journal[enabled]="Yes")),'
        'SUM(FILTER(tbl_plan_journal[delta_tax],_xlpm.mask,0)))'
    )
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, delta_tax_formula, plan_formats["panel_value_money"])
    row += 1
    
    # Delta Apron Total
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Δ Apron Total:", plan_formats["panel_label"])
    delta_apron_formula = (
        '=LET('
        '_xlpm.mask,((('
        'tbl_plan_journal[plan_id]=ActivePlanId)+('
        'tbl_plan_journal[plan_id]=""))*(('
        'tbl_plan_journal[salary_year]=SelectedYear)+('
        'tbl_plan_journal[salary_year]=""))*('
        'tbl_plan_journal[enabled]="Yes")),'
        'SUM(FILTER(tbl_plan_journal[delta_apron],_xlpm.mask,0)))'
    )
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, delta_apron_formula, plan_formats["panel_value_money"])
    row += 1
    
    row += 2  # Blank rows before cumulative section
    
    # -------------------------------------------------------------------------
    # CUMULATIVE RUNNING TOTALS BY STEP (using SCAN)
    # -------------------------------------------------------------------------
    # This section shows running cumulative totals aligned with each journal row.
    # Positioned starting at the same row as the journal table header + 1.
    # 
    # Columns: Step | Cumul Cap | Cumul Tax | Cumul Apron
    #
    # **Modern Implementation (Excel 365/2021):**
    # Instead of writing N separate SUMPRODUCT formulas (one per row, each
    # scanning the entire table), we use SCAN to compute running totals once.
    #
    # SCAN builds an array of cumulative sums in a single formula.
    # We filter the delta array by PlanRowMask (with step <= current step),
    # then SCAN accumulates.
    #
    # However, SCAN processes array elements sequentially, so we need to:
    # 1. Create an array of deltas masked by PlanRowMask (0 for non-matching rows)
    # 2. Use SCAN to compute running sums
    #
    # Formula pattern:
    #   =LET(
    #     mask, (((plan_ids=ActivePlanId)+(plan_ids=""))*((years=SelectedYear)+(years=""))*(enabled="Yes")),
    #     deltas, IF(mask, delta_col, 0),
    #     SCAN(0, deltas, LAMBDA(acc, val, acc + val))
    #   )
    #
    # This spills down into the cumulative column, one value per journal row.
    # The SCAN output aligns with the journal table rows.
    # -------------------------------------------------------------------------
    
    cumul_header_row = table_start_row  # Same as journal table header
    cumul_col_step = PJ_CUMULATIVE_COL_START
    cumul_col_cap = cumul_col_step + 1
    cumul_col_tax = cumul_col_step + 2
    cumul_col_apron = cumul_col_step + 3
    
    # Set column widths
    worksheet.set_column(cumul_col_step, cumul_col_step, 6)
    worksheet.set_column(cumul_col_cap, cumul_col_cap, 12)
    worksheet.set_column(cumul_col_tax, cumul_col_tax, 12)
    worksheet.set_column(cumul_col_apron, cumul_col_apron, 12)
    
    # Header row
    worksheet.write(cumul_header_row, cumul_col_step, "Step", plan_formats["panel_subheader"])
    worksheet.write(cumul_header_row, cumul_col_cap, "Cumul Δ Cap", plan_formats["panel_subheader"])
    worksheet.write(cumul_header_row, cumul_col_tax, "Cumul Δ Tax", plan_formats["panel_subheader"])
    worksheet.write(cumul_header_row, cumul_col_apron, "Cumul Δ Apron", plan_formats["panel_subheader"])
    
    # -------------------------------------------------------------------------
    # Cumulative formulas using SCAN (single spilling formula per column)
    # -------------------------------------------------------------------------
    # Write one SCAN formula at the first data row of each column.
    # The formula spills down to fill all rows automatically.
    #
    # Step column: Just reference the journal step column (spills automatically)
    # Cumul columns: Use LET + SCAN to compute running totals
    # -------------------------------------------------------------------------
    
    cumul_first_data_row = cumul_header_row + 1
    
    # Step column: reference the step column from the journal table
    # This spills to match the table size
    step_formula = "=tbl_plan_journal[step]"
    worksheet.write_formula(
        cumul_first_data_row, cumul_col_step,
        step_formula,
        plan_formats["panel_value"],
    )
    
    # Cumulative columns: DISABLED
    # The SCAN + LAMBDA approach caused Excel repair issues.
    # TODO: Implement per-row cumulative sums without LAMBDA if needed.
    # For now, show "-" placeholders in cumulative columns.
    worksheet.write(cumul_first_data_row, cumul_col_cap, "-", plan_formats["panel_value"])
    worksheet.write(cumul_first_data_row, cumul_col_tax, "-", plan_formats["panel_value"])
    worksheet.write(cumul_first_data_row, cumul_col_apron, "-", plan_formats["panel_value"])


# =============================================================================
# Helper: Get Plan Names for Dropdown Validation
# =============================================================================

def get_plan_names_formula() -> str:
    """
    Return an Excel formula that extracts non-blank plan names from tbl_plan_manager.
    
    This can be used for data validation source on the ActivePlan dropdown.
    
    Note: Excel data validation with dynamic formulas is complex.
    For now, we use the simpler approach of referencing the plan_name column directly.
    """
    # Simple approach: reference the entire plan_name column
    # Users will see blank entries but can only select non-blank ones
    return "tbl_plan_manager[plan_name]"


def get_plan_manager_table_ref() -> str:
    """Return the table reference for PLAN_MANAGER plan names."""
    return "tbl_plan_manager[plan_name]"
