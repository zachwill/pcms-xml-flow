"""excel.capbook.xlsx

XlsxWriter helpers for workbook generation.

Provides:
- Format definitions (colors, number formats, badges)
- Table writer (Excel Table / ListObject)
- Named range helpers
- Sheet heading helpers

Note: when mapping UI semantics (options/guarantees/restrictions), prefer the
existing decisions in web/ (SalaryBook) and keep the mapping explicit.
"""

from __future__ import annotations

from typing import Any

import xlsxwriter
from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet


# -----------------------------------------------------------------------------
# Font + Format constants
# -----------------------------------------------------------------------------

# Default font for the entire workbook
DEFAULT_FONT = "Aptos Narrow"
DEFAULT_FONT_SIZE = 11

# -----------------------------------------------------------------------------
# Format constants (mapped from web/src/features/SalaryBook/)
# -----------------------------------------------------------------------------

# Money formatting
# Amounts are stored as integer dollars; UI prefers dense display without "$".
FMT_MONEY = "#,##0"
FMT_MONEY_MILLIONS = "#,##0,,"  # Divide by 1M, show as X (no decimals)

# Percentage
FMT_PERCENT = "0.0%"

# Option badge colors
# web: OptionBadge.tsx
# - PO: blue
# - TO: purple
# - ETO: orange
COLOR_OPTION_PO = "#3B82F6"  # blue-500-ish
COLOR_OPTION_TO = "#8B5CF6"  # purple-500-ish
COLOR_OPTION_ETO = "#F97316"  # orange-500-ish

# Highlight background tints (table cell fills, Excel tab colors)
# web: option/trade highlight backgrounds in SalaryBook tables
COLOR_OPTION_PO_BG = "#DBEAFE"  # blue-100
COLOR_OPTION_TO_BG = "#EDE9FE"  # purple-100
COLOR_TRADE_KICKER_BG = "#FFEDD5"  # orange-100
COLOR_TRADE_RESTRICTION_BG = "#FEE2E2"  # red-100

# Guarantee badge colors
# web: GuaranteeBadge.tsx
COLOR_GTD_FULL = "#16A34A"  # green-600-ish
COLOR_GTD_PARTIAL = "#CA8A04"  # yellow-600-ish
COLOR_GTD_NON = "#EF4444"  # red-500-ish

# Trade restriction colors
# web: RightPanel/PlayerDetail/TradeRestrictions.tsx
COLOR_TRADE_KICKER = "#F97316"  # orange
COLOR_NO_TRADE = "#EF4444"  # red
COLOR_CONSENT_REQUIRED = "#EF4444"  # red
COLOR_POISON_PILL = "#EF4444"  # red
COLOR_PRECONSENTED = "#16A34A"  # green

# Alert/status colors
COLOR_ALERT_FAIL = "#EF4444"  # Red for failures
COLOR_ALERT_WARN = "#F59E0B"  # Amber for warnings
COLOR_ALERT_OK = "#10B981"  # Green for OK

# Header styling
COLOR_HEADER_BG = "#1F2937"  # Dark gray
COLOR_HEADER_FG = "#FFFFFF"  # White text


