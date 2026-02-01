"""
Subsystem sheet writers — scenario input tools that publish to PLAN_JOURNAL.

This module implements v1 layouts for:
1. TRADE_MACHINE — 4 lanes (A-D) for rapid trade iteration
2. SIGNINGS_AND_EXCEPTIONS — signing inputs with exception tracking
3. WAIVE_BUYOUT_STRETCH — dead money modeling inputs
4. ASSETS — exception/TPE + draft pick inventory

Per the blueprint (excel-cap-book-blueprint.md):
- Subsystem sheets are INPUT zones (generate journal entries)
- Each subsystem can "publish" rows into PLAN_JOURNAL
- Inline rule references shown adjacent to inputs

Design notes:
- All sheets include the shared command bar (read-only)
- Input tables use yellow background (input format)
- Formula-driven totals/summaries where possible
- Lane-based layout for TRADE_MACHINE enables side-by-side comparison
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import FMT_MONEY
from .command_bar import (
    write_command_bar_readonly,
    get_content_start_row,
)


# =============================================================================
# Shared Helpers
# =============================================================================


def _create_subsystem_formats(workbook: Workbook) -> dict[str, Any]:
    """Create formats specific to subsystem sheets."""
    formats = {}

    # Section headers
    formats["section_header"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#1E3A5F",  # Dark blue
        "font_color": "#FFFFFF",
        "bottom": 2,
    })

    # Lane headers (for TRADE_MACHINE)
    formats["lane_a"] = workbook.add_format({
        "bold": True,
        "bg_color": "#3B82F6",  # Blue
        "font_color": "#FFFFFF",
        "align": "center",
    })
    formats["lane_b"] = workbook.add_format({
        "bold": True,
        "bg_color": "#8B5CF6",  # Purple
        "font_color": "#FFFFFF",
        "align": "center",
    })
    formats["lane_c"] = workbook.add_format({
        "bold": True,
        "bg_color": "#10B981",  # Green
        "font_color": "#FFFFFF",
        "align": "center",
    })
    formats["lane_d"] = workbook.add_format({
        "bold": True,
        "bg_color": "#F97316",  # Orange
        "font_color": "#FFFFFF",
        "align": "center",
    })

    # Input cell format (editable zone)
    formats["input"] = workbook.add_format({
        "bg_color": "#FFFDE7",  # Light yellow
        "border": 1,
        "border_color": "#FBC02D",  # Amber
        "locked": False,
    })

    formats["input_money"] = workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "num_format": FMT_MONEY,
    })

    formats["input_date"] = workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "num_format": "yyyy-mm-dd",
    })

    formats["input_center"] = workbook.add_format({
        "bg_color": "#FFFDE7",
        "border": 1,
        "border_color": "#FBC02D",
        "locked": False,
        "align": "center",
    })

    # Output/computed cell format (formula-driven, not editable)
    formats["output"] = workbook.add_format({
        "bg_color": "#E3F2FD",  # Light blue
        "border": 1,
        "border_color": "#90CAF9",  # Blue border
        "locked": True,
    })

    formats["output_money"] = workbook.add_format({
        "bg_color": "#E3F2FD",
        "border": 1,
        "border_color": "#90CAF9",
        "locked": True,
        "num_format": FMT_MONEY,
    })

    # Total row format
    formats["total"] = workbook.add_format({
        "bold": True,
        "bg_color": "#E5E7EB",  # gray-200
        "border": 2,
        "num_format": FMT_MONEY,
    })

    # Label format
    formats["label"] = workbook.add_format({
        "font_size": 10,
    })

    formats["label_bold"] = workbook.add_format({
        "bold": True,
        "font_size": 10,
    })

    # Notes/help text
    formats["note"] = workbook.add_format({
        "font_size": 9,
        "font_color": "#6B7280",
        "italic": True,
    })

    # Status indicators
    formats["status_ok"] = workbook.add_format({
        "bold": True,
        "font_color": "#059669",  # green-600
        "align": "center",
    })
    formats["status_fail"] = workbook.add_format({
        "bold": True,
        "font_color": "#DC2626",  # red-600
        "bg_color": "#FEE2E2",  # red-100
        "align": "center",
    })
    formats["status_warn"] = workbook.add_format({
        "bold": True,
        "font_color": "#92400E",  # amber-800
        "bg_color": "#FEF3C7",  # amber-100
        "align": "center",
    })

    return formats


def _protect_sheet(worksheet: Worksheet) -> None:
    """Apply standard sheet protection (allows editing input cells)."""
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })


# =============================================================================
# TRADE_MACHINE Sheet Writer
# =============================================================================

# Trade Machine layout:
# - 4 lanes (A-D) side by side, each ~5 columns wide
# - Each lane: Team selector, Outgoing slots (5), Incoming slots (5), Totals
# - Matching rules reference at bottom

TRADE_LANE_WIDTH = 6  # columns per lane
TRADE_SLOTS_PER_SIDE = 5  # players per side (outgoing/incoming)


def write_trade_machine(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write TRADE_MACHINE sheet with 4 lanes (A-D) for side-by-side trade iteration.

    Per the blueprint:
    - 4 lanes (A/B/C/D), identical layout
    - Inputs: teams, outgoing, incoming, matching mode, year context
    - Outputs: outgoing/incoming totals, legality, max incoming, apron gate flags
    - A lane can be "published" into the Plan Journal

    This v1 implementation provides:
    - Lane headers with color coding
    - Team selection dropdowns (wired to DATA)
    - Player input slots for outgoing/incoming (manual entry for now)
    - Salary input fields (manual entry for now)
    - Subtotals and delta calculations (placeholder formulas)
    - Salary matching reference table
    """
    sub_formats = _create_subsystem_formats(workbook)

    # Sheet title
    worksheet.write(0, 0, "TRADE MACHINE", formats["header"])
    worksheet.write(1, 0, "Lane-based trade iteration — compare up to 4 trades side-by-side")

    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)

    content_row = get_content_start_row()

    # Column widths for the 4 lanes
    for lane_idx in range(4):
        base_col = lane_idx * TRADE_LANE_WIDTH
        worksheet.set_column(base_col, base_col, 18)      # Player name
        worksheet.set_column(base_col + 1, base_col + 1, 12)  # Salary
        worksheet.set_column(base_col + 2, base_col + 2, 8)   # Status/notes
        worksheet.set_column(base_col + 3, base_col + 3, 2)   # Spacer
        # Additional columns for overflow/notes
        worksheet.set_column(base_col + 4, base_col + 5, 10)

    # Lane headers
    lane_names = ["Lane A", "Lane B", "Lane C", "Lane D"]
    lane_formats = [sub_formats["lane_a"], sub_formats["lane_b"],
                    sub_formats["lane_c"], sub_formats["lane_d"]]

    for lane_idx, (lane_name, lane_fmt) in enumerate(zip(lane_names, lane_formats)):
        base_col = lane_idx * TRADE_LANE_WIDTH
        worksheet.merge_range(
            content_row, base_col,
            content_row, base_col + TRADE_LANE_WIDTH - 2,  # Leave spacer
            lane_name,
            lane_fmt,
        )

    content_row += 2

    # Instructions row
    worksheet.write(
        content_row, 0,
        "Enter player names and salaries. Totals calculated automatically. "
        "Use 'Publish to Journal' button to record trade in PLAN_JOURNAL.",
        sub_formats["note"],
    )
    content_row += 2

    # Write each lane
    for lane_idx in range(4):
        base_col = lane_idx * TRADE_LANE_WIDTH
        _write_trade_lane(worksheet, sub_formats, content_row, base_col, lane_idx)

    # Move to after the lanes
    rows_per_lane = 3 + TRADE_SLOTS_PER_SIDE * 2 + 6  # Team + labels + outgoing + incoming + totals
    content_row += rows_per_lane + 2

    # Salary matching reference table
    worksheet.merge_range(
        content_row, 0,
        content_row, 10,
        "SALARY MATCHING REFERENCE (displayed adjacent per blueprint)",
        sub_formats["section_header"],
    )
    content_row += 2

    # Matching tiers table
    matching_tiers = [
        ("Over first apron", "100% + $100K", "No matching requirement"),
        ("$0 – $7.5M outgoing", "Up to 200% + $250K", "175% + $250K incoming allowed"),
        ("$7.5M – $29M outgoing", "Up to 175% + $250K", "125% + $250K incoming allowed"),
        ("$29M+ outgoing", "Up to 125% + $250K", "110% + $100K incoming allowed"),
    ]

    worksheet.write(content_row, 0, "Team Status", sub_formats["label_bold"])
    worksheet.write(content_row, 1, "Outgoing Basis", sub_formats["label_bold"])
    worksheet.write(content_row, 2, "Max Incoming", sub_formats["label_bold"])
    content_row += 1

    for tier_name, outgoing_basis, max_incoming in matching_tiers:
        worksheet.write(content_row, 0, tier_name, sub_formats["label"])
        worksheet.write(content_row, 1, outgoing_basis, sub_formats["label"])
        worksheet.write(content_row, 2, max_incoming, sub_formats["label"])
        content_row += 1

    content_row += 2

    # Apron gate notes
    worksheet.write(content_row, 0, "Apron Gate Notes:", sub_formats["label_bold"])
    content_row += 1
    apron_notes = [
        "• First apron teams cannot aggregate salaries in trades",
        "• First apron teams cannot take back more than 110% + $100K",
        "• Second apron teams have additional restrictions on S&T and cash",
        "• Hard cap triggered by certain sign-and-trade and exception uses",
    ]
    for note in apron_notes:
        worksheet.write(content_row, 0, note, sub_formats["note"])
        content_row += 1

    _protect_sheet(worksheet)


