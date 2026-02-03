"""PLAYGROUND sheet setup: columns, context rows, and headers."""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..layout import (
    COL_AGENT,
    COL_INPUT,
    COL_INPUT_SALARY,
    COL_PCT_Y0,
    COL_PCT_Y1,
    COL_PCT_Y2,
    COL_PCT_Y3,
    COL_PCT_Y4,
    COL_PCT_Y5,
    COL_PLAYER,
    COL_RANK,
    COL_SAL_Y0,
    COL_SAL_Y1,
    COL_SAL_Y2,
    COL_SAL_Y3,
    COL_SAL_Y4,
    COL_SAL_Y5,
    COL_SECTION_LABEL,
    COL_STATUS,
    COL_TOTAL,
    ROW_BASE,
    ROW_HEADER,
    ROW_TEAM_CONTEXT,
    col_letter,
)


def write_setup(
    workbook: Workbook,
    worksheet: Worksheet,
    fmts: dict[str, Any],
    team_codes: list[str],
) -> None:
    """Write column defaults, context rows, KPI row, and roster headers."""

    # ---------------------------------------------------------------------
    # Columns (dense defaults)
    # ---------------------------------------------------------------------
    worksheet.set_column(COL_SECTION_LABEL, COL_SECTION_LABEL, 10)
    worksheet.set_column(COL_INPUT, COL_INPUT, 18)
    worksheet.set_column(COL_INPUT_SALARY, COL_INPUT_SALARY, 12)

    # NOTE: XlsxWriter's write_dynamic_array_formula only formats the anchor cell.
    # Spilled cells inherit the column format. We apply column formats here so
    # the spilled roster data displays correctly.
    # COL_RANK widened to 8 so "ROSTER" KPI label fits
    worksheet.set_column(COL_RANK, COL_RANK, 8, fmts["rank"])
    worksheet.set_column(COL_PLAYER, COL_PLAYER, 20, fmts["player"])

    # Salaries and % of cap (6-year slice)
    # NOTE: % columns are widened to 10 so KPI money values (row 1) fit
    worksheet.set_column(COL_SAL_Y0, COL_SAL_Y0, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y0, COL_PCT_Y0, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y1, COL_SAL_Y1, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y1, COL_PCT_Y1, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y2, COL_SAL_Y2, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y2, COL_PCT_Y2, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y3, COL_SAL_Y3, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y3, COL_PCT_Y3, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y4, COL_SAL_Y4, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y4, COL_PCT_Y4, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y5, COL_SAL_Y5, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y5, COL_PCT_Y5, 10, fmts["pct"])

    worksheet.set_column(COL_TOTAL, COL_TOTAL, 10, fmts["money_m"])
    worksheet.set_column(COL_AGENT, COL_AGENT, 18, fmts["agent"])
    worksheet.set_column(COL_STATUS, COL_STATUS, 10)

    # ---------------------------------------------------------------------
    # Freeze panes: rows 1-3 and cols A-C
    # ---------------------------------------------------------------------
    worksheet.freeze_panes(ROW_HEADER + 1, COL_RANK)

    # ---------------------------------------------------------------------
    # Row 1: Season context (left-aligned to match TEAM/POR below)
    # ---------------------------------------------------------------------
    worksheet.write(ROW_BASE, COL_SECTION_LABEL, "SEASON", fmts["section"])
    worksheet.write_formula(
        ROW_BASE,
        COL_INPUT,
        "=TEXT(MOD(MetaBaseYear,100),\"00\")&\"-\"&TEXT(MOD(MetaBaseYear+1,100),\"00\")",
        fmts["base_value"],
    )

    # ---------------------------------------------------------------------
    # Row 2: Team selector
    # ---------------------------------------------------------------------
    worksheet.write(ROW_TEAM_CONTEXT, COL_SECTION_LABEL, "TEAM", fmts["section"])
    worksheet.write(ROW_TEAM_CONTEXT, COL_INPUT, "POR", fmts["team_input"])

    if team_codes:
        worksheet.data_validation(
            ROW_TEAM_CONTEXT,
            COL_INPUT,
            ROW_TEAM_CONTEXT,
            COL_INPUT,
            {"validate": "list", "source": team_codes},
        )

    workbook.define_name(
        "SelectedTeam",
        f"=PLAYGROUND!${col_letter(COL_INPUT)}${ROW_TEAM_CONTEXT + 1}",
    )

    # ---------------------------------------------------------------------
    # KPI bar (Row 1, starting at COL_RANK)
    # ---------------------------------------------------------------------
    r = ROW_BASE

    worksheet.write(r, COL_RANK, "ROSTER", fmts["kpi_label"])
    worksheet.write_formula(r, COL_PLAYER, "=ScnRosterCount0", fmts["kpi_value"])

    worksheet.write(r, COL_SAL_Y0, "TWO-WAY", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_PCT_Y0,
        "=XLOOKUP(SelectedTeam&MetaBaseYear,tbl_team_salary_warehouse[team_code]&tbl_team_salary_warehouse[salary_year],tbl_team_salary_warehouse[two_way_row_count])",
        fmts["kpi_value"],
    )

    worksheet.write(r, COL_SAL_Y1, "TOTAL", fmts["kpi_label"])
    worksheet.write_formula(r, COL_PCT_Y1, "=ScnCapTotalFilled0", fmts["kpi_money"])
    workbook.define_name(
        "TeamTotal",
        f"=PLAYGROUND!${col_letter(COL_PCT_Y1)}${r + 1}",
    )

    worksheet.write(r, COL_SAL_Y2, "CAP", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_PCT_Y2,
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])-ScnCapTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    worksheet.write(r, COL_SAL_Y3, "TAX", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_PCT_Y3,
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_level_amount])-ScnTaxTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    worksheet.write(r, COL_SAL_Y4, "APR1", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_PCT_Y4,
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount])-ScnApronTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    worksheet.write(r, COL_SAL_Y5, "APR2", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_PCT_Y5,
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron2_amount])-ScnApronTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    # KPI conditional formatting (green if >=0, red if <0)
    for col in [COL_PCT_Y2, COL_PCT_Y3, COL_PCT_Y4, COL_PCT_Y5]:
        cell = f"{col_letter(col)}{r + 1}"
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["kpi_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["kpi_delta_neg"]})

    # ---------------------------------------------------------------------
    # Row 3: Roster headers
    # ---------------------------------------------------------------------
    worksheet.write(ROW_HEADER, COL_RANK, "#", fmts["header_right"])
    worksheet.write(ROW_HEADER, COL_PLAYER, "Player", fmts["header"])

    # Year columns (labels like 25-26, 26-27, ... derived from MetaBaseYear)
    def year_label(off: int) -> str:
        return (
            "=TEXT(MOD(MetaBaseYear+{o},100),\"00\")&\"-\"&TEXT(MOD(MetaBaseYear+{o1},100),\"00\")".format(
                o=off,
                o1=off + 1,
            )
        )

    worksheet.write_formula(ROW_HEADER, COL_SAL_Y0, year_label(0), fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_PCT_Y0, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y1, year_label(1), fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_PCT_Y1, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y2, year_label(2), fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_PCT_Y2, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y3, year_label(3), fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_PCT_Y3, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y4, year_label(4), fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_PCT_Y4, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y5, year_label(5), fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_PCT_Y5, "%", fmts["header_right"])

    worksheet.write(ROW_HEADER, COL_TOTAL, "Total", fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_AGENT, "Agent", fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_STATUS, "Status", fmts["header"])
