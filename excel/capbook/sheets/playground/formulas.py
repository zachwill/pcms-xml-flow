"""PLAYGROUND Excel formula builders.

These return Excel formula strings (including leading '=') and are used by the
sheet writer.

We prefer modern Excel functions: LET/FILTER/SORTBY/XLOOKUP/MAP.
"""

from __future__ import annotations


def _xlookup_team_warehouse(col_name: str, *, year_expr: str) -> str:
    """XLOOKUP into tbl_team_salary_warehouse for SelectedTeam and year_expr."""

    return (
        "XLOOKUP("  # noqa: ISC003
        f"SelectedTeam&({year_expr}),"  # noqa: ISC003
        "tbl_team_salary_warehouse[team_code]&tbl_team_salary_warehouse[salary_year],"  # noqa: ISC003
        f"tbl_team_salary_warehouse[{col_name}]"  # noqa: ISC003
        ")"
    )


def _count_unique_nonblank(range_name: str) -> str:
    """Count unique, non-empty values in a 1-col range."""

    # FILTER() with no matches throws; IFERROR guards that.
    return f"IFERROR(ROWS(UNIQUE(FILTER({range_name},{range_name}<>\"\"))),0)"


def sum_names_salary_yearly(
    names_range: str,
    *,
    year_expr: str,
    team_scoped: bool,
    salary_col: str = "cap_amount",
) -> str:
    """Sum a salary column for a list of player names in tbl_salary_book_yearly.

    Args:
        names_range: Named range like TradeOutNames
        year_expr: Excel expression that evaluates to a year (e.g. MetaBaseYear+1)
        team_scoped: If true, only match rows where team_code=SelectedTeam
        salary_col: Column in tbl_salary_book_yearly to sum (e.g. cap_amount,
            incoming_cap_amount, outgoing_apron_amount).
    """

    # Build boolean mask as multiplication (AND).
    mask = f"(tbl_salary_book_yearly[salary_year]=_xlpm.y)"
    if team_scoped:
        mask += "*(tbl_salary_book_yearly[team_code]=_xlpm.team)"

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.y,{year_expr},"  # noqa: ISC003
        "_xlpm.team,SelectedTeam,"
        f"_xlpm.has,COUNTA({names_range})>0,"
        f"_xlpm.n,IF(_xlpm.has,UNIQUE(FILTER({names_range},{names_range}<>\"\")),\"\"),"
        f"_xlpm.names,FILTER(tbl_salary_book_yearly[player_name],{mask}),"
        f"_xlpm.sals,FILTER(tbl_salary_book_yearly[{salary_col}],{mask}),"
        "IF(_xlpm.has,SUM(IFERROR(XLOOKUP(_xlpm.n,_xlpm.names,_xlpm.sals,0),0)),0)"
        ")"
    )