def _write_trade_lane(
    worksheet: Worksheet,
    formats: dict[str, Any],
    start_row: int,
    base_col: int,
    lane_idx: int,
) -> None:
    """Write a single trade lane (A/B/C/D) with input slots and totals."""
    row = start_row

    # Team selector
    worksheet.write(row, base_col, "Team:", formats["label"])
    worksheet.write(row, base_col + 1, "", formats["input"])  # Team input cell
    row += 2

    # Outgoing section
    worksheet.write(row, base_col, "OUTGOING", formats["label_bold"])
    worksheet.write(row, base_col + 1, "Salary", formats["label_bold"])
    row += 1

    outgoing_start_row = row
    for i in range(TRADE_SLOTS_PER_SIDE):
        worksheet.write(row, base_col, "", formats["input"])  # Player name
        worksheet.write(row, base_col + 1, 0, formats["input_money"])  # Salary
        row += 1

    # Outgoing total
    outgoing_end_row = row - 1
    worksheet.write(row, base_col, "Total Out:", formats["label_bold"])
    # SUM formula for outgoing salaries
    from_cell = f"{_col_letter(base_col + 1)}{outgoing_start_row + 1}"
    to_cell = f"{_col_letter(base_col + 1)}{outgoing_end_row + 1}"
    worksheet.write_formula(
        row, base_col + 1,
        f"=SUM({from_cell}:{to_cell})",
        formats["total"],
    )
    row += 2

    # Incoming section
    worksheet.write(row, base_col, "INCOMING", formats["label_bold"])
    worksheet.write(row, base_col + 1, "Salary", formats["label_bold"])
    row += 1

    incoming_start_row = row
    for i in range(TRADE_SLOTS_PER_SIDE):
        worksheet.write(row, base_col, "", formats["input"])  # Player name
        worksheet.write(row, base_col + 1, 0, formats["input_money"])  # Salary
        row += 1

    # Incoming total
    incoming_end_row = row - 1
    worksheet.write(row, base_col, "Total In:", formats["label_bold"])
    from_cell = f"{_col_letter(base_col + 1)}{incoming_start_row + 1}"
    to_cell = f"{_col_letter(base_col + 1)}{incoming_end_row + 1}"
    worksheet.write_formula(
        row, base_col + 1,
        f"=SUM({from_cell}:{to_cell})",
        formats["total"],
    )
    row += 2

    # Delta / Legality summary
    outgoing_total_cell = f"{_col_letter(base_col + 1)}{outgoing_end_row + 2}"
    incoming_total_cell = f"{_col_letter(base_col + 1)}{incoming_end_row + 2}"

    worksheet.write(row, base_col, "Net Delta:", formats["label_bold"])
    worksheet.write_formula(
        row, base_col + 1,
        f"={incoming_total_cell}-{outgoing_total_cell}",
        formats["output_money"],
    )
    row += 1

    worksheet.write(row, base_col, "Status:", formats["label"])
    worksheet.write(row, base_col + 1, "(check manually)", formats["output"])


