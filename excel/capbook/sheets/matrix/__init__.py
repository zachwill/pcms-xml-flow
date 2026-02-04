"""excel.capbook.sheets.matrix

MATRIX sheet package.

This is the code-generated Excel implementation of Sean's multi-team trade
scenario calculator ("The Matrix").

Public API:
- write_matrix_sheet(workbook, worksheet, formats_shared, team_codes, ...)

Design note (parity with PLAYGROUND):
- All scenario calculations live *on the Matrix worksheet itself* (in hidden
  columns) and are exposed via worksheet-scoped defined names. This makes it
  safe to duplicate the sheet in Excel to create multiple independent Matrix
  scenarios in the future.
"""

from .writer import write_matrix_sheet

__all__ = ["write_matrix_sheet"]
