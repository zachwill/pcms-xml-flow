"""
Quick drivers panel for TEAM_COCKPIT sheet.

Shows:
- Top N cap hits (from salary_book_warehouse)
- Top N dead money (from dead_money_warehouse)
- Top N holds (from cap_holds_warehouse)

Uses Excel 365 dynamic array formulas (LET + FILTER + SORTBY + TAKE)
instead of legacy AGGREGATE/MATCH patterns.

Each panel writes:
- A spilling name formula at the first data cell
- A spilling amount formula at the first data cell
- Both spill down to fill TOP_N_DRIVERS rows
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ...xlsx import FMT_MONEY
from .constants import (
    COL_DRIVERS_LABEL,
    COL_DRIVERS_PLAYER,
    COL_DRIVERS_VALUE,
    TOP_N_DRIVERS,
    DRIVERS_COLUMN_WIDTHS,
)


# =============================================================================
# Quick Drivers Panel
# =============================================================================


def write_quick_drivers(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    start_row: int,
) -> int:
    """Write the quick drivers panel (right side).
    
    Shows:
    - Top N cap hits (from salary_book_warehouse)
    - Top N dead money (from dead_money_warehouse)
    - Top N holds (from cap_holds_warehouse)
    
    Uses Excel 365 dynamic array formulas (LET + FILTER + SORTBY + TAKE)
    instead of legacy AGGREGATE/MATCH patterns.
    
    Each panel writes:
    - A spilling name formula at the first data cell
    - A spilling amount formula at the first data cell
    - Both spill down to fill TOP_N_DRIVERS rows
    
    Returns:
        Next available row
    """
    money_fmt = workbook.add_format({"num_format": FMT_MONEY})
    bold_fmt = workbook.add_format({"bold": True})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    player_fmt = workbook.add_format({"align": "left"})
    
    # Column widths for drivers area
    for col, width in DRIVERS_COLUMN_WIDTHS.items():
        worksheet.set_column(col, col, width)
    
    row = start_row
    n = TOP_N_DRIVERS
    
    # =========================================================================
    # Top Cap Hits (salary_book_warehouse)
    # =========================================================================
    worksheet.write(row, COL_DRIVERS_LABEL, "TOP CAP HITS", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_PLAYER, "Player", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_VALUE, "Amount", section_header_fmt)
    row += 1
    
    # Name formula: uses FilterSortTake with SalaryBookModeAmt/Filter
    cap_hits_name_formula = (
        f"=FilterSortTake(tbl_salary_book_warehouse[player_name],"
        f"SalaryBookModeAmt(),SalaryBookRosterFilter(),{n})"
    )
    worksheet.write_formula(row, COL_DRIVERS_PLAYER, cap_hits_name_formula, player_fmt)
    
    # Amount formula: uses FilterSortTake with SalaryBookModeAmt/Filter
    cap_hits_amount_formula = (
        f"=FilterSortTake(SalaryBookModeAmt(),"
        f"SalaryBookModeAmt(),SalaryBookRosterFilter(),{n})"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, cap_hits_amount_formula, money_fmt)
    
    # Row labels (static, don't spill)
    for rank in range(1, n + 1):
        worksheet.write(row + rank - 1, COL_DRIVERS_LABEL, f"#{rank}")
    
    row += n
    
    # Blank row
    row += 1
    
    # =========================================================================
    # Top Dead Money (dead_money_warehouse)
    # =========================================================================
    # dead_money_warehouse has: cap_value, tax_value, apron_value (per salary_year)
    # Filter by team_code + salary_year, sort by mode-aware value (DESC)
    # =========================================================================
    
    worksheet.write(row, COL_DRIVERS_LABEL, "TOP DEAD MONEY", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_PLAYER, "Player", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_VALUE, "Amount", section_header_fmt)
    row += 1
    
    # Name formula
    dead_money_name_formula = (
        f"=FilterSortTake(tbl_dead_money_warehouse[player_name],"
        f"DeadMoneyModeAmt(),DeadMoneyFilter(),{n})"
    )
    worksheet.write_formula(row, COL_DRIVERS_PLAYER, dead_money_name_formula, player_fmt)
    
    # Amount formula
    dead_money_amount_formula = (
        f"=FilterSortTake(DeadMoneyModeAmt(),"
        f"DeadMoneyModeAmt(),DeadMoneyFilter(),{n})"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, dead_money_amount_formula, money_fmt)
    
    # Row labels
    for rank in range(1, n + 1):
        worksheet.write(row + rank - 1, COL_DRIVERS_LABEL, f"#{rank}")
    
    row += n
    
    # Dead money total for the team/year (mode-aware)
    worksheet.write(row, COL_DRIVERS_LABEL, "Total:", bold_fmt)
    dead_money_total_formula = (
        "=SUM(FILTER(DeadMoneyModeAmt(),DeadMoneyFilter(),0))"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, dead_money_total_formula, money_fmt)
    row += 1
    
    # Blank row
    row += 1
    
    # =========================================================================
    # Top Cap Holds (cap_holds_warehouse)
    # =========================================================================
    # cap_holds_warehouse has: cap_amount, tax_amount, apron_amount (per salary_year)
    # Filter by team_code + salary_year, sort by mode-aware amount (DESC)
    # =========================================================================
    
    worksheet.write(row, COL_DRIVERS_LABEL, "TOP HOLDS", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_PLAYER, "Player", section_header_fmt)
    worksheet.write(row, COL_DRIVERS_VALUE, "Amount", section_header_fmt)
    row += 1
    
    # Name formula
    cap_holds_name_formula = (
        f"=FilterSortTake(tbl_cap_holds_warehouse[player_name],"
        f"CapHoldsModeAmt(),CapHoldsFilter(),{n})"
    )
    worksheet.write_formula(row, COL_DRIVERS_PLAYER, cap_holds_name_formula, player_fmt)
    
    # Amount formula
    cap_holds_amount_formula = (
        f"=FilterSortTake(CapHoldsModeAmt(),"
        f"CapHoldsModeAmt(),CapHoldsFilter(),{n})"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, cap_holds_amount_formula, money_fmt)
    
    # Row labels
    for rank in range(1, n + 1):
        worksheet.write(row + rank - 1, COL_DRIVERS_LABEL, f"#{rank}")
    
    row += n
    
    # Holds total for the team/year (mode-aware)
    worksheet.write(row, COL_DRIVERS_LABEL, "Total:", bold_fmt)
    cap_holds_total_formula = (
        "=SUM(FILTER(CapHoldsModeAmt(),CapHoldsFilter(),0))"
    )
    worksheet.write_formula(row, COL_DRIVERS_VALUE, cap_holds_total_formula, money_fmt)
    row += 1
    
    return row
