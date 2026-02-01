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
# - Each lane: Team selector, Status summary, Outgoing slots (5), Incoming slots (5), Totals
# - Matching rules reference at bottom

TRADE_LANE_WIDTH = 6  # columns per lane
TRADE_SLOTS_PER_SIDE = 5  # players per side (outgoing/incoming)

# Lane identifiers (A, B, C, D) used for named ranges
LANE_IDS = ["A", "B", "C", "D"]


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

    This v2 implementation provides (per backlog #15):
    - Lane headers with color coding
    - Team selection dropdowns validated from tbl_team_salary_warehouse[team_code]
    - **Lane status summary** showing cap/tax/apron totals + room for SelectedYear
    - **Apron level / taxpayer status** from warehouse
    - Player input slots for outgoing/incoming (manual entry for now)
    - Salary input fields (manual entry for now)
    - Subtotals and delta calculations
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
        worksheet.set_column(base_col, base_col, 18)      # Player name / labels
        worksheet.set_column(base_col + 1, base_col + 1, 14)  # Salary / values
        worksheet.set_column(base_col + 2, base_col + 2, 14)  # Status/room values
        worksheet.set_column(base_col + 3, base_col + 3, 2)   # Spacer
        # Additional columns for overflow/notes
        worksheet.set_column(base_col + 4, base_col + 5, 10)

    # =========================================================================
    # Define named range for team list (unique team codes from warehouse)
    # =========================================================================
    # Formula: =SORT(UNIQUE(tbl_team_salary_warehouse[team_code]))
    # We place this in a helper cell at the bottom of the sheet and reference it.
    # For now, we define a formula-based validation source.
    # =========================================================================

    # Lane headers
    lane_names = ["Lane A", "Lane B", "Lane C", "Lane D"]
    lane_formats_list = [sub_formats["lane_a"], sub_formats["lane_b"],
                         sub_formats["lane_c"], sub_formats["lane_d"]]

    for lane_idx, (lane_name, lane_fmt) in enumerate(zip(lane_names, lane_formats_list)):
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
        "Select team to see status summary. Enter player names and salaries. "
        "Status shows cap position for SelectedYear from tbl_team_salary_warehouse.",
        sub_formats["note"],
    )
    content_row += 2

    # Track team cell references for each lane (needed for status formulas)
    lane_team_cells: list[str] = []

    # Write each lane (first pass: team selectors and status)
    for lane_idx in range(4):
        base_col = lane_idx * TRADE_LANE_WIDTH
        team_cell_ref = _write_trade_lane(
            workbook, worksheet, sub_formats, formats, content_row, base_col, lane_idx
        )
        lane_team_cells.append(team_cell_ref)

    # Calculate rows used by lane content (status summary + outgoing + incoming + matching + journal)
    # Status summary: 10 rows (Team, blank, Status header, 8 status lines, blank)
    # Outgoing: 1 header + 5 slots + 1 total + 1 blank = 8 rows
    # Incoming: 1 header + 5 slots + 1 total + 1 blank = 8 rows
    # Matching summary: 5 rows (Net delta, Max Incoming, Legal?, Matching Rule, Note)
    # Journal output: 7 rows (header, Δ Cap, Δ Tax, Δ Apron, Source, publish note, blank)
    rows_per_lane = 10 + 8 + 8 + 5 + 7 + 2  # plus spacing
    content_row += rows_per_lane + 2

    # Salary matching reference table
    worksheet.merge_range(
        content_row, 0,
        content_row, 10,
        "SALARY MATCHING REFERENCE (displayed adjacent per blueprint)",
        sub_formats["section_header"],
    )
    content_row += 2

    # Matching tiers table (updated to reflect current CBA formulas)
    # The tier breakpoints are derived from TPE_dollar_allowance dynamically:
    # Low/Mid break: TPE - $250K (~$8M for 2025)
    # Mid/High break: 4 × (TPE - $250K) (~$33M for 2025)
    matching_tiers = [
        ("Below Tax (Expanded)", "Outgoing < ~$8M", "200% + $250K"),
        ("Below Tax (Expanded)", "Outgoing ~$8M-$33M", "100% + TPE allowance"),
        ("Below Tax (Expanded)", "Outgoing > ~$33M", "125% + $250K"),
        ("First Apron or above", "Any outgoing", "100% + $100K"),
    ]

    worksheet.write(content_row, 0, "Team Status", sub_formats["label_bold"])
    worksheet.write(content_row, 1, "Outgoing Range", sub_formats["label_bold"])
    worksheet.write(content_row, 2, "Max Incoming Formula", sub_formats["label_bold"])
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

    content_row += 2

    # =========================================================================
    # JOURNAL PUBLISH INSTRUCTIONS
    # =========================================================================
    # Detailed instructions for copying lane journal output to PLAN_JOURNAL
    # =========================================================================

    worksheet.write(content_row, 0, "How to publish Trade to PLAN_JOURNAL:", sub_formats["label_bold"])
    content_row += 1

    publish_steps = [
        "1. Go to PLAN_JOURNAL sheet",
        "2. Add a new row with action_type = 'Trade'",
        "3. Set plan_id, enabled, salary_year, target_player as needed",
        "4. Copy the Δ Cap/Tax/Apron values from the lane's JOURNAL OUTPUT into delta_cap/delta_tax/delta_apron",
        "5. Set source = 'Trade Lane A' (or B/C/D as appropriate)",
        "Note: For multi-team trades, add one PLAN_JOURNAL row per team involved",
    ]
    for step in publish_steps:
        worksheet.write(content_row, 0, step, sub_formats["note"])
        content_row += 1

    content_row += 3

    # =========================================================================
    # Team List Helper (for dropdown validation)
    # =========================================================================
    # Place a helper formula that creates a unique sorted list of team codes.
    # This is used by the data validation for team dropdowns.
    # =========================================================================

    worksheet.write(content_row, 0, "TEAM LIST HELPER (for dropdown validation):", sub_formats["label_bold"])
    content_row += 1

    helper_row = content_row
    helper_col = 0

    # Formula to get unique sorted team codes for SelectedYear
    team_list_formula = (
        '=IFERROR('
        'SORT(UNIQUE('
        'FILTER(tbl_team_salary_warehouse[team_code],'
        'tbl_team_salary_warehouse[salary_year]=SelectedYear)'
        ')),'
        '"(no teams)")'
    )

    worksheet.write_formula(helper_row, helper_col, team_list_formula, sub_formats["output"])

    # Define named range for the team list within a fixed range (avoid spill operator).
    from xlsxwriter.utility import xl_col_to_name
    helper_col_letter = xl_col_to_name(helper_col)
    team_list_max_rows = 32
    helper_end_row = helper_row + team_list_max_rows - 1
    helper_range_ref = (
        f"${helper_col_letter}${helper_row + 1}:${helper_col_letter}${helper_end_row + 1}"
    )  # Excel 1-indexed

    workbook.define_name(
        "TradeTeamList",
        f"='TRADE_MACHINE'!{helper_range_ref}"
    )

    # Reserve space for spill (up to 32 teams)
    content_row += team_list_max_rows

    worksheet.write(
        content_row, 0,
        "↑ Dynamic array — team list for dropdown validation. Shows teams with data for SelectedYear.",
        sub_formats["note"],
    )

    _protect_sheet(worksheet)


