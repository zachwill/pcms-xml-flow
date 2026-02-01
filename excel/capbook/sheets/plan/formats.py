from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook


def _create_plan_formats(workbook: Workbook) -> dict[str, Any]:
    """Create formats specific to plan sheets."""
    from ...xlsx import FMT_MONEY
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
