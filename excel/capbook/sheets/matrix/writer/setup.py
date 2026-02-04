"""MATRIX sheet setup: columns, headers, and the Trade Details block."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..layout import (
    COL_TRADE_LABEL,
    COL_TRADE_VALUE,
    ROW_DAYS_IN_SEASON,
    ROW_FILL_TO_12_TYPE,
    ROW_FILL_TO_14_TYPE,
    ROW_IN_DAYS,
    ROW_OUT_DAYS,
    ROW_SIGN_DATE,
    ROW_SIGN_DELAY,
    ROW_TRADE_DATE,
    ROW_TRADE_HDR,
    ROW_TRADE_PLAYING_START,
    ROW_TRADE_YEAR,
    TEAM_BLOCKS,
    a1,
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
    """Write Matrix scaffold: column widths, team selectors, and Trade Details."""

    sheet_name = worksheet.get_name()
    sheet_ref = _quote_sheet(sheet_name)

    # ------------------------------------------------------------------
    # Column defaults (roster views)
    # ------------------------------------------------------------------

    # Name columns
    for tb in TEAM_BLOCKS:
        worksheet.set_column(tb.roster.name_col, tb.roster.name_col, 18, fmts["player"])

        # Money columns (cap/tax/apron/earned/remaining)
        for c in [tb.roster.cap_col, tb.roster.tax_col, tb.roster.apron_col, tb.roster.earned_col, tb.roster.remaining_col]:
            worksheet.set_column(c, c, 12, fmts["trade_value"])

    # Trade detail block
    worksheet.set_column(COL_TRADE_LABEL, COL_TRADE_LABEL, 16, fmts["trade_label"])
    worksheet.set_column(COL_TRADE_VALUE, COL_TRADE_VALUE, 14, fmts["trade_value"])

    # Trade input blocks: set widths for name + cap/tax/apron columns.
    for tb in TEAM_BLOCKS:
        worksheet.set_column(tb.trade.out_name_col, tb.trade.out_name_col, 18, fmts["player"])
        worksheet.set_column(tb.trade.out_cap_col, tb.trade.out_cap_col, 12, fmts["trade_value"])
        worksheet.set_column(tb.trade.out_tax_col, tb.trade.out_tax_col, 12, fmts["trade_value"])
        worksheet.set_column(tb.trade.out_apron_col, tb.trade.out_apron_col, 12, fmts["trade_value"])

        worksheet.set_column(tb.trade.in_name_col, tb.trade.in_name_col, 18, fmts["player"])
        worksheet.set_column(tb.trade.in_cap_col, tb.trade.in_cap_col, 12, fmts["trade_value"])
        worksheet.set_column(tb.trade.in_tax_col, tb.trade.in_tax_col, 12, fmts["trade_value"])
        worksheet.set_column(tb.trade.in_apron_col, tb.trade.in_apron_col, 12, fmts["trade_value"])

    # ------------------------------------------------------------------
    # Freeze top 2 rows (team labels + small header bar)
    # ------------------------------------------------------------------
    worksheet.freeze_panes(2, 0)

    # ------------------------------------------------------------------
    # Team inputs (Sean coords: AK1/AW1/BI1/BU1 + AM1/AY1/BK1/BW1)
    # ------------------------------------------------------------------

    default_teams = ["POR", "MIL", "BRK", "PHI"]

    for i, tb in enumerate(TEAM_BLOCKS):
        code_row0 = 0
        mode_row0 = 0

        # Team code input
        default_team = default_teams[i] if i < len(default_teams) else (team_codes[i] if i < len(team_codes) else "")
        worksheet.write(code_row0, tb.code_input_col, default_team, fmts["team_input"])
        if team_codes:
            worksheet.data_validation(
                code_row0,
                tb.code_input_col,
                code_row0,
                tb.code_input_col,
                {"validate": "list", "source": team_codes},
            )

        # Mode input
        worksheet.write(mode_row0, tb.mode_input_col, "Expanded", fmts["input_right"])
        worksheet.data_validation(
            mode_row0,
            tb.mode_input_col,
            mode_row0,
            tb.mode_input_col,
            {"validate": "list", "source": ["Expanded", "Standard"]},
        )

        # Worksheet-scoped names
        workbook.define_name(
            f"{sheet_name}!MxTeam{tb.idx}Code",
            f"={sheet_ref}!${col_letter(tb.code_input_col)}$1",
        )
        workbook.define_name(
            f"{sheet_name}!MxTeam{tb.idx}Mode",
            f"={sheet_ref}!${col_letter(tb.mode_input_col)}$1",
        )

    # ------------------------------------------------------------------
    # Roster headers (left area) - display team codes + column labels
    # ------------------------------------------------------------------

    for tb in TEAM_BLOCKS:
        # Display the selected team code at the top of each roster block.
        # This mirrors Sean's `A1 = AK1` behavior.
        team_code_cell = a1(0, tb.code_input_col)
        worksheet.write_formula(0, tb.roster.name_col, f"={team_code_cell}", fmts["kpi_value"])

        worksheet.write(0, tb.roster.cap_col, "Cap:", fmts["trade_header"])
        worksheet.write(0, tb.roster.tax_col, "Tax:", fmts["trade_header"])
        worksheet.write(0, tb.roster.apron_col, "Apron:", fmts["trade_header"])
        worksheet.write(0, tb.roster.earned_col, "Salary Earned:", fmts["trade_header"])
        worksheet.write(0, tb.roster.remaining_col, "Salary Remaining:", fmts["trade_header"])

    # ------------------------------------------------------------------
    # Trade Details block (AH:AI)
    # ------------------------------------------------------------------

    worksheet.write(ROW_TRADE_HDR, COL_TRADE_LABEL - 1, "Trade Details", fmts["totals_section"])

    # Season year (base year)
    worksheet.write(ROW_TRADE_YEAR, COL_TRADE_LABEL, "Season:", fmts["trade_label"])
    worksheet.write_formula(ROW_TRADE_YEAR, COL_TRADE_VALUE, "=MetaBaseYear", fmts["trade_value"])
    workbook.define_name(
        f"{sheet_name}!MxYear",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_TRADE_YEAR + 1}",
    )

    # Regular season start (playing_start_at)
    worksheet.write(ROW_TRADE_PLAYING_START, COL_TRADE_LABEL, "Season Start:", fmts["trade_label"])
    worksheet.write_formula(
        ROW_TRADE_PLAYING_START,
        COL_TRADE_VALUE,
        "=XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[playing_start_at])",
        fmts["trade_date"],
    )
    workbook.define_name(
        f"{sheet_name}!MxPlayingStart",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_TRADE_PLAYING_START + 1}",
    )

    # Trade date input
    worksheet.write(ROW_TRADE_DATE, COL_TRADE_LABEL, "Trade Date:", fmts["trade_label"])
    if as_of is None:
        worksheet.write_formula(ROW_TRADE_DATE, COL_TRADE_VALUE, "=DATEVALUE(MetaAsOfDate)", fmts["input_date_right"])
    else:
        worksheet.write_datetime(
            ROW_TRADE_DATE,
            COL_TRADE_VALUE,
            datetime(as_of.year, as_of.month, as_of.day),
            fmts["input_date_right"],
        )
    worksheet.data_validation(
        ROW_TRADE_DATE,
        COL_TRADE_VALUE,
        ROW_TRADE_DATE,
        COL_TRADE_VALUE,
        {
            "validate": "date",
            "criteria": "between",
            "minimum": datetime(1990, 1, 1),
            "maximum": datetime(2100, 12, 31),
        },
    )
    workbook.define_name(
        f"{sheet_name}!MxTradeDate",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_TRADE_DATE + 1}",
    )

    # Delay to 14: for pricing the fill-to-14 minimums (Matrix-style +14).
    # Keep the same "knob" UX as PLAYGROUND.
    worksheet.write(ROW_SIGN_DELAY, COL_TRADE_LABEL, "Delay To 14:", fmts["trade_label"])

    delay_opts = ["Immediate", "1 Day"] + [f"{d} Days" for d in range(2, 15)]
    worksheet.write(ROW_SIGN_DELAY, COL_TRADE_VALUE, "14 Days", fmts["input_right"])
    worksheet.data_validation(
        ROW_SIGN_DELAY,
        COL_TRADE_VALUE,
        ROW_SIGN_DELAY,
        COL_TRADE_VALUE,
        {"validate": "list", "source": delay_opts},
    )

    # Store the label; numeric delay days are derived in the hidden calc block.
    workbook.define_name(
        f"{sheet_name}!MxSignDelayLabel",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_SIGN_DELAY + 1}",
    )

    # Day to sign (trade date + delay)
    worksheet.write(ROW_SIGN_DATE, COL_TRADE_LABEL, "Day To Sign:", fmts["trade_label"])
    worksheet.write_formula(ROW_SIGN_DATE, COL_TRADE_VALUE, "=MxTradeDate+MxSignDelayDays", fmts["trade_date"])
    workbook.define_name(
        f"{sheet_name}!MxSignDate",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_SIGN_DATE + 1}",
    )

    # Days in season
    worksheet.write(ROW_DAYS_IN_SEASON, COL_TRADE_LABEL, "Days In Season:", fmts["trade_label"])
    worksheet.write_formula(
        ROW_DAYS_IN_SEASON,
        COL_TRADE_VALUE,
        "=IFERROR(XLOOKUP(MxYear,tbl_system_values[salary_year],tbl_system_values[days_in_season]),174)",
        fmts["trade_value"],
    )
    workbook.define_name(
        f"{sheet_name}!MxDaysInSeason",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_DAYS_IN_SEASON + 1}",
    )

    # Outgoing days responsible (by trade date)
    worksheet.write(ROW_OUT_DAYS, COL_TRADE_LABEL, "Out Days:", fmts["trade_label"])
    worksheet.write_formula(
        ROW_OUT_DAYS,
        COL_TRADE_VALUE,
        "=LET(_xlpm.start,MxPlayingStart,_xlpm.dt,MxTradeDate,_xlpm.d,MxDaysInSeason,MAX(0,MIN(_xlpm.d,INT(_xlpm.dt-_xlpm.start+1))))",
        fmts["trade_value"],
    )
    workbook.define_name(
        f"{sheet_name}!MxOutDays",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_OUT_DAYS + 1}",
    )

    # Incoming days responsible
    worksheet.write(ROW_IN_DAYS, COL_TRADE_LABEL, "In Days:", fmts["trade_label"])
    worksheet.write_formula(ROW_IN_DAYS, COL_TRADE_VALUE, "=MxDaysInSeason-MxOutDays", fmts["trade_value"])
    workbook.define_name(
        f"{sheet_name}!MxInDays",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_IN_DAYS + 1}",
    )

    # ------------------------------------------------------------------
    # Fill assumptions (Sean parity knobs, same as PLAYGROUND)
    # ------------------------------------------------------------------

    worksheet.write(ROW_FILL_TO_12_TYPE, COL_TRADE_LABEL, "To 12:", fmts["trade_label"])
    worksheet.write(ROW_FILL_TO_12_TYPE, COL_TRADE_VALUE, "ROOKIE", fmts["input_right"])
    worksheet.data_validation(
        ROW_FILL_TO_12_TYPE,
        COL_TRADE_VALUE,
        ROW_FILL_TO_12_TYPE,
        COL_TRADE_VALUE,
        {"validate": "list", "source": ["ROOKIE", "VET"]},
    )
    workbook.define_name(
        f"{sheet_name}!MxFillTo12MinType",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_FILL_TO_12_TYPE + 1}",
    )

    worksheet.write(ROW_FILL_TO_14_TYPE, COL_TRADE_LABEL, "To 14:", fmts["trade_label"])
    worksheet.write(ROW_FILL_TO_14_TYPE, COL_TRADE_VALUE, "VET", fmts["input_right"])
    worksheet.data_validation(
        ROW_FILL_TO_14_TYPE,
        COL_TRADE_VALUE,
        ROW_FILL_TO_14_TYPE,
        COL_TRADE_VALUE,
        {"validate": "list", "source": ["VET", "ROOKIE"]},
    )
    workbook.define_name(
        f"{sheet_name}!MxFillTo14MinType",
        f"={sheet_ref}!${col_letter(COL_TRADE_VALUE)}${ROW_FILL_TO_14_TYPE + 1}",
    )

    # Verdict display cell
    worksheet.write(0, COL_TRADE_LABEL - 1, "Verdict", fmts["trade_header"])
    worksheet.write_formula(0, COL_TRADE_LABEL, "=MxVerdict", fmts["trade_status"])

    verdict_cell = f"{col_letter(COL_TRADE_LABEL)}1"
    worksheet.conditional_format(
        verdict_cell,
        {"type": "formula", "criteria": f'={verdict_cell}="Trade Works"', "format": fmts["trade_status_valid"]},
    )
    worksheet.conditional_format(
        verdict_cell,
        {"type": "formula", "criteria": f'={verdict_cell}="Does Not Work"', "format": fmts["trade_status_invalid"]},
    )
