"""PLAYGROUND layout constants + small helpers."""

from __future__ import annotations

# Columns (0-indexed)
COL_SECTION_LABEL = 0  # A - section labels
COL_INPUT = 1  # B - input cells
COL_INPUT_SALARY = 2  # C - salary inputs for SIGN

COL_RANK = 3  # D
COL_PLAYER = 4  # E

# Multi-year salary grid (6-year visible slice; base year + 5)
COL_SAL_Y0 = 5  # F
COL_PCT_Y0 = 6  # G
COL_SAL_Y1 = 7  # H
COL_PCT_Y1 = 8  # I
COL_SAL_Y2 = 9  # J
COL_PCT_Y2 = 10  # K
COL_SAL_Y3 = 11  # L
COL_PCT_Y3 = 12  # M
COL_SAL_Y4 = 13  # N
COL_PCT_Y4 = 14  # O
COL_SAL_Y5 = 15  # P
COL_PCT_Y5 = 16  # Q

COL_TOTAL = 17  # R
COL_AGENT = 18  # S
COL_STATUS = 19  # T

# Rows (0-indexed)
ROW_BASE = 0  # Excel row 1 - Base year
ROW_TEAM_CONTEXT = 1  # Excel row 2 - TEAM + KPIs
ROW_HEADER = 2  # Excel row 3 - column headers
ROW_BODY_START = 3  # Excel row 4 - roster/inputs start

# Roster display headroom
ROSTER_RESERVED = 25

# Scenario input slots
TRADE_OUT_SLOTS = 6
TRADE_IN_SLOTS = 6
WAIVE_SLOTS = 3
STRETCH_SLOTS = 3
SIGN_SLOTS = 3

# Visible year offsets in the grid
YEAR_OFFSETS = [0, 1, 2, 3, 4, 5]


def col_letter(col: int) -> str:
    """Convert 0-indexed column number to Excel letter (0=A, 1=B, ...)."""

    result = ""
    while col >= 0:
        result = chr(col % 26 + ord("A")) + result
        col = col // 26 - 1
    return result
