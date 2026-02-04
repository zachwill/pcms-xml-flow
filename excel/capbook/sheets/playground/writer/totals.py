"""PLAYGROUND totals block.

Includes:
- Scenario totals + room vs thresholds
- Exceptions inventory
- Draft pick ownership summary (team-facing)

Design:
- All outputs remain worksheet-scoped so duplicating a Playground tab stays
  self-contained.
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..layout import (
    COL_AGENT,
    COL_PCT_Y0,
    COL_PCT_Y1,
    COL_PCT_Y2,
    COL_PCT_Y3,
    COL_PCT_Y4,
    COL_PCT_Y5,
    COL_PLAYER,
    COL_RANK,
    COL_SAL_Y0,
    COL_SAL_Y1,
    COL_SAL_Y2,
    COL_SAL_Y3,
    COL_SAL_Y4,
    COL_SAL_Y5,
    COL_TOTAL,
    ROSTER_RESERVED,
    ROW_BODY_START,
    YEAR_OFFSETS,
    col_letter,
)


def _quote_sheet(sheet_name: str) -> str:
    return "'" + sheet_name.replace("'", "''") + "'"


def write_totals(
    workbook: Workbook,
    worksheet: Worksheet,
    fmts: dict[str, Any],
) -> None:
    """Write the totals block below the roster grid."""

    sheet_name = worksheet.get_name()
    sheet_ref = _quote_sheet(sheet_name)

    salary_cols = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3, COL_SAL_Y4, COL_SAL_Y5]
    pct_cols = [COL_PCT_Y0, COL_PCT_Y1, COL_PCT_Y2, COL_PCT_Y3, COL_PCT_Y4, COL_PCT_Y5]

    # Totals block immediately after roster (just 1 row gap)
    roster_start = ROW_BODY_START
    roster_end = roster_start + ROSTER_RESERVED - 1
    totals_start = roster_end + 2

    row = totals_start

    def year_label(off: int) -> str:
        return (
            "=TEXT(MOD(MetaBaseYear+{o},100),\"00\")&\"-\"&TEXT(MOD(MetaBaseYear+{o1},100),\"00\")".format(
                o=off,
                o1=off + 1,
            )
        )

    # ---------------------------------------------------------------------
    # TOTALS (Scenario)
    # ---------------------------------------------------------------------

    worksheet.write(row, COL_PLAYER, "TOTALS (Scenario)", fmts["totals_section"])

    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], year_label(off), fmts["totals_section"])

    legend_col = COL_AGENT
    legend_row = row
    worksheet.write(legend_row, legend_col, "LEGEND", fmts["totals_section"])
    legend_items = [
        ("PLAYER OPTION", fmts["option_player"]),
        ("TEAM OPTION", fmts["option_team"]),
        ("TRADE BONUS", fmts["trade_kicker"]),
        ("TRADE RESTRICTION", fmts["trade_restriction"]),
    ]
    for i, (label, fmt) in enumerate(legend_items, start=1):
        worksheet.write(legend_row + i, legend_col, label, fmt)

    row += 1

    # Scenario totals (layer-specific)
    worksheet.write(row, COL_PLAYER, "Cap Total (scenario)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnCapTotal{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Total (scenario)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnTaxTotal{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron Total (scenario)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnApronTotal{off}", fmts["totals_value"])
    row += 1

    # Dead money (modeling layer; informational)
    worksheet.write(row, COL_PLAYER, "Dead Money", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnDeadMoney{off}", fmts["totals_value"])
    row += 1

    # Roster fill (Sean convention, with configurable assumptions via the left rail)
    worksheet.write(row, COL_PLAYER, "Fill (to 12)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnFill12Amount{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Fill (to 14)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnFill14Amount{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Fill Total", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnFillAmount{off}", fmts["totals_value"])
    row += 1

    # Filled totals (must be used for posture/threshold room)
    worksheet.write(row, COL_PLAYER, "Cap Total (filled)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnCapTotalFilled{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Total (filled)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnTaxTotalFilled{off}", fmts["totals_value"])
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron Total (filled)", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnApronTotalFilled{off}", fmts["totals_value"])
    row += 1

    # ---------------------------------------------------------------------
    # Room vs thresholds (green if >=0, red if <0)
    # ---------------------------------------------------------------------

    worksheet.write(row, COL_PLAYER, "Cap Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        cap_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])"
        col = salary_cols[i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={cap_level}-ScnCapTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        tax_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[tax_level_amount])"
        col = salary_cols[i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={tax_level}-ScnTaxTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron 1 Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        apron1 = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[tax_apron_amount])"
        col = salary_cols[i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={apron1}-ScnApronTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Apron 2 Room", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        apron2 = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[tax_apron2_amount])"
        col = salary_cols[i]
        cell = f"{col_letter(col)}{row + 1}"
        worksheet.write_formula(row, col, f"={apron2}-ScnApronTotalFilled{off}", fmts["totals_delta_pos"])
        worksheet.conditional_format(cell, {"type": "cell", "criteria": ">=", "value": 0, "format": fmts["totals_delta_pos"]})
        worksheet.conditional_format(cell, {"type": "cell", "criteria": "<", "value": 0, "format": fmts["totals_delta_neg"]})
    row += 1

    worksheet.write(row, COL_PLAYER, "Tax Payment", fmts["totals_label"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(row, salary_cols[i], f"=ScnTaxPayment{off}", fmts["totals_value"])
    row += 2

    # ---------------------------------------------------------------------
    # EXCEPTIONS (inventory)
    # ---------------------------------------------------------------------

    worksheet.write(row, COL_PLAYER, "EXCEPTIONS", fmts["totals_section"])

    def exc_cell(idx: int, col: int) -> str:
        """Fetch a single field from the sorted exceptions inventory.

        Columns in the backing array:
          1 = display_name
          2 = expiration_date
          3 = exception_type_lk
          4 = remaining_amount (prorated when available)
        """

        formula = (
            "=LET("  # noqa: ISC003
            "_xlpm.team,SelectedTeam,"
            "_xlpm.y,MetaBaseYear,"
            # Prefer player name when present (TPE, Disabled Player, etc.) to match web/.
            "_xlpm.disp,IF(tbl_exceptions_warehouse[trade_exception_player_name]<>\"\","
            "tbl_exceptions_warehouse[trade_exception_player_name],"
            "tbl_exceptions_warehouse[exception_type_name]),"
            "_xlpm.rem,IF(tbl_exceptions_warehouse[prorated_remaining_amount]=\"\","
            "tbl_exceptions_warehouse[remaining_amount],"
            "tbl_exceptions_warehouse[prorated_remaining_amount]),"
            "_xlpm.exp,IF(tbl_exceptions_warehouse[expiration_date]=\"\",\"\",INT(tbl_exceptions_warehouse[expiration_date])),"
            "_xlpm.lk,tbl_exceptions_warehouse[exception_type_lk],"
            # Coarse type bucket (keep unknown codes as-is)
            "_xlpm.type,IF(OR(_xlpm.lk=\"MLE\",_xlpm.lk=\"NTPMLE\",_xlpm.lk=\"TPMLE\",_xlpm.lk=\"CNTPMLE\",_xlpm.lk=\"RMLE\"),\"MLE\",IF(_xlpm.lk=\"BAE\",\"BAE\",IF(_xlpm.lk=\"TPE\",\"TPE\",_xlpm.lk))),"
            "_xlpm.arr,CHOOSE({1,2,3,4},_xlpm.type,_xlpm.disp,_xlpm.rem,_xlpm.exp),"
            "_xlpm.mask,(tbl_exceptions_warehouse[team_code]=_xlpm.team)"
            "*(tbl_exceptions_warehouse[salary_year]=_xlpm.y)"
            "*(tbl_exceptions_warehouse[record_status_lk]=\"APPR\")"
            "*(tbl_exceptions_warehouse[is_expired]<>TRUE)"
            "*(_xlpm.rem>0),"
            "_xlpm.f,IFERROR(FILTER(_xlpm.arr,_xlpm.mask),\"\"),"
            "_xlpm.s,IFERROR(SORTBY(_xlpm.f,INDEX(_xlpm.f,,3),-1),\"\"),"
            f"IFERROR(INDEX(_xlpm.s,{idx},{col}),\"\")"
            ")"
        )

        # Guard against Excel repair warnings from accidental typos.
        assert formula.count("(") == formula.count(")"), formula
        return formula

    # Table headers (shifted left; start at D)
    hdr_row = row + 1
    worksheet.write(hdr_row, COL_RANK, "Type", fmts["trade_header"])
    worksheet.write(hdr_row, COL_PLAYER, "Exception", fmts["trade_header"])
    worksheet.write(hdr_row, COL_SAL_Y0, "Remaining", fmts["trade_header"])
    worksheet.write(hdr_row, COL_PCT_Y0, "Expires", fmts["trade_header"])

    exc_rows = 8
    for i in range(exc_rows):
        r = hdr_row + 1 + i
        worksheet.write_formula(r, COL_RANK, exc_cell(i + 1, 1), fmts["trade_label"])
        worksheet.write_formula(r, COL_PLAYER, exc_cell(i + 1, 2), fmts["trade_text"])
        worksheet.write_formula(r, COL_SAL_Y0, exc_cell(i + 1, 3), fmts["trade_value"])
        worksheet.write_formula(r, COL_PCT_Y0, exc_cell(i + 1, 4), fmts["trade_date"])

    row = hdr_row + 1 + exc_rows + 1

    # ---------------------------------------------------------------------
    # DRAFT PICKS (team-facing summary from tbl_draft_picks_warehouse)
    # ---------------------------------------------------------------------

    worksheet.write(row, COL_PLAYER, "DRAFT PICKS", fmts["totals_section"])
    row += 1

    # Layout: similar to EXCEPTIONS (Type rows + season columns).
    # Note: the "25-26" season corresponds to the **2026 Draft** (MetaBaseYear+1).
    picks_hdr = row
    worksheet.write(picks_hdr, COL_RANK, "Type", fmts["trade_header"])

    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.merge_range(
            picks_hdr,
            salary_cols[i],
            picks_hdr,
            pct_cols[i],
            year_label(off),
            fmts["trade_header"],
        )

    row += 1

    def picks_cell(*, year_expr: str, round_num: int) -> str:
        """Return a TEXTJOIN'd pick ownership string for (SelectedTeam, draft_year, round).

        Adds a small "(!)" suffix if any matching rows are flagged needs_review.
        """

        mask = (
            f"(tbl_draft_picks_warehouse[team_code]=_xlpm.team)"
            f"*(tbl_draft_picks_warehouse[draft_year]=_xlpm.y)"
            f"*(tbl_draft_picks_warehouse[draft_round]={round_num})"
        )

        return (
            "=LET("  # noqa: ISC003
            "_xlpm.team,SelectedTeam,"
            f"_xlpm.y,{year_expr},"
            f"_xlpm.mask,{mask},"
            "_xlpm.txt,FILTER(tbl_draft_picks_warehouse[raw_fragment],_xlpm.mask,\"\"),"
            "_xlpm.base,IF(_xlpm.txt=\"\",\"\",TEXTJOIN(\"; \",TRUE,_xlpm.txt)),"
            "_xlpm.review,SUMPRODUCT(_xlpm.mask*(tbl_draft_picks_warehouse[needs_review]=TRUE))>0,"
            "IF(_xlpm.base=\"\",\"\",_xlpm.base&IF(_xlpm.review,\" (!)\",\"\"))"
            ")"
        )

    for label, round_num in [("FRP", 1), ("SRP", 2)]:
        r = row

        worksheet.write(r, COL_RANK, label, fmts["trade_label"])

        for i, off in enumerate(YEAR_OFFSETS):
            draft_year_expr = f"MetaBaseYear+{off + 1}"

            worksheet.merge_range(
                r,
                salary_cols[i],
                r,
                pct_cols[i],
                picks_cell(year_expr=draft_year_expr, round_num=round_num),
                fmts["picks_text"],
            )

        # Long text tends to wrap; give it some headroom.
        worksheet.set_row(r, 32)

        row += 1

    row += 1