def stretch_dead_money_yearly(*, year_expr: str, amount_col: str = "cap_amount") -> str:
    """Approximate NBA stretch dead money for StretchNames for a given year.

    Simplified modeling:
    - For each stretched player, compute remaining salary total from MetaBaseYear onward
      (team-scoped to SelectedTeam).
    - Determine years_remaining as the number of future salary years with amount_col>0.
    - Stretch years = 2*years_remaining + 1.
    - Dead money per year = remaining_total / stretch_years.
    - If year < MetaBaseYear + stretch_years, apply per-year amount, else 0.

    This is intentionally approximate but directionally correct.

    Args:
        year_expr: Excel expression that evaluates to a salary_year.
        amount_col: Column in tbl_salary_book_yearly to use as the “salary stream”.
            Use cap_amount / tax_amount / apron_amount depending on the layer.
    """

    # If FILTER has no matches, SUM(MAP(...)) throws; IFERROR guards to 0.
    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.y,{year_expr},"
        "_xlpm.base,MetaBaseYear,"
        "_xlpm.team,SelectedTeam,"
        "IFERROR("
        "SUM(MAP(FILTER(StretchNames,StretchNames<>\"\"),LAMBDA(_xlpm.p,"
        "LET("
        "_xlpm.mask,(tbl_salary_book_yearly[player_name]=_xlpm.p)"
        "*(tbl_salary_book_yearly[team_code]=_xlpm.team)"
        "*(tbl_salary_book_yearly[salary_year]>=_xlpm.base)"
        f"*(tbl_salary_book_yearly[{amount_col}]>0),"
        "_xlpm.yrsRem,IFERROR(ROWS(FILTER(tbl_salary_book_yearly[salary_year],_xlpm.mask)),0),"
        f"_xlpm.remTot,SUM(IFERROR(FILTER(tbl_salary_book_yearly[{amount_col}],_xlpm.mask),0)),"
        "_xlpm.stretchYrs,2*_xlpm.yrsRem+1,"
        "_xlpm.perYr,IF(_xlpm.stretchYrs=0,0,_xlpm.remTot/_xlpm.stretchYrs),"
        "IF(_xlpm.y<_xlpm.base+_xlpm.stretchYrs,_xlpm.perYr,0)"
        ")"  # close inner LET
        "))),"  # close LAMBDA, MAP, SUM + comma for IFERROR 2nd arg
        "0)"  # IFERROR default + close IFERROR
        ")"  # close outer LET
    )


def scenario_roster_count(*, year_expr: str) -> str:
    """Scenario roster count for a year.

    base - trade_out - waive - stretch + trade_in + sign
    """

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.base,{_xlookup_team_warehouse('roster_row_count', year_expr=year_expr)},"
        f"_xlpm.out,{_count_unique_nonblank('TradeOutNames')},"
        f"_xlpm.waive,{_count_unique_nonblank('WaivedNames')},"
        f"_xlpm.stretch,{_count_unique_nonblank('StretchNames')},"
        f"_xlpm.in,{_count_unique_nonblank('TradeInNames')},"
        f"_xlpm.sign,{_count_unique_nonblank('SignNames')},"
        "MAX(0,_xlpm.base-_xlpm.out-_xlpm.waive-_xlpm.stretch+_xlpm.in+_xlpm.sign)"
        ")"
    )


def _as_expr(formula: str) -> str:
    """Convert a standalone formula string into an expression for nesting.

    XlsxWriter `define_name()` stores formulas without the leading `=` in the
    XML, but our Python helpers often return strings that *include* `=`.

    If you embed a returned formula (like `=LET(...)`) inside another formula,
    the nested `=` becomes illegal Excel syntax and can trigger Excel repair/
    "macro"-style warnings.

    This helper strips a single leading `=` when present.
    """

    if formula.startswith("="):
        return formula[1:]
    return formula


def scenario_team_total(*, year_expr: str, year_offset: int) -> str:
    """Scenario cap_total for a year (cap layer).

    - Trade Out removes salary (team-scoped)
    - Trade In adds salary (league-wide)
    - Sign adds salary (base year only)
    - Waive reclassifies to dead money (net 0 to cap_total)
    - Stretch re-times salary: remove original salaries and add stretched dead money

    This is still v1 modeling.
    """

    base = _xlookup_team_warehouse("cap_total", year_expr=year_expr)

    # IMPORTANT: sub-formulas must be embedded as expressions (no leading `=`).
    out_ = _as_expr(sum_names_salary_yearly("TradeOutNames", year_expr=year_expr, team_scoped=True))
    in_ = _as_expr(
        sum_names_salary_yearly(
            "TradeInNames",
            year_expr=year_expr,
            team_scoped=False,
            salary_col="incoming_cap_amount",
        )
    )

    # For stretch: remove original salaries (team-scoped) and add stretched per-year amounts.
    stretch_removed = _as_expr(sum_names_salary_yearly("StretchNames", year_expr=year_expr, team_scoped=True))
    stretch_dead = _as_expr(stretch_dead_money_yearly(year_expr=year_expr))

    # Sign (base year only)
    sign = "SUM(SignSalaries)" if year_offset == 0 else "0"

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.base,{base},"
        f"_xlpm.out,{out_},"
        f"_xlpm.in,{in_},"
        f"_xlpm.sign,{sign},"
        f"_xlpm.stretchRemoved,{stretch_removed},"
        f"_xlpm.stretchDead,{stretch_dead},"
        "_xlpm.base-_xlpm.out+_xlpm.in+_xlpm.sign-_xlpm.stretchRemoved+_xlpm.stretchDead"
        ")"
    )


