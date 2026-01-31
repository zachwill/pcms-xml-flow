"""
Shared Command Bar — repeated across all UI sheets.

Per the blueprint (excel-cap-book-blueprint.md), the command bar is the
workbook's "operating context" and MUST be consistent across all sheets:
- Same cells, same named ranges
- Team / Year / As-of / Mode selectors
- Plan selectors (ActivePlan, ComparePlanA/B/C/D)
- Policy toggles (roster fill, two-way counting, etc.)

Design rule: no hidden selectors. No context scattered across the workbook.

The command bar renders in two flavors:
1. EDITABLE (on TEAM_COCKPIT) - actual input cells with validation
2. READ-ONLY (on all other UI sheets) - formula references to TEAM_COCKPIT cells

Named ranges (workbook-scoped, defined once on TEAM_COCKPIT):
- Context: SelectedTeam, SelectedYear, AsOfDate, SelectedMode
- Plans: ActivePlan, ComparePlanA, ComparePlanB, ComparePlanC, ComparePlanD
- Policy toggles: RosterFillTarget, RosterFillType, CountTwoWayInRoster,
                  CountTwoWayInTotals, ShowExistsOnlyRows
- META (convenience): MetaValidationStatus, MetaRefreshedAt, MetaBaseYear,
                      MetaAsOfDate, MetaDataContractVersion
"""

from __future__ import annotations

from datetime import date
from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import define_named_cell


# =============================================================================
# Layout Constants
# =============================================================================

# Command bar occupies rows 3-8 (0-indexed), with a header row at 2
COMMAND_BAR_HEADER_ROW = 2
COMMAND_BAR_START_ROW = 3

# Column layout for command bar
COL_LABEL_1 = 0       # First label column
COL_INPUT_1 = 1       # First input column
COL_LABEL_2 = 2       # Second label column (policy toggles)
COL_INPUT_2 = 3       # Second input column
COL_LABEL_3 = 4       # Third label column (plan selectors)
COL_INPUT_3 = 5       # Third input column

# Row assignments (0-indexed)
# Group 1: Context selectors (cols 0-1)
ROW_TEAM = 3
ROW_YEAR = 4
ROW_AS_OF = 5
ROW_MODE = 6

# Group 2: Policy toggles (cols 2-3)
ROW_ROSTER_FILL_TARGET = 3
ROW_ROSTER_FILL_TYPE = 4
ROW_COUNT_2WAY_ROSTER = 5
ROW_COUNT_2WAY_TOTALS = 6
ROW_SHOW_EXISTS_ONLY = 7

# Group 3: Plan selectors (cols 4-5)
ROW_ACTIVE_PLAN = 3
ROW_COMPARE_A = 4
ROW_COMPARE_B = 5
ROW_COMPARE_C = 6
ROW_COMPARE_D = 7

# The command bar ends at row 8 (0-indexed) - leaves row 8 blank for visual separation
COMMAND_BAR_END_ROW = 8

# COCKPIT sheet name (canonical source of command bar inputs)
COCKPIT_SHEET_NAME = "TEAM_COCKPIT"


# =============================================================================
# Default Values
# =============================================================================

DEFAULT_MODE = "Cap"

# NOTE: Fill rows are not implemented yet. Default to OFF (0) so the workbook
# does not imply that generated assumptions are active.
DEFAULT_ROSTER_FILL_TARGET = 0  # 0 = off
DEFAULT_ROSTER_FILL_TYPE = "Vet Min"
DEFAULT_COUNT_2WAY_ROSTER = False
DEFAULT_COUNT_2WAY_TOTALS = False
DEFAULT_SHOW_EXISTS_ONLY = False
DEFAULT_ACTIVE_PLAN = "Baseline"


# =============================================================================
# Named Range Definitions
# =============================================================================

