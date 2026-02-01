"""
PLAN_JOURNAL sheet writer — ordered action journal for scenario modeling.
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .formats import _create_plan_formats
from ..command_bar import (
    write_command_bar_readonly,
    get_content_start_row,
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
# PLAN_JOURNAL Sheet Writer
# =============================================================================

def write_plan_journal(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write PLAN_JOURNAL sheet with ordered action journal and running-state panel.
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
        "salary_year",
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
    num_empty_rows = 20
    initial_data = []
    for i in range(num_empty_rows):
        initial_data.append({
            "step": i + 1,
            "plan_id": "",
            "enabled": "",
            "salary_year": "",
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
    
    # Column definitions
    column_defs = [
        {"header": "step", "format": formats["input_int"]},
        {"header": "plan_id", "format": formats["input_int"]},
        {"header": "enabled", "format": formats["input"]},
        {"header": "salary_year", "format": formats["input_int"]},
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
            "style": "Table Style Light 9",
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
    
    # Conditional formatting: gray out rows NOT in ActivePlan/SelectedYear
    first_data_row = table_start_row + 2
    gray_out_formula = (
        f'=NOT(AND('
        f'OR($B{first_data_row}=ActivePlanId,$B{first_data_row}=""),'
        f'OR($D{first_data_row}=SelectedYear,$D{first_data_row}="")'
        f'))'
    )
    
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
    
    # RUNNING-STATE PANEL
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
    
    # SUBSYSTEM OUTPUTS TABLE
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
    
    # Sheet protection
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

SO_COL_INCLUDE = 0
SO_COL_PLAN_ID = 1
SO_COL_SALARY_YEAR = 2
SO_COL_DELTA_CAP = 3
SO_COL_DELTA_TAX = 4
SO_COL_DELTA_APRON = 5
SO_COL_SOURCE = 6
SO_COL_NOTES = 7

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
    
    # Warning banner
    warning_format = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "font_color": "#7C2D12",
        "bg_color": "#FED7AA",
        "border": 2,
        "border_color": "#EA580C",
        "text_wrap": True,
    })
    worksheet.merge_range(
        content_row, SO_COL_INCLUDE,
        content_row, SO_COL_NOTES,
        "⚠️ WARNING: Do NOT also copy these deltas into tbl_plan_journal — they are already "
        "included via this table. Doing so will DOUBLE-COUNT the amounts!",
        warning_format,
    )
    worksheet.set_row(content_row, 30)
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
    table_start_row = content_row
    data_matrix = []
    
    for source_label, sheet_name in SUBSYSTEM_ROWS:
        data_matrix.append([
            "No",
            "",
            "",
            0,
            0,
            0,
            source_label,
            "",
        ])
    
    table_end_row = table_start_row + len(data_matrix)
    
    delta_formulas = [
        (None, None, None),  # Lane A
        (None, None, None),  # Lane B
        (None, None, None),  # Lane C
        (None, None, None),  # Lane D
        (
            "=SUBTOTAL(109,tbl_signings_input[delta_cap])",
            "=SUBTOTAL(109,tbl_signings_input[delta_tax])",
            "=SUBTOTAL(109,tbl_signings_input[delta_apron])",
        ),
        (
            "=SUBTOTAL(109,tbl_waive_input[delta_cap])",
            "=SUBTOTAL(109,tbl_waive_input[delta_tax])",
            "=SUBTOTAL(109,tbl_waive_input[delta_apron])",
        ),
    ]
    
    column_defs = [
        {"header": "include_in_plan", "format": formats["input"]},
        {"header": "plan_id", "format": plan_formats["panel_value"]},
        {"header": "salary_year", "format": plan_formats["panel_value"]},
        {"header": "delta_cap", "format": formats["input_money"]},
        {"header": "delta_tax", "format": formats["input_money"]},
        {"header": "delta_apron", "format": formats["input_money"]},
        {"header": "source"},
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
            "style": "Table Style Light 11",
        },
    )
    
    for row_idx, (source_label, sheet_name) in enumerate(SUBSYSTEM_ROWS):
        data_row = table_start_row + 1 + row_idx
        
        worksheet.write_formula(
            data_row, SO_COL_PLAN_ID,
            "=ActivePlanId",
            plan_formats["panel_value"],
        )
        
        worksheet.write_formula(
            data_row, SO_COL_SALARY_YEAR,
            "=SelectedYear",
            plan_formats["panel_value"],
        )
        
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
    
    worksheet.write(
        content_row, SO_COL_INCLUDE,
        "Note: Trade Lane deltas must be entered manually (copy from TRADE_MACHINE Journal Output). "
        "Signings and Waive deltas auto-update from their tables.",
        plan_formats["note"],
    )
    content_row += 2
    
    # Summary section
    worksheet.write(content_row, SO_COL_INCLUDE, "INCLUDED TOTALS", plan_formats["panel_subheader"])
    worksheet.write(content_row, SO_COL_PLAN_ID, "(where include_in_plan='Yes')", plan_formats["label"])
    content_row += 1
    
    worksheet.write(content_row, SO_COL_INCLUDE, "Δ Cap:", plan_formats["panel_label"])
    worksheet.write_formula(
        content_row, SO_COL_PLAN_ID,
        '=SUMIF(tbl_subsystem_outputs[include_in_plan],"Yes",tbl_subsystem_outputs[delta_cap])',
        plan_formats["panel_value_money"],
    )
    content_row += 1
    
    worksheet.write(content_row, SO_COL_INCLUDE, "Δ Tax:", plan_formats["panel_label"])
    worksheet.write_formula(
        content_row, SO_COL_PLAN_ID,
        '=SUMIF(tbl_subsystem_outputs[include_in_plan],"Yes",tbl_subsystem_outputs[delta_tax])',
        plan_formats["panel_value_money"],
    )
    content_row += 1
    
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
    """
    # Panel header
    worksheet.merge_range(
        panel_start_row, PJ_RUNNING_COL_LABEL,
        panel_start_row, PJ_RUNNING_COL_VALUE,
        "RUNNING STATE (ActivePlan + SelectedYear)",
        plan_formats["panel_header"],
    )
    
    row = panel_start_row + 2
    
    # SUMMARY BOX
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "PLAN SUMMARY", plan_formats["panel_subheader"])
    worksheet.write(row, PJ_RUNNING_COL_VALUE, "", plan_formats["panel_subheader"])
    row += 1
    
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Active Plan:", plan_formats["panel_label"])
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, "=ActivePlan", plan_formats["panel_value"])
    row += 1
    
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "Selected Year:", plan_formats["panel_label"])
    worksheet.write_formula(row, PJ_RUNNING_COL_VALUE, "=SelectedYear", plan_formats["panel_value"])
    row += 1
    
    row += 1
    
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
    
    row += 1
    
    worksheet.write(row, PJ_RUNNING_COL_LABEL, "TOTAL DELTAS", plan_formats["panel_subheader"])
    worksheet.write(row, PJ_RUNNING_COL_VALUE, "", plan_formats["panel_subheader"])
    row += 1
    
    # Delta Cap Total
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
    
    row += 2
    
    # CUMULATIVE RUNNING TOTALS
    cumul_header_row = table_start_row
    cumul_col_step = PJ_CUMULATIVE_COL_START
    cumul_col_cap = cumul_col_step + 1
    cumul_col_tax = cumul_col_step + 2
    cumul_col_apron = cumul_col_step + 3
    
    worksheet.set_column(cumul_col_step, cumul_col_step, 6)
    worksheet.set_column(cumul_col_cap, cumul_col_cap, 12)
    worksheet.set_column(cumul_col_tax, cumul_col_tax, 12)
    worksheet.set_column(cumul_col_apron, cumul_col_apron, 12)
    
    worksheet.write(cumul_header_row, cumul_col_step, "Step", plan_formats["panel_subheader"])
    worksheet.write(cumul_header_row, cumul_col_cap, "Cumul Δ Cap", plan_formats["panel_subheader"])
    worksheet.write(cumul_header_row, cumul_col_tax, "Cumul Δ Tax", plan_formats["panel_subheader"])
    worksheet.write(cumul_header_row, cumul_col_apron, "Cumul Δ Apron", plan_formats["panel_subheader"])
    
    cumul_first_data_row = cumul_header_row + 1
    step_formula = "=tbl_plan_journal[step]"
    worksheet.write_formula(
        cumul_first_data_row, cumul_col_step,
        step_formula,
        plan_formats["panel_value"],
    )
    
    worksheet.write(cumul_first_data_row, cumul_col_cap, "-", plan_formats["panel_value"])
    worksheet.write(cumul_first_data_row, cumul_col_tax, "-", plan_formats["panel_value"])
    worksheet.write(cumul_first_data_row, cumul_col_apron, "-", plan_formats["panel_value"])


def get_plan_names_formula() -> str:
    """
    Return an Excel formula that extracts non-blank plan names from tbl_plan_manager.
    """
    return "tbl_plan_manager[plan_name]"


def get_plan_manager_table_ref() -> str:
    """Return the table reference for PLAN_MANAGER plan names."""
    return "tbl_plan_manager[plan_name]"