def scenario_tax_total(*, year_expr: str, year_offset: int) -> str:
    """Scenario tax_total for a year (tax layer).

    Same adjustments as scenario_team_total but using tax_total as base and the
    tax_amount/incoming_tax_amount salary columns.
    """

    base = _xlookup_team_warehouse("tax_total", year_expr=year_expr)

    # IMPORTANT: sub-formulas must be embedded as expressions (no leading `=`).
    out_ = _as_expr(
        sum_names_salary_yearly(
            "TradeOutNames",
            year_expr=year_expr,
            team_scoped=True,
            salary_col="tax_amount",
        )
    )
    in_ = _as_expr(
        sum_names_salary_yearly(
            "TradeInNames",
            year_expr=year_expr,
            team_scoped=False,
            salary_col="incoming_tax_amount",
        )
    )

    # For stretch: remove original salaries (team-scoped) and add stretched per-year amounts.
    stretch_removed = _as_expr(
        sum_names_salary_yearly(
            "StretchNames",
            year_expr=year_expr,
            team_scoped=True,
            salary_col="tax_amount",
        )
    )
    stretch_dead = _as_expr(stretch_dead_money_yearly(year_expr=year_expr, amount_col="tax_amount"))

    # Sign (base year only)
    sign = "SUM(SignSalaries)" if year_offset == 0 else "0"

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.base,{base},"
        f"_xlpm.out,{out_},"
        f"_xlpm.in,{in_},"
        f"_xlpm.sign,{sign},"
        f"_xlpm.stretchRemoved,{stretch_removed},"
        f"_xlpm.stretchDead,{stretch_dead},"
        "_xlpm.base-_xlpm.out+_xlpm.in+_xlpm.sign-_xlpm.stretchRemoved+_xlpm.stretchDead"
        ")"
    )


def scenario_apron_total(*, year_expr: str, year_offset: int) -> str:
    """Scenario apron_total for a year (apron layer).

    Semantics:
    - Base: tbl_team_salary_warehouse[apron_total]
    - Trade Out: subtract outgoing_apron_amount (team-scoped)
    - Trade In: add incoming_apron_amount (NOT team-scoped)
    - Sign: base year only (treated as counting everywhere)
    - Waive: v1 semantics (reclassification; net 0)
    - Stretch: remove original apron_amount stream and add stretched dead money
      stream computed from apron_amount.
    """

    base = _xlookup_team_warehouse("apron_total", year_expr=year_expr)

    out_ = _as_expr(
        sum_names_salary_yearly(
            "TradeOutNames",
            year_expr=year_expr,
            team_scoped=True,
            salary_col="outgoing_apron_amount",
        )
    )
    in_ = _as_expr(
        sum_names_salary_yearly(
            "TradeInNames",
            year_expr=year_expr,
            team_scoped=False,
            salary_col="incoming_apron_amount",
        )
    )

    stretch_removed = _as_expr(
        sum_names_salary_yearly(
            "StretchNames",
            year_expr=year_expr,
            team_scoped=True,
            salary_col="apron_amount",
        )
    )
    stretch_dead = _as_expr(stretch_dead_money_yearly(year_expr=year_expr, amount_col="apron_amount"))

    sign = "SUM(SignSalaries)" if year_offset == 0 else "0"

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.base,{base},"
        f"_xlpm.out,{out_},"
        f"_xlpm.in,{in_},"
        f"_xlpm.sign,{sign},"
        f"_xlpm.stretchRemoved,{stretch_removed},"
        f"_xlpm.stretchDead,{stretch_dead},"
        "_xlpm.base-_xlpm.out+_xlpm.in+_xlpm.sign-_xlpm.stretchRemoved+_xlpm.stretchDead"
        ")"
    )