# All named ranges are defined on TEAM_COCKPIT and referenced globally
NAMED_RANGES = {
    # Context selectors
    "SelectedTeam": (ROW_TEAM, COL_INPUT_1),
    "SelectedYear": (ROW_YEAR, COL_INPUT_1),
    "AsOfDate": (ROW_AS_OF, COL_INPUT_1),
    "SelectedMode": (ROW_MODE, COL_INPUT_1),
    # Policy toggles
    "RosterFillTarget": (ROW_ROSTER_FILL_TARGET, COL_INPUT_2),
    "RosterFillType": (ROW_ROSTER_FILL_TYPE, COL_INPUT_2),
    "CountTwoWayInRoster": (ROW_COUNT_2WAY_ROSTER, COL_INPUT_2),
    "CountTwoWayInTotals": (ROW_COUNT_2WAY_TOTALS, COL_INPUT_2),
    "ShowExistsOnlyRows": (ROW_SHOW_EXISTS_ONLY, COL_INPUT_2),
    # Plan selectors
    "ActivePlan": (ROW_ACTIVE_PLAN, COL_INPUT_3),
    "ComparePlanA": (ROW_COMPARE_A, COL_INPUT_3),
    "ComparePlanB": (ROW_COMPARE_B, COL_INPUT_3),
    "ComparePlanC": (ROW_COMPARE_C, COL_INPUT_3),
    "ComparePlanD": (ROW_COMPARE_D, COL_INPUT_3),
}

# Formula-based named ranges (defined as formulas, not cell references)
# These derive values from other tables/ranges
FORMULA_NAMED_RANGES = {
    # ActivePlanId: looks up plan_id from tbl_plan_manager where plan_name = ActivePlan
    # Returns #N/A if ActivePlan is not found or blank; use IFERROR in consuming formulas
    "ActivePlanId": (
        '=IFERROR(INDEX(tbl_plan_manager[plan_id],'
        'MATCH(ActivePlan,tbl_plan_manager[plan_name],0)),"")'
    ),
}


def get_command_bar_height() -> int:
    """Return the number of rows the command bar occupies (for layout purposes)."""
    return COMMAND_BAR_END_ROW + 1  # 0-indexed, so +1


def get_content_start_row() -> int:
    """Return the first row after the command bar where content should start."""
    return COMMAND_BAR_END_ROW + 2  # Leave a blank row for visual separation


# =============================================================================
# Input Format Helpers
# =============================================================================

def create_input_format(workbook: Workbook) -> Any:
    """Create the input cell format (visually distinct, editable zone)."""
    return workbook.add_format({
        "bg_color": "#FFFDE7",  # Light yellow background
        "border": 1,
        "border_color": "#FBC02D",  # Amber border
        "locked": False,  # Unlocked for editing when sheet is protected
    })


def create_input_format_date(workbook: Workbook) -> Any:
    """Create the input cell format for dates."""
    return workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "num_format": "yyyy-mm-dd",
    })


def create_input_format_bool(workbook: Workbook) -> Any:
    """Create the input cell format for boolean toggles."""
    return workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "align": "center",
    })


def create_readonly_format(workbook: Workbook) -> Any:
    """Create the readonly reference cell format (shows values from TEAM_COCKPIT)."""
    return workbook.add_format({
        "bg_color": "#E3F2FD",  # Light blue background
        "border": 1,
        "border_color": "#90CAF9",  # Blue border
        "italic": True,
        "locked": True,
    })


def create_readonly_format_date(workbook: Workbook) -> Any:
    """Create the readonly reference cell format for dates."""
    return workbook.add_format({
        "bg_color": "#E3F2FD",
        "border": 1,
        "border_color": "#90CAF9",
        "italic": True,
        "locked": True,
        "num_format": "yyyy-mm-dd",
    })


# =============================================================================
# Editable Command Bar (TEAM_COCKPIT only)
# =============================================================================