def _col_letter(col: int) -> str:
    """Convert 0-indexed column number to Excel column letter."""
    import xlsxwriter.utility
    return xlsxwriter.utility.xl_col_to_name(col)


# =============================================================================
# SIGNINGS_AND_EXCEPTIONS Sheet Writer
# =============================================================================

# Signings table columns
SIG_COL_PLAYER = 0
SIG_COL_SIGNING_TYPE = 1
SIG_COL_EXCEPTION = 2
SIG_COL_YEARS = 3
SIG_COL_YEAR1 = 4
SIG_COL_YEAR2 = 5
SIG_COL_YEAR3 = 6
SIG_COL_YEAR4 = 7
SIG_COL_NOTES = 8

SIG_NUM_ROWS = 10  # Number of input slots


def write_signings_and_exceptions(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write SIGNINGS_AND_EXCEPTIONS sheet with signing input table.

    Per the blueprint:
    - Player/slot selection
    - Contract structure (years, amounts)
    - Signing method (cap room / exception / minimum)
    - Per-year deltas output
    - Exception usage remaining
    - Hard-cap trigger flags

    This v1 implementation provides:
    - Signing input table with player, method, years, and amounts
    - Exception inventory reference (filtered from DATA_exceptions_warehouse)
    - Signing method validation dropdown
    - Totals row
    """
    sub_formats = _create_subsystem_formats(workbook)

    # Sheet title
    worksheet.write(0, 0, "SIGNINGS & EXCEPTIONS", formats["header"])
    worksheet.write(1, 0, "Record signings and track exception usage")

    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)

    content_row = get_content_start_row()

    # Column widths
    worksheet.set_column(SIG_COL_PLAYER, SIG_COL_PLAYER, 22)
    worksheet.set_column(SIG_COL_SIGNING_TYPE, SIG_COL_SIGNING_TYPE, 14)
    worksheet.set_column(SIG_COL_EXCEPTION, SIG_COL_EXCEPTION, 18)
    worksheet.set_column(SIG_COL_YEARS, SIG_COL_YEARS, 8)
    worksheet.set_column(SIG_COL_YEAR1, SIG_COL_YEAR4, 12)
    worksheet.set_column(SIG_COL_NOTES, SIG_COL_NOTES, 25)

    # Section header: Signings Input
    worksheet.merge_range(
        content_row, SIG_COL_PLAYER,
        content_row, SIG_COL_NOTES,
        "SIGNINGS INPUT (tbl_signings_input)",
        sub_formats["section_header"],
    )
    content_row += 1

    # Instructions
    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "Enter prospective signings. Use 'Publish to Journal' to record in plan.",
        sub_formats["note"],
    )
    content_row += 2

    # Table columns
    signing_columns = [
        "player_name",
        "signing_type",
        "exception_used",
        "years",
        "year_1_salary",
        "year_2_salary",
        "year_3_salary",
        "year_4_salary",
        "notes",
    ]

    # Empty input rows
    table_start_row = content_row
    initial_data = []
    for _ in range(SIG_NUM_ROWS):
        initial_data.append({col: "" for col in signing_columns})
        # Set numeric defaults for salary columns
        initial_data[-1]["years"] = ""
        initial_data[-1]["year_1_salary"] = 0
        initial_data[-1]["year_2_salary"] = 0
        initial_data[-1]["year_3_salary"] = 0
        initial_data[-1]["year_4_salary"] = 0

    table_end_row = table_start_row + len(initial_data)

    # Build data matrix
    data_matrix = [[row_dict.get(col, "") for col in signing_columns] for row_dict in initial_data]

    # Column definitions with unlocked formats for editing on protected sheet
    column_defs = [
        {"header": "player_name", "format": formats["input"]},
        {"header": "signing_type", "format": formats["input"]},
        {"header": "exception_used", "format": formats["input"]},
        {"header": "years", "format": formats["input_int"]},
        {"header": "year_1_salary", "format": formats["input_money"]},
        {"header": "year_2_salary", "format": formats["input_money"]},
        {"header": "year_3_salary", "format": formats["input_money"]},
        {"header": "year_4_salary", "format": formats["input_money"]},
        {"header": "notes", "format": formats["input"]},
    ]

    worksheet.add_table(
        table_start_row,
        SIG_COL_PLAYER,
        table_end_row,
        SIG_COL_NOTES,
        {
            "name": "tbl_signings_input",
            "columns": column_defs,
            "data": data_matrix,
            "style": "Table Style Light 9",  # Yellow-ish for input
        },
    )

    # Data validation: signing_type
    signing_types = ["Cap Room", "MLE (Full)", "MLE (Taxpayer)", "MLE (Room)", "BAE", "Minimum", "TPE", "Other"]
    worksheet.data_validation(
        table_start_row + 1,
        SIG_COL_SIGNING_TYPE,
        table_end_row,
        SIG_COL_SIGNING_TYPE,
        {
            "validate": "list",
            "source": signing_types,
            "input_title": "Signing Type",
            "input_message": "How is this player being signed?",
        },
    )

    content_row = table_end_row + 3

    # Editable zone note
    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "📝 EDITABLE ZONE: The table above (yellow cells) is unlocked for editing. "
        "Formulas and sheet structure are protected.",
        sub_formats["note"],
    )
    content_row += 2

    # Totals row
    worksheet.write(content_row, SIG_COL_PLAYER, "TOTALS:", sub_formats["label_bold"])
    for year_col in [SIG_COL_YEAR1, SIG_COL_YEAR2, SIG_COL_YEAR3, SIG_COL_YEAR4]:
        col_letter = _col_letter(year_col)
        worksheet.write_formula(
            content_row, year_col,
            f"=SUBTOTAL(109,tbl_signings_input[{signing_columns[year_col]}])",
            sub_formats["total"],
        )
    content_row += 3

    # Exception inventory section
    worksheet.merge_range(
        content_row, SIG_COL_PLAYER,
        content_row, SIG_COL_NOTES,
        "EXCEPTION INVENTORY (from DATA — filtered by SelectedTeam)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "Shows available exceptions for the selected team. TPEs, MLE, BAE, etc.",
        sub_formats["note"],
    )
    content_row += 2

    # Exception reference (placeholder - will be formula-driven)
    exc_headers = ["Exception Type", "Original Amount", "Remaining", "Expiration", "Notes"]
    for i, header in enumerate(exc_headers):
        worksheet.write(content_row, i, header, sub_formats["label_bold"])
    content_row += 1

    # Formula to pull from DATA_exceptions_warehouse filtered by SelectedTeam
    # For v1, we show a note about the data source
    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "Use FILTER on tbl_exceptions_warehouse where team_code=SelectedTeam",
        sub_formats["note"],
    )
    content_row += 1

    # Example formula (commented out for now - will be enabled when wired to data)
    # =FILTER(tbl_exceptions_warehouse, tbl_exceptions_warehouse[team_code]=SelectedTeam)

    content_row += 3

    # Hard-cap trigger notes
    worksheet.write(content_row, SIG_COL_PLAYER, "Hard-Cap Trigger Notes:", sub_formats["label_bold"])
    content_row += 1

    trigger_notes = [
        "• Using the Non-Taxpayer MLE triggers hard cap at first apron",
        "• Sign-and-trade for incoming player triggers hard cap at first apron",
        "• BAE usage triggers hard cap at first apron",
        "• Room MLE does NOT trigger hard cap",
    ]
    for note in trigger_notes:
        worksheet.write(content_row, SIG_COL_PLAYER, note, sub_formats["note"])
        content_row += 1

    _protect_sheet(worksheet)


# =============================================================================
# WAIVE_BUYOUT_STRETCH Sheet Writer
# =============================================================================

# Waive table columns
WV_COL_PLAYER = 0
WV_COL_WAIVE_DATE = 1
WV_COL_REMAINING_GTD = 2
WV_COL_GIVEBACK = 3
WV_COL_NET_OWED = 4
WV_COL_STRETCH = 5
WV_COL_DEAD_Y1 = 6
WV_COL_DEAD_Y2 = 7
WV_COL_DEAD_Y3 = 8
WV_COL_NOTES = 9

WV_NUM_ROWS = 8  # Number of input slots


def write_waive_buyout_stretch(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write WAIVE_BUYOUT_STRETCH sheet with dead money modeling inputs.

    Per the blueprint:
    - Player selection
    - Waive date
    - Give-back amount
    - Stretch toggle
    - Set-off assumptions
    - Cap/tax/apron distribution by year output
    - Immediate savings vs future costs

    This v1 implementation provides:
    - Waive/buyout input table
    - Stretch toggle per row
    - Dead money distribution columns (formula-driven in future)
    - Stretch provision reference
    """
    sub_formats = _create_subsystem_formats(workbook)

    # Sheet title
    worksheet.write(0, 0, "WAIVE / BUYOUT / STRETCH", formats["header"])
    worksheet.write(1, 0, "Model dead money scenarios — waives, buyouts, and stretch provisions")

    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)

    content_row = get_content_start_row()

    # Column widths
    worksheet.set_column(WV_COL_PLAYER, WV_COL_PLAYER, 22)
    worksheet.set_column(WV_COL_WAIVE_DATE, WV_COL_WAIVE_DATE, 12)
    worksheet.set_column(WV_COL_REMAINING_GTD, WV_COL_REMAINING_GTD, 14)
    worksheet.set_column(WV_COL_GIVEBACK, WV_COL_GIVEBACK, 12)
    worksheet.set_column(WV_COL_NET_OWED, WV_COL_NET_OWED, 12)
    worksheet.set_column(WV_COL_STRETCH, WV_COL_STRETCH, 10)
    worksheet.set_column(WV_COL_DEAD_Y1, WV_COL_DEAD_Y3, 12)
    worksheet.set_column(WV_COL_NOTES, WV_COL_NOTES, 20)

    # Section header
    worksheet.merge_range(
        content_row, WV_COL_PLAYER,
        content_row, WV_COL_NOTES,
        "WAIVE/BUYOUT INPUT (tbl_waive_input)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, WV_COL_PLAYER,
        "Enter waive/buyout scenarios. Net Owed = Remaining GTD - Giveback. "
        "Stretch spreads dead money over (2 × years remaining + 1) years.",
        sub_formats["note"],
    )
    content_row += 2

    # Table columns
    waive_columns = [
        "player_name",
        "waive_date",
        "remaining_gtd",
        "giveback",
        "net_owed",
        "stretch",
        "dead_year_1",
        "dead_year_2",
        "dead_year_3",
        "notes",
    ]

    # Empty input rows
    table_start_row = content_row
    initial_data = []
    for _ in range(WV_NUM_ROWS):
        initial_data.append({
            "player_name": "",
            "waive_date": "",
            "remaining_gtd": 0,
            "giveback": 0,
            "net_owed": 0,
            "stretch": "No",
            "dead_year_1": 0,
            "dead_year_2": 0,
            "dead_year_3": 0,
            "notes": "",
        })

    table_end_row = table_start_row + len(initial_data)

    # Build data matrix
    data_matrix = [[row_dict.get(col, "") for col in waive_columns] for row_dict in initial_data]

    # Column definitions with unlocked formats for editing on protected sheet
    column_defs = [
        {"header": "player_name", "format": formats["input"]},
        {"header": "waive_date", "format": formats["input_date"]},
        {"header": "remaining_gtd", "format": formats["input_money"]},
        {"header": "giveback", "format": formats["input_money"]},
        {"header": "net_owed", "format": formats["input_money"]},
        {"header": "stretch", "format": formats["input"]},
        {"header": "dead_year_1", "format": formats["input_money"]},
        {"header": "dead_year_2", "format": formats["input_money"]},
        {"header": "dead_year_3", "format": formats["input_money"]},
        {"header": "notes", "format": formats["input"]},
    ]

    worksheet.add_table(
        table_start_row,
        WV_COL_PLAYER,
        table_end_row,
        WV_COL_NOTES,
        {
            "name": "tbl_waive_input",
            "columns": column_defs,
            "data": data_matrix,
            "style": "Table Style Light 9",
        },
    )

    # Data validation: stretch toggle
    worksheet.data_validation(
        table_start_row + 1,
        WV_COL_STRETCH,
        table_end_row,
        WV_COL_STRETCH,
        {
            "validate": "list",
            "source": ["Yes", "No"],
            "input_title": "Stretch Provision",
            "input_message": "Apply stretch provision to spread dead money?",
        },
    )

    content_row = table_end_row + 3

    # Editable zone note
    worksheet.write(
        content_row, WV_COL_PLAYER,
        "📝 EDITABLE ZONE: The table above (yellow cells) is unlocked for editing. "
        "Formulas and sheet structure are protected.",
        sub_formats["note"],
    )
    content_row += 2

    # Totals row
    worksheet.write(content_row, WV_COL_PLAYER, "TOTALS:", sub_formats["label_bold"])
    for col in [WV_COL_REMAINING_GTD, WV_COL_GIVEBACK, WV_COL_NET_OWED,
                WV_COL_DEAD_Y1, WV_COL_DEAD_Y2, WV_COL_DEAD_Y3]:
        col_name = waive_columns[col]
        worksheet.write_formula(
            content_row, col,
            f"=SUBTOTAL(109,tbl_waive_input[{col_name}])",
            sub_formats["total"],
        )
    content_row += 3

    # Stretch provision reference
    worksheet.write(content_row, WV_COL_PLAYER, "Stretch Provision Rules:", sub_formats["label_bold"])
    content_row += 1

    stretch_notes = [
        "• Stretch spreads remaining guaranteed over (2 × years remaining + 1) seasons",
        "• Example: 2 years remaining → spread over 5 seasons",
        "• Stretch must be elected within specific window after waiver",
        "• Cannot stretch mid-season signings in same season",
        "• Set-off: if player signs elsewhere, new salary may offset dead money",
    ]
    for note in stretch_notes:
        worksheet.write(content_row, WV_COL_PLAYER, note, sub_formats["note"])
        content_row += 1

    content_row += 2

    # Formula notes
    worksheet.write(content_row, WV_COL_PLAYER, "Formula Reference:", sub_formats["label_bold"])
    content_row += 1
    worksheet.write(
        content_row, WV_COL_PLAYER,
        "net_owed = remaining_gtd - giveback; dead_year columns computed based on stretch",
        sub_formats["note"],
    )

    _protect_sheet(worksheet)