def scenario_dead_money(*, year_expr: str) -> str:
    """Scenario dead money (cap_term proxy) for a year.

    Base cap_term + waived salaries + stretched dead money.

    Note: This is a modeling layer; it will not reconcile to warehouse by design.
    """

    base_term = _xlookup_team_warehouse("cap_term", year_expr=year_expr)

    waived = _as_expr(sum_names_salary_yearly("WaivedNames", year_expr=year_expr, team_scoped=True))
    stretched = _as_expr(stretch_dead_money_yearly(year_expr=year_expr))

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.base,{base_term},"
        f"_xlpm.waived,{waived},"
        f"_xlpm.stretch,{stretched},"
        "_xlpm.base+_xlpm.waived+_xlpm.stretch"
        ")"
    )


def roster_names_anchor(*, max_rows: int) -> str:
    """Spilled roster player_name list including trade-ins and signs.

    Sorted by base-year salary (sign salaries override lookup for sorting).
    """

    return (
        "=LET("  # noqa: ISC003
        "_xlpm.y,MetaBaseYear,"
        "_xlpm.team,SelectedTeam,"
        "_xlpm.baseMask,(tbl_salary_book_yearly[team_code]=_xlpm.team)*(tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.baseNames,FILTER(tbl_salary_book_yearly[player_name],_xlpm.baseMask),"
        "_xlpm.baseSals,FILTER(tbl_salary_book_yearly[cap_amount],_xlpm.baseMask),"
        "_xlpm.baseSorted,CHOOSECOLS(SORTBY(HSTACK(_xlpm.baseNames,_xlpm.baseSals),_xlpm.baseSals,-1),1),"
        "_xlpm.tradeIn,IFERROR(FILTER(TradeInNames,TradeInNames<>\"\"),\"\"),"
        "_xlpm.sign,IFERROR(FILTER(SignNames,SignNames<>\"\"),\"\"),"
        "_xlpm.all,VSTACK(_xlpm.baseSorted,_xlpm.tradeIn,_xlpm.sign),"
        "_xlpm.u,UNIQUE(FILTER(_xlpm.all,_xlpm.all<>\"\")),"
        "_xlpm.namesY,FILTER(tbl_salary_book_yearly[player_name],tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.salsY,FILTER(tbl_salary_book_yearly[cap_amount],tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.salsInY,FILTER(tbl_salary_book_yearly[incoming_cap_amount],tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.sortSal,MAP(_xlpm.u,LAMBDA(_xlpm.p,"
        "LET("
        "_xlpm.ss,IFERROR(XLOOKUP(_xlpm.p,SignNames,SignSalaries,0),0),"
        "_xlpm.db,IF(COUNTIF(TradeInNames,_xlpm.p)>0,IFERROR(XLOOKUP(_xlpm.p,_xlpm.namesY,_xlpm.salsInY,0),0),IFERROR(XLOOKUP(_xlpm.p,_xlpm.namesY,_xlpm.salsY,0),0)),"
        "IF(_xlpm.ss>0,_xlpm.ss,_xlpm.db)"
        ")"  # close inner LET
        ")),"  # close LAMBDA, MAP + comma for outer LET's next param
        "TAKE(SORTBY(_xlpm.u,_xlpm.sortSal,-1),"
        f"{max_rows}"
        ")"  # close TAKE
        ")"  # close outer LET
    )


