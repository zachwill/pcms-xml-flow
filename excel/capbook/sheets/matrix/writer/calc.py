"""MATRIX hidden calc block (stacked v2).

We follow the same philosophy as PLAYGROUND:
- Scalar formulas live on the Matrix worksheet itself (hidden columns)
- Worksheet-scoped names point at plain cell references

Layout note:
The legacy Matrix calc block was a wide horizontal grid (80+ columns), which
made the sheet feel "endless" even though the columns were hidden.

This version writes the calc block *vertically* (one value per row) to keep the
sheet narrow and reduce horizontal scrolling.
"""

from __future__ import annotations

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import (
    COL_IN_APRON,
    COL_IN_CAP,
    COL_IN_TAX,
    COL_OUT_APRON,
    COL_OUT_CAP,
    COL_OUT_TAX,
    TEAM_INPUTS,
    TRADE_INPUT_OFF,
    a1,
    col_letter,
    team_row,
)


# Hidden calc grid location (0-indexed).
# Visible UI currently ends at column K (index 10). We tuck the calc block
# just to the right and hide the columns.
CALC_START_ROW = 0
CALC_START_COL = 12  # Column M


def _quote_sheet(sheet_name: str) -> str:
    return "'" + sheet_name.replace("'", "''") + "'"


def write_calc_block(
    workbook: Workbook,
    worksheet: Worksheet,
    *,
    start_row: int = CALC_START_ROW,
    start_col: int = CALC_START_COL,
    hide_columns: bool = True,
) -> None:
    """Write the Matrix scalar calc block + worksheet-scoped defined names."""

    sheet_name = worksheet.get_name()
    sheet_ref = _quote_sheet(sheet_name)

    label_col = start_col
    value_col = start_col + 1

    if hide_columns:
        worksheet.set_column(label_col, value_col, 14, None, {"hidden": True})

    row_cursor = start_row

    def _define(name: str, formula: str) -> None:
        nonlocal row_cursor

        r = row_cursor

        # Helpful debug label when columns are unhidden.
        worksheet.write(r, label_col, name)

        worksheet.write_formula(r, value_col, formula)
        workbook.define_name(
            f"{sheet_name}!{name}",
            f"={sheet_ref}!${col_letter(value_col)}${r + 1}",
        )

        row_cursor += 1

    # ------------------------------------------------------------------
    # Shared date + proration helpers
    # ------------------------------------------------------------------

    # Parse the delay label ("Immediate", "1 Day", "14 Days") into a number.
    _define(
        "MxSignDelayDays",
        "=LET("  # noqa: ISC003
        "_xlpm.lbl,MxSignDelayLabel,"
        "IF(_xlpm.lbl=\"\",0,"
        "IF(ISNUMBER(_xlpm.lbl),_xlpm.lbl,"
        "IF(_xlpm.lbl=\"Immediate\",0,"
        "IFERROR(VALUE(LEFT(_xlpm.lbl,FIND(\" \",_xlpm.lbl&\" \")-1)),0)"
        ")"
        ")"
        ")"
        ")",
    )

    _define(
        "MxPlayingStart",
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[playing_start_at]),0)",
    )

    _define("MxSignDate", "=MxTradeDate+MxSignDelayDays")

    _define(
        "MxDaysInSeason",
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[days_in_season]),174)",
    )

    _define(
        "MxOutDays",
        "=LET("  # noqa: ISC003
        "_xlpm.start,MxPlayingStart,"
        "_xlpm.dt,MxTradeDate,"
        "_xlpm.d,MxDaysInSeason,"
        "MAX(0,MIN(_xlpm.d,INT(_xlpm.dt-_xlpm.start+1)))"
        ")",
    )

    _define("MxInDays", "=MxDaysInSeason-MxOutDays")

    # ------------------------------------------------------------------
    # CBA constants
    # ------------------------------------------------------------------

    _define(
        "MxTpeAllowance",
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[tpe_dollar_allowance]),0)",
    )

    _define(
        "MxApron1Level",
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount]),0)",
    )
    _define(
        "MxApron2Level",
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[tax_apron2_amount]),0)",
    )

    # Minimums (year-1 minimums by YOS)
    _define(
        "MxRookieMin",
        "=IFERROR(XLOOKUP((MxYear&0),tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount]),0)",
    )
    _define(
        "MxVetMin",
        "=IFERROR(XLOOKUP((MxYear&2),tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount]),0)",
    )

    # Fill pricing basis
    _define("MxFill12Min", "=IF(MxFillTo12MinType=\"VET\",MxVetMin,MxRookieMin)")
    _define("MxFill14Min", "=IF(MxFillTo14MinType=\"ROOKIE\",MxRookieMin,MxVetMin)")

    # Proration factors
    _define(
        "MxFill12ProrationFactor",
        "=LET("  # noqa: ISC003
        "_xlpm.start,MxPlayingStart,"
        "_xlpm.dt,MxTradeDate,"
        "_xlpm.d,MxDaysInSeason,"
        "_xlpm.day,MAX(0,MIN(_xlpm.d,INT(_xlpm.dt-_xlpm.start+1))),"
        "_xlpm.rem,MAX(0,MIN(_xlpm.d,INT(_xlpm.d-_xlpm.day+1))),"
        "IF(_xlpm.d=0,1,_xlpm.rem/_xlpm.d)"
        ")",
    )

    # Matrix-style: fill-to-14 is priced at trade date + delay.
    _define(
        "MxFill14ProrationFactor",
        "=LET("  # noqa: ISC003
        "_xlpm.start,MxPlayingStart,"
        "_xlpm.dt,MxSignDate,"
        "_xlpm.d,MxDaysInSeason,"
        "_xlpm.day,MAX(0,MIN(_xlpm.d,INT(_xlpm.dt-_xlpm.start+1))),"
        "_xlpm.rem,MAX(0,MIN(_xlpm.d,INT(_xlpm.d-_xlpm.day+1))),"
        "IF(_xlpm.d=0,1,_xlpm.rem/_xlpm.d)"
        ")",
    )

    # ------------------------------------------------------------------
    # Helper: roster count after trade (team-scoped, base year)
    # ------------------------------------------------------------------

    def _roster_count_post(*, team_idx: int) -> str:
        team = f"MxTeam{team_idx}Code"
        out_rng = f"MxT{team_idx}OutNames"
        in_rng = f"MxT{team_idx}InNames"

        return (
            "=LET("  # noqa: ISC003
            f"_xlpm.team,{team},"
            "_xlpm.y,MxYear,"
            "IF(_xlpm.team=\"\",0,"
            "LET("  # noqa: ISC003
            "_xlpm.baseNames,IFERROR(UNIQUE(FILTER(tbl_salary_book_yearly[player_name],"
            "(tbl_salary_book_yearly[team_code]=_xlpm.team)"
            "*(tbl_salary_book_yearly[salary_year]=_xlpm.y)"
            "*(tbl_salary_book_yearly[cap_amount]<>\"\")"
            "*(tbl_salary_book_yearly[is_two_way]<>TRUE)"
            ")),\"\"),"
            "_xlpm.baseN,IF(_xlpm.baseNames=\"\",0,ROWS(_xlpm.baseNames)),"
            f"_xlpm.outN,IFERROR(UNIQUE(FILTER({out_rng},{out_rng}<>\"\")),\"\"),"
            "_xlpm.out,IF(OR(_xlpm.baseNames=\"\",_xlpm.outN=\"\"),0,IFERROR(SUM(--(COUNTIF(_xlpm.baseNames,_xlpm.outN)>0)),0)),"
            f"_xlpm.inN,IFERROR(UNIQUE(FILTER({in_rng},{in_rng}<>\"\")),\"\"),"
            "_xlpm.in,IF(OR(_xlpm.baseNames=\"\",_xlpm.inN=\"\"),0,IFERROR(SUM(--(COUNTIF(_xlpm.baseNames,_xlpm.inN)=0)),0)),"
            "MAX(0,_xlpm.baseN-_xlpm.out+_xlpm.in)"
            ")"  # close inner LET
            ")"  # close IF
            ")"  # close outer LET
        )

    # ------------------------------------------------------------------
    # Per-team calc
    # ------------------------------------------------------------------

    base_team_key = "MxTeam{idx}Code&MxYear"
    team_tbl_key = "tbl_team_salary_warehouse[team_code]&tbl_team_salary_warehouse[salary_year]"

    for ti in TEAM_INPUTS:
        idx = ti.idx

        # Anchor cells for the spilled columns in the visible trade blocks
        trade_input_start = team_row(idx, TRADE_INPUT_OFF)

        out_cap_anchor = a1(trade_input_start, COL_OUT_CAP)
        out_tax_anchor = a1(trade_input_start, COL_OUT_TAX)
        out_apron_anchor = a1(trade_input_start, COL_OUT_APRON)

        in_cap_anchor = a1(trade_input_start, COL_IN_CAP)
        in_tax_anchor = a1(trade_input_start, COL_IN_TAX)
        in_apron_anchor = a1(trade_input_start, COL_IN_APRON)

        _define(f"MxT{idx}OutCapTotal", f"=SUM(ANCHORARRAY({out_cap_anchor}))")
        _define(f"MxT{idx}OutTaxTotal", f"=SUM(ANCHORARRAY({out_tax_anchor}))")
        _define(f"MxT{idx}OutApronTotal", f"=SUM(ANCHORARRAY({out_apron_anchor}))")

        _define(f"MxT{idx}InCapTotal", f"=SUM(ANCHORARRAY({in_cap_anchor}))")
        _define(f"MxT{idx}InTaxTotal", f"=SUM(ANCHORARRAY({in_tax_anchor}))")
        _define(f"MxT{idx}InApronTotal", f"=SUM(ANCHORARRAY({in_apron_anchor}))")

        _define(
            f"MxT{idx}AllowedInCap",
            formulas.trade_matching_allowed_in(
                out_salary_expr=f"MxT{idx}OutCapTotal",
                mode_expr=f"MxTeam{idx}Mode",
                year_expr="MxYear",
                tpe_allowance_expr="MxTpeAllowance",
            ),
        )

        _define(
            f"MxT{idx}MatchOk",
            f"=IF(MxTeam{idx}Code=\"\",TRUE,MxT{idx}AllowedInCap>=MxT{idx}InCapTotal)",
        )

        _define(f"MxT{idx}RosterCountPost", _roster_count_post(team_idx=idx))

        fill12_count = f"MAX(0,12-MxT{idx}RosterCountPost)"
        fill14_count = f"MAX(0,14-MxT{idx}RosterCountPost)-{fill12_count}"

        _define(
            f"MxT{idx}Fill12Amount",
            f"=IF(MxTeam{idx}Code=\"\",\"\",{fill12_count}*MxFill12Min*MxFill12ProrationFactor)",
        )

        _define(
            f"MxT{idx}Fill14Amount",
            f"=IF(MxTeam{idx}Code=\"\",\"\",{fill14_count}*MxFill14Min*MxFill14ProrationFactor)",
        )

        _define(
            f"MxT{idx}FillAmount",
            f"=IF(MxTeam{idx}Code=\"\",\"\",MxT{idx}Fill12Amount+MxT{idx}Fill14Amount)",
        )

        # Post-trade apron total (authoritative base from team_salary_warehouse)
        base_apron = f"IFERROR(XLOOKUP({base_team_key.format(idx=idx)},{team_tbl_key},tbl_team_salary_warehouse[apron_total]),0)"

        _define(
            f"MxT{idx}PostApronTotalFilled",
            f"=IF(MxTeam{idx}Code=\"\",\"\",{base_apron}-MxT{idx}OutApronTotal+MxT{idx}InApronTotal+MxT{idx}FillAmount)",
        )

        _define(
            f"MxT{idx}RoomUnderApron1Post",
            f"=IF(MxTeam{idx}Code=\"\",\"\",MxApron1Level-MxT{idx}PostApronTotalFilled)",
        )
        _define(
            f"MxT{idx}RoomUnderApron2Post",
            f"=IF(MxTeam{idx}Code=\"\",\"\",MxApron2Level-MxT{idx}PostApronTotalFilled)",
        )

        is_subject_to_apron = f"IFERROR(XLOOKUP({base_team_key.format(idx=idx)},{team_tbl_key},tbl_team_salary_warehouse[is_subject_to_apron],FALSE),FALSE)"

        # Apron check (v1):
        # - If team is hard-capped (is_subject_to_apron), must stay under Apron 1.
        # - If user sets mode=Expanded, we also require staying under Apron 1.
        _define(
            f"MxT{idx}ApronOk",
            "=LET("  # noqa: ISC003
            f"_xlpm.team,MxTeam{idx}Code,"
            f"_xlpm.mode,MxTeam{idx}Mode,"
            f"_xlpm.hard,{is_subject_to_apron},"
            f"_xlpm.post,MxT{idx}PostApronTotalFilled,"
            "IF(_xlpm.team=\"\",TRUE,"
            "AND("
            "IF(_xlpm.hard,_xlpm.post<=MxApron1Level,TRUE),"
            "IF(_xlpm.mode=\"Expanded\",_xlpm.post<=MxApron1Level,TRUE)"
            ")"
            ")"
            ")",
        )

        _define(
            f"MxT{idx}Works",
            f"=IF(MxTeam{idx}Code=\"\",\"\",IF(AND(MxT{idx}MatchOk,MxT{idx}ApronOk),\"Yes\",\"No\"))",
        )

    # ------------------------------------------------------------------
    # Final verdict: all non-blank teams must pass
    # ------------------------------------------------------------------

    verdict_parts = [f"IF(MxTeam{ti.idx}Code=\"\",TRUE,MxT{ti.idx}Works=\"Yes\")" for ti in TEAM_INPUTS]

    _define(
        "MxVerdict",
        "=IF(AND(" + ",".join(verdict_parts) + "),\"Trade Works\",\"Does Not Work\")",
    )
