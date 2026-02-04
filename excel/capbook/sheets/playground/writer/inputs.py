"""PLAYGROUND sheet left-rail inputs and trade math."""

from __future__ import annotations

from datetime import date, datetime
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
    base_year: int,
    salary_book_yearly_nrows: int,
    salary_book_warehouse_nrows: int,
    as_of: "date | None" = None,
) -> None:
    """Write the scenario input rail and trade math helpers."""

    # ---------------------------------------------------------------------
    # Left rail inputs (start at ROW_BODY_START)
    # ---------------------------------------------------------------------
    input_row = ROW_BODY_START

    sheet_name = worksheet.get_name()
    sheet_ref = "'" + sheet_name.replace("'", "''") + "'"

    # Player list for data validation dropdowns.
    #
    # Important UX: use the wide warehouse (1 row per player) so the dropdown is
    # not polluted by duplicate names across years.
    sbw_rows = max(int(salary_book_warehouse_nrows), 1)
    sbw_end = sbw_rows + 1  # header is row 1; data starts at row 2
    player_list_source = f"=DATA_salary_book_warehouse!$B$2:$B${sbw_end}"

    # Season labels for multi-year SIGN inputs.
    # Example (base_year=2025): ["25-26","26-27",...]
    season_labels = [
        f"{(base_year + off) % 100:02d}-{(base_year + off + 1) % 100:02d}" for off in range(6)
    ]

    # ---------------------------------------------------------------------
    # TRADE OUT
    # ---------------------------------------------------------------------
    worksheet.write(input_row, COL_SECTION_LABEL, "TRADE OUT", fmts["section"])
    input_row += 1
    trade_out_start = input_row
    for _ in range(TRADE_OUT_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    trade_out_end = input_row - 1
    workbook.define_name(
        f"{sheet_name}!TradeOutNames",
        f"={sheet_ref}!$B${trade_out_start + 1}:$B${trade_out_end + 1}",
    )

    input_row += 1

    # ---------------------------------------------------------------------
    # TRADE IN
    # ---------------------------------------------------------------------
    worksheet.write(input_row, COL_SECTION_LABEL, "TRADE IN", fmts["section"])
    input_row += 1
    trade_in_start = input_row
    for _ in range(TRADE_IN_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    trade_in_end = input_row - 1
    workbook.define_name(
        f"{sheet_name}!TradeInNames",
        f"={sheet_ref}!$B${trade_in_start + 1}:$B${trade_in_end + 1}",
    )

    input_row += 1

    # ---------------------------------------------------------------------
    # WAIVE
    # ---------------------------------------------------------------------
    worksheet.write(input_row, COL_SECTION_LABEL, "WAIVE", fmts["section"])
    input_row += 1
    waive_start = input_row
    for _ in range(WAIVE_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    waive_end = input_row - 1
    workbook.define_name(
        f"{sheet_name}!WaivedNames",
        f"={sheet_ref}!$B${waive_start + 1}:$B${waive_end + 1}",
    )

    input_row += 1

    # ---------------------------------------------------------------------
    # STRETCH
    # ---------------------------------------------------------------------
    worksheet.write(input_row, COL_SECTION_LABEL, "STRETCH", fmts["section"])
    input_row += 1
    stretch_start = input_row
    for _ in range(STRETCH_SLOTS):
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": player_list_source})
        input_row += 1
    stretch_end = input_row - 1
    workbook.define_name(
        f"{sheet_name}!StretchNames",
        f"={sheet_ref}!$B${stretch_start + 1}:$B${stretch_end + 1}",
    )

    input_row += 1

    # ---------------------------------------------------------------------
    # SIGN (multi-year)
    # ---------------------------------------------------------------------
    worksheet.write(input_row, COL_SECTION_LABEL, "SIGN", fmts["section"])
    input_row += 1
    sign_start = input_row

    # Default to *next* cap year for a better planning workflow.
    default_sign_season = season_labels[1] if len(season_labels) > 1 else season_labels[0]

    for _ in range(SIGN_SLOTS):
        # Season selector (Column A)
        worksheet.write(input_row, COL_SECTION_LABEL, default_sign_season, fmts["input_season"])
        worksheet.data_validation(
            input_row,
            COL_SECTION_LABEL,
            input_row,
            COL_SECTION_LABEL,
            {"validate": "list", "source": season_labels},
        )

        # Player name (Column B)
        worksheet.write(input_row, COL_INPUT, "", fmts["input"])
        worksheet.data_validation(
            input_row,
            COL_INPUT,
            input_row,
            COL_INPUT,
            {"validate": "list", "source": player_list_source},
        )

        # Salary input (Column C): allow numbers (15000000) or text like "15M".
        worksheet.write(input_row, COL_INPUT_SALARY, "", fmts["input_money"])
        input_row += 1

    sign_end = input_row - 1

    workbook.define_name(
        f"{sheet_name}!SignYears",
        f"={sheet_ref}!$A${sign_start + 1}:$A${sign_end + 1}",
    )
    workbook.define_name(
        f"{sheet_name}!SignNames",
        f"={sheet_ref}!$B${sign_start + 1}:$B${sign_end + 1}",
    )
    workbook.define_name(
        f"{sheet_name}!SignSalaries",
        f"={sheet_ref}!$C${sign_start + 1}:$C${sign_end + 1}",
    )

    input_row += 1

    # ---------------------------------------------------------------------
    # ROSTER FILL (pricing assumptions)
    # ---------------------------------------------------------------------
    worksheet.write(input_row, COL_SECTION_LABEL, "FILL", fmts["section"])
    input_row += 1

    # Fill pricing "trade" date. Default to workbook as-of date (better UX than a formula).
    worksheet.write(input_row, COL_SECTION_LABEL, "Trade Date:", fmts["trade_label"])

    if as_of is None:
        # Fallback to META if not provided (should be rare).
        worksheet.write_formula(input_row, COL_INPUT, "=DATEVALUE(MetaAsOfDate)", fmts["input_date_right"])
    else:
        worksheet.write_datetime(input_row, COL_INPUT, datetime(as_of.year, as_of.month, as_of.day), fmts["input_date_right"])
    # Date validation:
    # Use *datetime objects* so XlsxWriter writes proper Excel serial date bounds.
    # (If we pass strings like "1990-01-01", Excel interprets them as math
    #  expressions (1990-1-1) and rejects modern dates.)
    worksheet.data_validation(
        input_row,
        COL_INPUT,
        input_row,
        COL_INPUT,
        {
            "validate": "date",
            "criteria": "between",
            "minimum": datetime(1990, 1, 1),
            "maximum": datetime(2100, 12, 31),
        },
    )
    workbook.define_name(
        f"{sheet_name}!FillEventDate",
        f"={sheet_ref}!$B${input_row + 1}",
    )
    input_row += 1

    # Fill-to-12 minimum type (rookie vs vet). Default: ROOKIE.
    worksheet.write(input_row, COL_SECTION_LABEL, "To 12:", fmts["trade_label"])
    worksheet.write(input_row, COL_INPUT, "ROOKIE", fmts["input_right"])
    worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": ["ROOKIE", "VET"]})
    workbook.define_name(
        f"{sheet_name}!FillTo12MinType",
        f"={sheet_ref}!$B${input_row + 1}",
    )
    input_row += 1

    # Fill-to-14 minimum type. Default: VET.
    worksheet.write(input_row, COL_SECTION_LABEL, "To 14:", fmts["trade_label"])
    worksheet.write(input_row, COL_INPUT, "VET", fmts["input_right"])
    worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": ["VET", "ROOKIE"]})
    workbook.define_name(
        f"{sheet_name}!FillTo14MinType",
        f"={sheet_ref}!$B${input_row + 1}",
    )
    input_row += 1

    # Delay to 14: for pricing the fill-to-14 minimums (Matrix-style +14 supported).
    # UX: dropdown labels like "Immediate", "1 Day", ..., "14 Days".
    worksheet.write(input_row, COL_SECTION_LABEL, "Delay To 14:", fmts["trade_label"])
    delay_opts = ["Immediate"] + ["1 Day"] + [f"{d} Days" for d in range(2, 15)]
    worksheet.write(input_row, COL_INPUT, "14 Days", fmts["input_right"])
    worksheet.data_validation(input_row, COL_INPUT, input_row, COL_INPUT, {"validate": "list", "source": delay_opts})
    workbook.define_name(
        f"{sheet_name}!FillDelayDays",
        f"={sheet_ref}!$B${input_row + 1}",
    )
    input_row += 1

    input_row += 1

    # ---------------------------------------------------------------------
    # TRADE MATH (base year)
    # ---------------------------------------------------------------------
    worksheet.write(input_row, COL_SECTION_LABEL, "TRADE MATH", fmts["section"])
    input_row += 1

    worksheet.write(input_row, COL_SECTION_LABEL, "Out:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        formulas.sum_names_salary_yearly("TradeOutNames", year_expr="MetaBaseYear", team_scoped=True),
        fmts["trade_value"],
    )
    workbook.define_name(
        f"{sheet_name}!TradeOutSalary",
        f"={sheet_ref}!$B${input_row + 1}",
    )
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
    workbook.define_name(
        f"{sheet_name}!TradeInSalary",
        f"={sheet_ref}!$B${input_row + 1}",
    )
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
    workbook.define_name(
        f"{sheet_name}!TradePostApronTotal",
        f"={sheet_ref}!$B${input_row + 1}",
    )
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
    workbook.define_name(
        f"{sheet_name}!TradePadAmount",
        f"={sheet_ref}!$B${input_row + 1}",
    )
    input_row += 1

    # Max incoming:
    # - Under the First Apron: expanded matching (2x / +TPE / 125% + padding)
    # - Over the First Apron ("apron team" for matching): 1:1 (can only take back 100%)
    #
    # This aligns with Sean's Machine / Matrix behavior and fixes cases where an
    # apron team incorrectly appears to have +TPE headroom.
    worksheet.write(input_row, COL_SECTION_LABEL, "Max:", fmts["trade_label"])
    worksheet.write_formula(
        input_row,
        COL_INPUT,
        "=LET("  # noqa: ISC003
        "_xlpm.out,TradeOutSalary,"
        "_xlpm.tpe,IFERROR(XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tpe_dollar_allowance]),0),"
        "_xlpm.pad,TradePadAmount,"
        "_xlpm.first,IFERROR(XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount]),0),"
        "_xlpm.isApron,IF(_xlpm.first=0,FALSE,TradePostApronTotal>_xlpm.first),"
        "IF(_xlpm.out=0,0,"
        "IF(_xlpm.isApron,"
        "_xlpm.out,"
        "MAX("
        "MIN(_xlpm.out*2+_xlpm.pad,_xlpm.out+_xlpm.tpe),"
        "ROUNDUP(_xlpm.out*1.25,0)+_xlpm.pad"
        ")"
        ")"
        ")"
        ")",
        fmts["trade_value"],
    )
    workbook.define_name(
        f"{sheet_name}!TradeMaxIncoming",
        f"={sheet_ref}!$B${input_row + 1}",
    )
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
    workbook.define_name(
        f"{sheet_name}!TradeRemaining",
        f"={sheet_ref}!$B${input_row + 1}",
    )
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
