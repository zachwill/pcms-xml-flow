"""MATRIX trade input zones (stacked v2).

Each team gets its own vertical section:
- Trade inputs (Outgoing / Incoming)
- Per-team summary rows (totals, allowed-in, legality, fill amounts)

Named ranges follow the v1 convention so the calc block can stay formula-based:
- MxT{n}OutNames / MxT{n}InNames
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import (
    COL_IN_APRON,
    COL_IN_CAP,
    COL_IN_NAME,
    COL_IN_TAX,
    COL_OUT_APRON,
    COL_OUT_CAP,
    COL_OUT_NAME,
    COL_OUT_TAX,
    TEAM_HDR_OFF,
    TEAM_INPUTS,
    TRADE_ALLOWED_OFF,
    TRADE_APRON1_ROOM_OFF,
    TRADE_APRON2_ROOM_OFF,
    TRADE_FILL12_OFF,
    TRADE_FILL14_OFF,
    TRADE_FILL_TOTAL_OFF,
    TRADE_HDR_OFF,
    TRADE_INPUT_OFF,
    TRADE_INPUT_ROWS,
    TRADE_STATUS_OFF,
    TRADE_TOTAL_OFF,
    team_row,
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
    """Write the trade input blocks for all teams (stacked vertically)."""

    sheet_name = worksheet.get_name()
    sheet_ref = _quote_sheet(sheet_name)

    # Player list for data validation dropdowns.
    sbw_rows = max(int(salary_book_warehouse_nrows), 1)
    sbw_end = sbw_rows + 1  # header is row 1; data starts at row 2
    player_list_source = f"=DATA_salary_book_warehouse!$B$2:$B${sbw_end}"

    for ti in TEAM_INPUTS:
        idx = ti.idx

        r_team_hdr = team_row(idx, TEAM_HDR_OFF)
        r_hdr = team_row(idx, TRADE_HDR_OFF)
        r_in_start = team_row(idx, TRADE_INPUT_OFF)
        r_in_end = r_in_start + TRADE_INPUT_ROWS - 1

        r_total = team_row(idx, TRADE_TOTAL_OFF)
        r_allowed = team_row(idx, TRADE_ALLOWED_OFF)
        r_status = team_row(idx, TRADE_STATUS_OFF)

        r_fill12 = team_row(idx, TRADE_FILL12_OFF)
        r_fill14 = team_row(idx, TRADE_FILL14_OFF)
        r_fill_total = team_row(idx, TRADE_FILL_TOTAL_OFF)
        r_apr1 = team_row(idx, TRADE_APRON1_ROOM_OFF)
        r_apr2 = team_row(idx, TRADE_APRON2_ROOM_OFF)

        # ------------------------------------------------------------------
        # Team header (reactive KPIs)
        # ------------------------------------------------------------------

        worksheet.write(r_team_hdr, COL_OUT_NAME, f"TEAM {idx}", fmts["trade_header"])
        worksheet.write_formula(r_team_hdr, COL_OUT_CAP, f"=MxTeam{idx}Code", fmts["kpi_value"])

        worksheet.write(r_team_hdr, COL_OUT_TAX, "MODE", fmts["trade_header"])
        worksheet.write_formula(r_team_hdr, COL_OUT_APRON, f"=MxTeam{idx}Mode", fmts["trade_text"])

        worksheet.write(r_team_hdr, COL_IN_NAME, "WORKS?", fmts["trade_header"])
        worksheet.write_formula(r_team_hdr, COL_IN_CAP, f"=MxT{idx}Works", fmts["trade_status"])

        worksheet.write(r_team_hdr, COL_IN_TAX, "ALLOWED", fmts["trade_header"])
        worksheet.write_formula(r_team_hdr, COL_IN_APRON, f"=MxT{idx}AllowedInCap", fmts["trade_value"])

        works_hdr_cell = f"{col_letter(COL_IN_CAP)}{r_team_hdr + 1}"
        worksheet.conditional_format(
            works_hdr_cell,
            {"type": "formula", "criteria": f'={works_hdr_cell}="Yes"', "format": fmts["trade_status_valid"]},
        )
        worksheet.conditional_format(
            works_hdr_cell,
            {"type": "formula", "criteria": f'={works_hdr_cell}="No"', "format": fmts["trade_status_invalid"]},
        )

        # ------------------------------------------------------------------
        # Trade input header row
        # ------------------------------------------------------------------

        worksheet.write(r_hdr, COL_OUT_NAME, "Outgoing", fmts["trade_header"])
        worksheet.write(r_hdr, COL_OUT_CAP, "Cap", fmts["trade_header"])
        worksheet.write(r_hdr, COL_OUT_TAX, "Tax", fmts["trade_header"])
        worksheet.write(r_hdr, COL_OUT_APRON, "Apron", fmts["trade_header"])

        worksheet.write(r_hdr, COL_IN_NAME, "Incoming", fmts["trade_header"])
        worksheet.write(r_hdr, COL_IN_CAP, "Cap", fmts["trade_header"])
        worksheet.write(r_hdr, COL_IN_TAX, "Tax", fmts["trade_header"])
        worksheet.write(r_hdr, COL_IN_APRON, "Apron", fmts["trade_header"])

        # ------------------------------------------------------------------
        # Name input rows + validation
        # ------------------------------------------------------------------

        for r in range(r_in_start, r_in_end + 1):
            worksheet.write(r, COL_OUT_NAME, "", fmts["input"])
            worksheet.data_validation(r, COL_OUT_NAME, r, COL_OUT_NAME, {"validate": "list", "source": player_list_source})

            worksheet.write(r, COL_IN_NAME, "", fmts["input"])
            worksheet.data_validation(r, COL_IN_NAME, r, COL_IN_NAME, {"validate": "list", "source": player_list_source})

        # Define named ranges (worksheet-scoped)
        out_col = col_letter(COL_OUT_NAME)
        in_col = col_letter(COL_IN_NAME)

        out_rng = f"${out_col}${r_in_start + 1}:${out_col}${r_in_end + 1}"
        in_rng = f"${in_col}${r_in_start + 1}:${in_col}${r_in_end + 1}"

        workbook.define_name(f"{sheet_name}!MxT{idx}OutNames", f"={sheet_ref}!{out_rng}")
        workbook.define_name(f"{sheet_name}!MxT{idx}InNames", f"={sheet_ref}!{in_rng}")

        team_code_name = f"MxTeam{idx}Code"

        # ------------------------------------------------------------------
        # Spilled amount columns (computed from the input ranges)
        # ------------------------------------------------------------------

        # Outgoing (team-scoped)
        worksheet.write_dynamic_array_formula(
            r_in_start,
            COL_OUT_CAP,
            r_in_start,
            COL_OUT_CAP,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{idx}OutNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="cap_amount",
                team_scoped=True,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            r_in_start,
            COL_OUT_TAX,
            r_in_start,
            COL_OUT_TAX,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{idx}OutNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="tax_amount",
                team_scoped=True,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            r_in_start,
            COL_OUT_APRON,
            r_in_start,
            COL_OUT_APRON,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{idx}OutNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="outgoing_apron_amount",
                team_scoped=True,
            ),
            fmts["trade_value"],
        )

        # Incoming (league-wide)
        worksheet.write_dynamic_array_formula(
            r_in_start,
            COL_IN_CAP,
            r_in_start,
            COL_IN_CAP,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{idx}InNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="incoming_cap_amount",
                team_scoped=False,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            r_in_start,
            COL_IN_TAX,
            r_in_start,
            COL_IN_TAX,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{idx}InNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="incoming_tax_amount",
                team_scoped=False,
            ),
            fmts["trade_value"],
        )
        worksheet.write_dynamic_array_formula(
            r_in_start,
            COL_IN_APRON,
            r_in_start,
            COL_IN_APRON,
            formulas.map_input_names_to_amount(
                names_range=f"MxT{idx}InNames",
                team_code_expr=team_code_name,
                year_expr="MxYear",
                amount_col="incoming_apron_amount",
                team_scoped=False,
            ),
            fmts["trade_value"],
        )

        # ------------------------------------------------------------------
        # Summary rows
        # ------------------------------------------------------------------

        worksheet.write(r_total, COL_OUT_NAME, "Outgoing", fmts["trade_label"])
        worksheet.write_formula(r_total, COL_OUT_CAP, f"=MxT{idx}OutCapTotal", fmts["trade_value"])
        worksheet.write_formula(r_total, COL_OUT_TAX, f"=MxT{idx}OutTaxTotal", fmts["trade_value"])
        worksheet.write_formula(r_total, COL_OUT_APRON, f"=MxT{idx}OutApronTotal", fmts["trade_value"])

        worksheet.write(r_total, COL_IN_NAME, "Incoming", fmts["trade_label"])
        worksheet.write_formula(r_total, COL_IN_CAP, f"=MxT{idx}InCapTotal", fmts["trade_value"])
        worksheet.write_formula(r_total, COL_IN_TAX, f"=MxT{idx}InTaxTotal", fmts["trade_value"])
        worksheet.write_formula(r_total, COL_IN_APRON, f"=MxT{idx}InApronTotal", fmts["trade_value"])

        worksheet.write(r_allowed, COL_OUT_NAME, "Allowed In", fmts["trade_label"])
        worksheet.write_formula(r_allowed, COL_OUT_CAP, f"=MxT{idx}AllowedInCap", fmts["trade_value"])

        worksheet.write(r_status, COL_OUT_NAME, "Works?", fmts["trade_label"])
        worksheet.write_formula(r_status, COL_OUT_CAP, f"=MxT{idx}Works", fmts["trade_status"])

        works_cell = f"{col_letter(COL_OUT_CAP)}{r_status + 1}"
        worksheet.conditional_format(
            works_cell,
            {"type": "formula", "criteria": f'={works_cell}="Yes"', "format": fmts["trade_status_valid"]},
        )
        worksheet.conditional_format(
            works_cell,
            {"type": "formula", "criteria": f'={works_cell}="No"', "format": fmts["trade_status_invalid"]},
        )

        worksheet.write(r_fill12, COL_OUT_NAME, "Fill (to 12)", fmts["trade_label"])
        worksheet.write_formula(r_fill12, COL_OUT_CAP, f"=MxT{idx}Fill12Amount", fmts["trade_value"])

        worksheet.write(r_fill14, COL_OUT_NAME, "Fill (to 14)", fmts["trade_label"])
        worksheet.write_formula(r_fill14, COL_OUT_CAP, f"=MxT{idx}Fill14Amount", fmts["trade_value"])

        worksheet.write(r_fill_total, COL_OUT_NAME, "Fill Total", fmts["trade_label"])
        worksheet.write_formula(r_fill_total, COL_OUT_CAP, f"=MxT{idx}FillAmount", fmts["trade_value"])

        worksheet.write(r_apr1, COL_OUT_NAME, "Apron1 Room", fmts["trade_label"])
        worksheet.write_formula(r_apr1, COL_OUT_CAP, f"=MxT{idx}RoomUnderApron1Post", fmts["trade_value"])

        worksheet.write(r_apr2, COL_OUT_NAME, "Apron2 Room", fmts["trade_label"])
        worksheet.write_formula(r_apr2, COL_OUT_CAP, f"=MxT{idx}RoomUnderApron2Post", fmts["trade_value"])

        for rr in [r_apr1, r_apr2]:
            cell = f"{col_letter(COL_OUT_CAP)}{rr + 1}"
            worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["trade_delta_pos"]})
            worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["trade_delta_neg"]})
