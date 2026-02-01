"""
PLAN_MANAGER sheet writer — scenario engine foundation.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .formats import _create_plan_formats
from ..command_bar import (
    write_command_bar_readonly,
    get_content_start_row,
)


# =============================================================================
# Layout Constants
# =============================================================================

# PLAN_MANAGER layout
PM_COL_PLAN_ID = 0
PM_COL_PLAN_NAME = 1
PM_COL_NOTES = 2
PM_COL_CREATED_AT = 3
PM_COL_IS_ACTIVE = 4  # Helper for filtering


def write_plan_manager(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write PLAN_MANAGER sheet with plan definitions table.
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
