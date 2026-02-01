"""
TEAM_COCKPIT sheet writer with shared command bar, alerts, and readouts.

This module implements the primary flight display for team cap position:

1. The editable command bar (using command_bar.write_command_bar_editable)
2. Validation banner (references MetaValidationStatus)
3. Alert stack section (validation, reconciliation, policy alerts)
4. Primary readouts section driven by DATA_team_salary_warehouse
5. Quick drivers panel (top cap hits, top dead money, top holds)
   - Uses Excel 365 dynamic arrays: LET + FILTER + SORTBY + TAKE
   - Single spilling formula per column (replaces per-row AGGREGATE/MATCH)
   - Mode-aware sorting (respects SelectedMode: Cap/Tax/Apron)
6. Minimum contracts count + total (using is_min_contract)
7. Plan comparison panel (ComparePlan A/B/C/D deltas vs Baseline)
8. Sheet protection with unlocked input cells

Per the blueprint (excel-cap-book-blueprint.md), the command bar is the
workbook's "operating context" and should be consistent across all sheets.

Comparison workflow (per mental-models-and-design-principles.md):
- Analysts compare 2-4 deal candidates side-by-side (lane-based branching)
- The PLAN COMPARISON panel shows deltas for each ComparePlan vs Baseline
- Warnings appear if a ComparePlan is blank or equals Baseline

Split into modules:
- constants.py: Layout constants (column positions, TOP_N_DRIVERS)
- helpers.py: Formula builders (SUMIFS, mode expressions, etc.)
- alerts.py: Validation banner + alert stack
- readouts.py: Primary readouts + minimum contracts
- plan_comparison.py: Plan comparison panel
- quick_drivers.py: Quick drivers panel (top cap hits, dead money, holds)
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..command_bar import (
    write_command_bar_editable,
    get_content_start_row,
    NAMED_RANGES,
)

from .constants import (
    get_readouts_start_row,
    COL_READOUT_LABEL,
    COL_READOUT_VALUE,
    COL_READOUT_DESC,
    READOUT_COLUMN_WIDTHS,
)
from .alerts import write_validation_banner, write_alert_stack
from .readouts import write_primary_readouts, write_minimum_contracts_readout
from .plan_comparison import write_plan_comparison_panel
from .quick_drivers import write_quick_drivers


# =============================================================================
# Main Writer
# =============================================================================


def write_team_cockpit_with_command_bar(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    build_meta: dict[str, Any],
    team_codes: list[str] | None = None,
) -> None:
    """
    Write TEAM_COCKPIT sheet with editable command bar, alerts, and readouts.

    The command bar provides the workbook's operating context:
    - SelectedTeam, SelectedYear, AsOfDate, SelectedMode
    - Policy toggles (roster fill, etc.)
    - Plan selectors (ActivePlan, ComparePlanA/B/C/D)

    The cockpit includes:
    - Validation banner (PASS/FAIL status)
    - Alert stack (validation, policy alerts)
    - Primary readouts (cap/tax/apron positions, roster counts)
    - Minimum contracts count + total
    - Plan comparison panel (ComparePlan A/B/C/D deltas vs Baseline)
    - Quick drivers panel (top cap hits, dead money, holds)

    Args:
        workbook: The XlsxWriter Workbook (needed for define_name and formats)
        worksheet: The TEAM_COCKPIT worksheet
        formats: Standard format dict from create_standard_formats
        build_meta: Build metadata (base_year, as_of_date, etc.)
        team_codes: Optional list of team codes for validation dropdown
    """
    # Sheet title (row 0-1)
    worksheet.write(0, 0, "TEAM COCKPIT", formats["header"])
    worksheet.write(1, 0, "Primary flight display for team cap position")
    
    # Write the editable command bar
    write_command_bar_editable(
        workbook,
        worksheet,
        formats,
        build_meta,
        team_codes=team_codes,
        plan_names=None,  # Will be populated when PLAN_MANAGER is implemented
    )
    
    # =========================================================================
    # Content Sections (after command bar)
    # =========================================================================
    
    content_row = get_readouts_start_row()
    
    # Column widths for readouts area
    for col, width in READOUT_COLUMN_WIDTHS.items():
        worksheet.set_column(col, col, width)
    
    # 1. Validation banner
    content_row = write_validation_banner(workbook, worksheet, formats, content_row)
    
    # Blank row
    content_row += 1
    
    # 2. Alert stack
    content_row = write_alert_stack(workbook, worksheet, formats, content_row)
    
    # 3. Primary readouts
    content_row = write_primary_readouts(workbook, worksheet, formats, content_row)
    
    # 4. Minimum contracts readout
    content_row = write_minimum_contracts_readout(workbook, worksheet, formats, content_row)
    
    # 5. Plan comparison panel (ComparePlan A/B/C/D deltas)
    content_row = write_plan_comparison_panel(workbook, worksheet, formats, content_row)
    
    # 6. Quick drivers panel (starts at same row as validation banner, on right side)
    drivers_start_row = get_readouts_start_row()
    write_quick_drivers(workbook, worksheet, formats, drivers_start_row)
    
    # =========================================================================
    # Sheet Protection
    # =========================================================================
    # Protect the sheet but allow editing of unlocked (input) cells
    # Input cells are marked with locked=False in command_bar.py
    worksheet.protect(options={
        "objects": True,
        "scenarios": True,
        "format_cells": False,  # Allow format changes
        "select_unlocked_cells": True,
        "select_locked_cells": True,
    })


def get_command_bar_cell_refs() -> dict[str, tuple[int, int]]:
    """Return cell positions (row, col) for command bar inputs.

    Useful for other sheets that need to reference these cells.
    
    Deprecated: Use the named ranges (SelectedTeam, etc.) instead of cell refs.
    """
    return NAMED_RANGES.copy()
