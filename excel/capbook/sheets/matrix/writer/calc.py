"""MATRIX hidden calc block.

Same pattern as PLAYGROUND:
- write scalar formulas into hidden columns on the MATRIX sheet
- expose values via worksheet-scoped names

This is the foundation for future "duplicate this Matrix tab" workflows.
"""

from __future__ import annotations

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import TEAM_BLOCKS, TRADE_INPUT_START_ROW, a1, col_letter


# Hidden calc grid location (0-indexed).
CALC_START_ROW = 0
CALC_START_COL = 120  # Column DQ


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

    def _define(name: str, row0: int, col0: int, formula: str) -> None:
        r = start_row + row0
        c = start_col + col0
        worksheet.write_formula(r, c, formula)
        workbook.define_name(
            f"{sheet_name}!{name}",
            f"={sheet_ref}!${col_letter(c)}${r + 1}",
        )

    # ------------------------------------------------------------------
    # Header row (debug)
    # ------------------------------------------------------------------

    headers: list[tuple[int, str]] = [
        (1, "MxSignDelayDays"),
        (2, "MxTpeAllowance"),
        (3, "MxApron1Level"),
        (4, "MxApron2Level"),
        (5, "MxRookieMin"),
        (6, "MxVetMin"),
        (7, "MxFill12Min"),
        (8, "MxFill14Min"),
        (9, "MxFill12ProrationFactor"),
        (10, "MxFill14ProrationFactor"),
    ]

    col = 11
    for tb in TEAM_BLOCKS:
        headers.extend(
            [
                (col + 0, f"MxT{tb.idx}OutCapTotal"),
                (col + 1, f"MxT{tb.idx}OutTaxTotal"),
                (col + 2, f"MxT{tb.idx}OutApronTotal"),
                (col + 3, f"MxT{tb.idx}InCapTotal"),
                (col + 4, f"MxT{tb.idx}InTaxTotal"),
                (col + 5, f"MxT{tb.idx}InApronTotal"),
                (col + 6, f"MxT{tb.idx}AllowedInCap"),
                (col + 7, f"MxT{tb.idx}MatchOk"),
                (col + 8, f"MxT{tb.idx}RosterCountPost"),
                (col + 9, f"MxT{tb.idx}Fill12Amount"),
                (col + 10, f"MxT{tb.idx}Fill14Amount"),
                (col + 11, f"MxT{tb.idx}FillAmount"),
                (col + 12, f"MxT{tb.idx}PostApronTotalFilled"),
                (col + 13, f"MxT{tb.idx}RoomUnderApron1Post"),
                (col + 14, f"MxT{tb.idx}RoomUnderApron2Post"),
                (col + 15, f"MxT{tb.idx}ApronOk"),
                (col + 16, f"MxT{tb.idx}Works"),
            ]
        )
        col += 17

    headers.append((col, "MxVerdict"))

    max_col0 = max(c for c, _ in headers)

    if hide_columns:
        worksheet.set_column(start_col, start_col + max_col0, 12, None, {"hidden": True})

    for col0, label in headers:
        worksheet.write(start_row, start_col + col0, label)

    # ------------------------------------------------------------------
    # Shared constants + fill knobs
    # ------------------------------------------------------------------

    # Parse the delay label ("Immediate", "1 Day", "14 Days") into a number.
    _define(
        "MxSignDelayDays",
        1,
        1,
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
        "MxTpeAllowance",
        1,
        2,
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[tpe_dollar_allowance]),0)",
    )

    _define(
        "MxApron1Level",
        1,
        3,
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount]),0)",
    )
    _define(
        "MxApron2Level",
        1,
        4,
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[tax_apron2_amount]),0)",
    )

    # Minimums (year-1 minimums by YOS)
    _define(
        "MxRookieMin",
        1,
        5,
        "=IFERROR(XLOOKUP((MxYear&0),tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount]),0)",
    )
    _define(
        "MxVetMin",
        1,
        6,
        "=IFERROR(XLOOKUP((MxYear&2),tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount]),0)",
    )

    # Fill pricing basis
    _define(
        "MxFill12Min",
        1,
        7,
        "=IF(MxFillTo12MinType=\"VET\",MxVetMin,MxRookieMin)",
    )
    _define(
        "MxFill14Min",
        1,
        8,
        "=IF(MxFillTo14MinType=\"ROOKIE\",MxRookieMin,MxVetMin)",
    )

    # Proration factors
    _define(
        "MxFill12ProrationFactor",
        1,
        9,
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
        1,
        10,
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

    col = 11
    for tb in TEAM_BLOCKS:
        # Anchor cells for the spilled columns in the visible trade blocks
        out_cap_anchor = a1(TRADE_INPUT_START_ROW, tb.trade.out_cap_col)
        out_tax_anchor = a1(TRADE_INPUT_START_ROW, tb.trade.out_tax_col)
        out_apron_anchor = a1(TRADE_INPUT_START_ROW, tb.trade.out_apron_col)

        in_cap_anchor = a1(TRADE_INPUT_START_ROW, tb.trade.in_cap_col)
        in_tax_anchor = a1(TRADE_INPUT_START_ROW, tb.trade.in_tax_col)
        in_apron_anchor = a1(TRADE_INPUT_START_ROW, tb.trade.in_apron_col)

        _define(f"MxT{tb.idx}OutCapTotal", 1, col + 0, f"=SUM(ANCHORARRAY({out_cap_anchor}))")
        _define(f"MxT{tb.idx}OutTaxTotal", 1, col + 1, f"=SUM(ANCHORARRAY({out_tax_anchor}))")
        _define(f"MxT{tb.idx}OutApronTotal", 1, col + 2, f"=SUM(ANCHORARRAY({out_apron_anchor}))")

        _define(f"MxT{tb.idx}InCapTotal", 1, col + 3, f"=SUM(ANCHORARRAY({in_cap_anchor}))")
        _define(f"MxT{tb.idx}InTaxTotal", 1, col + 4, f"=SUM(ANCHORARRAY({in_tax_anchor}))")
        _define(f"MxT{tb.idx}InApronTotal", 1, col + 5, f"=SUM(ANCHORARRAY({in_apron_anchor}))")

        _define(
            f"MxT{tb.idx}AllowedInCap",
            1,
            col + 6,
            formulas.trade_matching_allowed_in(
                out_salary_expr=f"MxT{tb.idx}OutCapTotal",
                mode_expr=f"MxTeam{tb.idx}Mode",
                year_expr="MxYear",
                tpe_allowance_expr="MxTpeAllowance",
            ),
        )

        _define(
            f"MxT{tb.idx}MatchOk",
            1,
            col + 7,
            f"=IF(MxTeam{tb.idx}Code=\"\",TRUE,MxT{tb.idx}AllowedInCap>=MxT{tb.idx}InCapTotal)",
        )

        _define(
            f"MxT{tb.idx}RosterCountPost",
            1,
            col + 8,
            _roster_count_post(team_idx=tb.idx),
        )

        fill12_count = f"MAX(0,12-MxT{tb.idx}RosterCountPost)"
        fill14_count = f"MAX(0,14-MxT{tb.idx}RosterCountPost)-{fill12_count}"

        _define(
            f"MxT{tb.idx}Fill12Amount",
            1,
            col + 9,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",{fill12_count}*MxFill12Min*MxFill12ProrationFactor)",
        )

        _define(
            f"MxT{tb.idx}Fill14Amount",
            1,
            col + 10,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",{fill14_count}*MxFill14Min*MxFill14ProrationFactor)",
        )

        _define(
            f"MxT{tb.idx}FillAmount",
            1,
            col + 11,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",MxT{tb.idx}Fill12Amount+MxT{tb.idx}Fill14Amount)",
        )

        # Post-trade apron total (authoritative base from team_salary_warehouse)
        base_apron = (
            f"IFERROR(XLOOKUP({base_team_key.format(idx=tb.idx)},{team_tbl_key},tbl_team_salary_warehouse[apron_total]),0)"
        )

        _define(
            f"MxT{tb.idx}PostApronTotalFilled",
            1,
            col + 12,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",{base_apron}-MxT{tb.idx}OutApronTotal+MxT{tb.idx}InApronTotal+MxT{tb.idx}FillAmount)",
        )

        _define(
            f"MxT{tb.idx}RoomUnderApron1Post",
            1,
            col + 13,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",MxApron1Level-MxT{tb.idx}PostApronTotalFilled)",
        )
        _define(
            f"MxT{tb.idx}RoomUnderApron2Post",
            1,
            col + 14,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",MxApron2Level-MxT{tb.idx}PostApronTotalFilled)",
        )

        is_subject_to_apron = (
            f"IFERROR(XLOOKUP({base_team_key.format(idx=tb.idx)},{team_tbl_key},tbl_team_salary_warehouse[is_subject_to_apron],FALSE),FALSE)"
        )

        # Apron check (v1):
        # - If team is hard-capped (is_subject_to_apron), must stay under Apron 1.
        # - If user sets mode=Expanded, we also require staying under Apron 1.
        _define(
            f"MxT{tb.idx}ApronOk",
            1,
            col + 15,
            "=LET("  # noqa: ISC003
            f"_xlpm.team,MxTeam{tb.idx}Code,"
            f"_xlpm.mode,MxTeam{tb.idx}Mode,"
            f"_xlpm.hard,{is_subject_to_apron},"
            f"_xlpm.post,MxT{tb.idx}PostApronTotalFilled,"
            "IF(_xlpm.team=\"\",TRUE,"
            "AND("
            "IF(_xlpm.hard,_xlpm.post<=MxApron1Level,TRUE),"
            "IF(_xlpm.mode=\"Expanded\",_xlpm.post<=MxApron1Level,TRUE)"
            ")"
            ")"
            ")",
        )

        _define(
            f"MxT{tb.idx}Works",
            1,
            col + 16,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",IF(AND(MxT{tb.idx}MatchOk,MxT{tb.idx}ApronOk),\"Yes\",\"No\"))",
        )

        col += 17

    # ------------------------------------------------------------------
    # Final verdict: all non-blank teams must pass
    # ------------------------------------------------------------------

    verdict_parts = [f"IF(MxTeam{tb.idx}Code=\"\",TRUE,MxT{tb.idx}Works=\"Yes\")" for tb in TEAM_BLOCKS]

    _define(
        "MxVerdict",
        1,
        col,
        "=IF(AND(" + ",".join(verdict_parts) + "),\"Trade Works\",\"Does Not Work\")",
    )
