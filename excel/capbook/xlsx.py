"""
XlsxWriter helpers for workbook generation.

Provides:
- Format definitions (colors, number formats, badges)
- Table writer (Excel Table / ListObject)
- Named range helpers
"""

from __future__ import annotations

from typing import Any

import xlsxwriter
from xlsxwriter.worksheet import Worksheet
from xlsxwriter.workbook import Workbook


# -----------------------------------------------------------------------------
# Format constants (reusing conventions from web/src/features/SalaryBook/)
# -----------------------------------------------------------------------------

# Money formatting
FMT_MONEY = "$#,##0"
FMT_MONEY_MILLIONS = "$#,##0,,"  # Divide by 1M, show as $X

# Percentage
FMT_PERCENT = "0.0%"

# Option badge colors (from web OptionBadge.tsx)
COLOR_OPTION_PO = "#3B82F6"  # Player option - blue
COLOR_OPTION_TO = "#F59E0B"  # Team option - amber
COLOR_OPTION_ETO = "#8B5CF6"  # Early termination - purple

# Guarantee badge colors (from web GuaranteeBadge.tsx)
COLOR_GTD_FULL = "#10B981"  # Fully guaranteed - green
COLOR_GTD_PARTIAL = "#F59E0B"  # Partially guaranteed - amber
COLOR_GTD_NON = "#EF4444"  # Non-guaranteed - red

# Trade restriction colors (from web TradeRestrictions.tsx)
COLOR_NO_TRADE = "#EF4444"  # No-trade clause - red
COLOR_CONSENT = "#F59E0B"  # Consent required - amber
COLOR_TRADE_KICKER = "#3B82F6"  # Trade kicker - blue
COLOR_POISON_PILL = "#8B5CF6"  # Poison pill - purple

# Alert/status colors
COLOR_ALERT_FAIL = "#EF4444"  # Red for failures
COLOR_ALERT_WARN = "#F59E0B"  # Amber for warnings
COLOR_ALERT_OK = "#10B981"  # Green for OK

# Header styling
COLOR_HEADER_BG = "#1F2937"  # Dark gray
COLOR_HEADER_FG = "#FFFFFF"  # White text


def create_standard_formats(workbook: Workbook) -> dict[str, Any]:
    """
    Create and return standard format objects for the workbook.

    Returns a dict of named format objects.
    """
    formats = {}

    # Money formats
    formats["money"] = workbook.add_format({"num_format": FMT_MONEY})
    formats["money_millions"] = workbook.add_format({"num_format": FMT_MONEY_MILLIONS})

    # Percentage
    formats["percent"] = workbook.add_format({"num_format": FMT_PERCENT})

    # Header
    formats["header"] = workbook.add_format(
        {"bold": True, "bg_color": COLOR_HEADER_BG, "font_color": COLOR_HEADER_FG}
    )

    # Alert cells
    formats["alert_fail"] = workbook.add_format(
        {"bold": True, "bg_color": COLOR_ALERT_FAIL, "font_color": "#FFFFFF"}
    )
    formats["alert_warn"] = workbook.add_format(
        {"bold": True, "bg_color": COLOR_ALERT_WARN, "font_color": "#000000"}
    )
    formats["alert_ok"] = workbook.add_format(
        {"bold": True, "bg_color": COLOR_ALERT_OK, "font_color": "#FFFFFF"}
    )

    # Badge-style formats (for inline option/guarantee indicators)
    formats["badge_po"] = workbook.add_format(
        {"bg_color": COLOR_OPTION_PO, "font_color": "#FFFFFF", "bold": True}
    )
    formats["badge_to"] = workbook.add_format(
        {"bg_color": COLOR_OPTION_TO, "font_color": "#000000", "bold": True}
    )
    formats["badge_eto"] = workbook.add_format(
        {"bg_color": COLOR_OPTION_ETO, "font_color": "#FFFFFF", "bold": True}
    )

    return formats


def write_table(
    worksheet: Worksheet,
    table_name: str,
    start_row: int,
    start_col: int,
    columns: list[str],
    rows: list[dict[str, Any]],
    *,
    autofit: bool = True,
    style: str = "Table Style Light 1",
) -> tuple[int, int]:
    """
    Write an Excel Table (ListObject) with a stable, deterministic name.

    The table range is always explicit and deterministic:
    - Start: (start_row, start_col)
    - End: (start_row + len(rows), start_col + len(columns) - 1)

    The table includes a header row at start_row, followed by data rows.
    If rows is empty, a single-row table with headers only is created.

    Args:
        worksheet: Target worksheet
        table_name: Excel table name (e.g., "tbl_system_values").
                    Must be unique within the workbook and follow Excel
                    naming rules (no spaces, start with letter/underscore).
        start_row: 0-indexed starting row for the table header
        start_col: 0-indexed starting column
        columns: List of column header names (must not be empty)
        rows: List of dicts (each dict is a row; keys should match columns)
        autofit: If True, auto-size columns based on header width (default True)
        style: Excel table style name (default "Table Style Light 1")

    Returns:
        Tuple of (end_row, end_col) - 0-indexed position of the last cell.
        Useful for placing content below the table.

    Raises:
        ValueError: If columns is empty

    Example:
        >>> cols = ["team_code", "salary_year", "cap_total"]
        >>> data = [{"team_code": "LAL", "salary_year": 2025, "cap_total": 150000000}]
        >>> end_row, end_col = write_table(ws, "tbl_teams", 0, 0, cols, data)
    """
    if not columns:
        raise ValueError("columns must not be empty for write_table")

    # Calculate table range (deterministic)
    # Header is at start_row, data rows follow
    # For N data rows, end_row = start_row + N (0-indexed last row)
    # For 0 data rows, end_row = start_row (header-only table)
    num_data_rows = len(rows)
    end_row = start_row + max(num_data_rows, 1)  # At least 1 data row for valid table
    end_col = start_col + len(columns) - 1

    # Build data matrix from row dicts
    data = []
    for row_dict in rows:
        data.append([row_dict.get(col) for col in columns])

    # If no data rows, add an empty row (Excel tables require at least 1 data row)
    if not data:
        data = [[None] * len(columns)]

    # Build column definitions with explicit headers
    column_defs = [{"header": col} for col in columns]

    # Configure table options
    table_options: dict[str, Any] = {
        "name": table_name,
        "columns": column_defs,
        "data": data,
        "style": style,
    }

    # Add the table with explicit range
    worksheet.add_table(start_row, start_col, end_row, end_col, table_options)

    # Auto-fit column widths based on header length (approximate)
    if autofit:
        for i, col in enumerate(columns):
            # Use header length + padding, minimum 10 chars
            width = max(len(str(col)) + 2, 10)
            worksheet.set_column(start_col + i, start_col + i, width)

    return end_row, end_col


def define_named_cell(
    workbook: Workbook,
    name: str,
    sheet_name: str,
    row: int,
    col: int,
) -> None:
    """
    Define a workbook-scoped named range pointing to a single cell.

    Args:
        workbook: The workbook
        name: Name for the range (e.g., "SelectedTeam")
        sheet_name: Sheet containing the cell
        row: 0-indexed row
        col: 0-indexed column
    """
    # Convert to Excel notation (A1 style)
    col_letter = xlsxwriter.utility.xl_col_to_name(col)
    cell_ref = f"'{sheet_name}'!${col_letter}${row + 1}"
    workbook.define_name(name, cell_ref)
