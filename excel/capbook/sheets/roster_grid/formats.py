from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook

from ...xlsx import FMT_MONEY, FMT_PERCENT


def _create_roster_formats(workbook: Workbook) -> dict[str, Any]:
    """Create formats specific to the roster grid."""
    formats = {}

    # Section headers
    formats["section_header"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#E5E7EB",  # gray-200
        "bottom": 2,
    })

    # Exists-only section header (distinct purple color to indicate non-counting)
    formats["section_header_exists_only"] = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#EDE9FE",  # purple-100
        "font_color": "#6B21A8",  # purple-800
        "bottom": 2,
    })

    # Column headers
    formats["col_header"] = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "bg_color": "#F3F4F6",  # gray-100
        "align": "center",
        "bottom": 1,
    })

    # Money format
    formats["money"] = workbook.add_format({"num_format": FMT_MONEY})
    formats["money_bold"] = workbook.add_format({"num_format": FMT_MONEY, "bold": True})

    # Percent format
    formats["percent"] = workbook.add_format({"num_format": FMT_PERCENT, "align": "center"})

    # Badge formats (option/guarantee/trade)
    formats["badge_po"] = workbook.add_format({
        "bg_color": "#DBEAFE",  # blue-100
        "font_color": "#1E40AF",  # blue-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_to"] = workbook.add_format({
        "bg_color": "#EDE9FE",  # purple-100
        "font_color": "#5B21B6",  # purple-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_eto"] = workbook.add_format({
        "bg_color": "#FFEDD5",  # orange-100
        "font_color": "#9A3412",  # orange-800
        "align": "center",
        "font_size": 9,
    })

    formats["badge_gtd"] = workbook.add_format({
        "font_color": "#166534",  # green-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_prt"] = workbook.add_format({
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
        "align": "center",
        "font_size": 9,
    })
    formats["badge_ng"] = workbook.add_format({
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "align": "center",
        "font_size": 9,
    })

    # Trade restriction badges
    formats["badge_no_trade"] = workbook.add_format({
        "bg_color": "#FEE2E2",
        "font_color": "#991B1B",
        "align": "center",
        "font_size": 9,
    })
    formats["badge_kicker"] = workbook.add_format({
        "bg_color": "#FFEDD5",
        "font_color": "#9A3412",
        "align": "center",
        "font_size": 9,
    })
    formats["badge_consent"] = workbook.add_format({
        "bg_color": "#FEF3C7",
        "font_color": "#92400E",
        "align": "center",
        "font_size": 9,
    })

    # Minimum contract label
    formats["min_label"] = workbook.add_format({
        "italic": True,
        "font_color": "#6B7280",  # gray-500
        "font_size": 9,
        "align": "center",
    })

    # Bucket labels
    formats["bucket_rost"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
    })
    formats["bucket_fa"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#1E40AF",  # blue-800
    })
    formats["bucket_term"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#991B1B",  # red-800
    })
    formats["bucket_2way"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#6B7280",  # gray-500
        "italic": True,
    })
    formats["bucket_exists_only"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#9333EA",  # purple-600
        "italic": True,
    })

    # Counts column formats (Y/N badges)
    formats["counts_yes"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#166534",  # green-800
        "bold": True,
    })
    formats["counts_no"] = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#9CA3AF",  # gray-400
        "italic": True,
    })

    # Subtotal row
    formats["subtotal"] = workbook.add_format({
        "bold": True,
        "top": 1,
        "num_format": FMT_MONEY,
    })
    formats["subtotal_label"] = workbook.add_format({
        "bold": True,
        "top": 1,
    })

    # Reconciliation section
    formats["reconcile_header"] = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "bg_color": "#FEF3C7",  # amber-100
    })
    formats["reconcile_label"] = workbook.add_format({
        "font_size": 9,
    })
    formats["reconcile_value"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_size": 9,
    })
    formats["reconcile_delta_zero"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_size": 9,
        "bg_color": "#D1FAE5",  # green-100
        "font_color": "#065F46",  # green-800
    })
    formats["reconcile_delta_nonzero"] = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_size": 9,
        "bg_color": "#FEE2E2",  # red-100
        "font_color": "#991B1B",  # red-800
        "bold": True,
    })

    return formats
