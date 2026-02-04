"""MATRIX roster previews (stacked v2)."""

from __future__ import annotations

from typing import Any

from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import (
    COL_ROSTER_APRON,
    COL_ROSTER_CAP,
    COL_ROSTER_EARNED,
    COL_ROSTER_NAME,
    COL_ROSTER_REMAINING,
    COL_ROSTER_TAX,
    ROSTER_HDR_OFF,
    ROSTER_RESERVED,
    ROSTER_START_OFF,
    TEAM_INPUTS,
    team_row,
    a1,
)


def write_rosters(
    worksheet: Worksheet,
    fmts: dict[str, Any],
    *,
    base_year: int,
    salary_book_yearly_nrows: int,
) -> None:
    """Write the reactive roster blocks for each selected team."""

    # NOTE: base_year/salary_book_yearly_nrows are currently unused (kept for
    # parity with the Playground writer signature and future optimization).
    _ = (base_year, salary_book_yearly_nrows)

    for ti in TEAM_INPUTS:
        idx = ti.idx

        r_hdr = team_row(idx, ROSTER_HDR_OFF)
        r_start = team_row(idx, ROSTER_START_OFF)

        # Header row
        worksheet.write(r_hdr, COL_ROSTER_NAME, "Roster", fmts["trade_header"])
        worksheet.write(r_hdr, COL_ROSTER_CAP, "Cap", fmts["trade_header"])
        worksheet.write(r_hdr, COL_ROSTER_TAX, "Tax", fmts["trade_header"])
        worksheet.write(r_hdr, COL_ROSTER_APRON, "Apron", fmts["trade_header"])
        worksheet.write(r_hdr, COL_ROSTER_EARNED, "Earned", fmts["trade_header"])
        worksheet.write(r_hdr, COL_ROSTER_REMAINING, "Remaining", fmts["trade_header"])

        # Names spill
        name_anchor = a1(r_start, COL_ROSTER_NAME)
        names_spill = f"ANCHORARRAY({name_anchor})"

        worksheet.write_dynamic_array_formula(
            r_start,
            COL_ROSTER_NAME,
            r_start,
            COL_ROSTER_NAME,
            formulas.roster_names_anchor(
                team_code_expr=f"MxTeam{idx}Code",
                year_expr="MxYear",
                max_rows=ROSTER_RESERVED,
            ),
            fmts["player"],
        )

        # Cap
        cap_anchor = a1(r_start, COL_ROSTER_CAP)
        worksheet.write_dynamic_array_formula(
            r_start,
            COL_ROSTER_CAP,
            r_start,
            COL_ROSTER_CAP,
            formulas.roster_amount_column(
                names_spill=names_spill,
                team_code_expr=f"MxTeam{idx}Code",
                year_expr="MxYear",
                amount_col="cap_amount",
            ),
            fmts["trade_value"],
        )

        # Tax
        worksheet.write_dynamic_array_formula(
            r_start,
            COL_ROSTER_TAX,
            r_start,
            COL_ROSTER_TAX,
            formulas.roster_amount_column(
                names_spill=names_spill,
                team_code_expr=f"MxTeam{idx}Code",
                year_expr="MxYear",
                amount_col="tax_amount",
            ),
            fmts["trade_value"],
        )

        # Apron
        worksheet.write_dynamic_array_formula(
            r_start,
            COL_ROSTER_APRON,
            r_start,
            COL_ROSTER_APRON,
            formulas.roster_amount_column(
                names_spill=names_spill,
                team_code_expr=f"MxTeam{idx}Code",
                year_expr="MxYear",
                amount_col="apron_amount",
            ),
            fmts["trade_value"],
        )

        # Salary Earned / Remaining (prorated by trade date)
        cap_arr = f"ANCHORARRAY({cap_anchor})"

        earned_anchor = a1(r_start, COL_ROSTER_EARNED)
        worksheet.write_dynamic_array_formula(
            r_start,
            COL_ROSTER_EARNED,
            r_start,
            COL_ROSTER_EARNED,
            f"={cap_arr}*MxOutDays/MxDaysInSeason",
            fmts["trade_value"],
        )

        earned_arr = f"ANCHORARRAY({earned_anchor})"
        worksheet.write_dynamic_array_formula(
            r_start,
            COL_ROSTER_REMAINING,
            r_start,
            COL_ROSTER_REMAINING,
            f"={cap_arr}-{earned_arr}",
            fmts["trade_value"],
        )
