"""MATRIX trade input zones (outgoing/incoming players) + per-team summaries."""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import (
    TRADE_ALLOWED_ROW,
    TRADE_APRON1_ROOM_ROW,
    TRADE_APRON2_ROOM_ROW,
    TRADE_FILL12_ROW,
    TRADE_FILL14_ROW,
    TRADE_FILL_TOTAL_ROW,
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
        worksheet.write(header_row, tb.trade.out_tax_col, "Tax", fmts["trade_header"])
        worksheet.write(header_row, tb.trade.out_apron_col, "Apron", fmts["trade_header"])

        worksheet.write(header_row, tb.trade.in_name_col, "Buildup In:", fmts["trade_header"])
        worksheet.write(header_row, tb.trade.in_cap_col, "Cap", fmts["trade_header"])
        worksheet.write(header_row, tb.trade.in_tax_col, "Tax", fmts["trade_header"])
        worksheet.write(header_row, tb.trade.in_apron_col, "Apron", fmts["trade_header"])

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

        team_code_name = f"MxTeam{tb.idx}Code"

        # ------------------------------------------------------------------
        # Spilled amount columns (computed from the input ranges)
        # ------------------------------------------------------------------

        # Outgoing (team-scoped)
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
                team_scoped=True,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            TRADE_INPUT_START_ROW,
            tb.trade.out_tax_col,
            TRADE_INPUT_START_ROW,
            tb.trade.out_tax_col,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{tb.idx}OutNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="tax_amount",
                team_scoped=True,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            TRADE_INPUT_START_ROW,
            tb.trade.out_apron_col,
            TRADE_INPUT_START_ROW,
            tb.trade.out_apron_col,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{tb.idx}OutNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="outgoing_apron_amount",
                team_scoped=True,
            ),
            fmts["trade_value"],
        )

        # Incoming (league-wide)
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
                team_scoped=False,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            TRADE_INPUT_START_ROW,
            tb.trade.in_tax_col,
            TRADE_INPUT_START_ROW,
            tb.trade.in_tax_col,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{tb.idx}InNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="incoming_tax_amount",
                team_scoped=False,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            TRADE_INPUT_START_ROW,
            tb.trade.in_apron_col,
            TRADE_INPUT_START_ROW,
            tb.trade.in_apron_col,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{tb.idx}InNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="incoming_apron_amount",
                team_scoped=False,
            ),
            fmts["trade_value"],
        )

        # ------------------------------------------------------------------
        # Per-team summary rows (totals, allowed, posture)
        # ------------------------------------------------------------------

        worksheet.write(TRADE_TOTAL_ROW, tb.trade.out_name_col, "Outgoing", fmts["trade_label"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}OutCapTotal", fmts["trade_value"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.out_tax_col, f"=MxT{tb.idx}OutTaxTotal", fmts["trade_value"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.out_apron_col, f"=MxT{tb.idx}OutApronTotal", fmts["trade_value"])

        worksheet.write(TRADE_TOTAL_ROW, tb.trade.in_name_col, "Incoming", fmts["trade_label"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.in_cap_col, f"=MxT{tb.idx}InCapTotal", fmts["trade_value"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.in_tax_col, f"=MxT{tb.idx}InTaxTotal", fmts["trade_value"])
        worksheet.write_formula(TRADE_TOTAL_ROW, tb.trade.in_apron_col, f"=MxT{tb.idx}InApronTotal", fmts["trade_value"])

        worksheet.write(TRADE_ALLOWED_ROW, tb.trade.out_name_col, "Allowed In", fmts["trade_label"])
        worksheet.write_formula(TRADE_ALLOWED_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}AllowedInCap", fmts["trade_value"])

        worksheet.write(TRADE_STATUS_ROW, tb.trade.out_name_col, "Works?", fmts["trade_label"])
        worksheet.write_formula(TRADE_STATUS_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}Works", fmts["trade_status"])

        # Works cell badge styling (green/red)
        works_cell = f"{col_letter(tb.trade.out_cap_col)}{TRADE_STATUS_ROW + 1}"
        worksheet.conditional_format(
            works_cell,
            {"type": "formula", "criteria": f'={works_cell}="Yes"', "format": fmts["trade_status_valid"]},
        )
        worksheet.conditional_format(
            works_cell,
            {"type": "formula", "criteria": f'={works_cell}="No"', "format": fmts["trade_status_invalid"]},
        )

        # Fill posture (Sean convention, knobs live in Trade Details)
        worksheet.write(TRADE_FILL12_ROW, tb.trade.out_name_col, "Fill (to 12)", fmts["trade_label"])
        worksheet.write_formula(TRADE_FILL12_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}Fill12Amount", fmts["trade_value"])

        worksheet.write(TRADE_FILL14_ROW, tb.trade.out_name_col, "Fill (to 14)", fmts["trade_label"])
        worksheet.write_formula(TRADE_FILL14_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}Fill14Amount", fmts["trade_value"])

        worksheet.write(TRADE_FILL_TOTAL_ROW, tb.trade.out_name_col, "Fill Total", fmts["trade_label"])
        worksheet.write_formula(TRADE_FILL_TOTAL_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}FillAmount", fmts["trade_value"])

        # Apron room (post trade, with fill)
        worksheet.write(TRADE_APRON1_ROOM_ROW, tb.trade.out_name_col, "Apron1 Room", fmts["trade_label"])
        worksheet.write_formula(TRADE_APRON1_ROOM_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}RoomUnderApron1Post", fmts["trade_value"])

        worksheet.write(TRADE_APRON2_ROOM_ROW, tb.trade.out_name_col, "Apron2 Room", fmts["trade_label"])
        worksheet.write_formula(TRADE_APRON2_ROOM_ROW, tb.trade.out_cap_col, f"=MxT{tb.idx}RoomUnderApron2Post", fmts["trade_value"])

        # Conditional formatting: green if >=0, red if <0
        for rr in [TRADE_APRON1_ROOM_ROW, TRADE_APRON2_ROOM_ROW]:
            cell = f"{col_letter(tb.trade.out_cap_col)}{rr + 1}"
            worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["trade_delta_pos"]})
            worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["trade_delta_neg"]})
