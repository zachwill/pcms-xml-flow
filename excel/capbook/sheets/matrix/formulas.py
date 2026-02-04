"""MATRIX Excel formula builders.

These return Excel formula strings (including leading '=') and are used by the
sheet writer.

We prefer modern Excel functions: LET/FILTER/SORTBY/XLOOKUP/MAP.

Important: The workbook is created with `use_future_functions=True`, so we
write formulas using unprefixed function names (LET/FILTER/etc). XlsxWriter will
apply `_xlfn.` prefixes as needed.
"""

from __future__ import annotations


def roster_names_anchor(*, team_code_expr: str, year_expr: str, max_rows: int) -> str:
    """Spilled roster player_name list for (team, year), sorted by cap_amount desc."""

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.team,{team_code_expr},"
        f"_xlpm.y,{year_expr},"
        "IF(_xlpm.team=\"\",\"\","  # if team blank -> blank spill
        "LET("  # noqa: ISC003
        "_xlpm.mask,(tbl_salary_book_yearly[team_code]=_xlpm.team)*(tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.names,FILTER(tbl_salary_book_yearly[player_name],_xlpm.mask),"
        "_xlpm.sal,FILTER(tbl_salary_book_yearly[cap_amount],_xlpm.mask),"
        # Sort key: blank salaries go to bottom.
        "_xlpm.key,IF(_xlpm.sal=\"\",-10000000000,_xlpm.sal),"
        f"TAKE(SORTBY(_xlpm.names,_xlpm.key,-1),{max_rows})"
        ")"  # close inner LET
        ")"  # close IF
        ")"  # close outer LET
    )


def roster_amount_column(
    *,
    names_spill: str,
    team_code_expr: str,
    year_expr: str,
    amount_col: str,
) -> str:
    """Spilled amount column aligned to a roster names spill (team-scoped)."""

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.team,{team_code_expr},"
        f"_xlpm.y,{year_expr},"
        f"_xlpm.in,{names_spill},"
        "IF(_xlpm.team=\"\",MAP(_xlpm.in,LAMBDA(_xlpm.p,\"\")),"  # preserve spill height
        "LET("  # noqa: ISC003
        "_xlpm.mask,(tbl_salary_book_yearly[team_code]=_xlpm.team)*(tbl_salary_book_yearly[salary_year]=_xlpm.y),"
        "_xlpm.names,FILTER(tbl_salary_book_yearly[player_name],_xlpm.mask),"
        f"_xlpm.vals,FILTER(tbl_salary_book_yearly[{amount_col}],_xlpm.mask),"
        "MAP(_xlpm.in,LAMBDA(_xlpm.p,IF(_xlpm.p=\"\",\"\",IFERROR(XLOOKUP(_xlpm.p,_xlpm.names,_xlpm.vals,0),0))))"
        ")"  # close inner LET
        ")"  # close IF
        ")"  # close outer LET
    )


def map_input_names_to_amount(
    *,
    names_range: str,
    team_code_expr: str,
    year_expr: str,
    amount_col: str,
    team_scoped: bool,
) -> str:
    """Map an input name range (1-col) to a spilled amount array.

    Args:
        names_range: A worksheet-scoped named range like `MxT1OutNames`
        team_code_expr: Team code expression/name (used for gating + optional scoping)
        year_expr: Salary year expression/name
        amount_col: Column in `tbl_salary_book_yearly` to fetch
        team_scoped: If true, only match rows where team_code==team.
            Use this for outgoing salaries.
            If false, match league-wide rows for the year.
            Use this for incoming_* amounts.
    """

    mask = "(tbl_salary_book_yearly[salary_year]=_xlpm.y)"
    if team_scoped:
        mask += "*(tbl_salary_book_yearly[team_code]=_xlpm.team)"

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.team,{team_code_expr},"
        f"_xlpm.y,{year_expr},"
        f"_xlpm.in,{names_range},"
        "IF(_xlpm.team=\"\",MAP(_xlpm.in,LAMBDA(_xlpm.p,\"\")),"  # preserve spill height when team blank
        "LET("  # noqa: ISC003
        f"_xlpm.mask,{mask},"
        "_xlpm.names,FILTER(tbl_salary_book_yearly[player_name],_xlpm.mask),"
        f"_xlpm.vals,FILTER(tbl_salary_book_yearly[{amount_col}],_xlpm.mask),"
        "MAP(_xlpm.in,LAMBDA(_xlpm.p,IF(_xlpm.p=\"\",\"\",IFERROR(XLOOKUP(_xlpm.p,_xlpm.names,_xlpm.vals,0),0))))"
        ")"  # close inner LET
        ")"  # close IF
        ")"  # close outer LET
    )


def trade_matching_allowed_in(
    *,
    out_salary_expr: str,
    mode_expr: str,
    year_expr: str,
    tpe_allowance_expr: str = "MxTpeAllowance",
) -> str:
    """Expanded/Standard incoming limit for trade matching.

    Uses the CBA "greater of / not less than" structure:
      MAX( MIN(2x+250k, x+tpe_allowance), 1.25x+250k )

    Standard mode is dollar-for-dollar.

    NOTE: We keep MAX/MIN instead of GREATEST/LEAST so we don't need manual
    `_xlfn.` prefixes.

    Args:
        out_salary_expr: Expression for outgoing salary (cap layer)
        mode_expr: Expression that evaluates to "Expanded" or "Standard"
        year_expr: Included for future parity; currently unused.
        tpe_allowance_expr: Expression for the year-specific TPE allowance.
    """

    return (
        "=LET("  # noqa: ISC003
        f"_xlpm.out,{out_salary_expr},"
        f"_xlpm.mode,{mode_expr},"
        f"_xlpm.allow,{tpe_allowance_expr},"
        "IF(_xlpm.mode=\"Standard\",_xlpm.out,MAX(MIN(_xlpm.out*2+250000,_xlpm.out+_xlpm.allow),_xlpm.out*1.25+250000))"
        ")"
    )
