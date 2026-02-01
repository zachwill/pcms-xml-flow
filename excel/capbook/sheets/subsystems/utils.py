from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ...xlsx import FMT_MONEY


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


def _col_letter(col: int) -> str:
    """Convert 0-indexed column number to Excel column letter."""
    import xlsxwriter.utility
    return xlsxwriter.utility.xl_col_to_name(col)
