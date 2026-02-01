"""PLAYGROUND sheet writer.

This sheet is the dense, reactive working surface.

Authoritative UI spec: excel/UI.md
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from . import formulas
from .formats import create_playground_formats
from .layout import (
    COL_AGENT,
    COL_INPUT,
    COL_INPUT_SALARY,
    COL_PCT_Y0,
    COL_PCT_Y1,
    COL_PCT_Y2,
    COL_PCT_Y3,
    COL_PLAYER,
    COL_RANK,
    COL_SAL_Y0,
    COL_SAL_Y1,
    COL_SAL_Y2,
    COL_SAL_Y3,
    COL_SECTION_LABEL,
    COL_STATUS,
    COL_TOTAL,
    ROSTER_RESERVED,
    ROW_BODY_START,
    ROW_HEADER,
    ROW_KPI,
    ROW_TEAM_CONTEXT,
    SIGN_SLOTS,
    STRETCH_SLOTS,
    TRADE_IN_SLOTS,
    TRADE_OUT_SLOTS,
    WAIVE_SLOTS,
    YEAR_OFFSETS,
    col_letter,
)


def write_playground_sheet(
    workbook: Workbook,
    worksheet: Worksheet,
    formats_shared: dict[str, Any],
    team_codes: list[str],
) -> None:
    """Write the PLAYGROUND sheet."""

    fmts = create_playground_formats(workbook, formats_shared)

    # ---------------------------------------------------------------------
    # Columns (dense defaults)
    # ---------------------------------------------------------------------
    worksheet.set_column(COL_SECTION_LABEL, COL_SECTION_LABEL, 10)
    worksheet.set_column(COL_INPUT, COL_INPUT, 18)
    worksheet.set_column(COL_INPUT_SALARY, COL_INPUT_SALARY, 12)

    worksheet.set_column(COL_RANK, COL_RANK, 4)
    worksheet.set_column(COL_PLAYER, COL_PLAYER, 20)

    # Salaries and % of cap (4-year slice)
    worksheet.set_column(COL_SAL_Y0, COL_SAL_Y0, 10)
    worksheet.set_column(COL_PCT_Y0, COL_PCT_Y0, 6)
    worksheet.set_column(COL_SAL_Y1, COL_SAL_Y1, 10)
    worksheet.set_column(COL_PCT_Y1, COL_PCT_Y1, 6)
    worksheet.set_column(COL_SAL_Y2, COL_SAL_Y2, 10)
    worksheet.set_column(COL_PCT_Y2, COL_PCT_Y2, 6)
    worksheet.set_column(COL_SAL_Y3, COL_SAL_Y3, 10)
    worksheet.set_column(COL_PCT_Y3, COL_PCT_Y3, 6)

    worksheet.set_column(COL_TOTAL, COL_TOTAL, 10)
    worksheet.set_column(COL_AGENT, COL_AGENT, 18)
    worksheet.set_column(COL_STATUS, COL_STATUS, 10)

    # ---------------------------------------------------------------------
    # Freeze panes: rows 1-3 and cols A-C
    # ---------------------------------------------------------------------
    worksheet.freeze_panes(ROW_HEADER + 1, COL_RANK)

    # ---------------------------------------------------------------------
    # Row 1: Team context
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

    workbook.define_name("SelectedTeam", "=PLAYGROUND!$B$1")

    # Context fields (not inputs)
    worksheet.write(ROW_TEAM_CONTEXT, COL_RANK, "Base", fmts["kpi_label"])
    worksheet.write_formula(ROW_TEAM_CONTEXT, COL_PLAYER, "=MetaBaseYear", fmts["kpi_value"])
    worksheet.write(ROW_TEAM_CONTEXT, COL_SAL_Y0, "As of", fmts["kpi_label"])
    worksheet.write_formula(ROW_TEAM_CONTEXT, COL_PCT_Y0, "=MetaAsOfDate", fmts["kpi_value"])

    # ---------------------------------------------------------------------
    # Define scenario named formulas (base + 3 years)
    # ---------------------------------------------------------------------
    for off in YEAR_OFFSETS:
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"

        workbook.define_name(f"ScnRosterCount{off}", formulas.scenario_roster_count(year_expr=year_expr))
        workbook.define_name(f"ScnCapTotal{off}", formulas.scenario_team_total(year_expr=year_expr, year_offset=off))
        workbook.define_name(f"ScnDeadMoney{off}", formulas.scenario_dead_money(year_expr=year_expr))

        # Fill to 14 (rookie min)
        workbook.define_name(f"ScnFillCount{off}", f"=MAX(0,14-ScnRosterCount{off})")
        workbook.define_name(
            f"ScnRookieMin{off}",
            f"=XLOOKUP(({year_expr})&0,tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount])",
        )
        workbook.define_name(f"ScnFillAmount{off}", f"=ScnFillCount{off}*ScnRookieMin{off}")
        workbook.define_name(f"ScnCapTotalFilled{off}", f"=ScnCapTotal{off}+ScnFillAmount{off}")

    # ---------------------------------------------------------------------
    # Row 2: KPI bar (scenario-adjusted, base year)
    # Layout pattern: label cell + value cell pairs.
    # ---------------------------------------------------------------------
    r = ROW_KPI

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
    workbook.define_name("TeamTotal", "=PLAYGROUND!$I$2")

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
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_level_amount])-ScnCapTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    worksheet.write(r, COL_TOTAL, "APR1", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_AGENT,
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount])-ScnCapTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    worksheet.write(r, COL_STATUS, "APR2", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_STATUS + 1,
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron2_amount])-ScnCapTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    # KPI conditional formatting (green if >=0, red if <0)
    for col in [COL_PCT_Y2, COL_PCT_Y3, COL_AGENT, COL_STATUS + 1]:
        cell = f"{col_letter(col)}{r + 1}"
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["kpi_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["kpi_delta_neg"]})

    # ---------------------------------------------------------------------
    # Row 3: Roster headers
    # ---------------------------------------------------------------------
    worksheet.write(ROW_HEADER, COL_RANK, "#", fmts["header"])
    worksheet.write(ROW_HEADER, COL_PLAYER, "Player", fmts["header"])

    # Year columns (labels like 25-26, 26-27, ... derived from MetaBaseYear)
    year_label = lambda off: (
        "=TEXT(MOD(MetaBaseYear+{o},100),\"00\")&\"-\"&TEXT(MOD(MetaBaseYear+{o1},100),\"00\")".format(
            o=off,
            o1=off + 1,
        )
    )

    worksheet.write_formula(ROW_HEADER, COL_SAL_Y0, year_label(0), fmts["header_right"])
    worksheet.write(ROW_HEADER, COL_PCT_Y0, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y1, year_label(1), fmts["header_right"])
    worksheet.write(ROW_HEADER, COL_PCT_Y1, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y2, year_label(2), fmts["header_right"])
    worksheet.write(ROW_HEADER, COL_PCT_Y2, "%", fmts["header_right"])
    worksheet.write_formula(ROW_HEADER, COL_SAL_Y3, year_label(3), fmts["header_right"])
    worksheet.write(ROW_HEADER, COL_PCT_Y3, "%", fmts["header_right"])

    worksheet.write(ROW_HEADER, COL_TOTAL, "Total", fmts["header_right"])
    worksheet.write(ROW_HEADER, COL_AGENT, "Agent", fmts["header"])
    worksheet.write(ROW_HEADER, COL_STATUS, "Status", fmts["header"])

    # ---------------------------------------------------------------------
    # Left rail inputs (start at ROW_BODY_START)
    # ---------------------------------------------------------------------
    input_row = ROW_BODY_START

    # Player list: use the yearly table name list (600 is arbitrary headroom).
    # Keep this large enough to cover league-wide rows in DATA_salary_book_yearly.
    player_list_source = "=DATA_salary_book_yearly!$B$2:$B$20000"

    # TRADE OUT
    worksheet.write(input_row, COL_SECTION_LABEL, "TRADE OUT", fmts["section"])
    input_row += 1
    trade_out_start = input_row
    for _ in range(TRADE_OUT_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    trade_out_end = input_row - 1
    workbook.define_name("TradeOutNames", f"=PLAYGROUND!$B${trade_out_start + 1}:$B${trade_out_end + 1}")

    input_row += 1

    # TRADE IN
    worksheet.write(input_row, COL_SECTION_LABEL, "TRADE IN", fmts["section"])
    input_row += 1
    trade_in_start = input_row
    for _ in range(TRADE_IN_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    trade_in_end = input_row - 1
    workbook.define_name("TradeInNames", f"=PLAYGROUND!$B${trade_in_start + 1}:$B${trade_in_end + 1}")

    input_row += 1

    # WAIVE
    worksheet.write(input_row, COL_SECTION_LABEL, "WAIVE", fmts["section"])
    input_row += 1
    waive_start = input_row
    for _ in range(WAIVE_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    waive_end = input_row - 1
    workbook.define_name("WaivedNames", f"=PLAYGROUND!$B${waive_start + 1}:$B${waive_end + 1}")

    input_row += 1

    # STRETCH
    worksheet.write(input_row, COL_SECTION_LABEL, "STRETCH", fmts["section"])
    input_row += 1
    stretch_start = input_row
    for _ in range(STRETCH_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    stretch_end = input_row - 1
    workbook.define_name("StretchNames", f"=PLAYGROUND!$B${stretch_start + 1}:$B${stretch_end + 1}")

    input_row += 1

    # SIGN (v1: base-year only)
    worksheet.write(input_row, COL_SECTION_LABEL, "SIGN", fmts["section"])
    input_row += 1
    sign_start = input_row
    for _ in range(SIGN_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.write(input_row, COL_INPUT_SALARY, "", fmts["input_money"])
        input_row += 1
    sign_end = input_row - 1
    workbook.define_name("SignNames", f"=PLAYGROUND!$B${sign_start + 1}:$B${sign_end + 1}")
    workbook.define_name("SignSalaries", f"=PLAYGROUND!$C${sign_start + 1}:$C${sign_end + 1}")

    input_row += 1

    # TRADE MATH (base year)
    worksheet.write(input_row, COL_SECTION_LABEL, "TRADE MATH", fmts["section"])
    input_row += 1

    worksheet.write(input_row, COL_SECTION_LABEL, "Out:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        formulas.sum_names_salary_yearly("TradeOutNames", year_expr="MetaBaseYear", team_scoped=True),
        fmts["trade_value"],
    )
    workbook.define_name("TradeOutSalary", f"=PLAYGROUND!$B${input_row + 1}")
    input_row += 1

    worksheet.write(input_row, COL_SECTION_LABEL, "In:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        formulas.sum_names_salary_yearly("TradeInNames", year_expr="MetaBaseYear", team_scoped=False),
        fmts["trade_value"],
    )
    workbook.define_name("TradeInSalary", f"=PLAYGROUND!$B${input_row + 1}")
    input_row += 1

    worksheet.write(input_row, COL_SECTION_LABEL, "Match:", fmts["trade_label"])
    worksheet.write_formula(input_row, COL_INPUT, '=IF(TradeOutSalary=0,"-",TEXT(TradeInSalary/TradeOutSalary,"0%"))')

    # ---------------------------------------------------------------------
    # Roster grid (reactive)
    # ---------------------------------------------------------------------
    roster_start = ROW_BODY_START
    roster_end = roster_start + ROSTER_RESERVED - 1

    # Names anchor (E4#)
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_PLAYER,
        roster_start,
        COL_PLAYER,
        formulas.roster_names_anchor(max_rows=ROSTER_RESERVED),
        fmts["player"],
    )

    names_spill = f"${col_letter(COL_PLAYER)}${roster_start + 1}#"  # e.g. $E$4#

    # Rank (D4#)
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_RANK,
        roster_start,
        COL_RANK,
        f"=SEQUENCE(ROWS({names_spill}))",
        fmts["rank"],
    )

    # Salaries Y0..Y3 and % columns
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"

        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        pct_col = [COL_PCT_Y0, COL_PCT_Y1, COL_PCT_Y2, COL_PCT_Y3][i]

        worksheet.write_dynamic_array_formula(
            roster_start,
            sal_col,
            roster_start,
            sal_col,
            formulas.roster_salary_column(names_spill=names_spill, year_expr=year_expr, year_offset=off),
            fmts["money_m"],
        )

        cap_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])"
        sal_spill = f"${col_letter(sal_col)}${roster_start + 1}#"
        worksheet.write_dynamic_array_formula(
            roster_start,
            pct_col,
            roster_start,
            pct_col,
            f"=IFERROR({sal_spill}/{cap_level},0)",
            fmts["pct"],
        )

    # Total across visible years
    y0 = f"${col_letter(COL_SAL_Y0)}${roster_start + 1}#"
    y1 = f"${col_letter(COL_SAL_Y1)}${roster_start + 1}#"
    y2 = f"${col_letter(COL_SAL_Y2)}${roster_start + 1}#"
    y3 = f"${col_letter(COL_SAL_Y3)}${roster_start + 1}#"
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_TOTAL,
        roster_start,
        COL_TOTAL,
        f"=IFERROR({y0}+{y1}+{y2}+{y3},0)",
        fmts["money_m"],
    )

    # Agent (best-effort, from warehouse wide table)
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_AGENT,
        roster_start,
        COL_AGENT,
        f"=MAP({names_spill},LAMBDA(_xlpm.p,IFERROR(XLOOKUP(_xlpm.p,tbl_salary_book_warehouse[player_name],tbl_salary_book_warehouse[agent_name],\"\"),\"\")))",
        fmts["agent"],
    )

    # Status
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_STATUS,
        roster_start,
        COL_STATUS,
        formulas.roster_status_column(names_spill=names_spill),
        fmts["player"],
    )

    roster_range = f"{col_letter(COL_RANK)}{roster_start + 1}:{col_letter(COL_STATUS)}{roster_end + 1}"

    # Conditional formatting by status source lists.
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(TradeOutNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_out"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(WaivedNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_waived"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(StretchNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_stretch"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(TradeInNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_in"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(SignNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_sign"]},
    )

    # ---------------------------------------------------------------------
    # Totals block (scenario-adjusted) below roster
    # ---------------------------------------------------------------------
    depth_rows = 6
    totals_start = roster_end + depth_rows + 3

    row = totals_start

    worksheet.write(row, COL_PLAYER, "TOTALS (Scenario)", fmts["totals_section"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write(row, col, f"Y{off}", fmts["totals_section"])
    row += 1

    # Scenario Team Total (cap_total)
    worksheet.write(row, COL_PLAYER, "Team Total (cap)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnCapTotal{off}", fmts["totals_value"])
    row += 1

    # Dead money
    worksheet.write(row, COL_PLAYER, "Dead Money", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnDeadMoney{off}", fmts["totals_value"])
    row += 1

    # Fill line
    worksheet.write(row, COL_PLAYER, "Fill to 14 (rookie min)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnFillAmount{off}", fmts["totals_value"])
    row += 1

    # Filled total
    worksheet.write(row, COL_PLAYER, "Team Total (filled)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnCapTotalFilled{off}", fmts["totals_value"])
    row += 1

    # Cap room
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

    # Tax room
    worksheet.write(row, COL_PLAYER, "Tax Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        tax_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[tax_level_amount])"
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={tax_level}-ScnCapTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 2

    # Placeholders
    worksheet.write(row, COL_PLAYER, "EXCEPTIONS", fmts["totals_section"])
    worksheet.write(row + 1, COL_PLAYER, "(coming soon)", fmts["placeholder"])
    row += 3

    worksheet.write(row, COL_PLAYER, "DRAFT PICKS", fmts["totals_section"])
    worksheet.write(row + 1, COL_PLAYER, "(coming soon)", fmts["placeholder"])