def write_command_bar_editable(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    build_meta: dict[str, Any],
    *,
    team_codes: list[str] | None = None,
    plan_names: list[str] | None = None,  # Deprecated: now sourced from tbl_plan_manager
) -> None:
    """
    Write the editable command bar on TEAM_COCKPIT.
    
    This is the canonical source for all command bar inputs.
    Other sheets reference these cells via named ranges.
    
    Args:
        workbook: The XlsxWriter Workbook (for define_name and formats)
        worksheet: The TEAM_COCKPIT worksheet
        formats: Standard format dict from create_standard_formats
        build_meta: Build metadata (base_year, as_of_date, etc.)
        team_codes: Optional list of team codes for validation dropdown
        plan_names: DEPRECATED - now dynamically sourced from tbl_plan_manager[plan_name]
    """
    # Create input formats
    input_fmt = create_input_format(workbook)
    input_date_fmt = create_input_format_date(workbook)
    input_bool_fmt = create_input_format_bool(workbook)
    label_fmt = workbook.add_format({"bold": False})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    
    # Column widths
    worksheet.set_column(COL_LABEL_1, COL_LABEL_1, 14)
    worksheet.set_column(COL_INPUT_1, COL_INPUT_1, 14)
    worksheet.set_column(COL_LABEL_2, COL_LABEL_2, 18)
    worksheet.set_column(COL_INPUT_2, COL_INPUT_2, 12)
    worksheet.set_column(COL_LABEL_3, COL_LABEL_3, 14)
    worksheet.set_column(COL_INPUT_3, COL_INPUT_3, 14)
    
    # Command bar header
    worksheet.write(COMMAND_BAR_HEADER_ROW, COL_LABEL_1, "COMMAND BAR", formats["header"])
    worksheet.merge_range(
        COMMAND_BAR_HEADER_ROW, COL_LABEL_1,
        COMMAND_BAR_HEADER_ROW, COL_INPUT_3,
        "COMMAND BAR",
        formats["header"],
    )
    
    # Section sub-headers
    worksheet.write(COMMAND_BAR_START_ROW - 1, COL_LABEL_1, "Context", section_header_fmt)
    worksheet.write(COMMAND_BAR_START_ROW - 1, COL_LABEL_2, "Policy Toggles", section_header_fmt)
    worksheet.write(COMMAND_BAR_START_ROW - 1, COL_LABEL_3, "Plan Selection", section_header_fmt)
    
    base_year = build_meta.get("base_year", 2025)
    as_of_str = build_meta.get("as_of_date", "")
    
    # =========================================================================
    # Group 1: Context Selectors (cols 0-1)
    # =========================================================================
    
    # Team
    worksheet.write(ROW_TEAM, COL_LABEL_1, "Team:", label_fmt)
    default_team = team_codes[0] if team_codes else "LAL"
    worksheet.write(ROW_TEAM, COL_INPUT_1, default_team, input_fmt)
    
    if team_codes:
        worksheet.data_validation(
            ROW_TEAM, COL_INPUT_1, ROW_TEAM, COL_INPUT_1,
            {
                "validate": "list",
                "source": team_codes,
                "input_title": "Select Team",
                "input_message": "Choose a team from the dropdown",
                "error_title": "Invalid Team",
                "error_message": "Please select a valid team code",
            },
        )
    
    # Year
    worksheet.write(ROW_YEAR, COL_LABEL_1, "Year:", label_fmt)
    worksheet.write(ROW_YEAR, COL_INPUT_1, base_year, input_fmt)
    
    year_list = [base_year + i for i in range(6)]
    worksheet.data_validation(
        ROW_YEAR, COL_INPUT_1, ROW_YEAR, COL_INPUT_1,
        {
            "validate": "list",
            "source": year_list,
            "input_title": "Select Year",
            "input_message": "Choose a salary year",
        },
    )
    
    # As-Of Date
    worksheet.write(ROW_AS_OF, COL_LABEL_1, "As-Of:", label_fmt)
    if as_of_str:
        try:
            as_of_date = date.fromisoformat(as_of_str)
            worksheet.write_datetime(ROW_AS_OF, COL_INPUT_1, as_of_date, input_date_fmt)
        except ValueError:
            worksheet.write(ROW_AS_OF, COL_INPUT_1, as_of_str, input_fmt)
    else:
        worksheet.write(ROW_AS_OF, COL_INPUT_1, "", input_fmt)
    
    # Mode
    worksheet.write(ROW_MODE, COL_LABEL_1, "Mode:", label_fmt)
    worksheet.write(ROW_MODE, COL_INPUT_1, DEFAULT_MODE, input_fmt)
    
    worksheet.data_validation(
        ROW_MODE, COL_INPUT_1, ROW_MODE, COL_INPUT_1,
        {
            "validate": "list",
            "source": ["Cap", "Tax", "Apron"],
            "input_title": "Select Mode",
            "input_message": "Choose display mode",
        },
    )
    
    # =========================================================================
    # Group 2: Policy Toggles (cols 2-3)
    # =========================================================================
    
    # Roster Fill Target
    worksheet.write(ROW_ROSTER_FILL_TARGET, COL_LABEL_2, "Roster Fill Target (0=off):", label_fmt)
    worksheet.write(ROW_ROSTER_FILL_TARGET, COL_INPUT_2, DEFAULT_ROSTER_FILL_TARGET, input_fmt)
    
    worksheet.data_validation(
        ROW_ROSTER_FILL_TARGET, COL_INPUT_2, ROW_ROSTER_FILL_TARGET, COL_INPUT_2,
        {
            "validate": "list",
            "source": [0, 12, 14, 15],
            "input_title": "Roster Fill Target",
            "input_message": "0 = off; otherwise target roster size for fill rows",
        },
    )
    
    # Roster Fill Type
    worksheet.write(ROW_ROSTER_FILL_TYPE, COL_LABEL_2, "Roster Fill Type:", label_fmt)
    worksheet.write(ROW_ROSTER_FILL_TYPE, COL_INPUT_2, DEFAULT_ROSTER_FILL_TYPE, input_fmt)
    
    worksheet.data_validation(
        ROW_ROSTER_FILL_TYPE, COL_INPUT_2, ROW_ROSTER_FILL_TYPE, COL_INPUT_2,
        {
            "validate": "list",
            "source": ["Rookie Min", "Vet Min", "Cheapest"],
            "input_title": "Roster Fill Type",
            "input_message": "Type of minimum for fill rows",
        },
    )
    
    # Count Two-Way in Roster
    worksheet.write(ROW_COUNT_2WAY_ROSTER, COL_LABEL_2, "2-Way in Roster?:", label_fmt)
    worksheet.write(ROW_COUNT_2WAY_ROSTER, COL_INPUT_2, "No", input_bool_fmt)
    
    worksheet.data_validation(
        ROW_COUNT_2WAY_ROSTER, COL_INPUT_2, ROW_COUNT_2WAY_ROSTER, COL_INPUT_2,
        {
            "validate": "list",
            "source": ["Yes", "No"],
            "input_title": "Count Two-Way in Roster",
            "input_message": "Include two-way contracts in roster count?",
        },
    )
    
    # Count Two-Way in Totals
    worksheet.write(ROW_COUNT_2WAY_TOTALS, COL_LABEL_2, "2-Way in Totals?:", label_fmt)
    worksheet.write(ROW_COUNT_2WAY_TOTALS, COL_INPUT_2, "No", input_bool_fmt)
    
    worksheet.data_validation(
        ROW_COUNT_2WAY_TOTALS, COL_INPUT_2, ROW_COUNT_2WAY_TOTALS, COL_INPUT_2,
        {
            "validate": "list",
            "source": ["Yes", "No"],
            "input_title": "Count Two-Way in Totals",
            "input_message": "Include two-way contracts in cap/tax totals?",
        },
    )
    
    # Show Exists-Only Rows
    worksheet.write(ROW_SHOW_EXISTS_ONLY, COL_LABEL_2, "Show Exists-Only?:", label_fmt)
    worksheet.write(ROW_SHOW_EXISTS_ONLY, COL_INPUT_2, "No", input_bool_fmt)
    
    worksheet.data_validation(
        ROW_SHOW_EXISTS_ONLY, COL_INPUT_2, ROW_SHOW_EXISTS_ONLY, COL_INPUT_2,
        {
            "validate": "list",
            "source": ["Yes", "No"],
            "input_title": "Show Exists-Only Rows",
            "input_message": "Display rows that exist but don't count?",
        },
    )
    
    # =========================================================================
    # Group 3: Plan Selectors (cols 4-5)
    # =========================================================================
    
    # ActivePlan validation is wired to tbl_plan_manager[plan_name]
    # This allows dynamic plan lists based on what users add to PLAN_MANAGER
    # Note: XlsxWriter requires formula source to be a string starting with '='
    
    # Active Plan
    worksheet.write(ROW_ACTIVE_PLAN, COL_LABEL_3, "Active Plan:", label_fmt)
    worksheet.write(ROW_ACTIVE_PLAN, COL_INPUT_3, DEFAULT_ACTIVE_PLAN, input_fmt)
    
    # Use INDIRECT to reference the plan_name column from tbl_plan_manager
    # This creates a dynamic dropdown that updates when plans are added
    worksheet.data_validation(
        ROW_ACTIVE_PLAN, COL_INPUT_3, ROW_ACTIVE_PLAN, COL_INPUT_3,
        {
            "validate": "list",
            "source": "=tbl_plan_manager[plan_name]",
            "input_title": "Active Plan",
            "input_message": "Select a plan from PLAN_MANAGER",
        },
    )
    
    # Compare Plans A-D - also use tbl_plan_manager
    compare_labels = ["Compare A:", "Compare B:", "Compare C:", "Compare D:"]
    compare_rows = [ROW_COMPARE_A, ROW_COMPARE_B, ROW_COMPARE_C, ROW_COMPARE_D]
    
    for row, label in zip(compare_rows, compare_labels):
        worksheet.write(row, COL_LABEL_3, label, label_fmt)
        worksheet.write(row, COL_INPUT_3, "", input_fmt)
        
        worksheet.data_validation(
            row, COL_INPUT_3, row, COL_INPUT_3,
            {
                "validate": "list",
                "source": "=tbl_plan_manager[plan_name]",
                "input_title": label.replace(":", ""),
                "input_message": "Optional: select a plan to compare",
            },
        )
    
    # =========================================================================
    # Define Named Ranges (workbook-scoped)
    # =========================================================================
    
    # Cell-based named ranges (reference specific cells on TEAM_COCKPIT)
    for name, (row, col) in NAMED_RANGES.items():
        define_named_cell(workbook, name, COCKPIT_SHEET_NAME, row, col)
    
    # Formula-based named ranges (computed from other ranges/tables)
    for name, formula in FORMULA_NAMED_RANGES.items():
        workbook.define_name(name, formula)


