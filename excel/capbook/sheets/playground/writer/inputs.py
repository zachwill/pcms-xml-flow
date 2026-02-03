"""PLAYGROUND sheet left-rail inputs and trade math."""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import (
    COL_INPUT,
    COL_INPUT_SALARY,
    COL_SECTION_LABEL,
    ROW_BODY_START,
    SIGN_SLOTS,
    STRETCH_SLOTS,
    TRADE_IN_SLOTS,
    TRADE_OUT_SLOTS,
    WAIVE_SLOTS,
)


def write_inputs(
    workbook: Workbook,
    worksheet: Worksheet,
    fmts: dict[str, Any],
    *,
    salary_book_yearly_nrows: int,
) -> None:
    """Write the scenario input rail and trade math helpers."""

    # ---------------------------------------------------------------------
    # Left rail inputs (start at ROW_BODY_START)
    # ---------------------------------------------------------------------
    input_row = ROW_BODY_START

    # Player list for data validation dropdowns.
    #
    # Use the *actual* extracted table size instead of hard-coded headroom.
    # Large fixed ranges slow down recalculation and conditional formatting.
    yearly_rows = max(int(salary_book_yearly_nrows), 1)
    player_list_end = yearly_rows + 1  # header is row 1; data starts at row 2
    player_list_source = f"=DATA_salary_book_yearly!$B$2:$B${player_list_end}"

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
    out_apron_expr = formulas.as_expr(
        formulas.sum_names_salary_yearly(
            "TradeOutNames",
            year_expr="MetaBaseYear",
            team_scoped=True,
            salary_col="outgoing_apron_amount",
        )
    )
    in_apron_expr = formulas.as_expr(
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
