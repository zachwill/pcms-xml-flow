"""excel.capbook.sheets.playground

PLAYGROUND sheet package.

`excel/UI.md` is the source of truth for layout/behavior.

Public API:
- write_playground_sheet(workbook, worksheet, formats, team_codes)
"""

from .writer import write_playground_sheet

__all__ = ["write_playground_sheet"]