def define_meta_named_ranges(
    workbook: Workbook,
    meta_sheet_name: str = "META",
) -> dict[str, tuple[int, int]]:
    """
    Define named ranges for META fields.
    
    These are defined on the META sheet and provide global access to
    build metadata (validation status, timestamps, etc.).
    
    IMPORTANT: These positions must match the layout in meta.py:
    - Row 2: validation_status
    - Row 3: refreshed_at
    - Row 4: base_year
    - Row 5: as_of_date
    - Row 6: data_contract_version
    
    Returns a dict of name -> (row, col) for reference.
    """
    # META sheet layout (must match meta.py)
    # Column 1 (B) contains the values; column 0 (A) has labels
    meta_ranges = {
        "MetaValidationStatus": (2, 1),     # Row 3, col B (0-indexed: row 2)
        "MetaRefreshedAt": (3, 1),          # Row 4, col B
        "MetaBaseYear": (4, 1),             # Row 5, col B
        "MetaAsOfDate": (5, 1),             # Row 6, col B
        "MetaDataContractVersion": (6, 1),  # Row 7, col B
    }
    
    for name, (row, col) in meta_ranges.items():
        define_named_cell(workbook, name, meta_sheet_name, row, col)
    
    return meta_ranges


# =============================================================================
# Read-Only Command Bar (all other UI sheets)
# =============================================================================

