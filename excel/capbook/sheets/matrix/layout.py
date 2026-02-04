"""MATRIX layout constants + small helpers.

We loosely mirror Sean's workbook coordinates so it is easy to compare against
`reference/warehouse/the_matrix.json`.

Column indices are 0-based.
"""

from __future__ import annotations

from dataclasses import dataclass


# -----------------------------------------------------------------------------
# Core grid positions
# -----------------------------------------------------------------------------

# Roster spills start at Excel row 3 (0-index row 2)
ROSTER_START_ROW = 2
ROSTER_RESERVED = 25

# Trade input rows (player name entry slots)
TRADE_INPUT_START_ROW = 3  # Excel row 4
TRADE_INPUT_ROWS = 11  # rows 4..14 inclusive

# Trade summary rows (below the input slots)
TRADE_TOTAL_ROW = TRADE_INPUT_START_ROW + TRADE_INPUT_ROWS  # Excel row 15
TRADE_ALLOWED_ROW = TRADE_TOTAL_ROW + 1  # Excel row 16
TRADE_STATUS_ROW = TRADE_TOTAL_ROW + 2  # Excel row 17


# -----------------------------------------------------------------------------
# Trade Details block (AH:AI)
# -----------------------------------------------------------------------------

COL_TRADE_LABEL = 33  # AH
COL_TRADE_VALUE = 34  # AI

ROW_TRADE_HDR = 1  # Excel row 2
ROW_TRADE_YEAR = 2  # Excel row 3
ROW_TRADE_PLAYING_START = 3  # Excel row 4
ROW_TRADE_DATE = 4  # Excel row 5
ROW_SIGN_DELAY = 5  # Excel row 6
ROW_SIGN_DATE = 6  # Excel row 7
ROW_DAYS_IN_SEASON = 7  # Excel row 8
ROW_OUT_DAYS = 8  # Excel row 9
ROW_IN_DAYS = 9  # Excel row 10


# -----------------------------------------------------------------------------
# Team blocks
# -----------------------------------------------------------------------------


@dataclass(frozen=True)
class RosterBlock:
    name_col: int
    cap_col: int
    tax_col: int
    apron_col: int
    earned_col: int
    remaining_col: int


@dataclass(frozen=True)
class TradeBlock:
    out_name_col: int
    out_cap_col: int
    in_name_col: int
    in_cap_col: int


@dataclass(frozen=True)
class TeamBlock:
    idx: int
    code_input_col: int
    mode_input_col: int
    roster: RosterBlock
    trade: TradeBlock


# Mirrors the 4-team roster layout in Sean's sheet:
# - Team inputs: AK/AW/BI/BU (codes) and AM/AY/BK/BW (modes)
# - Roster views: A..G, I..O, Q..W, Y..AE
# - Trade blocks: AK.., AW.., BI.., BU..
TEAM_BLOCKS: list[TeamBlock] = [
    TeamBlock(
        idx=1,
        code_input_col=36,  # AK
        mode_input_col=38,  # AM
        roster=RosterBlock(name_col=0, cap_col=2, tax_col=3, apron_col=4, earned_col=5, remaining_col=6),
        trade=TradeBlock(out_name_col=36, out_cap_col=37, in_name_col=43, in_cap_col=44),  # AK/AL, AR/AS
    ),
    TeamBlock(
        idx=2,
        code_input_col=48,  # AW
        mode_input_col=50,  # AY
        roster=RosterBlock(name_col=8, cap_col=10, tax_col=11, apron_col=12, earned_col=13, remaining_col=14),
        trade=TradeBlock(out_name_col=48, out_cap_col=49, in_name_col=55, in_cap_col=56),  # AW/AX, BD/BE
    ),
    TeamBlock(
        idx=3,
        code_input_col=60,  # BI
        mode_input_col=62,  # BK
        roster=RosterBlock(name_col=16, cap_col=18, tax_col=19, apron_col=20, earned_col=21, remaining_col=22),
        trade=TradeBlock(out_name_col=60, out_cap_col=61, in_name_col=67, in_cap_col=68),  # BI/BJ, BP/BQ
    ),
    TeamBlock(
        idx=4,
        code_input_col=72,  # BU
        mode_input_col=74,  # BW
        roster=RosterBlock(name_col=24, cap_col=26, tax_col=27, apron_col=28, earned_col=29, remaining_col=30),
        trade=TradeBlock(out_name_col=72, out_cap_col=73, in_name_col=79, in_cap_col=80),  # BU/BV, CB/CC
    ),
]


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
