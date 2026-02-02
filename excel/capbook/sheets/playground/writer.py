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
    ROW_BASE,
    ROW_BODY_START,
    ROW_HEADER,
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
    *,
    calc_worksheet: Worksheet,
    base_year: int = 2025,
) -> None:
    """Write the PLAYGROUND sheet."""

    fmts = create_playground_formats(workbook, formats_shared)

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

    # Salaries and % of cap (4-year slice)
    # NOTE: % columns are widened to 10 so KPI money values (row 1) fit
    worksheet.set_column(COL_SAL_Y0, COL_SAL_Y0, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y0, COL_PCT_Y0, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y1, COL_SAL_Y1, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y1, COL_PCT_Y1, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y2, COL_SAL_Y2, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y2, COL_PCT_Y2, 10, fmts["pct"])
    worksheet.set_column(COL_SAL_Y3, COL_SAL_Y3, 10, fmts["money_m"])
    worksheet.set_column(COL_PCT_Y3, COL_PCT_Y3, 10, fmts["pct"])

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

    # KPIs on row 1 (starting at COL_RANK)
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

    worksheet.write(r, COL_TOTAL, "APR1", fmts["kpi_label"])
    worksheet.write_formula(
        r,
        COL_AGENT,
        "=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount])-ScnApronTotalFilled0",
        fmts["kpi_delta_pos"],
    )

    # KPI conditional formatting (green if >=0, red if <0)
    for col in [COL_PCT_Y2, COL_PCT_Y3, COL_AGENT]:
        cell = f"{col_letter(col)}{r + 1}"
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["kpi_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["kpi_delta_neg"]})

    # ---------------------------------------------------------------------
    # Scenario calculations (CALC sheet) + stable defined names
    #
    # Excel appears to warn/repair when workbook-level <definedName> formulas
    # contain dynamic-array functions like UNIQUE/FILTER/MAP.
    #
    # Workaround: write the complex formulas into hidden CALC cells, then
    # define names as simple cell references (=CALC!$B$12).
    # ---------------------------------------------------------------------

    # Simple grid: each year offset gets its own row; each metric gets its own column.
    #
    #   Row:  off (0..3)
    #   Cols:
    #     B=RosterCount
    #     C=CapTotal
    #     D=TaxTotal
    #     E=ApronTotal
    #     F=DeadMoney
    #     G=RookieFillCount (fill-to-12)
    #     H=VetFillCount (fill-to-14)
    #     I=ProrationFactor (base year only)
    #     J=RookieMin (YOS 0)
    #     K=VetMin (YOS 2)
    #     L=RookieFillAmount
    #     M=VetFillAmount
    #     N=FillAmount
    #     O=CapTotalFilled
    #     P=TaxTotalFilled
    #     Q=ApronTotalFilled
    #     R=TaxPayment

    calc_worksheet.write(0, 1, "ScnRosterCount")
    calc_worksheet.write(0, 2, "ScnCapTotal")
    calc_worksheet.write(0, 3, "ScnTaxTotal")
    calc_worksheet.write(0, 4, "ScnApronTotal")
    calc_worksheet.write(0, 5, "ScnDeadMoney")

    calc_worksheet.write(0, 6, "ScnRookieFillCount")
    calc_worksheet.write(0, 7, "ScnVetFillCount")
    calc_worksheet.write(0, 8, "ScnProrationFactor")

    calc_worksheet.write(0, 9, "ScnRookieMin")
    calc_worksheet.write(0, 10, "ScnVetMin")

    calc_worksheet.write(0, 11, "ScnRookieFillAmount")
    calc_worksheet.write(0, 12, "ScnVetFillAmount")
    calc_worksheet.write(0, 13, "ScnFillAmount")

    calc_worksheet.write(0, 14, "ScnCapTotalFilled")
    calc_worksheet.write(0, 15, "ScnTaxTotalFilled")
    calc_worksheet.write(0, 16, "ScnApronTotalFilled")
    calc_worksheet.write(0, 17, "ScnTaxPayment")

    def _define_calc_name(name: str, row0: int, col0: int, formula: str) -> None:
        # Write the scalar formula into CALC.
        calc_worksheet.write_formula(row0, col0, formula)
        # Define name as a pure cell reference.
        colA = col_letter(col0)
        workbook.define_name(name, f"=CALC!${colA}${row0 + 1}")

    for off in YEAR_OFFSETS:
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        r0 = 1 + off

        # Base scenario metrics
        _define_calc_name(f"ScnRosterCount{off}", r0, 1, formulas.scenario_roster_count(year_expr=year_expr))
        _define_calc_name(f"ScnCapTotal{off}", r0, 2, formulas.scenario_team_total(year_expr=year_expr, year_offset=off))
        _define_calc_name(f"ScnTaxTotal{off}", r0, 3, formulas.scenario_tax_total(year_expr=year_expr, year_offset=off))
        _define_calc_name(f"ScnApronTotal{off}", r0, 4, formulas.scenario_apron_total(year_expr=year_expr, year_offset=off))
        _define_calc_name(f"ScnDeadMoney{off}", r0, 5, formulas.scenario_dead_money(year_expr=year_expr))

        # Roster fill semantics:
        # - fill-to-12 at rookie min (YOS 0)
        # - fill-to-14 at vet min (YOS 2)
        _define_calc_name(f"ScnRookieFillCount{off}", r0, 6, f"=MAX(0,12-ScnRosterCount{off})")
        _define_calc_name(f"ScnVetFillCount{off}", r0, 7, f"=MAX(0,14-ScnRosterCount{off})-ScnRookieFillCount{off}")

        # Base-year-only fill proration: days_remaining / days_in_season.
        if off == 0:
            _define_calc_name(
                f"ScnProrationFactor{off}",
                r0,
                8,
                "=LET("  # noqa: ISC003
                "_xlpm.y,MetaBaseYear,"
                "_xlpm.asof,DATEVALUE(MetaAsOfDate),"
                "_xlpm.end,IFERROR(XLOOKUP(_xlpm.y,tbl_system_values[salary_year],tbl_system_values[season_end_at]),0),"
                "_xlpm.d,IFERROR(XLOOKUP(_xlpm.y,tbl_system_values[salary_year],tbl_system_values[days_in_season]),0),"
                "_xlpm.rem,MAX(0,MIN(_xlpm.d,INT(_xlpm.end-_xlpm.asof+1))),"
                "IF(OR(_xlpm.end=0,_xlpm.d=0),1,_xlpm.rem/_xlpm.d)"
                ")",
            )
        else:
            _define_calc_name(f"ScnProrationFactor{off}", r0, 8, "=1")

        # Minimum salaries
        _define_calc_name(
            f"ScnRookieMin{off}",
            r0,
            9,
            f"=XLOOKUP(({year_expr})&0,tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount])",
        )
        _define_calc_name(
            f"ScnVetMin{off}",
            r0,
            10,
            f"=XLOOKUP(({year_expr})&2,tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount])",
        )

        # Fill amounts
        _define_calc_name(
            f"ScnRookieFillAmount{off}",
            r0,
            11,
            f"=ScnRookieFillCount{off}*ScnRookieMin{off}*ScnProrationFactor{off}",
        )
        _define_calc_name(
            f"ScnVetFillAmount{off}",
            r0,
            12,
            f"=ScnVetFillCount{off}*ScnVetMin{off}*ScnProrationFactor{off}",
        )
        _define_calc_name(f"ScnFillAmount{off}", r0, 13, f"=ScnRookieFillAmount{off}+ScnVetFillAmount{off}")

        # Filled totals (layer-aware)
        _define_calc_name(f"ScnCapTotalFilled{off}", r0, 14, f"=ScnCapTotal{off}+ScnFillAmount{off}")
        _define_calc_name(f"ScnTaxTotalFilled{off}", r0, 15, f"=ScnTaxTotal{off}+ScnFillAmount{off}")
        _define_calc_name(f"ScnApronTotalFilled{off}", r0, 16, f"=ScnApronTotal{off}+ScnFillAmount{off}")

        # Luxury tax payment (progressive via tbl_tax_rates)
        _define_calc_name(
            f"ScnTaxPayment{off}",
            r0,
            17,
            "=LET("  # noqa: ISC003
            f"_xlpm.y,{year_expr},"
            "_xlpm.taxLvl,IFERROR(XLOOKUP(_xlpm.y,tbl_system_values[salary_year],tbl_system_values[tax_level_amount]),0),"
            f"_xlpm.over,MAX(0,ScnTaxTotalFilled{off}-_xlpm.taxLvl),"
            "_xlpm.isRep,IFERROR(XLOOKUP(SelectedTeam&_xlpm.y,tbl_team_salary_warehouse[team_code]&tbl_team_salary_warehouse[salary_year],tbl_team_salary_warehouse[is_repeater_taxpayer],FALSE),FALSE),"
            "_xlpm.lower,IF(_xlpm.over=0,0,MAXIFS(tbl_tax_rates[lower_limit],tbl_tax_rates[salary_year],_xlpm.y,tbl_tax_rates[lower_limit],\"<=\"&_xlpm.over)),"
            "_xlpm.key,_xlpm.y&\"|\"&_xlpm.lower,"
            "_xlpm.rate,IF(_xlpm.over=0,0,XLOOKUP(_xlpm.key,tbl_tax_rates[salary_year]&\"|\"&tbl_tax_rates[lower_limit],IF(_xlpm.isRep,tbl_tax_rates[tax_rate_repeater],tbl_tax_rates[tax_rate_non_repeater]),0)),"
            "_xlpm.base,IF(_xlpm.over=0,0,XLOOKUP(_xlpm.key,tbl_tax_rates[salary_year]&\"|\"&tbl_tax_rates[lower_limit],IF(_xlpm.isRep,tbl_tax_rates[base_charge_repeater],tbl_tax_rates[base_charge_non_repeater]),0)),"
            "IF(_xlpm.over=0,0,_xlpm.base+(_xlpm.over-_xlpm.lower)*_xlpm.rate)"
            ")",
        )

    # ---------------------------------------------------------------------
    # Row 3: Roster headers
    # ---------------------------------------------------------------------
    worksheet.write(ROW_HEADER, COL_RANK, "#", fmts["header_right"])
    worksheet.write(ROW_HEADER, COL_PLAYER, "Player", fmts["header"])

    # Year columns (labels like 25-26, 26-27, ... derived from MetaBaseYear)
    year_label = lambda off: (
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

    worksheet.write(ROW_HEADER, COL_TOTAL, "Total", fmts["header_center"])
    worksheet.write(ROW_HEADER, COL_AGENT, "Agent", fmts["header_center"])
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
        formulas.sum_names_salary_yearly(
            "TradeInNames",
            year_expr="MetaBaseYear",
            team_scoped=False,
            salary_col="incoming_cap_amount",
        ),
        fmts["trade_value"],
    )
    workbook.define_name("TradeInSalary", f"=PLAYGROUND!$B${input_row + 1}")
    input_row += 1

    # Post-trade apron total for SelectedTeam (baseline - outgoing + incoming)
    out_apron_expr = formulas._as_expr(
        formulas.sum_names_salary_yearly(
            "TradeOutNames",
            year_expr="MetaBaseYear",
            team_scoped=True,
            salary_col="outgoing_apron_amount",
        )
    )
    in_apron_expr = formulas._as_expr(
        formulas.sum_names_salary_yearly(
            "TradeInNames",
            year_expr="MetaBaseYear",
            team_scoped=False,
            salary_col="incoming_apron_amount",
        )
    )

    worksheet.write(input_row, COL_SECTION_LABEL, "Apron Post:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        "=LET("  # noqa: ISC003
        "_xlpm.base,"
        "XLOOKUP(SelectedTeam&MetaBaseYear,"
        "tbl_team_salary_warehouse[team_code]&tbl_team_salary_warehouse[salary_year],"
        "tbl_team_salary_warehouse[apron_total]),"
        f"_xlpm.out,{out_apron_expr},"
        f"_xlpm.in,{in_apron_expr},"
        "_xlpm.base-_xlpm.out+_xlpm.in"
        ")",
        fmts["trade_value"],
    )
    workbook.define_name("TradePostApronTotal", f"=PLAYGROUND!$B${input_row + 1}")
    input_row += 1

    # 250K padding is removed if post-trade apron total exceeds the First Apron.
    worksheet.write(input_row, COL_SECTION_LABEL, "Pad:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        "=LET("  # noqa: ISC003
        "_xlpm.first,IFERROR(XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount]),0),"
        "IF(_xlpm.first=0,250000,IF(TradePostApronTotal>_xlpm.first,0,250000))"
        ")",
        fmts["trade_value"],
    )
    workbook.define_name("TradePadAmount", f"=PLAYGROUND!$B${input_row + 1}")
    input_row += 1

    # Max incoming (Expanded matching; matches pcms.fn_tpe_trade_math semantics)
    worksheet.write(input_row, COL_SECTION_LABEL, "Max:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        "=LET("  # noqa: ISC003
        "_xlpm.out,TradeOutSalary,"
        "_xlpm.tpe,IFERROR(XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tpe_dollar_allowance]),0),"
        "_xlpm.pad,TradePadAmount,"
        "IF(_xlpm.out=0,0,"
        "MAX("
        "MIN(_xlpm.out*2+_xlpm.pad,_xlpm.out+_xlpm.tpe),"
        "ROUNDUP(_xlpm.out*1.25,0)+_xlpm.pad"
        ")"
        ")"
        ")",
        fmts["trade_value"],
    )
    workbook.define_name("TradeMaxIncoming", f"=PLAYGROUND!$B${input_row + 1}")
    input_row += 1

    worksheet.write(input_row, COL_SECTION_LABEL, "Rem:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        "=TradeMaxIncoming-TradeInSalary",
        fmts["trade_value"],
    )
    rem_cell = f"B{input_row + 1}"
    worksheet.conditional_format(rem_cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["trade_delta_pos"]})
    worksheet.conditional_format(rem_cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["trade_delta_neg"]})
    workbook.define_name("TradeRemaining", f"=PLAYGROUND!$B${input_row + 1}")
    input_row += 1

    worksheet.write(input_row, COL_SECTION_LABEL, "Legal:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        "=IF(TradeInSalary=0,\"—\",IF(TradeOutSalary=0,\"FAIL\",IF(TradeInSalary<=TradeMaxIncoming,\"PASS\",\"FAIL\")))",
        fmts["trade_status"],
    )
    status_cell = f"B{input_row + 1}"
    worksheet.conditional_format(status_cell, {"type": "formula", "criteria": f"={status_cell}=\"PASS\"", "format": fmts["trade_status_valid"]})
    worksheet.conditional_format(status_cell, {"type": "formula", "criteria": f"={status_cell}=\"FAIL\"", "format": fmts["trade_status_invalid"]})

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

    # Important: don't reference spill ranges with the UI operator `#`.
    # In stored formulas, use ANCHORARRAY(<anchor_cell>) per XlsxWriter docs.
    names_anchor = f"{col_letter(COL_PLAYER)}{roster_start + 1}"  # e.g. E4
    names_spill = f"ANCHORARRAY({names_anchor})"

    # Rank (D4 spill) - skips traded/waived/stretched players
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_RANK,
        roster_start,
        COL_RANK,
        formulas.roster_rank_column(names_spill=names_spill),
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
        sal_anchor = f"{col_letter(sal_col)}{roster_start + 1}"
        sal_arr = f"ANCHORARRAY({sal_anchor})"
        worksheet.write_dynamic_array_formula(
            roster_start,
            pct_col,
            roster_start,
            pct_col,
            f"=IFERROR({sal_arr}/{cap_level},0)",
            fmts["pct"],
        )

    # Total contract value (warehouse), fallback to visible years when missing.
    y0 = f"ANCHORARRAY({col_letter(COL_SAL_Y0)}{roster_start + 1})"
    y1 = f"ANCHORARRAY({col_letter(COL_SAL_Y1)}{roster_start + 1})"
    y2 = f"ANCHORARRAY({col_letter(COL_SAL_Y2)}{roster_start + 1})"
    y3 = f"ANCHORARRAY({col_letter(COL_SAL_Y3)}{roster_start + 1})"
    total_visible = f"IFERROR({y0}+{y1}+{y2}+{y3},0)"
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_TOTAL,
        roster_start,
        COL_TOTAL,
        "=LET("  # noqa: ISC003
        f"_xlpm.total,XLOOKUP({names_spill},tbl_salary_book_warehouse[player_name],tbl_salary_book_warehouse[total_salary_from_2025]),"
        f"_xlpm.visible,{total_visible},"
        "IFERROR(_xlpm.total,_xlpm.visible)"
        ")",
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

    # -------------------------------------------------------------------------
    # Trade restrictions conditional formatting (red)
    #
    # Web parity (SalaryBook):
    # - No-Trade Clause (is_no_trade): red in ALL seasons, but options can take
    #   visual precedence in future years.
    # - Player consent required now (is_trade_consent_required_now): red in the
    #   current season only and should override other coloring.
    # - Trade restricted now (is_trade_restricted_now): red in the current
    #   season only and should override other coloring.
    #
    # We avoid structured refs / XLOOKUP in conditional formatting to prevent
    # Excel "repair" warnings. We also avoid hardcoding column letters for the
    # boolean flags by using MATCH() against the header row.
    # -------------------------------------------------------------------------

    player_ref = f"${col_letter(COL_PLAYER)}{roster_start + 1}"  # e.g. $E4

    sbw_end = 5000
    sbw_hdr = "DATA_salary_book_warehouse!$1:$1"
    sbw_data = f"DATA_salary_book_warehouse!$A$2:$ZZ${sbw_end}"

    sbw_name = f'INDEX({sbw_data},0,MATCH("player_name",{sbw_hdr},0))'
    sbw_no_trade = f'INDEX({sbw_data},0,MATCH("is_no_trade",{sbw_hdr},0))'
    sbw_trade_bonus = f'INDEX({sbw_data},0,MATCH("is_trade_bonus",{sbw_hdr},0))'
    sbw_consent = f'INDEX({sbw_data},0,MATCH("is_trade_consent_required_now",{sbw_hdr},0))'
    sbw_trade_restricted = f'INDEX({sbw_data},0,MATCH("is_trade_restricted_now",{sbw_hdr},0))'

    # NOTE: salary_book_warehouse is 1 row per player. We match by player_name
    # only (no team_code filter) so trade-in rows still get correct styling.
    cond_no_trade = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_no_trade}=TRUE))>0"
    cond_trade_bonus = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_trade_bonus}=TRUE))>0"
    cond_consent = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_consent}=TRUE))>0"
    cond_trade_restricted = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_trade_restricted}=TRUE))>0"
    cond_restricted_now = f"OR({cond_consent},{cond_trade_restricted})"

    # -------------------------------------------------------------------------
    # Two-way salary display: show "Two-Way" (gray pill) instead of "-".
    #
    # IMPORTANT: Conditional formatting formulas have quirks (see options block
    # below). We avoid structured refs and XLOOKUP here.
    #
    # DATA_salary_book_yearly columns:
    #   B=player_name, C=team_code, D=salary_year, E=cap_amount, H=is_two_way
    #
    # Two-Way contracts can be 1 or 2 years. We must check that cap_amount is
    # not blank (NULL in DB = empty cell) to confirm an actual contract row
    # exists for that year. Otherwise we'd show the pill for projected years
    # where the player isn't actually under contract.
    # -------------------------------------------------------------------------
    data_end = 20000
    rng_name = f"DATA_salary_book_yearly!$B$2:$B${data_end}"
    rng_team = f"DATA_salary_book_yearly!$C$2:$C${data_end}"
    rng_year = f"DATA_salary_book_yearly!$D$2:$D${data_end}"
    rng_cap = f"DATA_salary_book_yearly!$E$2:$E${data_end}"
    rng_tw = f"DATA_salary_book_yearly!$H$2:$H${data_end}"

    trade_in_flag = f"COUNTIF(TradeInNames,{player_ref})>0"

    # NOTE: player_ref is defined above (used for both restriction + two-way logic)

    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]

        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"
        sal_cell = f"{col_letter(sal_col)}{roster_start + 1}"  # relative row in CF

        # Only apply when:
        #  - this salary cell is 0 (so we don't hide real numeric values)
        #  - the player is marked as two-way for the selected team or trade-ins + year
        #  - the player has a non-blank cap_amount for that year (i.e. actual contract)
        tw_cond_team = (
            f"SUMPRODUCT(({rng_team}=SelectedTeam)*({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_tw}=TRUE)*({rng_cap}<>\"\"))>0"
        )
        tw_cond_any = (
            f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_tw}=TRUE)*({rng_cap}<>\"\"))>0"
        )

        # Two-Way contracts can be trade restricted / consent-required in the current season.
        # In web/ we render the Two-Way badge red in that case; replicate here by using a
        # dedicated red pill format.
        if off == 0:
            worksheet.conditional_format(
                col_range,
                {
                    "type": "formula",
                    "criteria": f"=AND({sal_cell}=0,{tw_cond_any},{cond_restricted_now})",
                    "format": fmts["two_way_salary_restricted"],
                    "stop_if_true": True,
                },
            )

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({sal_cell}=0,{trade_in_flag},{tw_cond_any})",
                "format": fmts["two_way_salary_in"],
                "stop_if_true": True,
            },
        )

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({sal_cell}=0,{tw_cond_team})",
                "format": fmts["two_way_salary"],
                "stop_if_true": True,
            },
        )

    # -------------------------------------------------------------------------
    # Current-season trade restrictions (override other coloring)
    #
    # Applies ONLY to the base-year salary column. This matches web/ where
    # consent-required and trade-restricted flags are "current season" behavior.
    #
    # NOTE: Two-Way restricted players are handled above with a dedicated
    # two_way_salary_restricted pill so we preserve the "Two-Way" display.
    # -------------------------------------------------------------------------
    y0_range = f"{col_letter(COL_SAL_Y0)}{roster_start + 1}:{col_letter(COL_SAL_Y0)}{roster_end + 1}"
    worksheet.conditional_format(
        y0_range,
        {
            "type": "formula",
            "criteria": f"={cond_restricted_now}",
            "format": fmts["trade_restriction"],
            "stop_if_true": True,
        },
    )

    # -------------------------------------------------------------------------
    # Contract option conditional formatting (Team Option / Player Option)
    #
    # Web parity (PlayerRow.tsx): options ALWAYS take precedence visually over
    # no-trade in future seasons.
    #
    # IMPORTANT: Avoid structured refs / XLOOKUP in CF; use INDEX/MATCH with
    # absolute sheet references.
    # -------------------------------------------------------------------------

    for i, off in enumerate(YEAR_OFFSETS):
        # Skip base year - options already decided for current season
        if off == 0:
            continue

        year_num = base_year + off
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"

        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"

        # Only color true contract years (avoid tinting trailing '-' years).
        # NOTE: We don't team-scope this check; roster salary lookups aren't team-scoped.
        has_contract = f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_cap}<>\"\"))>0"

        # Option value from DATA_salary_book_warehouse (schema evolves; lookup by header name).
        opt_expr = f'INDEX({sbw_data},0,MATCH("option_{year_num}",{sbw_hdr},0))'

        has_team_option = f'SUMPRODUCT(({sbw_name}={player_ref})*({opt_expr}="TEAM"))>0'
        has_player_option = f'SUMPRODUCT(({sbw_name}={player_ref})*({opt_expr}="PLYR"))>0'

        # Team Option (TO) - purple
        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{has_team_option})",
                "format": fmts["option_team"],
                "stop_if_true": True,
            },
        )

        # Player Option (PO) - blue
        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{has_player_option})",
                "format": fmts["option_player"],
                "stop_if_true": True,
            },
        )

    # -------------------------------------------------------------------------
    # Trade kicker / trade bonus (orange)
    #
    # Matches web behavior at a high level:
    # - Only tint real contract years (avoid trailing '-' years)
    # - Options (PO/TO) should win (we add option CF above with stop_if_true)
    # - No-trade should win over this (we add no-trade CF below)
    # -------------------------------------------------------------------------
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"

        has_contract = f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_cap}<>\"\"))>0"

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{cond_trade_bonus})",
                "format": fmts["trade_kicker"],
            },
        )

    # -------------------------------------------------------------------------
    # No-Trade Clause (all seasons, but only for actual contract years)
    #
    # Must come AFTER option CF so options take precedence (Excel CF priority).
    # Also comes AFTER trade kicker so no-trade wins over orange.
    # -------------------------------------------------------------------------
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"

        has_contract = f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_cap}<>\"\"))>0"

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{cond_no_trade})",
                "format": fmts["trade_restriction"],
            },
        )

    # ---------------------------------------------------------------------
    # Totals block (scenario-adjusted) below roster
    # ---------------------------------------------------------------------
    # Totals block immediately after roster (just 1 row gap)
    totals_start = roster_end + 2

    row = totals_start

    worksheet.write(row, COL_PLAYER, "TOTALS (Scenario)", fmts["totals_section"])
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

    # Roster fill (Sean convention)
    worksheet.write(row, COL_PLAYER, "Fill (Rookie to 12)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnRookieFillAmount{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Fill (Vet to 14)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        worksheet.write_formula(row, col, f"=ScnVetFillAmount{off}", fmts["totals_value"])
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
