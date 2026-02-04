"""CONTRACT CALCULATOR sheet.

Standalone worksheet for the hypothetical contract stream calculator.

This logic previously lived at the bottom of each Playground sheet. It now lives
on its own sheet so it can breathe.

All calculator names are **worksheet-scoped** so analysts can duplicate the
sheet in Excel (Move/Copy → Create a copy) and get an independent calculator.
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..xlsx import write_sheet_heading
from .playground.formats import create_playground_formats
from .playground.layout import (
    COL_INPUT,
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
    COL_SECTION_LABEL,
    COL_TOTAL,
    YEAR_OFFSETS,
    col_letter,
)

__all__ = ["write_contract_calculator_sheet"]


def write_contract_calculator_sheet(
    workbook: Workbook,
    worksheet: Worksheet,
    formats_shared: dict[str, Any],
    *,
    base_year: int = 2025,
) -> None:
    """Write the Contract Calculator sheet."""

    fmts = create_playground_formats(workbook, formats_shared)

    # ---------------------------------------------------------------------
    # Column defaults (reuse Playground's dense year grid)
    # ---------------------------------------------------------------------
    salary_cols = [COL_SAL_Y0, COL_SAL_Y1, COL_SAL_Y2, COL_SAL_Y3, COL_SAL_Y4, COL_SAL_Y5]
    pct_cols = [COL_PCT_Y0, COL_PCT_Y1, COL_PCT_Y2, COL_PCT_Y3, COL_PCT_Y4, COL_PCT_Y5]

    worksheet.set_column(COL_SECTION_LABEL, COL_SECTION_LABEL, 16)
    worksheet.set_column(COL_INPUT, COL_INPUT, 18)

    worksheet.set_column(COL_RANK, COL_RANK, 10)
    worksheet.set_column(COL_PLAYER, COL_PLAYER, 20)

    for col in salary_cols:
        worksheet.set_column(col, col, 10, fmts["money_m"])
    for col in pct_cols:
        worksheet.set_column(col, col, 8, fmts["pct"])

    worksheet.set_column(COL_TOTAL, COL_TOTAL, 10, fmts["money_m"])

    # ---------------------------------------------------------------------
    # Heading
    # ---------------------------------------------------------------------
    row = write_sheet_heading(worksheet, formats_shared, "Contract Calculator", row=0, col=0, width=6)

    sheet_name = worksheet.get_name()
    sheet_ref = "'" + sheet_name.replace("'", "''") + "'"

    def define_local(name: str, row0: int, col0: int) -> None:
        workbook.define_name(
            f"{sheet_name}!{name}",
            f"={sheet_ref}!${col_letter(col0)}${row0 + 1}",
        )

    def year_label(off: int) -> str:
        return (
            "=TEXT(MOD(MetaBaseYear+{o},100),\"00\")&\"-\"&TEXT(MOD(MetaBaseYear+{o1},100),\"00\")".format(
                o=off,
                o1=off + 1,
            )
        )

    # ---------------------------------------------------------------------
    # Inputs
    # ---------------------------------------------------------------------
    worksheet.write(row, COL_SECTION_LABEL, "INPUTS", fmts["section"])
    row += 1

    season_labels = [f"{(base_year + off) % 100:02d}-{(base_year + off + 1) % 100:02d}" for off in range(6)]
    default_season = season_labels[1] if len(season_labels) > 1 else season_labels[0]

    # Start season
    worksheet.write(row, COL_SECTION_LABEL, "Start:", fmts["trade_label"])
    worksheet.write(row, COL_INPUT, default_season, fmts["input_season"])
    worksheet.data_validation(row, COL_INPUT, row, COL_INPUT, {"validate": "list", "source": season_labels})
    define_local("CcStartSeason", row, COL_INPUT)
    row += 1

    # Contract years
    worksheet.write(row, COL_SECTION_LABEL, "Yrs:", fmts["trade_label"])
    worksheet.write(row, COL_INPUT, 4, fmts["input_int_right"])
    worksheet.data_validation(
        row,
        COL_INPUT,
        row,
        COL_INPUT,
        {"validate": "integer", "criteria": "between", "minimum": 1, "maximum": 6},
    )
    define_local("CcYears", row, COL_INPUT)
    row += 1

    # Raise %
    worksheet.write(row, COL_SECTION_LABEL, "Raise:", fmts["trade_label"])
    worksheet.write(row, COL_INPUT, 0.08, fmts["input_pct"])
    worksheet.data_validation(
        row,
        COL_INPUT,
        row,
        COL_INPUT,
        {"validate": "decimal", "criteria": "between", "minimum": 0, "maximum": 0.25},
    )
    define_local("CcRaisePct", row, COL_INPUT)
    row += 1

    # Start salary (optional)
    worksheet.write(row, COL_SECTION_LABEL, "Start $:", fmts["trade_label"])
    worksheet.write(row, COL_INPUT, "", fmts["input_money"])
    define_local("CcStartSalaryIn", row, COL_INPUT)
    row += 1

    # Contract total (optional)
    worksheet.write(row, COL_SECTION_LABEL, "Total $:", fmts["trade_label"])
    worksheet.write(row, COL_INPUT, "", fmts["input_money"])
    define_local("CcTotalIn", row, COL_INPUT)
    row += 2

    # ---------------------------------------------------------------------
    # Output (aligned to the standard 6-year grid)
    # ---------------------------------------------------------------------
    hdr_row = row

    worksheet.write(hdr_row, COL_PLAYER, "STREAM", fmts["totals_section"])
    for i, off in enumerate(YEAR_OFFSETS):
        worksheet.write_formula(hdr_row, salary_cols[i], year_label(off), fmts["totals_section"])
        worksheet.write(hdr_row, pct_cols[i], "%", fmts["totals_section"])
    worksheet.write(hdr_row, COL_TOTAL, "Total", fmts["totals_section"])

    output_row = hdr_row + 1

    # Parse helpers (inline expressions)
    start_year_expr = "IFERROR(2000+VALUE(LEFT(TRIM(CcStartSeason),2)),0)"

    def parse_amount_expr(cell_name: str) -> str:
        # Supports numeric, "15000000", and "15M".
        return (
            "LET(_xlpm.v," + cell_name + ","
            "IF(_xlpm.v=\"\",0,"
            "IF(ISNUMBER(_xlpm.v),_xlpm.v,"
            "LET(_xlpm.t,TRIM(_xlpm.v),_xlpm.last,RIGHT(_xlpm.t,1),"
            "IF(OR(_xlpm.last=\"M\",_xlpm.last=\"m\"),"
            "IFERROR(VALUE(LEFT(_xlpm.t,LEN(_xlpm.t)-1))*1000000,0),"
            "IFERROR(VALUE(_xlpm.t),0)"
            ")"
            ")"
            ")"
            ")"
            ")"
        )

    start_salary_amt = parse_amount_expr("CcStartSalaryIn")
    total_amt = parse_amount_expr("CcTotalIn")

    def salary_stream_cell(*, year_expr: str) -> str:
        """Return cap salary for the hypothetical contract in a given salary_year."""

        return (
            "=LET("  # noqa: ISC003
            f"_xlpm.y,{year_expr},"
            f"_xlpm.start,{start_year_expr},"
            "_xlpm.n,MAX(1,MIN(6,IFERROR(INT(CcYears),0))),"
            "_xlpm.r,IFERROR(CcRaisePct,0),"
            f"_xlpm.startIn,{start_salary_amt},"
            f"_xlpm.totIn,{total_amt},"
            "_xlpm.coeff,_xlpm.n+_xlpm.r*(_xlpm.n*(_xlpm.n-1)/2),"
            "_xlpm.s0,IF(_xlpm.startIn>0,_xlpm.startIn,IF(AND(_xlpm.totIn>0,_xlpm.coeff>0),_xlpm.totIn/_xlpm.coeff,0)),"
            "_xlpm.t,_xlpm.y-_xlpm.start,"
            "IF(OR(_xlpm.start=0,_xlpm.t<0,_xlpm.t>=_xlpm.n),0,_xlpm.s0*(1+_xlpm.t*_xlpm.r))"
            ")"
        )

    worksheet.write(output_row, COL_PLAYER, "Stream", fmts["totals_label"])

    salary_cells: list[str] = []
    for i, off in enumerate(YEAR_OFFSETS):
        year_expr = f"MetaBaseYear+{off}" if off else "MetaBaseYear"

        sal_col = salary_cols[i]
        pct_col = pct_cols[i]

        # Salary
        worksheet.write_formula(output_row, sal_col, salary_stream_cell(year_expr=year_expr), fmts["money_m"])

        sal_a1 = f"{col_letter(sal_col)}{output_row + 1}"
        salary_cells.append(sal_a1)

        # % of cap
        cap_level = f"XLOOKUP({year_expr},tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])"
        worksheet.write_formula(
            output_row,
            pct_col,
            f"=IF({sal_a1}=0,\"-\",IFERROR({sal_a1}/{cap_level},0))",
            fmts["pct"],
        )

        define_local(f"CcSalary{off}", output_row, sal_col)

    worksheet.write_formula(output_row, COL_TOTAL, "=SUM(" + ",".join(salary_cells) + ")", fmts["money_m"])
    define_local("CcTotal", output_row, COL_TOTAL)
