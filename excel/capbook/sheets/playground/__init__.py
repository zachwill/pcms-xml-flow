"""excel.capbook.sheets.playground

PLAYGROUND sheet package.

`excel/UI.md` is the source of truth for layout/behavior.

Public API:
- write_playground_sheet(
    workbook,
    worksheet,
    formats,
    team_codes,
    *,
    calc_worksheet,
    base_year=2025,
    salary_book_yearly_nrows=...,
    salary_book_warehouse_nrows=...,
  )
"""

from .writer import write_playground_sheet

__all__ = ["write_playground_sheet"]
