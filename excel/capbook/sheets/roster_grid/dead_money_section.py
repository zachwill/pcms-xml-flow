from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ...named_formulas import (
    dead_money_col_formula,
    dead_money_derived_formula,
)
from .helpers import (
    COL_BUCKET, COL_COUNTS_TOTAL, COL_COUNTS_ROSTER, COL_NAME,
    COL_CAP_Y0, COL_PCT_CAP,
    num_dead_rows,
    _mode_year_label, _write_column_headers,
    _dead_money_sumproduct, _dead_money_countproduct
)


def _write_dead_money_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the dead money section (from tbl_dead_money_warehouse).

    Uses Excel 365 dynamic array formulas (FILTER, SORTBY, TAKE).

    Returns next row.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "DEAD MONEY (Terminated Contracts)", section_fmt)
    row += 1

    # Column headers
    year_labels = [
        _mode_year_label(0),
        _mode_year_label(1),
        _mode_year_label(2),
        _mode_year_label(3),
        _mode_year_label(4),
        _mode_year_label(5),
    ]
    row = _write_column_headers(worksheet, row, roster_formats, year_labels)

    # -------------------------------------------------------------------------
    # Player Name column
    # -------------------------------------------------------------------------
    name_formula = dead_money_col_formula("tbl_dead_money_warehouse[player_name]", num_dead_rows)
    worksheet.write_formula(row, COL_NAME, name_formula)

    # -------------------------------------------------------------------------
    # Bucket column (TERM)
    # -------------------------------------------------------------------------
    bucket_formula = dead_money_derived_formula(
        "tbl_dead_money_warehouse[player_name]", 'IF({result}<>"", "TERM", "")', num_dead_rows
    )
    worksheet.write_formula(row, COL_BUCKET, bucket_formula, roster_formats["bucket_term"])

    # -------------------------------------------------------------------------
    # CountsTowardTotal (Y for TERM)
    # -------------------------------------------------------------------------
    ct_total_formula = dead_money_derived_formula(
        "tbl_dead_money_warehouse[player_name]", 'IF({result}<>"", "Y", "")', num_dead_rows
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, ct_total_formula, roster_formats["counts_yes"])

    # -------------------------------------------------------------------------
    # CountsTowardRoster (N for TERM)
    # -------------------------------------------------------------------------
    ct_roster_formula = dead_money_derived_formula(
        "tbl_dead_money_warehouse[player_name]", 'IF({result}<>"", "N", "")', num_dead_rows
    )
    worksheet.write_formula(row, COL_COUNTS_ROSTER, ct_roster_formula, roster_formats["counts_no"])

    # -------------------------------------------------------------------------
    # Salary columns (dead money only shows in SelectedYear column)
    # -------------------------------------------------------------------------
    # SelectedYear column
    sal_formula = dead_money_col_formula("DeadMoneyModeAmt()", num_dead_rows)
    worksheet.write_formula(row, COL_CAP_Y0, sal_formula, roster_formats["money"])

    # Future columns are empty for now as dead_money_warehouse is tall and filtered by SelectedYear
    for yi in range(1, 6):
        worksheet.write_formula(row, COL_CAP_Y0 + yi, '=""', roster_formats["money"])

    # Move past spill zone
    row += num_dead_rows

    # Subtotal row
    worksheet.write(row, COL_NAME, "Dead Money Subtotal:", roster_formats["subtotal_label"])
    
    worksheet.write_formula(
        row,
        COL_CAP_Y0,
        f"={_dead_money_sumproduct()}",
        roster_formats["subtotal"],
    )
    worksheet.write_formula(
        row,
        COL_BUCKET,
        f"={_dead_money_countproduct()}",
        roster_formats["subtotal_label"],
    )

    row += 2  # Blank row

    return row
