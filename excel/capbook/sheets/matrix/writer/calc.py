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
from ..layout import TEAM_BLOCKS, a1, col_letter


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

    # Column map (relative to start_col)
    #  1: TpeAllowance
    #  2..: Team totals + checks (4 cols per team)
    headers = [(1, "MxTpeAllowance")]
    col = 2
    for tb in TEAM_BLOCKS:
        headers.extend(
            [
                (col + 0, f"MxT{tb.idx}OutCapTotal"),
                (col + 1, f"MxT{tb.idx}InCapTotal"),
                (col + 2, f"MxT{tb.idx}AllowedInCap"),
                (col + 3, f"MxT{tb.idx}Works"),
            ]
        )
        col += 4

    headers.append((col, "MxVerdict"))

    max_col0 = max(c for c, _ in headers)

    if hide_columns:
        worksheet.set_column(start_col, start_col + max_col0, 12, None, {"hidden": True})

    # Header row (debug)
    for col0, label in headers:
        worksheet.write(start_row, start_col + col0, label)

    def _define(name: str, row0: int, col0: int, formula: str) -> None:
        r = start_row + row0
        c = start_col + col0
        worksheet.write_formula(r, c, formula)
        workbook.define_name(
            f"{sheet_name}!{name}",
            f"={sheet_ref}!${col_letter(c)}${r + 1}",
        )

    # tpe dollar allowance for the selected season
    _define(
        "MxTpeAllowance",
        1,
        1,
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[tpe_dollar_allowance]),0)",
    )

    # Per-team calc
    col = 2
    for tb in TEAM_BLOCKS:
        # Anchor cells for the spilled cap columns in the visible trade blocks
        out_cap_anchor = a1(3, tb.trade.out_cap_col)  # e.g. AL4
        in_cap_anchor = a1(3, tb.trade.in_cap_col)  # e.g. AS4

        _define(
            f"MxT{tb.idx}OutCapTotal",
            1,
            col + 0,
            f"=SUM(ANCHORARRAY({out_cap_anchor}))",
        )
        _define(
            f"MxT{tb.idx}InCapTotal",
            1,
            col + 1,
            f"=SUM(ANCHORARRAY({in_cap_anchor}))",
        )
        _define(
            f"MxT{tb.idx}AllowedInCap",
            1,
            col + 2,
            formulas.trade_matching_allowed_in(
                out_salary_expr=f"MxT{tb.idx}OutCapTotal",
                mode_expr=f"MxTeam{tb.idx}Mode",
                year_expr="MxYear",
                tpe_allowance_expr="MxTpeAllowance",
            ),
        )
        _define(
            f"MxT{tb.idx}Works",
            1,
            col + 3,
            f"=IF(MxTeam{tb.idx}Code=\"\",\"\",IF(MxT{tb.idx}AllowedInCap>=MxT{tb.idx}InCapTotal,\"Yes\",\"No\"))",
        )

        col += 4

    # Final verdict: all non-blank teams must pass
    verdict_parts = []
    for tb in TEAM_BLOCKS:
        verdict_parts.append(
            f"IF(MxTeam{tb.idx}Code=\"\",TRUE,MxT{tb.idx}AllowedInCap>=MxT{tb.idx}InCapTotal)"
        )

    _define(
        "MxVerdict",
        1,
        col,
        "=IF(AND(" + ",".join(verdict_parts) + "),\"Trade Works\",\"Does Not Work\")",
    )