def _write_trade_lane(
    workbook: Workbook,
    worksheet: Worksheet,
    sub_formats: dict[str, Any],
    formats: dict[str, Any],
    start_row: int,
    base_col: int,
    lane_idx: int,
) -> str:
    """
    Write a single trade lane (A/B/C/D) with team selector, status summary, and trade slots.

    This v4 implementation (per backlog #17) adds:
    - Journal Output block with net deltas (Δ Cap/Tax/Apron)
    - Source label for PLAN_JOURNAL (e.g., "Trade Lane A")
    - Brief publish instructions per lane

    Previous features (v3, backlog #16):
    - Max Incoming calculation using salary matching rules
    - Legal? check comparing Incoming Total vs Max Incoming
    - Matching Rule note explaining which tier applies

    Matching rule tiers (for below-apron teams using "expanded" mode):
    - Low tier: outgoing < (TPE_allowance - $250K) → max = 200% + $250K
    - Mid tier: outgoing between breakpoints → max = 100% + TPE_allowance
    - High tier: outgoing > 4 × (TPE_allowance - $250K) → max = 125% + $250K
    - Result: GREATEST(LEAST(200%+250K, 100%+TPE), 125%+250K)

    For first apron or above teams: max = 100% + $100K (no aggregation allowed)

    Returns the cell reference for the team selector (e.g., "B15") for use in formulas.
    """
    row = start_row
    lane_id = LANE_IDS[lane_idx]

    # =========================================================================
    # Team Selector (with dropdown validation)
    # =========================================================================
    worksheet.write(row, base_col, "Team:", sub_formats["label_bold"])
    team_cell_row = row
    team_cell_col = base_col + 1
    worksheet.write(row, team_cell_col, "", sub_formats["input"])  # Team input cell

    # Data validation for team dropdown
    # Uses the TradeTeamList named range (defined in main function)
    worksheet.data_validation(
        row, team_cell_col,
        row, team_cell_col,
        {
            "validate": "list",
            "source": "=TradeTeamList",
            "input_title": "Select Team",
            "input_message": "Choose a team from the list (filtered by SelectedYear).",
            "error_type": "warning",
        },
    )

    # Store cell reference for status formulas
    team_cell_ref = f"{_col_letter(team_cell_col)}{team_cell_row + 1}"  # Excel 1-indexed

    # Define a named range for this lane's team (for formula clarity)
    workbook.define_name(
        f"TradeLane{lane_id}Team",
        f"='TRADE_MACHINE'!${_col_letter(team_cell_col)}${team_cell_row + 1}"
    )

    row += 2

    # =========================================================================
    # Lane Status Summary (from tbl_team_salary_warehouse for SelectedYear)
    # =========================================================================
    # Shows: Cap/Tax/Apron totals, Room values, Taxpayer/Repeater/Apron status
    #
    # Uses SUMIFS/INDEX+MATCH to look up the selected team + SelectedYear
    # from tbl_team_salary_warehouse.
    # =========================================================================

    worksheet.write(row, base_col, "STATUS SUMMARY", sub_formats["label_bold"])
    worksheet.write(row, base_col + 1, "(SelectedYear)", sub_formats["label"])
    row += 1

    # Helper: create SUMIFS formula for a column from tbl_team_salary_warehouse
    def make_warehouse_lookup(column_name: str) -> str:
        """Create SUMIFS formula to look up a value from warehouse for team + year."""
        return (
            f'=IFERROR(SUMIFS(tbl_team_salary_warehouse[{column_name}],'
            f'tbl_team_salary_warehouse[team_code],{team_cell_ref},'
            f'tbl_team_salary_warehouse[salary_year],SelectedYear),"")'
        )

    # Cap Total
    worksheet.write(row, base_col, "Cap Total:", sub_formats["label"])
    worksheet.write_formula(row, base_col + 1, make_warehouse_lookup("cap_total"), sub_formats["output_money"])
    row += 1

    # Tax Total
    worksheet.write(row, base_col, "Tax Total:", sub_formats["label"])
    worksheet.write_formula(row, base_col + 1, make_warehouse_lookup("tax_total"), sub_formats["output_money"])
    row += 1

    # Apron Total
    worksheet.write(row, base_col, "Apron Total:", sub_formats["label"])
    worksheet.write_formula(row, base_col + 1, make_warehouse_lookup("apron_total"), sub_formats["output_money"])
    row += 1

    # Room under Tax
    worksheet.write(row, base_col, "Room (Tax):", sub_formats["label"])
    worksheet.write_formula(row, base_col + 1, make_warehouse_lookup("room_under_tax"), sub_formats["output_money"])
    row += 1

    # Room under Apron 1
    worksheet.write(row, base_col, "Room (Apron 1):", sub_formats["label"])
    worksheet.write_formula(row, base_col + 1, make_warehouse_lookup("room_under_apron1"), sub_formats["output_money"])
    row += 1

    # Taxpayer status (Yes/No)
    worksheet.write(row, base_col, "Is Taxpayer:", sub_formats["label"])
    taxpayer_formula = (
        f'=IFERROR(IF(SUMIFS(tbl_team_salary_warehouse[is_taxpayer],'
        f'tbl_team_salary_warehouse[team_code],{team_cell_ref},'
        f'tbl_team_salary_warehouse[salary_year],SelectedYear),"Yes","No"),"")'
    )
    worksheet.write_formula(row, base_col + 1, taxpayer_formula, sub_formats["output"])
    row += 1

    # Repeater status (Yes/No)
    worksheet.write(row, base_col, "Repeater:", sub_formats["label"])
    repeater_formula = (
        f'=IFERROR(IF(SUMIFS(tbl_team_salary_warehouse[is_repeater_taxpayer],'
        f'tbl_team_salary_warehouse[team_code],{team_cell_ref},'
        f'tbl_team_salary_warehouse[salary_year],SelectedYear),"Yes","No"),"")'
    )
    worksheet.write_formula(row, base_col + 1, repeater_formula, sub_formats["output"])
    row += 1

    # Apron Level (lookup text value)
    worksheet.write(row, base_col, "Apron Level:", sub_formats["label"])
    # Use INDEX/MATCH for text lookup (apron_level_lk)
    apron_level_formula = (
        f'=IFERROR(INDEX(tbl_team_salary_warehouse[apron_level_lk],'
        f'MATCH(1,(tbl_team_salary_warehouse[team_code]={team_cell_ref})*'
        f'(tbl_team_salary_warehouse[salary_year]=SelectedYear),0)),"")'
    )
    worksheet.write_formula(row, base_col + 1, apron_level_formula, sub_formats["output"])
    # Store apron level cell reference for matching rule formulas
    apron_level_cell = f"{_col_letter(base_col + 1)}{row + 1}"  # Excel 1-indexed
    row += 2

    # =========================================================================
    # Outgoing Section
    # =========================================================================
    worksheet.write(row, base_col, "OUTGOING", sub_formats["label_bold"])
    worksheet.write(row, base_col + 1, "Salary", sub_formats["label_bold"])
    row += 1

    outgoing_start_row = row
    for i in range(TRADE_SLOTS_PER_SIDE):
        worksheet.write(row, base_col, "", sub_formats["input"])  # Player name
        worksheet.write(row, base_col + 1, 0, sub_formats["input_money"])  # Salary
        row += 1

    # Outgoing total
    outgoing_end_row = row - 1
    worksheet.write(row, base_col, "Total Out:", sub_formats["label_bold"])
    # SUM formula for outgoing salaries
    from_cell = f"{_col_letter(base_col + 1)}{outgoing_start_row + 1}"
    to_cell = f"{_col_letter(base_col + 1)}{outgoing_end_row + 1}"
    worksheet.write_formula(
        row, base_col + 1,
        f"=SUM({from_cell}:{to_cell})",
        sub_formats["total"],
    )
    outgoing_total_cell = f"{_col_letter(base_col + 1)}{row + 1}"  # Excel 1-indexed
    row += 2

    # =========================================================================
    # Incoming Section
    # =========================================================================
    worksheet.write(row, base_col, "INCOMING", sub_formats["label_bold"])
    worksheet.write(row, base_col + 1, "Salary", sub_formats["label_bold"])
    row += 1

    incoming_start_row = row
    for i in range(TRADE_SLOTS_PER_SIDE):
        worksheet.write(row, base_col, "", sub_formats["input"])  # Player name
        worksheet.write(row, base_col + 1, 0, sub_formats["input_money"])  # Salary
        row += 1

    # Incoming total
    incoming_end_row = row - 1
    worksheet.write(row, base_col, "Total In:", sub_formats["label_bold"])
    from_cell = f"{_col_letter(base_col + 1)}{incoming_start_row + 1}"
    to_cell = f"{_col_letter(base_col + 1)}{incoming_end_row + 1}"
    worksheet.write_formula(
        row, base_col + 1,
        f"=SUM({from_cell}:{to_cell})",
        sub_formats["total"],
    )
    incoming_total_cell = f"{_col_letter(base_col + 1)}{row + 1}"  # Excel 1-indexed
    row += 2

    # =========================================================================
    # Trade Summary & Matching (Net Delta, Max Incoming, Legal?, Matching Rule)
    # =========================================================================

    # Net Delta
    worksheet.write(row, base_col, "Net Delta:", sub_formats["label_bold"])
    worksheet.write_formula(
        row, base_col + 1,
        f"={incoming_total_cell}-{outgoing_total_cell}",
        sub_formats["output_money"],
    )
    row += 1

    # =========================================================================
    # Max Incoming formula
    # =========================================================================
    # The matching rule depends on the team's apron level:
    #
    # For BELOW_TAX teams (expanded matching):
    #   max = GREATEST(LEAST(outgoing*2+250000, outgoing+TPE_allowance), outgoing*1.25+250000)
    #
    # For FIRST_APRON or above teams:
    #   max = outgoing + 100000 (first apron padding; no aggregation)
    #
    # We look up TPE_allowance from tbl_system_values for SelectedYear.
    # =========================================================================

    # Helper formula to get TPE dollar allowance from system values
    tpe_allowance_lookup = (
        'IFERROR(SUMIFS(tbl_system_values[tpe_dollar_allowance],'
        'tbl_system_values[salary_year],SelectedYear),7500000)'
    )

    # Build max incoming formula with tier logic
    # Uses LET for readability (Excel 365+)
    max_incoming_formula = (
        f'=IFERROR('
        f'LET('
        f'_xlpm.out,{outgoing_total_cell},'
        f'_xlpm.apron,{apron_level_cell},'
        f'_xlpm.tpe,{tpe_allowance_lookup},'
        # Below-tax teams get expanded matching
        f'IF(OR(_xlpm.apron="BELOW_TAX",_xlpm.apron=""),'
        # Expanded matching: GREATEST(LEAST(200%+250K, 100%+TPE), 125%+250K)
        f'MAX(MIN(_xlpm.out*2+250000,_xlpm.out+_xlpm.tpe),_xlpm.out*1.25+250000),'
        # First apron or above: 100% + $100K (no aggregation)
        f'_xlpm.out+100000)'
        f'),'
        f'"")'
    )

    worksheet.write(row, base_col, "Max Incoming:", sub_formats["label_bold"])
    worksheet.write_formula(row, base_col + 1, max_incoming_formula, sub_formats["output_money"])
    max_incoming_cell = f"{_col_letter(base_col + 1)}{row + 1}"
    row += 1

    # =========================================================================
    # Legal? check — is incoming total <= max incoming?
    # =========================================================================
    legal_formula = (
        f'=IF({outgoing_total_cell}=0,"",'
        f'IF({incoming_total_cell}<={max_incoming_cell},"✓ LEGAL","✗ OVER LIMIT"))'
    )

    worksheet.write(row, base_col, "Legal?:", sub_formats["label_bold"])
    worksheet.write_formula(row, base_col + 1, legal_formula, sub_formats["output"])

    # Conditional formatting for legal status (green for legal, red for over limit)
    legal_cell_row = row
    worksheet.conditional_format(
        legal_cell_row, base_col + 1,
        legal_cell_row, base_col + 1,
        {
            "type": "text",
            "criteria": "containing",
            "value": "LEGAL",
            "format": sub_formats["status_ok"],
        },
    )
    worksheet.conditional_format(
        legal_cell_row, base_col + 1,
        legal_cell_row, base_col + 1,
        {
            "type": "text",
            "criteria": "containing",
            "value": "OVER",
            "format": sub_formats["status_fail"],
        },
    )
    row += 1

    # =========================================================================
    # Matching Rule note — explains which tier applies
    # =========================================================================
    # Shows the applicable matching tier based on outgoing salary and apron level
    matching_rule_formula = (
        f'=IF({outgoing_total_cell}=0,"",'
        f'LET('
        f'_xlpm.out,{outgoing_total_cell},'
        f'_xlpm.apron,{apron_level_cell},'
        f'_xlpm.tpe,{tpe_allowance_lookup},'
        # Determine tier based on breakpoints
        f'_xlpm.low_break,_xlpm.tpe-250000,'
        f'_xlpm.high_break,4*(_xlpm.tpe-250000),'
        # Check apron level first
        f'IF(AND(_xlpm.apron<>"BELOW_TAX",_xlpm.apron<>""),'
        f'"Apron: 100%+$100K",'
        # For below-tax teams, check which tier applies
        f'IF(_xlpm.out<_xlpm.low_break,"Low: 200%+$250K",'
        f'IF(_xlpm.out>_xlpm.high_break,"High: 125%+$250K",'
        f'"Mid: 100%+TPE")))))'
    )

    worksheet.write(row, base_col, "Matching Rule:", sub_formats["label"])
    worksheet.write_formula(row, base_col + 1, matching_rule_formula, sub_formats["output"])
    row += 1

    # Note about aggregation restrictions
    worksheet.write(
        row, base_col,
        "Note: Apron teams cannot aggregate players",
        sub_formats["note"],
    )
    row += 2

    # =========================================================================
    # JOURNAL OUTPUT BLOCK (per lane)
    # =========================================================================
    # Provides net delta for SelectedYear + source label for copying into
    # PLAN_JOURNAL.
    #
    # Per backlog task #17:
    # - Net delta (cap/tax/apron) = Total In - Total Out
    # - Source label: "Trade Lane {A|B|C|D}"
    # - Publish instructions
    #
    # Note: For trades, the delta for this team is (incoming - outgoing).
    # Cap/tax/apron deltas are all the same since traded salaries count
    # identically toward all three thresholds.
    # =========================================================================

    worksheet.write(row, base_col, "JOURNAL OUTPUT", sub_formats["label_bold"])
    row += 1

    # Net Delta (same as already computed above, but we re-state for journal)
    # This is the change in salary for this team: incoming - outgoing
    worksheet.write(row, base_col, "Δ Cap:", sub_formats["label"])
    worksheet.write_formula(
        row, base_col + 1,
        f"={incoming_total_cell}-{outgoing_total_cell}",
        sub_formats["output_money"],
    )
    row += 1

    worksheet.write(row, base_col, "Δ Tax:", sub_formats["label"])
    worksheet.write_formula(
        row, base_col + 1,
        f"={incoming_total_cell}-{outgoing_total_cell}",
        sub_formats["output_money"],
    )
    row += 1

    worksheet.write(row, base_col, "Δ Apron:", sub_formats["label"])
    worksheet.write_formula(
        row, base_col + 1,
        f"={incoming_total_cell}-{outgoing_total_cell}",
        sub_formats["output_money"],
    )
    row += 1

    # Source label
    worksheet.write(row, base_col, "Source:", sub_formats["label"])
    worksheet.write(row, base_col + 1, f"Trade Lane {lane_id}", sub_formats["output"])
    row += 1

    # Publish note (brief, since full instructions are after all lanes)
    worksheet.write(
        row, base_col,
        "→ Copy to PLAN_JOURNAL",
        sub_formats["note"],
    )

    return team_cell_ref


