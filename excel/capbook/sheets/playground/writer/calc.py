"""PLAYGROUND sheet CALC block writers."""

from __future__ import annotations

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .. import formulas
from ..layout import YEAR_OFFSETS, col_letter


def write_calc_sheet(workbook: Workbook, calc_worksheet: Worksheet) -> None:
    """Write the CALC worksheet formulas + defined names.

    CALC is a simple scalar grid.

    Each year offset gets its own row. Each metric gets its own column.

    Column map (0-indexed):
      B=RosterCount
      C=CapTotal
      D=TaxTotal
      E=ApronTotal
      F=DeadMoney

      G=Fill12Count
      H=Fill14Count
      I=Fill12ProrationFactor   (base year only)
      J=Fill14ProrationFactor   (base year only; can be delayed by FillDelayDays)

      K=RookieMin (YOS 0)
      L=VetMin    (YOS 2)
      M=Fill12Min (ROOKIE vs VET)
      N=Fill14Min (default VET)

      O=Fill12Amount
      P=Fill14Amount
      Q=FillAmount

      R=CapTotalFilled
      S=TaxTotalFilled
      T=ApronTotalFilled
      U=TaxPayment

    Naming convention: all CALC scalars are surfaced via defined names like:
      ScnCapTotal0, ScnFill12Amount0, etc.
    """

    # Header row (for debugging when CALC sheet is inspected)
    headers = [
        (1, "ScnRosterCount"),
        (2, "ScnCapTotal"),
        (3, "ScnTaxTotal"),
        (4, "ScnApronTotal"),
        (5, "ScnDeadMoney"),
        (6, "ScnFill12Count"),
        (7, "ScnFill14Count"),
        (8, "ScnFill12ProrationFactor"),
        (9, "ScnFill14ProrationFactor"),
        (10, "ScnRookieMin"),
        (11, "ScnVetMin"),
        (12, "ScnFill12Min"),
        (13, "ScnFill14Min"),
        (14, "ScnFill12Amount"),
        (15, "ScnFill14Amount"),
        (16, "ScnFillAmount"),
        (17, "ScnCapTotalFilled"),
        (18, "ScnTaxTotalFilled"),
        (19, "ScnApronTotalFilled"),
        (20, "ScnTaxPayment"),
    ]

    for col0, label in headers:
        calc_worksheet.write(0, col0, label)

    def _define_calc_name(name: str, row0: int, col0: int, formula: str) -> None:
        """Write formula into CALC and define a stable named range."""

        # Write the scalar formula into CALC.
        calc_worksheet.write_formula(row0, col0, formula)
        # Define name as a pure cell reference.
        colA = col_letter(col0)
        workbook.define_name(name, f"=CALC!${colA}${row0 + 1}")

    # Shared proration helper fragments (base-year only)
    #
    # Note: MetaAsOfDate is stored as a text ISO date in META, so DATEVALUE() is
    # required when using it as a date.
    base_year_end_expr = (
        "IFERROR("  # noqa: ISC003
        "XLOOKUP(_xlpm.y,tbl_system_values[salary_year],tbl_system_values[playing_end_at]),"
        "IFERROR(XLOOKUP(_xlpm.y,tbl_system_values[salary_year],tbl_system_values[season_end_at]),0)"
        ")"
    )

    base_year_days_expr = "IFERROR(XLOOKUP(_xlpm.y,tbl_system_values[salary_year],tbl_system_values[days_in_season]),0)"

    for off in YEAR_OFFSETS:
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"
        r0 = 1 + off

        # Base scenario metrics
        _define_calc_name(f"ScnRosterCount{off}", r0, 1, formulas.scenario_roster_count(year_expr=year_expr))
        _define_calc_name(f"ScnCapTotal{off}", r0, 2, formulas.scenario_team_total(year_expr=year_expr, year_offset=off))
        _define_calc_name(f"ScnTaxTotal{off}", r0, 3, formulas.scenario_tax_total(year_expr=year_expr, year_offset=off))
        _define_calc_name(f"ScnApronTotal{off}", r0, 4, formulas.scenario_apron_total(year_expr=year_expr, year_offset=off))
        _define_calc_name(f"ScnDeadMoney{off}", r0, 5, formulas.scenario_dead_money(year_expr=year_expr))

        # Roster fill counts
        # - Fill12Count: number of missing roster slots to reach 12
        # - Fill14Count: additional missing slots to reach 14 (12–14 only)
        _define_calc_name(f"ScnFill12Count{off}", r0, 6, f"=MAX(0,12-ScnRosterCount{off})")
        _define_calc_name(f"ScnFill14Count{off}", r0, 7, f"=MAX(0,14-ScnRosterCount{off})-ScnFill12Count{off}")

        # Base-year-only fill proration
        #
        # Sean parity:
        # - Fill-to-12 pricing date = FillEventDate (immediate)
        # - Fill-to-14 pricing date = FillEventDate + FillDelayDays (defaults to 0; Matrix-style is 14)
        if off == 0:
            _define_calc_name(
                f"ScnFill12ProrationFactor{off}",
                r0,
                8,
                "=LET("  # noqa: ISC003
                "_xlpm.y,MetaBaseYear,"
                "_xlpm.dt,IF(FillEventDate=\"\",DATEVALUE(MetaAsOfDate),FillEventDate),"
                f"_xlpm.end,{base_year_end_expr},"
                f"_xlpm.d,{base_year_days_expr},"
                "_xlpm.rem,MAX(0,MIN(_xlpm.d,INT(_xlpm.end-_xlpm.dt+1))),"
                "IF(OR(_xlpm.end=0,_xlpm.d=0),1,_xlpm.rem/_xlpm.d)"
                ")",
            )

            _define_calc_name(
                f"ScnFill14ProrationFactor{off}",
                r0,
                9,
                "=LET("  # noqa: ISC003
                "_xlpm.y,MetaBaseYear,"
                "_xlpm.baseDt,IF(FillEventDate=\"\",DATEVALUE(MetaAsOfDate),FillEventDate),"
                "_xlpm.delayLbl,FillDelayDays,"
                "_xlpm.delay,IF(ISNUMBER(_xlpm.delayLbl),_xlpm.delayLbl,IF(_xlpm.delayLbl=\"Immediate\",0,IFERROR(VALUE(LEFT(_xlpm.delayLbl,FIND(\" \",_xlpm.delayLbl&\" \")-1)),0))),"
                "_xlpm.dt,_xlpm.baseDt+_xlpm.delay,"
                f"_xlpm.end,{base_year_end_expr},"
                f"_xlpm.d,{base_year_days_expr},"
                "_xlpm.rem,MAX(0,MIN(_xlpm.d,INT(_xlpm.end-_xlpm.dt+1))),"
                "IF(OR(_xlpm.end=0,_xlpm.d=0),1,_xlpm.rem/_xlpm.d)"
                ")",
            )
        else:
            _define_calc_name(f"ScnFill12ProrationFactor{off}", r0, 8, "=1")
            _define_calc_name(f"ScnFill14ProrationFactor{off}", r0, 9, "=1")

        # Minimum salaries (Year 1 minimums by YOS)
        _define_calc_name(
            f"ScnRookieMin{off}",
            r0,
            10,
            f"=IFERROR(XLOOKUP(({year_expr})&0,tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount]),0)",
        )
        _define_calc_name(
            f"ScnVetMin{off}",
            r0,
            11,
            f"=IFERROR(XLOOKUP(({year_expr})&2,tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount]),0)",
        )

        # Fill pricing: allow fill-to-12 basis selection (ROOKIE vs VET). Fill-to-14 defaults to VET.
        _define_calc_name(
            f"ScnFill12Min{off}",
            r0,
            12,
            f"=IF(FillTo12MinType=\"VET\",ScnVetMin{off},ScnRookieMin{off})",
        )
        _define_calc_name(
            f"ScnFill14Min{off}",
            r0,
            13,
            f"=IF(FillTo14MinType=\"ROOKIE\",ScnRookieMin{off},ScnVetMin{off})",
        )

        # Fill amounts
        _define_calc_name(
            f"ScnFill12Amount{off}",
            r0,
            14,
            f"=ScnFill12Count{off}*ScnFill12Min{off}*ScnFill12ProrationFactor{off}",
        )
        _define_calc_name(
            f"ScnFill14Amount{off}",
            r0,
            15,
            f"=ScnFill14Count{off}*ScnFill14Min{off}*ScnFill14ProrationFactor{off}",
        )
        _define_calc_name(f"ScnFillAmount{off}", r0, 16, f"=ScnFill12Amount{off}+ScnFill14Amount{off}")

        # Filled totals (layer-aware)
        _define_calc_name(f"ScnCapTotalFilled{off}", r0, 17, f"=ScnCapTotal{off}+ScnFillAmount{off}")
        _define_calc_name(f"ScnTaxTotalFilled{off}", r0, 18, f"=ScnTaxTotal{off}+ScnFillAmount{off}")
        _define_calc_name(f"ScnApronTotalFilled{off}", r0, 19, f"=ScnApronTotal{off}+ScnFillAmount{off}")

        # Luxury tax payment (progressive via tbl_tax_rates)
        _define_calc_name(
            f"ScnTaxPayment{off}",
            r0,
            20,
            "=LET("  # noqa: ISC003
            f"_xlpm.y,{year_expr},"
            "_xlpm.taxLvl,IFERROR(XLOOKUP(_xlpm.y,tbl_system_values[salary_year],tbl_system_values[tax_level_amount]),0),"
            f"_xlpm.over,MAX(0,ScnTaxTotalFilled{off}-_xlpm.taxLvl),"
            "_xlpm.isRep,IFERROR(XLOOKUP(SelectedTeam&_xlpm.y,tbl_team_salary_warehouse[team_code]&tbl_team_salary_warehouse[salary_year],tbl_team_salary_warehouse[is_repeater_taxpayer],FALSE),FALSE),"
            "_xlpm.lower,IF(_xlpm.over=0,0,MAXIFS(tbl_tax_rates[lower_limit],tbl_tax_rates[salary_year],_xlpm.y,tbl_tax_rates[lower_limit],\"<=\"&_xlpm.over)),"
            "_xlpm.key,_xlpm.y&\"|\"&_xlpm.lower,"
            "_xlpm.rate,IF(_xlpm.over=0,0,XLOOKUP(_xlpm.key,tbl_tax_rates[salary_year]&\"|\"&tbl_tax_rates[lower_limit],IF(_xlpm.isRep,tbl_tax_rates[tax_rate_repeater],tbl_tax_rates[tax_rate_non_repeater]),0)),"
            "_xlpm.base,IF(_xlpm.over=0,0,XLOOKUP(_xlpm.key,tbl_tax_rates[salary_year]&\"|\"&tbl_tax_rates[lower_limit],IF(_xlpm.isRep,tbl_tax_rates[base_charge_repeater],tbl_tax_rates[base_charge_non_repeater]),0)),"
            "IF(_xlpm.over=0,0,_xlpm.base+(_xlpm.over-_xlpm.lower)*_xlpm.rate)"
            ")",
        )
