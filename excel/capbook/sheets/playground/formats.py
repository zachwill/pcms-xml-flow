"""PLAYGROUND sheet formats.

We start from the shared workbook formats (input, input_money, etc.) and add
sheet-specific formats for density + semantics.
"""

from __future__ import annotations

from typing import Any

from ...xlsx import DEFAULT_FONT, DEFAULT_FONT_SIZE


def create_playground_formats(workbook, shared: dict[str, Any]) -> dict[str, Any]:
    base_font = {"font_name": DEFAULT_FONT, "font_size": DEFAULT_FONT_SIZE}

    fmts: dict[str, Any] = {}

    fmts["section"] = workbook.add_format({**base_font, "bold": True, "font_color": "#374151", "font_size": 9})

    fmts["team_input"] = workbook.add_format(
        {
            **base_font,
            "bold": True,
            "font_size": 14,
            "bg_color": "#FFFDE7",
            "align": "left",
            "locked": False,
        }
    )

    # KPI bar
    fmts["kpi_label"] = workbook.add_format({**base_font, "font_color": "#6B7280", "font_size": 9, "align": "center"})
    fmts["kpi_value"] = workbook.add_format({**base_font, "bold": True, "font_size": 12, "align": "center"})
    fmts["kpi_money"] = workbook.add_format(
        {
            **base_font,
            "bold": True,
            "font_size": 12,
            "align": "center",
            # 187.5M density
            "num_format": '#,##0.0,,"M";[Red]-#,##0.0,,"M";"-"',
        }
    )
    fmts["kpi_delta_pos"] = workbook.add_format(
        {
            **base_font,
            "bold": True,
            "font_size": 12,
            "align": "center",
            "font_color": "#16A34A",
            "num_format": '+#,##0.0,,"M";-#,##0.0,,"M";"-"',
        }
    )
    fmts["kpi_delta_neg"] = workbook.add_format(
        {
            **base_font,
            "bold": True,
            "font_size": 12,
            "align": "center",
            "font_color": "#DC2626",
            "num_format": '+#,##0.0,,"M";-#,##0.0,,"M";"-"',
        }
    )

    # Column headers
    fmts["header"] = workbook.add_format(
        {
            **base_font,
            "bold": True,
            "bg_color": "#F3F4F6",
            "bottom": 1,
            "bottom_color": "#D1D5DB",
            "font_size": 10,
        }
    )
    fmts["header_right"] = workbook.add_format(
        {
            **base_font,
            "bold": True,
            "bg_color": "#F3F4F6",
            "bottom": 1,
            "bottom_color": "#D1D5DB",
            "font_size": 10,
            "align": "right",
        }
    )

    # Roster data
    fmts["rank"] = workbook.add_format({**base_font, "font_color": "#9CA3AF", "align": "center"})
    fmts["player"] = workbook.add_format({**base_font})

    # Salary (dense, millions)
    fmts["money_m"] = workbook.add_format(
        {
            **base_font,
            "align": "right",
            "num_format": '#,##0.0,,"M";[Red]-#,##0.0,,"M";"-"',
        }
    )

    # Percent of cap
    fmts["pct"] = workbook.add_format({**base_font, "align": "right", "font_color": "#6B7280", "num_format": "0.0%"})

    fmts["agent"] = workbook.add_format({**base_font, "font_color": "#6B7280", "font_size": 10})

    # Status highlight formats (used in conditional formatting)
    fmts["status_out"] = workbook.add_format({**base_font, "font_color": "#9CA3AF", "font_strikeout": True})
    fmts["status_in"] = workbook.add_format({**base_font, "font_color": "#7C3AED", "bold": True})
    fmts["status_sign"] = workbook.add_format({**base_font, "font_color": "#059669", "bold": True})
    fmts["status_waived"] = workbook.add_format({**base_font, "font_color": "#9CA3AF", "font_strikeout": True})
    fmts["status_stretch"] = workbook.add_format({**base_font, "font_color": "#9CA3AF", "font_strikeout": True})

    # Totals section
    fmts["totals_section"] = workbook.add_format({**base_font, "bold": True, "font_size": 10, "top": 2, "top_color": "#9CA3AF"})
    fmts["totals_label"] = workbook.add_format({**base_font, "font_size": 10})
    fmts["totals_value"] = workbook.add_format({**base_font, "font_size": 10, "align": "right", "num_format": '#,##0,;[Red]-#,##0,;"-"'})
    fmts["totals_delta_pos"] = workbook.add_format({**base_font, "font_size": 10, "align": "right", "font_color": "#16A34A", "num_format": '+#,##0,;-#,##0,;"-"'})
    fmts["totals_delta_neg"] = workbook.add_format({**base_font, "font_size": 10, "align": "right", "font_color": "#DC2626", "num_format": '+#,##0,;-#,##0,;"-"'})

    fmts["trade_label"] = workbook.add_format({**base_font, "font_color": "#6B7280", "font_size": 9})
    fmts["trade_value"] = workbook.add_format({**base_font, "num_format": "#,##0", "font_size": 9})

    # Trade math helpers
    fmts["trade_delta_pos"] = workbook.add_format({**base_font, "font_size": 9, "font_color": "#16A34A", "num_format": "#,##0"})
    fmts["trade_delta_neg"] = workbook.add_format({**base_font, "font_size": 9, "font_color": "#DC2626", "num_format": "#,##0"})

    fmts["trade_status"] = workbook.add_format({**base_font, "font_size": 9, "bold": True, "align": "center"})
    fmts["trade_status_valid"] = workbook.add_format({**base_font, "font_size": 9, "bold": True, "font_color": "#16A34A", "align": "center"})
    fmts["trade_status_invalid"] = workbook.add_format({**base_font, "font_size": 9, "bold": True, "font_color": "#DC2626", "align": "center"})

    # Deprecated (kept for now; older builds used a simplistic match %)
    fmts["trade_match"] = workbook.add_format({**base_font, "font_size": 9, "num_format": "0%"})
    fmts["trade_match_valid"] = workbook.add_format({**base_font, "font_size": 9, "font_color": "#16A34A", "num_format": "0%"})
    fmts["trade_match_invalid"] = workbook.add_format({**base_font, "font_size": 9, "font_color": "#DC2626", "num_format": "0%"})

    # Base year display (left-aligned to match team input)
    fmts["base_value"] = workbook.add_format({**base_font, "bold": True, "font_size": 14, "align": "left"})

    fmts["placeholder"] = workbook.add_format({**base_font, "bg_color": "#F3F4F6", "font_color": "#9CA3AF", "align": "center"})

    # Carry through shared formats we depend on
    fmts["input"] = shared["input"]
    fmts["input_money"] = shared["input_money"]

    return fmts
