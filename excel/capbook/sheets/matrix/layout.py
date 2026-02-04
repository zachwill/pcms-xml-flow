"""MATRIX layout constants + small helpers (Stacked v2).

The original Matrix implementation mirrored Sean's workbook coordinates
(`reference/warehouse/the_matrix.json`) with 4 teams laid out side-by-side.
That parity was useful for verification, but it required extreme horizontal
scrolling.

This layout is a "stacked" redesign optimized for laptop-sized screens:

- All interactive controls live in the top frozen rows.
- Each team gets a vertical section containing:
  - trade inputs (out / in)
  - post-trade summary rows
  - a reactive roster preview

Column indices are 0-based.
"""

from __future__ import annotations

from dataclasses import dataclass


# -----------------------------------------------------------------------------
# Frozen control panel
# -----------------------------------------------------------------------------

# Left rail (mirrors Playground)
COL_SECTION_LABEL = 0  # A
COL_INPUT = 1  # B
COL_HIDDEN = 2  # C (hidden helper cells)

# Main grid starts at column D
COL_MAIN_START = 3  # D

# Top rows (0-indexed)
ROW_VERDICT = 0  # Excel row 1
ROW_SEASON = 1  # Excel row 2
ROW_PARAMS = 2  # Excel row 3

# First scrollable row (below the frozen control panel)
ROW_BODY_START = 3  # Excel row 4


# -----------------------------------------------------------------------------
# Team selector inputs (top panel)
# -----------------------------------------------------------------------------


@dataclass(frozen=True)
class TeamInputs:
    idx: int
    code_col: int
    mode_col: int


# Team selectors live on ROW_SEASON (row 1) to match Playground's "TEAM" row.
# We allocate 2 columns per team: code + mode.
TEAM_INPUTS: list[TeamInputs] = [
    TeamInputs(idx=1, code_col=3, mode_col=4),  # D/E
    TeamInputs(idx=2, code_col=5, mode_col=6),  # F/G
    TeamInputs(idx=3, code_col=7, mode_col=8),  # H/I
    TeamInputs(idx=4, code_col=9, mode_col=10),  # J/K
]


# -----------------------------------------------------------------------------
# Per-team section sizing
# -----------------------------------------------------------------------------

# Trade input rows (player name entry slots)
TRADE_INPUT_ROWS = 11

# Roster spill headroom per team
ROSTER_RESERVED = 25

# Row offsets within a team section
TEAM_HDR_OFF = 0
TRADE_HDR_OFF = 1
TRADE_INPUT_OFF = 2

TRADE_TOTAL_OFF = TRADE_INPUT_OFF + TRADE_INPUT_ROWS
TRADE_ALLOWED_OFF = TRADE_TOTAL_OFF + 1
TRADE_STATUS_OFF = TRADE_TOTAL_OFF + 2

TRADE_FILL12_OFF = TRADE_STATUS_OFF + 1
TRADE_FILL14_OFF = TRADE_STATUS_OFF + 2
TRADE_FILL_TOTAL_OFF = TRADE_STATUS_OFF + 3
TRADE_APRON1_ROOM_OFF = TRADE_STATUS_OFF + 4
TRADE_APRON2_ROOM_OFF = TRADE_STATUS_OFF + 5

# Gap + roster block
ROSTER_HDR_OFF = TRADE_APRON2_ROOM_OFF + 2
ROSTER_START_OFF = ROSTER_HDR_OFF + 1

# Total rows reserved per team section, including 2 spacer rows at bottom.
TEAM_SECTION_ROWS = ROSTER_START_OFF + ROSTER_RESERVED + 2


def team_section_start_row(team_idx: int) -> int:
    """Return the start row (0-indexed) for a given team section."""

    if team_idx < 1:
        raise ValueError("team_idx must be 1-based")

    return ROW_BODY_START + (team_idx - 1) * TEAM_SECTION_ROWS


def team_row(team_idx: int, off: int) -> int:
    """Helper: (team section start) + offset."""

    return team_section_start_row(team_idx) + off


# -----------------------------------------------------------------------------
# Trade block columns (shared across teams)
# -----------------------------------------------------------------------------

# Outgoing players (names + cap/tax/apron amounts)
COL_OUT_NAME = 3  # D
COL_OUT_CAP = 4  # E
COL_OUT_TAX = 5  # F
COL_OUT_APRON = 6  # G

# Incoming players (names + cap/tax/apron amounts)
COL_IN_NAME = 7  # H
COL_IN_CAP = 8  # I
COL_IN_TAX = 9  # J
COL_IN_APRON = 10  # K


# -----------------------------------------------------------------------------
# Roster block columns (shared across teams)
# -----------------------------------------------------------------------------

COL_ROSTER_NAME = 3  # D
COL_ROSTER_CAP = 4  # E
COL_ROSTER_TAX = 5  # F
COL_ROSTER_APRON = 6  # G
COL_ROSTER_EARNED = 7  # H
COL_ROSTER_REMAINING = 8  # I


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------


def col_letter(col: int) -> str:
    """Convert 0-indexed column number to Excel letter (0=A, 1=B, ...)."""

    result = ""
    while col >= 0:
        result = chr(col % 26 + ord("A")) + result
        col = col // 26 - 1
    return result


def a1(row0: int, col0: int) -> str:
    """Return an A1 reference like 'C3' for 0-indexed (row, col)."""

    return f"{col_letter(col0)}{row0 + 1}"
