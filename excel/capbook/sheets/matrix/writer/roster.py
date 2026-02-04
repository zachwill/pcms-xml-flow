"""MATRIX roster views (4 teams side-by-side)."""

from __future__ import annotations

from typing import Any

from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import ROSTER_RESERVED, ROSTER_START_ROW, TEAM_BLOCKS, a1


def write_rosters(
    worksheet: Worksheet,
    fmts: dict[str, Any],
    *,
    base_year: int,
    salary_book_yearly_nrows: int,
) -> None:
    """Write the reactive roster blocks for each selected team."""

    # Names + amounts (cap/tax/apron)
    for tb in TEAM_BLOCKS:
        name_anchor = a1(ROSTER_START_ROW, tb.roster.name_col)
        names_spill = f"ANCHORARRAY({name_anchor})"

        worksheet.write_dynamic_array_formula(
            ROSTER_START_ROW,
            tb.roster.name_col,
            ROSTER_START_ROW,
            tb.roster.name_col,
            formulas.roster_names_anchor(
                team_code_expr=f"MxTeam{tb.idx}Code",
                year_expr="MxYear",
                max_rows=ROSTER_RESERVED,
            ),
            fmts["player"],
        )

        # Cap
        cap_anchor = a1(ROSTER_START_ROW, tb.roster.cap_col)
        worksheet.write_dynamic_array_formula(
            ROSTER_START_ROW,
            tb.roster.cap_col,
            ROSTER_START_ROW,
            tb.roster.cap_col,
            formulas.roster_amount_column(
                names_spill=names_spill,
                team_code_expr=f"MxTeam{tb.idx}Code",
                year_expr="MxYear",
                amount_col="cap_amount",
            ),
            fmts["trade_value"],
        )

        # Tax
        worksheet.write_dynamic_array_formula(
            ROSTER_START_ROW,
            tb.roster.tax_col,
            ROSTER_START_ROW,
            tb.roster.tax_col,
            formulas.roster_amount_column(
                names_spill=names_spill,
                team_code_expr=f"MxTeam{tb.idx}Code",
                year_expr="MxYear",
                amount_col="tax_amount",
            ),
            fmts["trade_value"],
        )

        # Apron
        worksheet.write_dynamic_array_formula(
            ROSTER_START_ROW,
            tb.roster.apron_col,
            ROSTER_START_ROW,
            tb.roster.apron_col,
            formulas.roster_amount_column(
                names_spill=names_spill,
                team_code_expr=f"MxTeam{tb.idx}Code",
                year_expr="MxYear",
                amount_col="apron_amount",
            ),
            fmts["trade_value"],
        )

        # Salary Earned / Remaining (prorated by trade date)
        cap_arr = f"ANCHORARRAY({cap_anchor})"

        earned_anchor = a1(ROSTER_START_ROW, tb.roster.earned_col)
        worksheet.write_dynamic_array_formula(
            ROSTER_START_ROW,
            tb.roster.earned_col,
            ROSTER_START_ROW,
            tb.roster.earned_col,
            f"={cap_arr}*MxOutDays/MxDaysInSeason",
            fmts["trade_value"],
        )

        earned_arr = f"ANCHORARRAY({earned_anchor})"
        worksheet.write_dynamic_array_formula(
            ROSTER_START_ROW,
            tb.roster.remaining_col,
            ROSTER_START_ROW,
            tb.roster.remaining_col,
            f"={cap_arr}-{earned_arr}",
            fmts["trade_value"],
        )
