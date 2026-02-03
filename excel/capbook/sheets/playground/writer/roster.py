"""PLAYGROUND roster grid + conditional formatting."""

from __future__ import annotations

from typing import Any

from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import (
    COL_AGENT,
    COL_PCT_Y0,
    COL_PCT_Y1,
    COL_PCT_Y2,
    COL_PCT_Y3,
    COL_PLAYER,
    COL_RANK,
    COL_SAL_Y0,
    COL_SAL_Y1,
    COL_SAL_Y2,
    COL_SAL_Y3,
    COL_STATUS,
    COL_TOTAL,
    ROSTER_RESERVED,
    ROW_BODY_START,
    YEAR_OFFSETS,
    col_letter,
)


def write_roster(
    worksheet: Worksheet,
    fmts: dict[str, Any],
    *,
    base_year: int,
    salary_book_yearly_nrows: int,
    salary_book_warehouse_nrows: int,
) -> None:
    """Write the reactive roster grid and conditional formatting."""

    # ---------------------------------------------------------------------
    # Roster grid (reactive)
    # ---------------------------------------------------------------------
    roster_start = ROW_BODY_START
    roster_end = roster_start + ROSTER_RESERVED - 1

    # Names anchor (E4#)
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_PLAYER,
        roster_start,
        COL_PLAYER,
        formulas.roster_names_anchor(max_rows=ROSTER_RESERVED),
        fmts["player"],
    )

    # Important: don't reference spill ranges with the UI operator `#`.
    # In stored formulas, use ANCHORARRAY(<anchor_cell>) per XlsxWriter docs.
    names_anchor = f"{col_letter(COL_PLAYER)}{roster_start + 1}"  # e.g. E4
    names_spill = f"ANCHORARRAY({names_anchor})"

    # Rank (D4 spill) - skips traded/waived/stretched players
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_RANK,
        roster_start,
        COL_RANK,
        formulas.roster_rank_column(names_spill=names_spill),
        fmts["rank"],
    )

    # Salaries Y0..Y3 and % columns
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"

        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        pct_col = [COL_PCT_Y0, COL_PCT_Y1, COL_PCT_Y2, COL_PCT_Y3][i]

        worksheet.write_dynamic_array_formula(
            roster_start,
            sal_col,
            roster_start,
            sal_col,
            formulas.roster_salary_column(names_spill=names_spill, year_expr=year_expr, year_offset=off),
            fmts["money_m"],
        )

        cap_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])"
        sal_anchor = f"{col_letter(sal_col)}{roster_start + 1}"
        sal_arr = f"ANCHORARRAY({sal_anchor})"
        # % of cap (web parity): for true minimum contracts (min_contract_code=1OR2,
        # exposed as salary_book_warehouse.is_min_contract), show "MIN" instead of a
        # numeric percent.
        worksheet.write_dynamic_array_formula(
            roster_start,
            pct_col,
            roster_start,
            pct_col,
            # If salary is 0 we treat it as a non-contract display cell ("-")
            # or a Two-Way display cell (salary column is CF-overridden to "Two-Way").
            # In both cases, pct-cap should display "-" (not 0.0%).
            f"=LET(_xlpm.sal,{sal_arr},_xlpm.cap,{cap_level},_xlpm.isMin,IFERROR(XLOOKUP({names_spill},tbl_salary_book_warehouse[player_name],tbl_salary_book_warehouse[is_min_contract],FALSE),FALSE),IF(_xlpm.sal=0,\"-\",IF(_xlpm.isMin,\"MIN\",IFERROR(_xlpm.sal/_xlpm.cap,0))))",
            fmts["pct"],
        )

    # Total contract value (warehouse), fallback to visible years when missing.
    y0 = f"ANCHORARRAY({col_letter(COL_SAL_Y0)}{roster_start + 1})"
    y1 = f"ANCHORARRAY({col_letter(COL_SAL_Y1)}{roster_start + 1})"
    y2 = f"ANCHORARRAY({col_letter(COL_SAL_Y2)}{roster_start + 1})"
    y3 = f"ANCHORARRAY({col_letter(COL_SAL_Y3)}{roster_start + 1})"
    total_visible = f"IFERROR({y0}+{y1}+{y2}+{y3},0)"
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_TOTAL,
        roster_start,
        COL_TOTAL,
        "=LET("  # noqa: ISC003
        f"_xlpm.total,XLOOKUP({names_spill},tbl_salary_book_warehouse[player_name],tbl_salary_book_warehouse[total_salary_from_2025]),"
        f"_xlpm.visible,{total_visible},"
        "IFERROR(_xlpm.total,_xlpm.visible)"
        ")",
        fmts["money_m"],
    )

    # Agent (best-effort, from warehouse wide table)
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_AGENT,
        roster_start,
        COL_AGENT,
        f"=MAP({names_spill},LAMBDA(_xlpm.p,IFERROR(XLOOKUP(_xlpm.p,tbl_salary_book_warehouse[player_name],tbl_salary_book_warehouse[agent_name],\"\"),\"\")))",
        fmts["agent"],
    )

    # Status
    worksheet.write_dynamic_array_formula(
        roster_start,
        COL_STATUS,
        roster_start,
        COL_STATUS,
        formulas.roster_status_column(names_spill=names_spill),
        fmts["player"],
    )

    roster_range = f"{col_letter(COL_RANK)}{roster_start + 1}:{col_letter(COL_STATUS)}{roster_end + 1}"

    # Conditional formatting by status source lists.
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(TradeOutNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_out"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(WaivedNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_waived"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(StretchNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_stretch"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(TradeInNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_in"]},
    )
    worksheet.conditional_format(
        roster_range,
        {"type": "formula", "criteria": f"=COUNTIF(SignNames,${col_letter(COL_PLAYER)}{roster_start + 1})>0", "format": fmts["status_sign"]},
    )

    # -------------------------------------------------------------------------
    # Trade restrictions conditional formatting (red)
    #
    # Web parity (SalaryBook):
    # - No-Trade Clause (is_no_trade): red in ALL seasons, but options can take
    #   visual precedence in future years.
    # - Player consent required now (is_trade_consent_required_now): red in the
    #   current season only and should override other coloring.
    # - Trade restricted now (is_trade_restricted_now): red in the current
    #   season only and should override other coloring.
    #
    # We avoid structured refs / XLOOKUP in conditional formatting to prevent
    # Excel "repair" warnings. We also avoid hardcoding column letters for the
    # boolean flags by using MATCH() against the header row.
    # -------------------------------------------------------------------------

    player_ref = f"${col_letter(COL_PLAYER)}{roster_start + 1}"  # e.g. $E4

    # Performance: shrink fixed sheet ranges to the actual table size instead of
    # scanning thousands of blank rows in conditional formatting formulas.
    sbw_rows = max(int(salary_book_warehouse_nrows), 1)
    sbw_end = sbw_rows + 1  # header is row 1; data starts at row 2
    sbw_hdr = "DATA_salary_book_warehouse!$1:$1"
    sbw_data = f"DATA_salary_book_warehouse!$A$2:$ZZ${sbw_end}"

    sbw_name = f'INDEX({sbw_data},0,MATCH("player_name",{sbw_hdr},0))'
    sbw_no_trade = f'INDEX({sbw_data},0,MATCH("is_no_trade",{sbw_hdr},0))'
    sbw_trade_bonus = f'INDEX({sbw_data},0,MATCH("is_trade_bonus",{sbw_hdr},0))'
    sbw_consent = f'INDEX({sbw_data},0,MATCH("is_trade_consent_required_now",{sbw_hdr},0))'
    sbw_trade_restricted = f'INDEX({sbw_data},0,MATCH("is_trade_restricted_now",{sbw_hdr},0))'

    # NOTE: salary_book_warehouse is 1 row per player. We match by player_name
    # only (no team_code filter) so trade-in rows still get correct styling.
    cond_no_trade = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_no_trade}=TRUE))>0"
    cond_trade_bonus = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_trade_bonus}=TRUE))>0"
    cond_consent = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_consent}=TRUE))>0"
    cond_trade_restricted = f"SUMPRODUCT(({sbw_name}={player_ref})*({sbw_trade_restricted}=TRUE))>0"
    cond_restricted_now = f"OR({cond_consent},{cond_trade_restricted})"

    # -------------------------------------------------------------------------
    # Two-way salary display: show "Two-Way" (gray pill) instead of "-".
    #
    # IMPORTANT: Conditional formatting formulas have quirks (see options block
    # below). We avoid structured refs and XLOOKUP here.
    #
    # DATA_salary_book_yearly columns:
    #   B=player_name, C=team_code, D=salary_year, E=cap_amount, H=is_two_way
    #
    # Two-Way contracts can be 1 or 2 years. We must check that cap_amount is
    # not blank (NULL in DB = empty cell) to confirm an actual contract row
    # exists for that year. Otherwise we'd show the pill for projected years
    # where the player isn't actually under contract.
    # -------------------------------------------------------------------------
    yearly_rows = max(int(salary_book_yearly_nrows), 1)
    data_end = yearly_rows + 1  # header is row 1; data starts at row 2
    rng_name = f"DATA_salary_book_yearly!$B$2:$B${data_end}"
    rng_team = f"DATA_salary_book_yearly!$C$2:$C${data_end}"
    rng_year = f"DATA_salary_book_yearly!$D$2:$D${data_end}"
    rng_cap = f"DATA_salary_book_yearly!$E$2:$E${data_end}"
    rng_tw = f"DATA_salary_book_yearly!$H$2:$H${data_end}"

    trade_in_flag = f"COUNTIF(TradeInNames,{player_ref})>0"

    # NOTE: player_ref is defined above (used for both restriction + two-way logic)

    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]

        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"
        sal_cell = f"{col_letter(sal_col)}{roster_start + 1}"  # relative row in CF

        # Only apply when:
        #  - this salary cell is 0 (so we don't hide real numeric values)
        #  - the player is marked as two-way for the selected team or trade-ins + year
        #  - the player has a non-blank cap_amount for that year (i.e. actual contract)
        tw_cond_team = (
            f"SUMPRODUCT(({rng_team}=SelectedTeam)*({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_tw}=TRUE)*({rng_cap}<>\"\"))>0"
        )
        tw_cond_any = (
            f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_tw}=TRUE)*({rng_cap}<>\"\"))>0"
        )

        # Two-Way contracts can be trade restricted / consent-required in the current season.
        # In web/ we render the Two-Way badge red in that case; replicate here by using a
        # dedicated red pill format.
        if off == 0:
            worksheet.conditional_format(
                col_range,
                {
                    "type": "formula",
                    "criteria": f"=AND({sal_cell}=0,{tw_cond_any},{cond_restricted_now})",
                    "format": fmts["two_way_salary_restricted"],
                    "stop_if_true": True,
                },
            )

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({sal_cell}=0,{trade_in_flag},{tw_cond_any})",
                "format": fmts["two_way_salary_in"],
                "stop_if_true": True,
            },
        )

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({sal_cell}=0,{tw_cond_team})",
                "format": fmts["two_way_salary"],
                "stop_if_true": True,
            },
        )

    # -------------------------------------------------------------------------
    # Current-season trade restrictions (override other coloring)
    #
    # Applies ONLY to the base-year salary column. This matches web/ where
    # consent-required and trade-restricted flags are "current season" behavior.
    #
    # NOTE: Two-Way restricted players are handled above with a dedicated
    # two_way_salary_restricted pill so we preserve the "Two-Way" display.
    # -------------------------------------------------------------------------
    y0_range = f"{col_letter(COL_SAL_Y0)}{roster_start + 1}:{col_letter(COL_SAL_Y0)}{roster_end + 1}"
    worksheet.conditional_format(
        y0_range,
        {
            "type": "formula",
            "criteria": f"={cond_restricted_now}",
            "format": fmts["trade_restriction"],
            "stop_if_true": True,
        },
    )

    # -------------------------------------------------------------------------
    # Contract option conditional formatting (Team Option / Player Option)
    #
    # Web parity (PlayerRow.tsx): options ALWAYS take precedence visually over
    # no-trade in future seasons.
    #
    # IMPORTANT: Avoid structured refs / XLOOKUP in CF; use INDEX/MATCH with
    # absolute sheet references.
    # -------------------------------------------------------------------------

    for i, off in enumerate(YEAR_OFFSETS):
        # Skip base year - options already decided for current season
        if off == 0:
            continue

        year_num = base_year + off
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"

        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"

        # Only color true contract years (avoid tinting trailing '-' years).
        # NOTE: We don't team-scope this check; roster salary lookups aren't team-scoped.
        has_contract = f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_cap}<>\"\"))>0"

        # Option value from DATA_salary_book_warehouse (schema evolves; lookup by header name).
        opt_expr = f'INDEX({sbw_data},0,MATCH("option_{year_num}",{sbw_hdr},0))'

        has_team_option = f'SUMPRODUCT(({sbw_name}={player_ref})*({opt_expr}="TEAM"))>0'
        has_player_option = f'SUMPRODUCT(({sbw_name}={player_ref})*({opt_expr}="PLYR"))>0'

        # Team Option (TO) - purple
        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{has_team_option})",
                "format": fmts["option_team"],
                "stop_if_true": True,
            },
        )

        # Player Option (PO) - blue
        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{has_player_option})",
                "format": fmts["option_player"],
                "stop_if_true": True,
            },
        )

    # -------------------------------------------------------------------------
    # Trade kicker / trade bonus (orange)
    #
    # Matches web behavior at a high level:
    # - Only tint real contract years (avoid trailing '-' years)
    # - Options (PO/TO) should win (we add option CF above with stop_if_true)
    # - No-trade should win over this (we add no-trade CF below)
    # -------------------------------------------------------------------------
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"

        has_contract = f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_cap}<>\"\"))>0"

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{cond_trade_bonus})",
                "format": fmts["trade_kicker"],
            },
        )

    # -------------------------------------------------------------------------
    # No-Trade Clause (all seasons, but only for actual contract years)
    #
    # Must come AFTER option CF so options take precedence (Excel CF priority).
    # Also comes AFTER trade kicker so no-trade wins over orange.
    # -------------------------------------------------------------------------
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        sal_col = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3][i]
        col_range = f"{col_letter(sal_col)}{roster_start + 1}:{col_letter(sal_col)}{roster_end + 1}"

        has_contract = f"SUMPRODUCT(({rng_name}={player_ref})*({rng_year}={year_expr})*({rng_cap}<>\"\"))>0"

        worksheet.conditional_format(
            col_range,
            {
                "type": "formula",
                "criteria": f"=AND({has_contract},{cond_no_trade})",
                "format": fmts["trade_restriction"],
            },
        )