def write_command_bar_readonly(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write the read-only command bar on a non-cockpit UI sheet.
    
    This displays the same layout as the editable command bar, but all
    input cells contain formula references to the TEAM_COCKPIT cells.
    
    Args:
        workbook: The XlsxWriter Workbook (for formats)
        worksheet: The target UI worksheet
        formats: Standard format dict from create_standard_formats
    """
    # Create readonly format
    readonly_fmt = create_readonly_format(workbook)
    readonly_date_fmt = create_readonly_format_date(workbook)
    label_fmt = workbook.add_format({"bold": False})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    
    # Column widths (same as editable)
    worksheet.set_column(COL_LABEL_1, COL_LABEL_1, 14)
    worksheet.set_column(COL_INPUT_1, COL_INPUT_1, 14)
    worksheet.set_column(COL_LABEL_2, COL_LABEL_2, 18)
    worksheet.set_column(COL_INPUT_2, COL_INPUT_2, 12)
    worksheet.set_column(COL_LABEL_3, COL_LABEL_3, 14)
    worksheet.set_column(COL_INPUT_3, COL_INPUT_3, 14)
    
    # Command bar header
    worksheet.merge_range(
        COMMAND_BAR_HEADER_ROW, COL_LABEL_1,
        COMMAND_BAR_HEADER_ROW, COL_INPUT_3,
        "COMMAND BAR (read-only — edit on TEAM_COCKPIT)",
        formats["header"],
    )
    
    # Section sub-headers
    worksheet.write(COMMAND_BAR_START_ROW - 1, COL_LABEL_1, "Context", section_header_fmt)
    worksheet.write(COMMAND_BAR_START_ROW - 1, COL_LABEL_2, "Policy Toggles", section_header_fmt)
    worksheet.write(COMMAND_BAR_START_ROW - 1, COL_LABEL_3, "Plan Selection", section_header_fmt)
    
    # =========================================================================
    # Group 1: Context Selectors
    # =========================================================================
    
    worksheet.write(ROW_TEAM, COL_LABEL_1, "Team:", label_fmt)
    worksheet.write_formula(ROW_TEAM, COL_INPUT_1, "=SelectedTeam", readonly_fmt)
    
    worksheet.write(ROW_YEAR, COL_LABEL_1, "Year:", label_fmt)
    worksheet.write_formula(ROW_YEAR, COL_INPUT_1, "=SelectedYear", readonly_fmt)
    
    worksheet.write(ROW_AS_OF, COL_LABEL_1, "As-Of:", label_fmt)
    worksheet.write_formula(ROW_AS_OF, COL_INPUT_1, "=AsOfDate", readonly_date_fmt)
    
    worksheet.write(ROW_MODE, COL_LABEL_1, "Mode:", label_fmt)
    worksheet.write_formula(ROW_MODE, COL_INPUT_1, "=SelectedMode", readonly_fmt)
    
    # =========================================================================
    # Group 2: Policy Toggles
    # =========================================================================
    
    worksheet.write(ROW_ROSTER_FILL_TARGET, COL_LABEL_2, "Roster Fill Target:", label_fmt)
    worksheet.write_formula(ROW_ROSTER_FILL_TARGET, COL_INPUT_2, "=RosterFillTarget", readonly_fmt)
    
    worksheet.write(ROW_ROSTER_FILL_TYPE, COL_LABEL_2, "Roster Fill Type:", label_fmt)
    worksheet.write_formula(ROW_ROSTER_FILL_TYPE, COL_INPUT_2, "=RosterFillType", readonly_fmt)
    
    worksheet.write(ROW_COUNT_2WAY_ROSTER, COL_LABEL_2, "2-Way in Roster?:", label_fmt)
    worksheet.write_formula(ROW_COUNT_2WAY_ROSTER, COL_INPUT_2, "=CountTwoWayInRoster", readonly_fmt)
    
    worksheet.write(ROW_COUNT_2WAY_TOTALS, COL_LABEL_2, "2-Way in Totals?:", label_fmt)
    worksheet.write_formula(ROW_COUNT_2WAY_TOTALS, COL_INPUT_2, "=CountTwoWayInTotals", readonly_fmt)
    
    worksheet.write(ROW_SHOW_EXISTS_ONLY, COL_LABEL_2, "Show Exists-Only?:", label_fmt)
    worksheet.write_formula(ROW_SHOW_EXISTS_ONLY, COL_INPUT_2, "=ShowExistsOnlyRows", readonly_fmt)
    
    # =========================================================================
    # Group 3: Plan Selectors
    # =========================================================================
    
    worksheet.write(ROW_ACTIVE_PLAN, COL_LABEL_3, "Active Plan:", label_fmt)
    worksheet.write_formula(ROW_ACTIVE_PLAN, COL_INPUT_3, "=ActivePlan", readonly_fmt)
    
    compare_labels = ["Compare A:", "Compare B:", "Compare C:", "Compare D:"]
    compare_names = ["ComparePlanA", "ComparePlanB", "ComparePlanC", "ComparePlanD"]
    compare_rows = [ROW_COMPARE_A, ROW_COMPARE_B, ROW_COMPARE_C, ROW_COMPARE_D]
    
    for row, label, name in zip(compare_rows, compare_labels, compare_names):
        worksheet.write(row, COL_LABEL_3, label, label_fmt)
        worksheet.write_formula(row, COL_INPUT_3, f"={name}", readonly_fmt)
