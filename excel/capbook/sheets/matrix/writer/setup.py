"""MATRIX sheet setup (stacked v2).

Responsibilities:
- Column widths + default column formats
- Frozen control panel (verdict, season, trade date, knobs, team selectors)
- Worksheet-scoped defined names for all user inputs

The goal is to keep *all interactive cells* in the top-left, eliminating the
side-scrolling required by the legacy Sean-coordinate layout.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..layout import (
    COL_HIDDEN,
    COL_INPUT,
    COL_IN_APRON,
    COL_IN_CAP,
    COL_IN_NAME,
    COL_IN_TAX,
    COL_MAIN_START,
    COL_OUT_APRON,
    COL_OUT_CAP,
    COL_OUT_NAME,
    COL_OUT_TAX,
    COL_SECTION_LABEL,
    ROW_PARAMS,
    ROW_SEASON,
    ROW_VERDICT,
    ROW_BODY_START,
    TEAM_INPUTS,
    col_letter,
)


def _quote_sheet(sheet_name: str) -> str:
    return "'" + sheet_name.replace("'", "''") + "'"


def write_setup(
    workbook: Workbook,
    worksheet: Worksheet,
    fmts: dict[str, Any],
    *,
    team_codes: list[str],
    as_of: "date | None" = None,
) -> None:
    """Write Matrix column defaults + frozen control panel + input names."""

    sheet_name = worksheet.get_name()
    sheet_ref = _quote_sheet(sheet_name)

    # ------------------------------------------------------------------
    # Column defaults
    # ------------------------------------------------------------------

    # Left rail (labels + single value column)
    worksheet.set_column(COL_SECTION_LABEL, COL_SECTION_LABEL, 12)
    worksheet.set_column(COL_INPUT, COL_INPUT, 18)

    # Hidden helper column (numeric base year for MxYear)
    worksheet.set_column(COL_HIDDEN, COL_HIDDEN, 8, None, {"hidden": True})

    # Trade / roster grid
    worksheet.set_column(COL_OUT_NAME, COL_OUT_NAME, 22, fmts["player"])
    worksheet.set_column(COL_OUT_CAP, COL_OUT_APRON, 12, fmts["trade_value"])

    # NOTE: Column H pulls double duty:
    # - Incoming player name inputs (explicitly formatted per-cell)
    # - Roster earned spill (needs numeric column format)
    worksheet.set_column(COL_IN_NAME, COL_IN_NAME, 22, fmts["trade_value"])
    worksheet.set_column(COL_IN_CAP, COL_IN_APRON, 12, fmts["trade_value"])

    # ------------------------------------------------------------------
    # Freeze panes (Playground-style)
    # - Top 3 rows: control panel
    # - Cols A-C: left rail (C hidden)
    # ------------------------------------------------------------------
    worksheet.freeze_panes(ROW_BODY_START, COL_MAIN_START)

    # ------------------------------------------------------------------
    # Row 1: Verdict (reactive) + team selector labels
    # ------------------------------------------------------------------

    worksheet.write(ROW_VERDICT, COL_SECTION_LABEL, "VERDICT", fmts["section"])
    worksheet.write_formula(ROW_VERDICT, COL_INPUT, "=MxVerdict", fmts["trade_status"])

    verdict_cell = f"{col_letter(COL_INPUT)}{ROW_VERDICT + 1}"
    worksheet.conditional_format(
        verdict_cell,
        {"type": "formula", "criteria": f'={verdict_cell}="Trade Works"', "format": fmts["trade_status_valid"]},
    )
    worksheet.conditional_format(
        verdict_cell,
        {"type": "formula", "criteria": f'={verdict_cell}="Does Not Work"', "format": fmts["trade_status_invalid"]},
    )

    for ti in TEAM_INPUTS:
        worksheet.write(ROW_VERDICT, ti.code_col, f"T{ti.idx}", fmts["trade_header"])
        worksheet.write(ROW_VERDICT, ti.mode_col, "Mode", fmts["trade_header"])

    # ------------------------------------------------------------------
    # Row 2: Season context + team selector inputs
    # ------------------------------------------------------------------

    worksheet.write(ROW_SEASON, COL_SECTION_LABEL, "SEASON", fmts["section"])
    worksheet.write_formula(
        ROW_SEASON,
        COL_INPUT,
        '=TEXT(MOD(MetaBaseYear,100),"00")&"-"&TEXT(MOD(MetaBaseYear+1,100),"00")',
        fmts["base_value"],
    )

    # Numeric base year lives in a hidden helper cell.
    worksheet.write_formula(ROW_SEASON, COL_HIDDEN, "=MetaBaseYear")
    workbook.define_name(
        f"{sheet_name}!MxYear",
        f"={sheet_ref}!${col_letter(COL_HIDDEN)}${ROW_SEASON + 1}",
    )

    default_teams = ["POR", "MIL", "BRK", "PHI"]

    for i, ti in enumerate(TEAM_INPUTS):
        default_team = default_teams[i] if i < len(default_teams) else (team_codes[i] if i < len(team_codes) else "")

        # Team code input
        worksheet.write(ROW_SEASON, ti.code_col, default_team, fmts["team_input"])
        if team_codes:
            worksheet.data_validation(
                ROW_SEASON,
                ti.code_col,
                ROW_SEASON,
                ti.code_col,
                {"validate": "list", "source": team_codes},
            )

        # Mode input
        worksheet.write(ROW_SEASON, ti.mode_col, "Expanded", fmts["input_right"])
        worksheet.data_validation(
            ROW_SEASON,
            ti.mode_col,
            ROW_SEASON,
            ti.mode_col,
            {"validate": "list", "source": ["Expanded", "Standard"]},
        )

        # Worksheet-scoped names
        workbook.define_name(
            f"{sheet_name}!MxTeam{ti.idx}Code",
            f"={sheet_ref}!${col_letter(ti.code_col)}${ROW_SEASON + 1}",
        )
        workbook.define_name(
            f"{sheet_name}!MxTeam{ti.idx}Mode",
            f"={sheet_ref}!${col_letter(ti.mode_col)}${ROW_SEASON + 1}",
        )

    # ------------------------------------------------------------------
    # Row 3: Trade parameters (global knobs)
    # ------------------------------------------------------------------

    worksheet.write(ROW_PARAMS, COL_SECTION_LABEL, "TRADE DATE", fmts["section"])

    if as_of is None:
        worksheet.write_formula(ROW_PARAMS, COL_INPUT, "=DATEVALUE(MetaAsOfDate)", fmts["input_date_right"])
    else:
        worksheet.write_datetime(
            ROW_PARAMS,
            COL_INPUT,
            datetime(as_of.year, as_of.month, as_of.day),
            fmts["input_date_right"],
        )

    worksheet.data_validation(
        ROW_PARAMS,
        COL_INPUT,
        ROW_PARAMS,
        COL_INPUT,
        {
            "validate": "date",
            "criteria": "between",
            "minimum": datetime(1990, 1, 1),
            "maximum": datetime(2100, 12, 31),
        },
    )

    workbook.define_name(
        f"{sheet_name}!MxTradeDate",
        f"={sheet_ref}!${col_letter(COL_INPUT)}${ROW_PARAMS + 1}",
    )

    # Delay to 14 (Matrix-style +14)
    worksheet.write(ROW_PARAMS, COL_MAIN_START, "Delay To 14", fmts["trade_header"])

    delay_opts = ["Immediate", "1 Day"] + [f"{d} Days" for d in range(2, 15)]
    worksheet.write(ROW_PARAMS, COL_MAIN_START + 1, "14 Days", fmts["input_right"])
    worksheet.data_validation(
        ROW_PARAMS,
        COL_MAIN_START + 1,
        ROW_PARAMS,
        COL_MAIN_START + 1,
        {"validate": "list", "source": delay_opts},
    )

    workbook.define_name(
        f"{sheet_name}!MxSignDelayLabel",
        f"={sheet_ref}!${col_letter(COL_MAIN_START + 1)}${ROW_PARAMS + 1}",
    )

    # Fill assumptions (same knobs as Playground)
    worksheet.write(ROW_PARAMS, COL_MAIN_START + 2, "To 12", fmts["trade_header"])
    worksheet.write(ROW_PARAMS, COL_MAIN_START + 3, "ROOKIE", fmts["input_right"])
    worksheet.data_validation(
        ROW_PARAMS,
        COL_MAIN_START + 3,
        ROW_PARAMS,
        COL_MAIN_START + 3,
        {"validate": "list", "source": ["ROOKIE", "VET"]},
    )

    workbook.define_name(
        f"{sheet_name}!MxFillTo12MinType",
        f"={sheet_ref}!${col_letter(COL_MAIN_START + 3)}${ROW_PARAMS + 1}",
    )

    worksheet.write(ROW_PARAMS, COL_MAIN_START + 4, "To 14", fmts["trade_header"])
    worksheet.write(ROW_PARAMS, COL_MAIN_START + 5, "VET", fmts["input_right"])
    worksheet.data_validation(
        ROW_PARAMS,
        COL_MAIN_START + 5,
        ROW_PARAMS,
        COL_MAIN_START + 5,
        {"validate": "list", "source": ["VET", "ROOKIE"]},
    )

    workbook.define_name(
        f"{sheet_name}!MxFillTo14MinType",
        f"={sheet_ref}!${col_letter(COL_MAIN_START + 5)}${ROW_PARAMS + 1}",
    )