def _col_letter(col: int) -> str:
    """Convert 0-indexed column number to Excel column letter."""
    import xlsxwriter.utility
    return xlsxwriter.utility.xl_col_to_name(col)


# =============================================================================
# SIGNINGS_AND_EXCEPTIONS Sheet Writer
# =============================================================================

# Signings table columns
# Input columns (user-editable)
SIG_COL_PLAYER = 0
SIG_COL_SIGNING_TYPE = 1
SIG_COL_EXCEPTION = 2
SIG_COL_YEARS = 3
SIG_COL_YEAR1 = 4
SIG_COL_YEAR2 = 5
SIG_COL_YEAR3 = 6
SIG_COL_YEAR4 = 7
SIG_COL_NOTES = 8
# Computed delta columns (formula-driven, locked)
SIG_COL_DELTA_CAP = 9
SIG_COL_DELTA_TAX = 10
SIG_COL_DELTA_APRON = 11

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

    This v4 implementation provides:
    - Signing input table with player, method, years, and amounts
    - Per-row SelectedYear delta columns (delta_cap, delta_tax, delta_apron)
        - Formulas compute the delta based on which year column matches SelectedYear
        - year_1_salary = MetaBaseYear, year_2 = MetaBaseYear+1, etc.
    - Journal Output block with aggregated deltas + source label
        - For copying into PLAN_JOURNAL
    - Exception inventory with live FILTER formulas from DATA_exceptions_warehouse
    - **NEW**: exception_used dropdown validation helper list
        - Helper spill range creates unique labels from tbl_exceptions_warehouse for SelectedTeam
        - Label format: "exception_type_name ($remaining)" or "TPE: player_name ($remaining)"
        - Data validation wired to reference the helper range
    - Signing method validation dropdown
    - Totals row
    - Money/date formats aligned with RULES_REFERENCE
    """
    sub_formats = _create_subsystem_formats(workbook)

    # Sheet title
    worksheet.write(0, 0, "SIGNINGS & EXCEPTIONS", formats["header"])
    worksheet.write(1, 0, "Record signings and track exception usage — SelectedYear deltas computed automatically")

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
    # Delta columns
    worksheet.set_column(SIG_COL_DELTA_CAP, SIG_COL_DELTA_CAP, 12)
    worksheet.set_column(SIG_COL_DELTA_TAX, SIG_COL_DELTA_TAX, 12)
    worksheet.set_column(SIG_COL_DELTA_APRON, SIG_COL_DELTA_APRON, 12)

    # Section header: Signings Input
    worksheet.merge_range(
        content_row, SIG_COL_PLAYER,
        content_row, SIG_COL_DELTA_APRON,
        "SIGNINGS INPUT (tbl_signings_input) — SelectedYear deltas auto-computed",
        sub_formats["section_header"],
    )
    content_row += 1

    # Instructions
    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "Enter prospective signings. Delta columns show SelectedYear impact. "
        "Copy Journal Output rows into PLAN_JOURNAL to record in plan.",
        sub_formats["note"],
    )
    content_row += 2

    # Table columns (including delta columns)
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
        "delta_cap",
        "delta_tax",
        "delta_apron",
    ]

    # Empty input rows
    table_start_row = content_row
    initial_data = []
    for _ in range(SIG_NUM_ROWS):
        row_data = {col: "" for col in signing_columns}
        # Set numeric defaults for salary columns
        row_data["years"] = ""
        row_data["year_1_salary"] = 0
        row_data["year_2_salary"] = 0
        row_data["year_3_salary"] = 0
        row_data["year_4_salary"] = 0
        # Delta columns will be formula-driven; initialize to 0
        row_data["delta_cap"] = 0
        row_data["delta_tax"] = 0
        row_data["delta_apron"] = 0
        initial_data.append(row_data)

    table_end_row = table_start_row + len(initial_data)

    # Build data matrix
    data_matrix = [[row_dict.get(col, "") for col in signing_columns] for row_dict in initial_data]

    # =========================================================================
    # Delta column formulas:
    # Each delta column picks the salary for the year matching SelectedYear.
    # year_1_salary = MetaBaseYear, year_2 = MetaBaseYear+1, etc.
    #
    # Formula pattern (using INDEX + ModeYearIndex named formula):
    #   =LET(idx, ModeYearIndex,
    #        IF(idx > 4, 0,
    #           IFNA(INDEX([@year_1_salary]:[@year_4_salary], 1, idx), 0)))
    #
    # ModeYearIndex = SelectedYear - MetaBaseYear + 1 (defined in named_formulas.py)
    #
    # NOTE: Avoid LET in table calculated columns - XlsxWriter generates invalid XML
    # Use IFERROR(CHOOSE(...)) instead of LET+INDEX
    #
    # For now, cap/tax/apron deltas are all the same (the salary amount).
    # In future, could adjust if different counting rules apply.
    # =========================================================================
    delta_formula = (
        '=IFERROR(CHOOSE(ModeYearIndex,[@year_1_salary],[@year_2_salary],[@year_3_salary],[@year_4_salary]),0)'
    )

    # Column definitions with unlocked formats for editing on protected sheet
    # Note: delta columns are LOCKED (formula-driven, not user-editable)
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
        {"header": "delta_cap", "format": sub_formats["output_money"], "formula": delta_formula},
        {"header": "delta_tax", "format": sub_formats["output_money"], "formula": delta_formula},
        {"header": "delta_apron", "format": sub_formats["output_money"], "formula": delta_formula},
    ]

    worksheet.add_table(
        table_start_row,
        SIG_COL_PLAYER,
        table_end_row,
        SIG_COL_DELTA_APRON,
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

    # =========================================================================
    # exception_used data validation (per backlog task #13)
    # =========================================================================
    # Uses a formula-based list that pulls from tbl_exceptions_warehouse.
    # The formula creates a dynamic list of exception labels for SelectedTeam.
    #
    # Label format: "exception_type_name ($remaining)" or for TPEs with a
    # player name: "TPE: player_name ($remaining)"
    #
    # Note: XlsxWriter requires formula-based list validation to use a named
    # range or a direct formula. We use a formula that builds labels from the
    # warehouse table. Excel 365 dynamic arrays support this pattern.
    #
    # Formula logic:
    # - Filter tbl_exceptions_warehouse by team_code = SelectedTeam AND NOT is_expired
    # - Concatenate exception_type_name with remaining_amount
    # - Include TPE player name if present
    #
    # The formula is placed in a helper cell (after the inventory section)
    # and referenced via a named range "ExceptionUsedList".
    # =========================================================================
    # Note: data validation formula will be wired after the helper is created below

    content_row = table_end_row + 3

    # Editable zone note
    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "📝 EDITABLE ZONE: Yellow cells are unlocked for editing. "
        "Blue delta columns (Δ Cap/Tax/Apron) are formula-driven based on SelectedYear.",
        sub_formats["note"],
    )
    content_row += 2

    # Totals row (for year salary columns)
    worksheet.write(content_row, SIG_COL_PLAYER, "YEAR TOTALS:", sub_formats["label_bold"])
    for year_col in [SIG_COL_YEAR1, SIG_COL_YEAR2, SIG_COL_YEAR3, SIG_COL_YEAR4]:
        worksheet.write_formula(
            content_row, year_col,
            f"=SUBTOTAL(109,tbl_signings_input[{signing_columns[year_col]}])",
            sub_formats["total"],
        )
    content_row += 3

    # =========================================================================
    # JOURNAL OUTPUT BLOCK
    # =========================================================================
    # Provides aggregated deltas for SelectedYear + source label for copying
    # into PLAN_JOURNAL.
    #
    # Per backlog task #11:
    # - Total delta cap/tax/apron for SelectedYear (sum of delta columns)
    # - Source label: "Signings (SIGNINGS_AND_EXCEPTIONS)"
    # - Instructions for manual copy workflow
    # =========================================================================

    worksheet.merge_range(
        content_row, SIG_COL_PLAYER,
        content_row, SIG_COL_NOTES,
        "JOURNAL OUTPUT (copy into PLAN_JOURNAL to record in plan)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "Total signing deltas for SelectedYear. Copy the values below into a new PLAN_JOURNAL row.",
        sub_formats["note"],
    )
    content_row += 2

    # Journal output: summary row with aggregated deltas
    # Layout: label | value
    journal_label_col = SIG_COL_PLAYER
    journal_value_col = SIG_COL_SIGNING_TYPE

    # SelectedYear context (for reference)
    worksheet.write(content_row, journal_label_col, "Selected Year:", sub_formats["label_bold"])
    worksheet.write_formula(content_row, journal_value_col, "=SelectedYear", sub_formats["output"])
    content_row += 1

    # Signing count (non-blank player_name rows)
    worksheet.write(content_row, journal_label_col, "Signings Count:", sub_formats["label_bold"])
    worksheet.write_formula(
        content_row, journal_value_col,
        '=COUNTA(tbl_signings_input[player_name])',
        sub_formats["output"],
    )
    content_row += 2

    # Total deltas section header
    worksheet.write(content_row, journal_label_col, "TOTAL DELTAS", sub_formats["label_bold"])
    worksheet.write(content_row, journal_value_col, "(for SelectedYear)", sub_formats["label"])
    content_row += 1

    # Delta Cap Total
    worksheet.write(content_row, journal_label_col, "Δ Cap:", sub_formats["label"])
    worksheet.write_formula(
        content_row, journal_value_col,
        "=SUBTOTAL(109,tbl_signings_input[delta_cap])",
        sub_formats["total"],
    )
    content_row += 1

    # Delta Tax Total
    worksheet.write(content_row, journal_label_col, "Δ Tax:", sub_formats["label"])
    worksheet.write_formula(
        content_row, journal_value_col,
        "=SUBTOTAL(109,tbl_signings_input[delta_tax])",
        sub_formats["total"],
    )
    content_row += 1

    # Delta Apron Total
    worksheet.write(content_row, journal_label_col, "Δ Apron:", sub_formats["label"])
    worksheet.write_formula(
        content_row, journal_value_col,
        "=SUBTOTAL(109,tbl_signings_input[delta_apron])",
        sub_formats["total"],
    )
    content_row += 2

    # Source label (for PLAN_JOURNAL source column)
    worksheet.write(content_row, journal_label_col, "Source:", sub_formats["label_bold"])
    worksheet.write(content_row, journal_value_col, "Signings (SIGNINGS_AND_EXCEPTIONS)", sub_formats["output"])
    content_row += 2

    # Manual publish instructions
    worksheet.write(content_row, journal_label_col, "How to publish to PLAN_JOURNAL:", sub_formats["label_bold"])
    content_row += 1

    publish_steps = [
        "1. Go to PLAN_JOURNAL sheet",
        "2. Add a new row with action_type = 'Sign (Exception)' or appropriate type",
        "3. Set plan_id, enabled, salary_year, target_player as needed",
        "4. Copy the Δ Cap/Tax/Apron values above into delta_cap/delta_tax/delta_apron columns",
        "5. Set source = 'Signings (SIGNINGS_AND_EXCEPTIONS)'",
    ]
    for step in publish_steps:
        worksheet.write(content_row, journal_label_col, step, sub_formats["note"])
        content_row += 1

    content_row += 2

    # ==========================================================================
    # EXCEPTION INVENTORY SECTION (live FILTER from tbl_exceptions_warehouse)
    # ==========================================================================
    #
    # Per backlog task #10:
    # - Live exception table filtered by SelectedTeam
    # - (TODO) exception_used validation helper list (currently freeform)
    # - Formats aligned with RULES_REFERENCE (money/date)

    worksheet.merge_range(
        content_row, SIG_COL_PLAYER,
        content_row, SIG_COL_NOTES,
        "EXCEPTION INVENTORY (filtered by SelectedTeam from tbl_exceptions_warehouse)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "Shows available exceptions for the selected team. Use for exception_used validation in signings above.",
        sub_formats["note"],
    )
    content_row += 2

    # Exception column headers (match the FILTER output columns)
    # Columns: salary_year, exception_type_name, trade_exception_player_name,
    #          original_amount, remaining_amount, effective_date, expiration_date, status
    exc_headers = [
        "Year",
        "Exception Type",
        "TPE Player",
        "Original Amt",
        "Remaining Amt",
        "Effective",
        "Expiration",
        "Status",
    ]
    for i, header in enumerate(exc_headers):
        worksheet.write(content_row, i, header, sub_formats["label_bold"])
    exc_header_row = content_row
    content_row += 1

    # FILTER formula for exceptions
    # Filters tbl_exceptions_warehouse by team_code = SelectedTeam
    # Columns selected: salary_year, exception_type_name, trade_exception_player_name,
    #                   original_amount, remaining_amount, effective_date, expiration_date, status
    # Uses IFERROR to handle empty result (displays "None")
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
    # Note: Money and date formatting is applied via conditional formatting or
    # will display raw values (Excel FILTER spill doesn't inherit formatting).
    # For consistent display, we document this limitation.
    worksheet.write_formula(content_row, 0, exc_filter_formula, sub_formats["output"])

    # Reserve space for spill results (up to 15 exception rows)
    exc_data_start_row = content_row
    content_row += 15

    # Note about dynamic array + formatting
    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "↑ Dynamic array — results spill automatically. 'None' shown if no exceptions for team. "
        "Amounts in dollars; dates as yyyy-mm-dd.",
        sub_formats["note"],
    )
    content_row += 2

    # =========================================================================
    # EXCEPTION_USED VALIDATION HELPER (per backlog task #13)
    # =========================================================================
    # Creates a helper spill range with unique exception labels for SelectedTeam.
    # This enables dropdown validation for the exception_used column.
    #
    # Label format:
    # - For TPEs with player name: "TPE: {player_name} (${remaining})"
    # - For other exceptions: "{exception_type_name} (${remaining})"
    #
    # The formula:
    # - Filters tbl_exceptions_warehouse by team_code = SelectedTeam AND NOT is_expired
    # - Concatenates exception_type_name with remaining_amount (formatted)
    # - Uses SORT to order by exception type + remaining descending
    # =========================================================================

    worksheet.merge_range(
        content_row, SIG_COL_PLAYER,
        content_row, SIG_COL_NOTES,
        "EXCEPTION DROPDOWN LIST (helper for exception_used validation)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "Dynamic list of available exceptions for SelectedTeam. Used as dropdown source for exception_used column above.",
        sub_formats["note"],
    )
    content_row += 2

    # Helper list header
    worksheet.write(content_row, SIG_COL_PLAYER, "Available Exceptions:", sub_formats["label_bold"])
    content_row += 1

    # Store the helper cell location for the named range
    helper_row = content_row
    helper_col = SIG_COL_PLAYER

    # The helper formula creates a list of exception labels.
    # Formula logic:
    # 1. FILTER tbl_exceptions_warehouse for SelectedTeam AND NOT is_expired
    # 2. Build label: IF(has TPE player, "TPE: player ($amt)", "type ($amt)")
    # 3. SORT by exception type, then remaining amount DESC
    # 4. IFERROR for empty result
    #
    # Excel formula (uses TEXT for money formatting):
    # =IFERROR(
    #   SORT(
    #     FILTER(
    #       IF(
    #         LEN(tbl_exceptions_warehouse[trade_exception_player_name])>0,
    #         "TPE: "&tbl_exceptions_warehouse[trade_exception_player_name]&" ($"&TEXT(tbl_exceptions_warehouse[remaining_amount],"#,##0")&")",
    #         tbl_exceptions_warehouse[exception_type_name]&" ($"&TEXT(tbl_exceptions_warehouse[remaining_amount],"#,##0")&")"
    #       ),
    #       (tbl_exceptions_warehouse[team_code]=SelectedTeam)*(NOT(tbl_exceptions_warehouse[is_expired]))
    #     ),
    #     1, 1
    #   ),
    #   "(none available)"
    # )
    exception_helper_formula = (
        '=IFERROR('
        'SORT('
        'FILTER('
        'IF('
        'LEN(tbl_exceptions_warehouse[trade_exception_player_name])>0,'
        '"TPE: "&tbl_exceptions_warehouse[trade_exception_player_name]&" ($"&TEXT(tbl_exceptions_warehouse[remaining_amount],"#,##0")&")",'
        'tbl_exceptions_warehouse[exception_type_name]&" ($"&TEXT(tbl_exceptions_warehouse[remaining_amount],"#,##0")&")"'
        '),'
        '(tbl_exceptions_warehouse[team_code]=SelectedTeam)*(NOT(tbl_exceptions_warehouse[is_expired]))'
        '),'
        '1,1'
        '),'
        '"(none available)")'
    )

    worksheet.write_formula(helper_row, helper_col, exception_helper_formula, sub_formats["output"])

    # Reserve space for spill results (up to 15 exceptions per team)
    # The helper will spill downward automatically
    exception_helper_start_row = helper_row
    exception_list_max_rows = 15
    content_row = helper_row + exception_list_max_rows

    worksheet.write(
        content_row, SIG_COL_PLAYER,
        "↑ Dynamic array — available exceptions for dropdown. Shows '(none available)' if no valid exceptions.",
        sub_formats["note"],
    )
    content_row += 2

    # =========================================================================
    # Define named range for the helper and wire data validation
    # =========================================================================
    # We define a named range "ExceptionUsedList" that references the helper
    # range within the reserved block (fixed range to avoid the spill operator).
    #
    # Note: XlsxWriter's define_name requires the formula without leading =
    # =========================================================================
    from xlsxwriter.utility import xl_col_to_name

    helper_col_letter = xl_col_to_name(helper_col)
    helper_end_row = exception_helper_start_row + exception_list_max_rows - 1
    helper_range_ref = (
        f"${helper_col_letter}${exception_helper_start_row + 1}:"
        f"${helper_col_letter}${helper_end_row + 1}"
    )  # Excel 1-indexed

    workbook.define_name(
        "ExceptionUsedList",
        f"='SIGNINGS_AND_EXCEPTIONS'!{helper_range_ref}"
    )

    # Now add data validation for exception_used column in the signings table
    # Use the named range we just defined
    worksheet.data_validation(
        table_start_row + 1,
        SIG_COL_EXCEPTION,
        table_end_row,
        SIG_COL_EXCEPTION,
        {
            "validate": "list",
            "source": "=ExceptionUsedList",
            "input_title": "Exception Used",
            "input_message": "Select the exception being used for this signing (filtered by SelectedTeam).",
            "error_title": "Invalid Exception",
            "error_message": "Please select from the available exceptions list, or leave blank.",
            "error_type": "warning",  # Allow non-list values with warning
        },
    )

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

# Waive table columns (input columns)
WV_COL_PLAYER = 0
WV_COL_WAIVE_DATE = 1
WV_COL_YEARS_REMAINING = 2
WV_COL_REMAINING_GTD = 3
WV_COL_GIVEBACK = 4
WV_COL_STRETCH = 5
# Computed columns (formula-driven)
WV_COL_NET_OWED = 6
WV_COL_DEAD_Y1 = 7
WV_COL_DEAD_Y2 = 8
WV_COL_DEAD_Y3 = 9
WV_COL_DELTA_CAP = 10
WV_COL_DELTA_TAX = 11
WV_COL_DELTA_APRON = 12
WV_COL_NOTES = 13

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

    This v2 implementation provides (per backlog task #14):
    - Waive/buyout input table with formula-driven computed columns
    - Formula: net_owed = remaining_gtd - giveback
    - Formula: dead_year_1/2/3 based on stretch toggle and years_remaining
      - If stretch="No": all net_owed goes to dead_year_1
      - If stretch="Yes": net_owed is divided evenly across stretch period
        - Stretch period = (2 × years_remaining + 1), capped at 3 for display
    - Formula: delta_cap/tax/apron picks appropriate dead_year based on SelectedYear
      - dead_year_1 = MetaBaseYear, dead_year_2 = MetaBaseYear+1, etc.
    - Journal Output block with aggregated deltas for SelectedYear
    - Stretch provision reference notes
    """
    sub_formats = _create_subsystem_formats(workbook)

    # Sheet title
    worksheet.write(0, 0, "WAIVE / BUYOUT / STRETCH", formats["header"])
    worksheet.write(1, 0, "Model dead money scenarios — formulas auto-compute net owed, dead money distribution, and SelectedYear deltas")

    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)

    content_row = get_content_start_row()

    # Column widths
    worksheet.set_column(WV_COL_PLAYER, WV_COL_PLAYER, 22)
    worksheet.set_column(WV_COL_WAIVE_DATE, WV_COL_WAIVE_DATE, 12)
    worksheet.set_column(WV_COL_YEARS_REMAINING, WV_COL_YEARS_REMAINING, 10)
    worksheet.set_column(WV_COL_REMAINING_GTD, WV_COL_REMAINING_GTD, 14)
    worksheet.set_column(WV_COL_GIVEBACK, WV_COL_GIVEBACK, 12)
    worksheet.set_column(WV_COL_STRETCH, WV_COL_STRETCH, 10)
    worksheet.set_column(WV_COL_NET_OWED, WV_COL_NET_OWED, 12)
    worksheet.set_column(WV_COL_DEAD_Y1, WV_COL_DEAD_Y3, 12)
    worksheet.set_column(WV_COL_DELTA_CAP, WV_COL_DELTA_APRON, 12)
    worksheet.set_column(WV_COL_NOTES, WV_COL_NOTES, 20)

    # Section header
    worksheet.merge_range(
        content_row, WV_COL_PLAYER,
        content_row, WV_COL_NOTES,
        "WAIVE/BUYOUT INPUT (tbl_waive_input) — formulas auto-compute net owed + dead money + SelectedYear deltas",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, WV_COL_PLAYER,
        "Yellow = input cells. Blue = formula-driven. Net Owed = Remaining GTD - Giveback. "
        "Stretch spreads over (2 × years remaining + 1) years.",
        sub_formats["note"],
    )
    content_row += 2

    # Table columns
    waive_columns = [
        "player_name",
        "waive_date",
        "years_remaining",
        "remaining_gtd",
        "giveback",
        "stretch",
        "net_owed",
        "dead_year_1",
        "dead_year_2",
        "dead_year_3",
        "delta_cap",
        "delta_tax",
        "delta_apron",
        "notes",
    ]

    # Empty input rows
    table_start_row = content_row
    initial_data = []
    for _ in range(WV_NUM_ROWS):
        initial_data.append({
            "player_name": "",
            "waive_date": "",
            "years_remaining": 1,
            "remaining_gtd": 0,
            "giveback": 0,
            "stretch": "No",
            "net_owed": 0,
            "dead_year_1": 0,
            "dead_year_2": 0,
            "dead_year_3": 0,
            "delta_cap": 0,
            "delta_tax": 0,
            "delta_apron": 0,
            "notes": "",
        })

    table_end_row = table_start_row + len(initial_data)

    # Build data matrix
    data_matrix = [[row_dict.get(col, "") for col in waive_columns] for row_dict in initial_data]

    # =========================================================================
    # Formula definitions for computed columns (modernized with LET + INDEX)
    # =========================================================================
    #
    # Per backlog task #10:
    # - Use LET for net_owed and dead-year distribution
    # - Use INDEX + ModeYearIndex for SelectedYear delta pick
    # - Preserve stretch toggle logic and validations
    #
    # ModeYearIndex = SelectedYear - MetaBaseYear + 1 (defined in named_formulas.py)
    # =========================================================================

    # net_owed = remaining_gtd - giveback
    # NOTE: Avoid LET in table calculated columns - XlsxWriter generates invalid XML
    net_owed_formula = '=[@remaining_gtd]-[@giveback]'

    # dead_year_1/2/3 formulas based on stretch toggle:
    #
    # If stretch="No": all goes to dead_year_1, years 2 and 3 are 0
    # If stretch="Yes": divide net_owed by stretch_period
    #   stretch_period = MIN(2*years_remaining+1, 5)
    #
    # Using LET for readability:
    # - net: the net owed amount
    # - is_stretch: boolean for stretch toggle
    # - period: stretch period (1 if no stretch, otherwise (2*years+1) capped at 5)
    # - per_year: net / period (rounded)
    # - Result varies by year position
    #
    # dead_year_1: always gets a share (all if no stretch, per_year if stretch)
    # NOTE: Avoid LET in table calculated columns - XlsxWriter generates invalid XML
    # Inline: IF(stretch="Yes", ROUND(net_owed / MIN(2*years+1,5), 0), net_owed)
    dead_y1_formula = (
        '=IF([@stretch]="Yes",'
        'ROUND([@net_owed]/MIN(2*[@years_remaining]+1,5),0),'
        '[@net_owed])'
    )

    # dead_year_2: gets share if stretch="Yes" AND stretch_period >= 2
    # period = MIN(2*years+1, 5); if stretch and period>=2, return per_year, else 0
    dead_y2_formula = (
        '=IF(AND([@stretch]="Yes",MIN(2*[@years_remaining]+1,5)>=2),'
        'ROUND([@net_owed]/MIN(2*[@years_remaining]+1,5),0),'
        '0)'
    )

    # dead_year_3: gets share if stretch="Yes" AND stretch_period >= 3
    dead_y3_formula = (
        '=IF(AND([@stretch]="Yes",MIN(2*[@years_remaining]+1,5)>=3),'
        'ROUND([@net_owed]/MIN(2*[@years_remaining]+1,5),0),'
        '0)'
    )

    # delta_cap/tax/apron: pick the dead_year matching SelectedYear
    # dead_year_1 corresponds to MetaBaseYear, dead_year_2 to MetaBaseYear+1, etc.
    #
    # ModeYearIndex = SelectedYear - MetaBaseYear + 1 (values 1..6)
    # We only have 3 dead_year columns, so return 0 for idx > 3
    #
    # NOTE: Avoid LET in table calculated columns - XlsxWriter generates invalid XML
    # Use IFERROR(CHOOSE(...)) instead of LET+INDEX
    #
    # Note: cap/tax/apron all get the same dead money amount (waived salary
    # counts identically toward all three thresholds per CBA).
    delta_formula = (
        '=IFERROR(CHOOSE(ModeYearIndex,[@dead_year_1],[@dead_year_2],[@dead_year_3]),0)'
    )

    # Column definitions with unlocked formats for input columns,
    # locked output formats for computed columns
    column_defs = [
        {"header": "player_name", "format": formats["input"]},
        {"header": "waive_date", "format": formats["input_date"]},
        {"header": "years_remaining", "format": formats["input_int"]},
        {"header": "remaining_gtd", "format": formats["input_money"]},
        {"header": "giveback", "format": formats["input_money"]},
        {"header": "stretch", "format": formats["input"]},
        # Computed columns (formula-driven, locked)
        {"header": "net_owed", "format": sub_formats["output_money"], "formula": net_owed_formula},
        {"header": "dead_year_1", "format": sub_formats["output_money"], "formula": dead_y1_formula},
        {"header": "dead_year_2", "format": sub_formats["output_money"], "formula": dead_y2_formula},
        {"header": "dead_year_3", "format": sub_formats["output_money"], "formula": dead_y3_formula},
        {"header": "delta_cap", "format": sub_formats["output_money"], "formula": delta_formula},
        {"header": "delta_tax", "format": sub_formats["output_money"], "formula": delta_formula},
        {"header": "delta_apron", "format": sub_formats["output_money"], "formula": delta_formula},
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

    # Data validation: years_remaining (1-4 typical)
    worksheet.data_validation(
        table_start_row + 1,
        WV_COL_YEARS_REMAINING,
        table_end_row,
        WV_COL_YEARS_REMAINING,
        {
            "validate": "integer",
            "criteria": "between",
            "minimum": 1,
            "maximum": 5,
            "input_title": "Years Remaining",
            "input_message": "How many years remain on the contract (1-5)?",
        },
    )

    content_row = table_end_row + 3

    # Editable zone note
    worksheet.write(
        content_row, WV_COL_PLAYER,
        "📝 EDITABLE ZONE: Yellow cells (input) are unlocked. Blue cells (net_owed, dead_year_*, delta_*) "
        "are formula-driven and locked.",
        sub_formats["note"],
    )
    content_row += 2

    # Totals row
    worksheet.write(content_row, WV_COL_PLAYER, "TOTALS:", sub_formats["label_bold"])
    for col in [WV_COL_REMAINING_GTD, WV_COL_GIVEBACK, WV_COL_NET_OWED,
                WV_COL_DEAD_Y1, WV_COL_DEAD_Y2, WV_COL_DEAD_Y3,
                WV_COL_DELTA_CAP, WV_COL_DELTA_TAX, WV_COL_DELTA_APRON]:
        col_name = waive_columns[col]
        worksheet.write_formula(
            content_row, col,
            f"=SUBTOTAL(109,tbl_waive_input[{col_name}])",
            sub_formats["total"],
        )
    content_row += 3

    # =========================================================================
    # JOURNAL OUTPUT BLOCK
    # =========================================================================
    # Provides aggregated deltas for SelectedYear + source label for copying
    # into PLAN_JOURNAL.

    worksheet.merge_range(
        content_row, WV_COL_PLAYER,
        content_row, WV_COL_STRETCH,
        "JOURNAL OUTPUT (copy into PLAN_JOURNAL to record in plan)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, WV_COL_PLAYER,
        "Total waive/buyout deltas for SelectedYear. Copy values into a new PLAN_JOURNAL row.",
        sub_formats["note"],
    )
    content_row += 2

    # Journal output: summary row with aggregated deltas
    journal_label_col = WV_COL_PLAYER
    journal_value_col = WV_COL_WAIVE_DATE

    # SelectedYear context (for reference)
    worksheet.write(content_row, journal_label_col, "Selected Year:", sub_formats["label_bold"])
    worksheet.write_formula(content_row, journal_value_col, "=SelectedYear", sub_formats["output"])
    content_row += 1

    # Waive count (non-blank player_name rows)
    worksheet.write(content_row, journal_label_col, "Waive Count:", sub_formats["label_bold"])
    worksheet.write_formula(
        content_row, journal_value_col,
        '=COUNTA(tbl_waive_input[player_name])',
        sub_formats["output"],
    )
    content_row += 2

    # Total deltas section header
    worksheet.write(content_row, journal_label_col, "TOTAL DELTAS", sub_formats["label_bold"])
    worksheet.write(content_row, journal_value_col, "(for SelectedYear)", sub_formats["label"])
    content_row += 1

    # Delta Cap Total
    worksheet.write(content_row, journal_label_col, "Δ Cap:", sub_formats["label"])
    worksheet.write_formula(
        content_row, journal_value_col,
        "=SUBTOTAL(109,tbl_waive_input[delta_cap])",
        sub_formats["total"],
    )
    content_row += 1

    # Delta Tax Total
    worksheet.write(content_row, journal_label_col, "Δ Tax:", sub_formats["label"])
    worksheet.write_formula(
        content_row, journal_value_col,
        "=SUBTOTAL(109,tbl_waive_input[delta_tax])",
        sub_formats["total"],
    )
    content_row += 1

    # Delta Apron Total
    worksheet.write(content_row, journal_label_col, "Δ Apron:", sub_formats["label"])
    worksheet.write_formula(
        content_row, journal_value_col,
        "=SUBTOTAL(109,tbl_waive_input[delta_apron])",
        sub_formats["total"],
    )
    content_row += 2

    # Source label (for PLAN_JOURNAL source column)
    worksheet.write(content_row, journal_label_col, "Source:", sub_formats["label_bold"])
    worksheet.write(content_row, journal_value_col, "Waive/Buyout (WAIVE_BUYOUT_STRETCH)", sub_formats["output"])
    content_row += 2

    # Manual publish instructions
    worksheet.write(content_row, journal_label_col, "How to publish to PLAN_JOURNAL:", sub_formats["label_bold"])
    content_row += 1

    publish_steps = [
        "1. Go to PLAN_JOURNAL sheet",
        "2. Add a new row with action_type = 'Waive' or 'Buyout' or 'Stretch'",
        "3. Set plan_id, enabled, salary_year, target_player as needed",
        "4. Copy the Δ Cap/Tax/Apron values above into delta_cap/delta_tax/delta_apron columns",
        "5. Set source = 'Waive/Buyout (WAIVE_BUYOUT_STRETCH)'",
    ]
    for step in publish_steps:
        worksheet.write(content_row, journal_label_col, step, sub_formats["note"])
        content_row += 1

    content_row += 2

    # =========================================================================
    # STRETCH PROVISION REFERENCE
    # =========================================================================

    worksheet.write(content_row, WV_COL_PLAYER, "Stretch Provision Rules:", sub_formats["label_bold"])
    content_row += 1

    stretch_notes = [
        "• Stretch spreads remaining guaranteed over (2 × years remaining + 1) seasons",
        "• Example: 2 years remaining → spread over 5 seasons (only first 3 shown in table)",
        "• Stretch must be elected within specific window after waiver",
        "• Cannot stretch mid-season signings in same season",
        "• Set-off: if player signs elsewhere, new salary may offset dead money",
    ]
    for note in stretch_notes:
        worksheet.write(content_row, WV_COL_PLAYER, note, sub_formats["note"])
        content_row += 1

    content_row += 2

    # =========================================================================
    # FORMULA REFERENCE
    # =========================================================================

    worksheet.write(content_row, WV_COL_PLAYER, "Formula Reference:", sub_formats["label_bold"])
    content_row += 1

    formula_notes = [
        "• net_owed = LET(gtd, remaining_gtd, give, giveback, gtd - give)",
        "• If stretch='No': dead_year_1 = net_owed, dead_year_2/3 = 0",
        "• If stretch='Yes': LET computes period = MIN(2×years+1, 5), per_year = net/period",
        "• delta_cap/tax/apron = LET(idx, ModeYearIndex, INDEX(dead_years, 1, idx))",
        "• ModeYearIndex = SelectedYear - MetaBaseYear + 1 (values 1..6)",
        "• Dead money counts identically toward cap, tax, and apron per CBA",
    ]
    for note in formula_notes:
        worksheet.write(content_row, WV_COL_PLAYER, note, sub_formats["note"])
        content_row += 1

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

    This v3 implementation provides:
    - Exceptions section with live FILTER formulas pulling from tbl_exceptions_warehouse
    - Draft picks section with live FILTER+SORT formulas pulling from tbl_draft_picks_warehouse
    - Both filtered by SelectedTeam from command bar
    - Draft picks sorted by draft_year, draft_round, asset_slot
    - Conditional formatting to highlight needs_review rows in red
    - Money/date formats applied to output cells
    - Explicit "None" empty-state when no data exists for selected team
    """
    sub_formats = _create_subsystem_formats(workbook)

    # Sheet title
    worksheet.write(0, 0, "ASSETS", formats["header"])
    worksheet.write(1, 0, "Exception/TPE and draft pick inventory for selected team")

    # Write read-only command bar
    write_command_bar_readonly(workbook, worksheet, formats)

    content_row = get_content_start_row()

    # Column widths for both exceptions and draft picks display
    # (both sections use 8 columns)
    worksheet.set_column(0, 0, 10)   # Year (both: salary_year / draft_year)
    worksheet.set_column(1, 1, 22)   # Exception Type / Round
    worksheet.set_column(2, 2, 22)   # Player Name (TPEs) / Slot
    worksheet.set_column(3, 3, 16)   # Original Amount / Type
    worksheet.set_column(4, 4, 40)   # Remaining Amount / Description (raw_fragment)
    worksheet.set_column(5, 5, 14)   # Effective Date / Conditional?
    worksheet.set_column(6, 6, 14)   # Expiration Date / Swap?
    worksheet.set_column(7, 7, 14)   # Status / Needs Review

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
        content_row, 7,
        "DRAFT PICKS (filtered by SelectedTeam from tbl_draft_picks_warehouse)",
        sub_formats["section_header"],
    )
    content_row += 1

    worksheet.write(
        content_row, 0,
        "Shows owned picks and picks owed. Sorted by year, round, slot. Review flags highlighted.",
        sub_formats["note"],
    )
    content_row += 2

    # Draft pick headers (match the FILTER output columns)
    # Columns: draft_year, draft_round, asset_slot, asset_type, raw_fragment, is_conditional_text, is_swap_text, needs_review
    pick_headers = [
        "Year",
        "Round",
        "Slot",
        "Type",
        "Description",
        "Conditional?",
        "Swap?",
        "Needs Review",
    ]
    for i, header in enumerate(pick_headers):
        worksheet.write(content_row, i, header, sub_formats["label_bold"])
    pick_header_row = content_row
    content_row += 1

    # FILTER formula for draft picks
    # Columns selected: draft_year, draft_round, asset_slot, asset_type, raw_fragment,
    #                   is_conditional_text, is_swap_text, needs_review
    # Filter: team_code = SelectedTeam
    # Sort: by draft_year, draft_round, asset_slot (via SORT wrapper)
    # Empty result: display "None"
    #
    # Excel FILTER + SORT syntax:
    #   =IFERROR(
    #     SORT(
    #       FILTER(
    #         CHOOSE({1,2,3,4,5,6,7,8},
    #           tbl_draft_picks_warehouse[draft_year],
    #           tbl_draft_picks_warehouse[draft_round],
    #           tbl_draft_picks_warehouse[asset_slot],
    #           tbl_draft_picks_warehouse[asset_type],
    #           tbl_draft_picks_warehouse[raw_fragment],
    #           IF(tbl_draft_picks_warehouse[is_conditional_text],"Yes",""),
    #           IF(tbl_draft_picks_warehouse[is_swap_text],"Yes",""),
    #           IF(tbl_draft_picks_warehouse[needs_review],"⚠ REVIEW","")
    #         ),
    #         tbl_draft_picks_warehouse[team_code]=SelectedTeam
    #       ),
    #       {1,2,3},  -- sort by columns 1 (year), 2 (round), 3 (slot)
    #       {1,1,1}   -- all ascending
    #     ),
    #     "None"
    #   )
    pick_filter_formula = (
        '=IFERROR('
        'SORT('
        'FILTER('
        'CHOOSE({1,2,3,4,5,6,7,8},'
        'tbl_draft_picks_warehouse[draft_year],'
        'tbl_draft_picks_warehouse[draft_round],'
        'tbl_draft_picks_warehouse[asset_slot],'
        'tbl_draft_picks_warehouse[asset_type],'
        'tbl_draft_picks_warehouse[raw_fragment],'
        'IF(tbl_draft_picks_warehouse[is_conditional_text],"Yes",""),'
        'IF(tbl_draft_picks_warehouse[is_swap_text],"Yes",""),'
        'IF(tbl_draft_picks_warehouse[needs_review],"⚠ REVIEW","")),'
        'tbl_draft_picks_warehouse[team_code]=SelectedTeam),'
        '{1,2,3},{1,1,1}),'
        '"None")'
    )

    # Write the FILTER formula - it will spill into the cells below/right
    worksheet.write_formula(content_row, 0, pick_filter_formula, sub_formats["output"])

    # Reserve space for spill results (up to 30 draft pick rows — 6 years × ~5 picks)
    pick_data_start_row = content_row
    content_row += 30  # Reserve 30 rows for draft pick data

    # Conditional formatting for needs_review column (column 7 = index 7)
    # Highlight cells containing "⚠ REVIEW" in red
    worksheet.conditional_format(
        pick_data_start_row, 7,
        pick_data_start_row + 29, 7,
        {
            "type": "text",
            "criteria": "containing",
            "value": "REVIEW",
            "format": sub_formats["status_fail"],
        },
    )

    # Note about dynamic array behavior
    worksheet.write(
        content_row, 0,
        "↑ Dynamic array formula — results spill automatically. 'None' shown if no picks for selected team.",
        sub_formats["note"],
    )
    content_row += 2

    # Asset type legend
    worksheet.write(content_row, 0, "Asset Type Legend:", sub_formats["label_bold"])
    content_row += 1

    asset_types = [
        ("OWN", "Team's own pick"),
        ("TO", "Pick owed to another team"),
        ("HAS", "Pick acquired from another team"),
        ("MAY_HAVE", "Conditional pick (may acquire)"),
        ("OTHER", "Other/complex arrangement"),
    ]
    for type_code, type_desc in asset_types:
        worksheet.write(content_row, 0, f"• {type_code}:", sub_formats["label"])
        worksheet.write(content_row, 2, type_desc, sub_formats["note"])
        content_row += 1

    content_row += 1

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
