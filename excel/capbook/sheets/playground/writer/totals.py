"""PLAYGROUND totals block."""

from __future__ import annotations

from typing import Any

from xlsxwriter.worksheet import Worksheet

from ..layout import (
    COL_AGENT,
    COL_PLAYER,
    COL_SAL_Y0,
    COL_SAL_Y1,
    COL_SAL_Y2,
    COL_SAL_Y3,
    ROSTER_RESERVED,
    ROW_BODY_START,
    YEAR_OFFSETS,
    col_letter,
)


def write_totals(worksheet: Worksheet, fmts: dict[str, Any]) -> None:
    """Write the totals block below the roster grid."""

    # Totals block immediately after roster (just 1 row gap)
    roster_start = ROW_BODY_START
    roster_end = roster_start + ROSTER_RESERVED - 1
    totals_start = roster_end + 2

    row = totals_start

    worksheet.write(row, COL_PLAYER, "TOTALS (Scenario)", fmts["totals_section"])

    def year_label(off: int) -> str:
        return (
            "=TEXT(MOD(MetaBaseYear+{o},100),\"00\")&\"-\"&TEXT(MOD(MetaBaseYear+{o1},100),\"00\")".format(
                o=off,
                o1=off + 1,
            )
        )

    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, year_label(off), fmts["totals_section"])

    legend_col = COL_AGENT
    legend_row = row
    worksheet.write(legend_row, legend_col, "LEGEND", fmts["totals_section"])
    legend_items = [
        ("PLAYER OPTION", fmts["option_player"]),
        ("TEAM OPTION", fmts["option_team"]),
        ("TRADE BONUS", fmts["trade_kicker"]),
        ("TRADE RESTRICTION", fmts["trade_restriction"]),
    ]
    for i, (label, fmt) in enumerate(legend_items, start=1):
        worksheet.write(legend_row + i, legend_col, label, fmt)

    row += 1

    # Scenario totals (layer-specific)

    worksheet.write(row, COL_PLAYER, "Cap Total (scenario)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnCapTotal{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Total (scenario)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnTaxTotal{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron Total (scenario)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnApronTotal{off}", fmts["totals_value"])
    row += 1

    # Dead money (modeling layer; informational)
    worksheet.write(row, COL_PLAYER, "Dead Money", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnDeadMoney{off}", fmts["totals_value"])
    row += 1

    # Roster fill (Sean convention, with configurable assumptions via the left rail)
    worksheet.write(row, COL_PLAYER, "Fill (to 12)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnFill12Amount{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Fill (to 14)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnFill14Amount{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Fill Total", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnFillAmount{off}", fmts["totals_value"])
    row += 1

    # Filled totals (must be used for posture/threshold room)
    worksheet.write(row, COL_PLAYER, "Cap Total (filled)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnCapTotalFilled{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Total (filled)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnTaxTotalFilled{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron Total (filled)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnApronTotalFilled{off}", fmts["totals_value"])
    row += 1

    # Room vs thresholds (green if >=0, red if <0)
    worksheet.write(row, COL_PLAYER, "Cap Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        cap_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])"
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={cap_level}-ScnCapTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        tax_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[tax_level_amount])"
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={tax_level}-ScnTaxTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron 1 Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        apron1 = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[tax_apron_amount])"
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={apron1}-ScnApronTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron 2 Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        apron2 = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[tax_apron2_amount])"
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={apron2}-ScnApronTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Payment", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnTaxPayment{off}", fmts["totals_value"])
    row += 2

    # Placeholders
    worksheet.write(row, COL_PLAYER, "EXCEPTIONS", fmts["totals_section"])
    worksheet.write(row + 1, COL_PLAYER, "(coming soon)", fmts["placeholder"])
    row += 3

    worksheet.write(row, COL_PLAYER, "DRAFT PICKS", fmts["totals_section"])
    worksheet.write(row + 1, COL_PLAYER, "(coming soon)", fmts["placeholder"])
