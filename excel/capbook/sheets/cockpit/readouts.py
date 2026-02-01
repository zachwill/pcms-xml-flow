"""
Primary readouts and minimum contracts section for TEAM_COCKPIT sheet.

Implements:
- Primary readouts (cap/tax/apron positions, roster counts, two-way info)
- Minimum contracts count + total
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ...xlsx import FMT_MONEY
from .constants import COL_READOUT_LABEL, COL_READOUT_VALUE, COL_READOUT_DESC
from .helpers import (
    sumifs_formula,
    if_formula,
    salary_book_min_contract_count_formula,
    salary_book_min_contract_sum_formula,
)


# =============================================================================
# Primary Readouts
# =============================================================================


def write_primary_readouts(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the primary readouts section.
    
    Returns:
        Next available row
    """
    # Create formats
    money_fmt = workbook.add_format({"num_format": FMT_MONEY, "bold": True})
    label_fmt = workbook.add_format({"bold": False})
    bold_fmt = workbook.add_format({"bold": True})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    
    # Section header
    worksheet.write(row, COL_READOUT_LABEL, "PRIMARY READOUTS", section_header_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(values update when Team/Year changes)")
    row += 1
    
    # Cap Position
    worksheet.write(row, COL_READOUT_LABEL, "Cap Position:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("over_cap"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({sumifs_formula("over_cap")[1:]}>=0,"over cap","cap room")',
    )
    row += 1
    
    # Tax Position
    worksheet.write(row, COL_READOUT_LABEL, "Tax Position:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("room_under_tax"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({sumifs_formula("room_under_tax")[1:]}>0,"under tax line","over tax line")',
    )
    row += 1
    
    # Room Under Apron 1
    worksheet.write(row, COL_READOUT_LABEL, "Room Under Apron 1:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("room_under_apron1"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({sumifs_formula("room_under_apron1")[1:]}>0,"under 1st apron","at/above 1st apron")',
    )
    row += 1
    
    # Room Under Apron 2
    worksheet.write(row, COL_READOUT_LABEL, "Room Under Apron 2:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("room_under_apron2"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'=IF({sumifs_formula("room_under_apron2")[1:]}>0,"under 2nd apron","at/above 2nd apron")',
    )
    row += 1
    
    # Roster Count
    worksheet.write(row, COL_READOUT_LABEL, "Roster Count:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("roster_row_count"), bold_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'="NBA roster + "&{sumifs_formula("two_way_row_count")[1:]}&" two-way"',
    )
    row += 1
    
    # Repeater Status
    worksheet.write(row, COL_READOUT_LABEL, "Repeater Status:", label_fmt)
    worksheet.write_formula(
        row, COL_READOUT_VALUE,
        f'=IF({if_formula("is_repeater_taxpayer")[1:]}=TRUE,"YES","NO")',
        bold_fmt,
    )
    worksheet.write(row, COL_READOUT_DESC, "(repeater taxpayer if TRUE)", label_fmt)
    row += 1
    
    # Cap Total (for reference)
    worksheet.write(row, COL_READOUT_LABEL, "Cap Total:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("cap_total"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'="vs cap of "&TEXT({sumifs_formula("salary_cap_amount")[1:]},"$#,##0")',
    )
    row += 1
    
    # Tax Total (for reference)
    worksheet.write(row, COL_READOUT_LABEL, "Tax Total:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("tax_total"), money_fmt)
    worksheet.write_formula(
        row, COL_READOUT_DESC,
        f'="vs tax line of "&TEXT({sumifs_formula("tax_level_amount")[1:]},"$#,##0")',
    )
    row += 1
    
    # =========================================================================
    # Two-Way Informational Readouts
    # =========================================================================
    # NOTE: Two-way counting is a CBA fact, not a user policy toggle.
    # Per CBA: two-way contracts COUNT toward cap/tax/apron totals but do NOT
    # count toward the 15-player NBA roster limit (they have separate 2-slot limit).
    # These readouts provide transparency for analysts who want to see the breakdown.
    
    # Two-Way Count
    worksheet.write(row, COL_READOUT_LABEL, "Two-Way Count:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("two_way_row_count"), bold_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(separate from 15-player roster)", label_fmt)
    row += 1
    
    # Two-Way Cap Amount (mode-aware would require more complexity; show cap for consistency)
    worksheet.write(row, COL_READOUT_LABEL, "Two-Way Cap Amount:", label_fmt)
    worksheet.write_formula(row, COL_READOUT_VALUE, sumifs_formula("cap_2way"), money_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(included in Cap Total above)", label_fmt)
    row += 1
    
    # Blank row for spacing
    row += 1
    
    return row


# =============================================================================
# Minimum Contracts Readout
# =============================================================================


def write_minimum_contracts_readout(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the minimum contracts count + total readout.
    
    Uses is_min_contract from tbl_salary_book_warehouse.
    Uses LET + FILTER + SUM/ROWS pattern (Excel 365+) per formula standard.
    
    Returns:
        Next available row
    """
    money_fmt = workbook.add_format({"num_format": FMT_MONEY, "bold": True})
    label_fmt = workbook.add_format({"bold": False})
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    
    worksheet.write(row, COL_READOUT_LABEL, "MINIMUM CONTRACTS", section_header_fmt)
    row += 1
    
    # Count of minimum contracts for selected team
    # Uses LET + FILTER + ROWS pattern instead of COUNTIFS
    worksheet.write(row, COL_READOUT_LABEL, "Min Contract Count:", label_fmt)
    worksheet.write_formula(
        row, COL_READOUT_VALUE,
        salary_book_min_contract_count_formula(),
    )
    worksheet.write(row, COL_READOUT_DESC, "players on minimum contracts", label_fmt)
    row += 1
    
    # Total salary for minimum contracts (SelectedYear cap amounts)
    # Uses LET + FILTER + SUM pattern instead of SUMPRODUCT
    worksheet.write(row, COL_READOUT_LABEL, "Min Contract Total:", label_fmt)
    worksheet.write_formula(
        row, COL_READOUT_VALUE,
        salary_book_min_contract_sum_formula(),
        money_fmt,
    )
    worksheet.write(row, COL_READOUT_DESC, "(SelectedYear cap amounts)", label_fmt)
    row += 1
    
    # Blank row for spacing
    row += 1
    
    return row