# =============================================================================
# ASSETS Sheet Writer
# =============================================================================


def write_assets(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write ASSETS sheet with exception and draft pick inventory.

    Per the blueprint:
    - Exceptions/TPEs: remaining amount, expiration, restrictions, usage in plan
    - Picks: ownership grid + encumbrances; plan usage

    This v2 implementation provides:
    - Exceptions section with live FILTER formulas pulling from tbl_exceptions_warehouse
    - Draft picks section with formula reference to DATA_draft_picks_warehouse
    - Both filtered by SelectedTeam from command bar
    - Money/date formats applied to output cells
    - Explicit "None" empty-state when no exceptions exist
    """
    sub_formats = _create_subsystem_formats(workbook)

    # Sheet title
    worksheet.write(0, 0, "ASSETS", formats["header"])
    worksheet.write(1, 0, "Exception/TPE and draft pick inventory for selected team")

    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)

    content_row = get_content_start_row()

    # Column widths for exceptions display
    worksheet.set_column(0, 0, 10)   # Year
    worksheet.set_column(1, 1, 22)   # Exception Type
    worksheet.set_column(2, 2, 22)   # Player Name (for TPEs)
    worksheet.set_column(3, 3, 16)   # Original Amount
    worksheet.set_column(4, 4, 16)   # Remaining Amount
    worksheet.set_column(5, 5, 14)   # Effective Date
    worksheet.set_column(6, 6, 14)   # Expiration Date
    worksheet.set_column(7, 7, 10)   # Status

    # ==========================================================================
    # EXCEPTIONS SECTION
    # ==========================================================================

    worksheet.merge_range(
        content_row, 0,
        content_row, 7,
        "EXCEPTIONS & TPEs (filtered by SelectedTeam from tbl_exceptions_warehouse)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, 0,
        "Shows tradeable player exceptions (TPEs), MLE, BAE, and other exceptions for the selected team.",
        sub_formats["note"],
    )
    content_row += 2

    # Exception headers (match the FILTER output columns)
    exc_headers = [
        "Year",
        "Exception Type",
        "TPE Player",
        "Original Amount",
        "Remaining Amount",
        "Effective Date",
        "Expiration Date",
        "Status",
    ]
    for i, header in enumerate(exc_headers):
        worksheet.write(content_row, i, header, sub_formats["label_bold"])
    exc_header_row = content_row
    content_row += 1

    # FILTER formula for exceptions
    # Columns selected: salary_year, exception_type_name, trade_exception_player_name,
    #                   original_amount, remaining_amount, effective_date, expiration_date, is_expired
    # Filter: team_code = SelectedTeam
    # Empty result: display "None"
    #
    # The FILTER formula uses IFERROR to handle the case where no rows match
    # (FILTER returns #CALC! when no rows match and no if_empty is provided).
    #
    # Excel FILTER syntax:
    #   =IFERROR(
    #     FILTER(
    #       CHOOSE({1,2,3,4,5,6,7,8},
    #         tbl_exceptions_warehouse[salary_year],
    #         tbl_exceptions_warehouse[exception_type_name],
    #         tbl_exceptions_warehouse[trade_exception_player_name],
    #         tbl_exceptions_warehouse[original_amount],
    #         tbl_exceptions_warehouse[remaining_amount],
    #         tbl_exceptions_warehouse[effective_date],
    #         tbl_exceptions_warehouse[expiration_date],
    #         IF(tbl_exceptions_warehouse[is_expired],"Expired","Active")),
    #       tbl_exceptions_warehouse[team_code]=SelectedTeam
    #     ),
    #     "None"
    #   )
    exc_filter_formula = (
        '=IFERROR('
        'FILTER('
        'CHOOSE({1,2,3,4,5,6,7,8},'
        'tbl_exceptions_warehouse[salary_year],'
        'tbl_exceptions_warehouse[exception_type_name],'
        'tbl_exceptions_warehouse[trade_exception_player_name],'
        'tbl_exceptions_warehouse[original_amount],'
        'tbl_exceptions_warehouse[remaining_amount],'
        'tbl_exceptions_warehouse[effective_date],'
        'tbl_exceptions_warehouse[expiration_date],'
        'IF(tbl_exceptions_warehouse[is_expired],"Expired","Active")),'
        'tbl_exceptions_warehouse[team_code]=SelectedTeam'
        '),'
        '"None")'
    )

    # Write the FILTER formula - it will spill into the cells below/right
    worksheet.write_formula(content_row, 0, exc_filter_formula, sub_formats["output"])

    # Reserve space for spill results (up to 20 exception rows)
    # We don't know how many rows will spill, but we can leave space
    exc_data_start_row = content_row
    content_row += 20  # Reserve 20 rows for exception data

    # Note about dynamic array behavior
    worksheet.write(
        content_row, 0,
        "↑ Dynamic array formula — results spill automatically. 'None' shown if no exceptions for selected team.",
        sub_formats["note"],
    )
    content_row += 2

    # Exception types reference
    worksheet.write(content_row, 0, "Common Exception Types:", sub_formats["label_bold"])
    content_row += 1

    exception_types = [
        ("TPE", "Traded Player Exception — absorb player up to exception amount"),
        ("MLE (Non-Taxpayer)", "Mid-Level Exception for under-tax teams (~$12.9M)"),
        ("MLE (Taxpayer)", "Taxpayer Mid-Level Exception (~$5M)"),
        ("MLE (Room)", "Room Mid-Level Exception for cap-room teams (~$8M)"),
        ("BAE", "Bi-Annual Exception (~$4.7M, available every other year)"),
    ]
    for exc_name, exc_desc in exception_types:
        worksheet.write(content_row, 0, f"• {exc_name}:", sub_formats["label"])
        worksheet.write(content_row, 2, exc_desc, sub_formats["note"])
        content_row += 1

    content_row += 2

    # ==========================================================================
    # DRAFT PICKS SECTION
    # ==========================================================================

    worksheet.merge_range(
        content_row, 0,
        content_row, 5,
        "DRAFT PICKS (filtered by SelectedTeam from tbl_draft_picks_warehouse)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, 0,
        "Shows owned picks and picks owed. Encumbrances noted.",
        sub_formats["note"],
    )
    content_row += 2

    # Draft pick headers
    pick_headers = ["Year", "Round", "Original Owner", "Current Owner", "Protection", "Notes"]
    for i, header in enumerate(pick_headers):
        worksheet.write(content_row, i, header, sub_formats["label_bold"])
    content_row += 1

    # Placeholder for filtered data
    worksheet.write(
        content_row, 0,
        "← Filtered from DATA_draft_picks_warehouse (tbl_draft_picks_warehouse) where team_code=SelectedTeam",
        sub_formats["note"],
    )
    content_row += 1

    worksheet.write(
        content_row, 0,
        '=FILTER(tbl_draft_picks_warehouse, tbl_draft_picks_warehouse[team_code]=SelectedTeam, "None")',
        sub_formats["note"],
    )
    content_row += 3

    # Pick encumbrance notes
    worksheet.write(content_row, 0, "Pick Trading Rules:", sub_formats["label_bold"])
    content_row += 1

    pick_notes = [
        "• Stepien Rule: teams must keep a 1st-round pick in at least every other year",
        "• Pick swaps count as 'conveying' a pick for Stepien purposes",
        "• Protections convert: e.g., 'Top-10 protected' → conveys if outside top 10",
        "• Second-round picks can be traded freely",
    ]
    for note in pick_notes:
        worksheet.write(content_row, 0, note, sub_formats["note"])
        content_row += 1

    _protect_sheet(worksheet)