def roster_salary_column(*, names_spill: str, year_expr: str, year_offset: int) -> str:
    """Roster salary column for a given year.

    Notes:
      - `names_spill` should be a stored-formula-compatible spill reference, i.e.
        `ANCHORARRAY(E4)`, not `E4#`.
    """

    # Sign salaries only apply in base year.
    if year_offset == 0:
        sign_override = (
            "IF(COUNTIF(SignNames,_xlpm.p)>0,IFERROR(XLOOKUP(_xlpm.p,SignNames,SignSalaries,0),0),"
        )
        sign_close = ")"
    else:
        sign_override = ""
        sign_close = ""

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.y,{year_expr},"
        "_xlpm.namesY,FILTER(tbl_salary_book_yearly[player_name],tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.salsY,FILTER(tbl_salary_book_yearly[cap_amount],tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.salsInY,FILTER(tbl_salary_book_yearly[incoming_cap_amount],tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        f"MAP({names_spill},LAMBDA(_xlpm.p,"
        f"{sign_override}"
        "IF(COUNTIF(TradeInNames,_xlpm.p)>0,"
        "IFERROR(XLOOKUP(_xlpm.p,_xlpm.namesY,_xlpm.salsInY,0),0),"
        "IFERROR(XLOOKUP(_xlpm.p,_xlpm.namesY,_xlpm.salsY,0),0)"
        ")"
        f"{sign_close}"
        "))"
        ")"
    )


def roster_status_column(*, names_spill: str) -> str:
    """Roster status derived from input name ranges."""

    return (
        "=MAP("  # noqa: ISC003
        f"{names_spill},"  # noqa: ISC003
        "LAMBDA(_xlpm.p,"
        "IF(COUNTIF(TradeOutNames,_xlpm.p)>0,\"OUT\","  # noqa: ISC003
        "IF(COUNTIF(WaivedNames,_xlpm.p)>0,\"WAIVED\","  # noqa: ISC003
        "IF(COUNTIF(StretchNames,_xlpm.p)>0,\"STRETCH\","  # noqa: ISC003
        "IF(COUNTIF(SignNames,_xlpm.p)>0,\"SIGN\","  # noqa: ISC003
        "IF(COUNTIF(TradeInNames,_xlpm.p)>0,\"IN\",\"\")"  # noqa: ISC003
        ")))))"
        ")"
    )


def roster_rank_column(*, names_spill: str) -> str:
    """Roster rank column that matches the roster KPI semantics.

    - Blanks OUT/WAIVED/STRETCH players.
    - Blanks two-way players (since roster_row_count excludes them).
    - Numbers remaining players 1..N with no gaps.
    """

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.names,{names_spill},"
        "_xlpm.y,MetaBaseYear,"
        "_xlpm.namesY,IFERROR(FILTER(tbl_salary_book_yearly[player_name],tbl_salary_book_yearly[salary_year]=_xlpm.y),\"\"),"
        "_xlpm.twY,IFERROR(FILTER(tbl_salary_book_yearly[is_two_way],tbl_salary_book_yearly[salary_year]=_xlpm.y),FALSE),"
        "_xlpm.counted,MAP(_xlpm.names,LAMBDA(_xlpm.p,"
        "LET("
        "_xlpm.isOut,OR(COUNTIF(TradeOutNames,_xlpm.p)>0,COUNTIF(WaivedNames,_xlpm.p)>0,COUNTIF(StretchNames,_xlpm.p)>0),"
        "_xlpm.isTwoWay,SUMPRODUCT((_xlpm.namesY=_xlpm.p)*(_xlpm.twY=TRUE))>0,"
        "IF(OR(_xlpm.isOut,_xlpm.isTwoWay),0,1)"
        "))),"
        "_xlpm.cum,SCAN(0,_xlpm.counted,LAMBDA(_xlpm.acc,_xlpm.v,_xlpm.acc+_xlpm.v)),"
        "IF(_xlpm.counted=1,_xlpm.cum,\"\")"
        ")"
    )
