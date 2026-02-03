"""PLAYGROUND sheet writer package."""

from __future__ import annotations

from datetime import date
from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ..formats import create_playground_formats
from .calc import write_calc_sheet
from .inputs import write_inputs
from .roster import write_roster
from .setup import write_setup
from .totals import write_totals

__all__ = ["write_playground_sheet"]


def write_playground_sheet(
    workbook: Workbook,
    worksheet: Worksheet,
    formats_shared: dict[str, Any],
    team_codes: list[str],
    *,
    calc_worksheet: Worksheet,
    base_year: int = 2025,
    as_of: "date | None" = None,
    salary_book_yearly_nrows: int = 20000,
    salary_book_warehouse_nrows: int = 5000,
) -> None:
    """Write the PLAYGROUND sheet."""

    fmts = create_playground_formats(workbook, formats_shared)

    write_setup(workbook, worksheet, fmts, team_codes)
    write_calc_sheet(workbook, calc_worksheet)
    write_inputs(
        workbook,
        worksheet,
        fmts,
        salary_book_yearly_nrows=salary_book_yearly_nrows,
        salary_book_warehouse_nrows=salary_book_warehouse_nrows,
        as_of=as_of,
    )
    write_roster(
        worksheet,
        fmts,
        base_year=base_year,
        salary_book_yearly_nrows=salary_book_yearly_nrows,
        salary_book_warehouse_nrows=salary_book_warehouse_nrows,
    )
    write_totals(worksheet, fmts)
