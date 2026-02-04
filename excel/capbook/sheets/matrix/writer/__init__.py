"""MATRIX sheet writer package."""

from __future__ import annotations

from datetime import date
from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ...playground.formats import create_playground_formats
from .calc import write_calc_block
from .inputs import write_trade_inputs
from .roster import write_rosters
from .setup import write_setup

__all__ = ["write_matrix_sheet"]


def write_matrix_sheet(
    workbook: Workbook,
    worksheet: Worksheet,
    formats_shared: dict[str, Any],
    team_codes: list[str],
    *,
    base_year: int = 2025,
    as_of: "date | None" = None,
    salary_book_yearly_nrows: int = 20000,
    salary_book_warehouse_nrows: int = 5000,
) -> None:
    """Write the MATRIX sheet."""

    # v1: reuse Playground's dense capbook styling.
    fmts = create_playground_formats(workbook, formats_shared)

    write_setup(
        workbook,
        worksheet,
        fmts,
        team_codes=team_codes,
        as_of=as_of,
    )
    write_trade_inputs(
        workbook,
        worksheet,
        fmts,
        salary_book_warehouse_nrows=salary_book_warehouse_nrows,
    )
    write_calc_block(workbook, worksheet)
    write_rosters(
        worksheet,
        fmts,
        base_year=base_year,
        salary_book_yearly_nrows=salary_book_yearly_nrows,
    )
