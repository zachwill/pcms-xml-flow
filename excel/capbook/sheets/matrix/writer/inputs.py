"""MATRIX trade input zones (outgoing/incoming players) + per-team summaries."""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import (
    TRADE_ALLOWED_ROW,
    TRADE_INPUT_ROWS,
    TRADE_INPUT_START_ROW,
    TRADE_STATUS_ROW,
    TRADE_TOTAL_ROW,
    TEAM_BLOCKS,
    col_letter,
)


def _quote_sheet(sheet_name: str) -> str:
    return "'" + sheet_name.replace("'", "''") + "'"


def write_trade_inputs(
    workbook: Workbook,
    worksheet: Worksheet,
    fmts: dict[str, Any],
    *,
    salary_book_warehouse_nrows: int,
) -> None:
    """Write the trade input blocks for all 4 teams."""

    sheet_name = worksheet.get_name()
    sheet_ref = _quote_sheet(sheet_name)

    # Player list for data validation dropdowns.
    sbw_rows = max(int(salary_book_warehouse_nrows), 1)
    sbw_end = sbw_rows + 1  # header is row 1; data starts at row 2
    player_list_source = f"=DATA_salary_book_warehouse!$B$2:$B${sbw_end}"

    # Header row (Excel row 3): section labels for each team block
    header_row = TRADE_INPUT_START_ROW - 1

    for tb in TEAM_BLOCKS:
        worksheet.write(header_row, tb.trade.out_name_col, "Buildup Out:", fmts["trade_header"])
        worksheet.write(header_row, tb.trade.out_cap_col, "Cap", fmts["trade_header"])
        worksheet.write(header_row, tb.trade.in_name_col, "Buildup In:", fmts["trade_header"])
        worksheet.write(header_row, tb.trade.in_cap_col, "Cap", fmts["trade_header"])

    # Input rows
    for tb in TEAM_BLOCKS:
        out_start = TRADE_INPUT_START_ROW
        out_end = TRADE_INPUT_START_ROW + TRADE_INPUT_ROWS - 1

        in_start = TRADE_INPUT_START_ROW
        in_end = TRADE_INPUT_START_ROW + TRADE_INPUT_ROWS - 1

        # Outgoing name inputs
        for r in range(out_start, out_end + 1):
            worksheet.write(r, tb.trade.out_name_col, "", fmts["input"])
            worksheet.data_validation(
                r,
                tb.trade.out_name_col,
                r,
                tb.trade.out_name_col,
                {"validate": "list", "source": player_list_source},
            )

        # Incoming name inputs
        for r in range(in_start, in_end + 1):
            worksheet.write(r, tb.trade.in_name_col, "", fmts["input"])
            worksheet.data_validation(
                r,
                tb.trade.in_name_col,
                r,
                tb.trade.in_name_col,
                {"validate": "list", "source": player_list_source},
            )

        # Define ranges (worksheet-scoped)
        out_col = col_letter(tb.trade.out_name_col)
        in_col = col_letter(tb.trade.in_name_col)

        out_rng = f"${out_col}${out_start + 1}:${out_col}${out_end + 1}"
        in_rng = f"${in_col}${in_start + 1}:${in_col}${in_end + 1}"

        workbook.define_name(
            f"{sheet_name}!MxT{tb.idx}OutNames",
            f"={sheet_ref}!{out_rng}",
        )
        workbook.define_name(
            f"{sheet_name}!MxT{tb.idx}InNames",
            f"={sheet_ref}!{in_rng}",
        )

        # Spilled cap columns (computed from the input ranges)
        team_code_name = f"MxTeam{tb.idx}Code"

        worksheet.write_dynamic_array_formula(
            TRADE_INPUT_START_ROW,
            tb.trade.out_cap_col,
            TRADE_INPUT_START_ROW,
            tb.trade.out_cap_col,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{tb.idx}OutNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="cap_amount",
            ),
            fmts["trade_value"],
        )

        worksheet.write_dynamic_array_formula(
            TRADE_INPUT_START_ROW,
            tb.trade.in_cap_col,
            TRADE_INPUT_START_ROW,
            tb.trade.in_cap_col,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{tb.idx}InNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="incoming_cap_amount",
            ),
            fmts["trade_value"],
        )

        # ------------------------------------------------------------------
        # Per-team summary rows (totals, allowed, works)
        # ------------------------------------------------------------------

        worksheet.write(TRADE_TOTAL_ROW, tb.trade.out_name_col, "Outgoing", fmts["trade_label"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}OutCapTotal", fmts["trade_value"])

        worksheet.write(TRADE_TOTAL_ROW, tb.trade.in_name_col, "Incoming", fmts["trade_label"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.in_cap_col, f"=MxT{tb.idx}InCapTotal", fmts["trade_value"])

        worksheet.write(TRADE_ALLOWED_ROW, tb.trade.out_name_col, "Allowed In", fmts["trade_label"])
        worksheet.write_formula(TRADE_ALLOWED_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}AllowedInCap", fmts["trade_value"])

        worksheet.write(TRADE_STATUS_ROW, tb.trade.out_name_col, "Works?", fmts["trade_label"])
        worksheet.write_formula(TRADE_STATUS_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}Works", fmts["trade_status"])