def create_standard_formats(workbook: Workbook) -> dict[str, Any]:
    """Create and return standard format objects for the workbook.
    
    All formats use DEFAULT_FONT (Aptos Narrow) for consistency.
    """

    formats: dict[str, Any] = {}

    # Base font properties applied to all formats
    base_font = {"font_name": DEFAULT_FONT, "font_size": DEFAULT_FONT_SIZE}

    # Money formats
    formats["money"] = workbook.add_format({**base_font, "num_format": FMT_MONEY})
    formats["money_millions"] = workbook.add_format({**base_font, "num_format": FMT_MONEY_MILLIONS})

    # Percentage
    formats["percent"] = workbook.add_format({**base_font, "num_format": FMT_PERCENT})

    # Header
    formats["header"] = workbook.add_format(
        {**base_font, "bold": True, "bg_color": COLOR_HEADER_BG, "font_color": COLOR_HEADER_FG}
    )

    # Alert cells
    formats["alert_fail"] = workbook.add_format(
        {**base_font, "bold": True, "bg_color": COLOR_ALERT_FAIL, "font_color": "#FFFFFF"}
    )
    formats["alert_warn"] = workbook.add_format(
        {**base_font, "bold": True, "bg_color": COLOR_ALERT_WARN, "font_color": "#000000"}
    )
    formats["alert_ok"] = workbook.add_format(
        {**base_font, "bold": True, "bg_color": COLOR_ALERT_OK, "font_color": "#FFFFFF"}
    )

    # Badge-style formats (inline indicators)
    formats["badge_po"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_OPTION_PO, "font_color": "#FFFFFF", "bold": True}
    )
    formats["badge_to"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_OPTION_TO, "font_color": "#FFFFFF", "bold": True}
    )
    formats["badge_eto"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_OPTION_ETO, "font_color": "#FFFFFF", "bold": True}
    )

    formats["badge_gtd"] = workbook.add_format(
        {**base_font, "font_color": COLOR_GTD_FULL, "bold": True}
    )
    formats["badge_prt"] = workbook.add_format(
        {**base_font, "font_color": COLOR_GTD_PARTIAL, "bold": True}
    )
    formats["badge_ng"] = workbook.add_format(
        {**base_font, "font_color": COLOR_GTD_NON, "bold": True}
    )

    formats["badge_trade_kicker"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_TRADE_KICKER, "font_color": "#FFFFFF", "bold": True}
    )
    formats["badge_no_trade"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_NO_TRADE, "font_color": "#FFFFFF", "bold": True}
    )
    formats["badge_consent_required"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_CONSENT_REQUIRED, "font_color": "#FFFFFF", "bold": True}
    )
    formats["badge_poison_pill"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_POISON_PILL, "font_color": "#FFFFFF", "bold": True, "italic": True}
    )
    formats["badge_preconsented"] = workbook.add_format(
        {**base_font, "bg_color": COLOR_PRECONSENTED, "font_color": "#FFFFFF", "bold": True}
    )

    # -------------------------------------------------------------------------
    # Input table formats (unlocked for editing on protected sheets)
    # Light yellow background indicates editable zones.
    # -------------------------------------------------------------------------
    formats["input"] = workbook.add_format({
        **base_font,
        "bg_color": "#FFFDE7",  # Light yellow
        "locked": False,
    })
    formats["input_money"] = workbook.add_format({
        **base_font,
        "bg_color": "#FFFDE7",
        "num_format": FMT_MONEY,
        "locked": False,
    })
    formats["input_date"] = workbook.add_format({
        **base_font,
        "bg_color": "#FFFDE7",
        "num_format": "yyyy-mm-dd",
        "locked": False,
    })
    formats["input_int"] = workbook.add_format({
        **base_font,
        "bg_color": "#FFFDE7",
        "num_format": "0",
        "locked": False,
    })

    # -------------------------------------------------------------------------
    # Sheet heading format (large, bold title at top of each sheet)
    # -------------------------------------------------------------------------
    formats["sheet_heading"] = workbook.add_format({
        "font_name": DEFAULT_FONT,
        "font_size": 16,
        "bold": True,
        "font_color": "#1F2937",  # Dark gray
        "bottom": 2,
        "bottom_color": "#3B82F6",  # Blue accent underline
    })

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
    """Write an Excel Table (ListObject) with a stable, deterministic name.

    Notes:
    - Excel tables require at least one data row.
    - If `rows` is empty, we still create the table with a single blank row so
      downstream formulas can refer to a stable table name.

    Returns:
        (end_row, end_col) - 0-indexed position of the last cell.
    """

    if not columns:
        raise ValueError("columns must not be empty for write_table")

    num_data_rows = len(rows)

    # Header is at start_row; data rows start at start_row + 1.
    # XlsxWriter requires the table range to include at least 1 data row.
    # So: N=0 -> 1 blank data row.
    table_data_rows = max(num_data_rows, 1)
    end_row = start_row + table_data_rows
    end_col = start_col + len(columns) - 1

    # Build data matrix from row dicts
    data: list[list[Any]] = [[row_dict.get(col) for col in columns] for row_dict in rows]

    # If no data rows, add an empty row.
    if not data:
        data = [[None] * len(columns)]

    column_defs = [{"header": col} for col in columns]

    worksheet.add_table(
        start_row,
        start_col,
        end_row,
        end_col,
        {
            "name": table_name,
            "columns": column_defs,
            "data": data,
            "style": style,
        },
    )

    if autofit:
        for i, col in enumerate(columns):
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
    """Define a workbook-scoped named range pointing to a single cell."""

    col_letter = xlsxwriter.utility.xl_col_to_name(col)
    cell_ref = f"'{sheet_name}'!${col_letter}${row + 1}"
    workbook.define_name(name, cell_ref)


def write_sheet_heading(
    worksheet: Worksheet,
    formats: dict[str, Any],
    title: str,
    row: int = 0,
    col: int = 0,
    width: int = 4,
) -> int:
    """Write a standard sheet heading at the top of a worksheet.
    
    Args:
        worksheet: The worksheet to write to
        formats: Standard format dict (must include 'sheet_heading')
        title: The heading text to display
        row: Starting row (default 0)
        col: Starting column (default 0)
        width: Number of columns to span with the underline (default 4)
    
    Returns:
        The next row after the heading (row + 2, leaving a blank row)
    """
    heading_fmt = formats.get("sheet_heading")
    
    # Write the title
    worksheet.write(row, col, title, heading_fmt)
    
    # Extend the bottom border across additional columns for visual weight
    for c in range(col + 1, col + width):
        worksheet.write(row, c, "", heading_fmt)
    
    # Return the next content row (skip a blank row after heading)
    return row + 2


def set_workbook_default_font(workbook: Workbook) -> None:
    """Set the default font for cells without explicit formatting.
    
    This modifies the workbook's default format (format index 0) to use
    Aptos Narrow. Cells written without a format will inherit this.
    
    Note: Must be called immediately after creating the workbook,
    before adding any worksheets or formats.
    """
    # Access the default format and set font properties
    # This affects cells written with write() without an explicit format
    default_format = workbook.formats[0]
    default_format.set_font_name(DEFAULT_FONT)
    default_format.set_font_size(DEFAULT_FONT_SIZE)
