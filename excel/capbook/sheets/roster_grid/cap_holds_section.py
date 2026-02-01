from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ...named_formulas import (
    cap_holds_col_formula,
    cap_holds_derived_formula,
)
from .helpers import (
    COL_BUCKET, COL_COUNTS_TOTAL, COL_COUNTS_ROSTER, COL_NAME,
    COL_CAP_Y0, COL_PCT_CAP,
    num_hold_rows,
    _mode_year_label, _write_column_headers,
    _cap_holds_sumproduct, _cap_holds_countproduct
)


def _write_cap_holds_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the cap holds section (from tbl_cap_holds_warehouse).

    Uses Excel 365 dynamic array formulas (FILTER, SORTBY, TAKE).

    Returns next row.
    """
    section_fmt = roster_formats["section_header"]

    # Section header
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "CAP HOLDS (Free Agent Rights)", section_fmt)
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
    name_formula = cap_holds_col_formula("tbl_cap_holds_warehouse[player_name]", num_hold_rows)
    worksheet.write_formula(row, COL_NAME, name_formula)

    # -------------------------------------------------------------------------
    # Bucket column (FA)
    # -------------------------------------------------------------------------
    bucket_formula = cap_holds_derived_formula(
        "tbl_cap_holds_warehouse[player_name]", 'IF({result}<>"", "FA", "")', num_hold_rows
    )
    worksheet.write_formula(row, COL_BUCKET, bucket_formula, roster_formats["bucket_fa"])

    # -------------------------------------------------------------------------
    # CountsTowardTotal (Y for FA)
    # -------------------------------------------------------------------------
    ct_total_formula = cap_holds_derived_formula(
        "tbl_cap_holds_warehouse[player_name]", 'IF({result}<>"", "Y", "")', num_hold_rows
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, ct_total_formula, roster_formats["counts_yes"])

    # -------------------------------------------------------------------------
    # CountsTowardRoster (N for FA)
    # -------------------------------------------------------------------------
    ct_roster_formula = cap_holds_derived_formula(
        "tbl_cap_holds_warehouse[player_name]", 'IF({result}<>"", "N", "")', num_hold_rows
    )
    worksheet.write_formula(row, COL_COUNTS_ROSTER, ct_roster_formula, roster_formats["counts_no"])

    # -------------------------------------------------------------------------
    # Salary columns (cap holds only show in SelectedYear column)
    # -------------------------------------------------------------------------
    # SelectedYear column
    sal_formula = cap_holds_col_formula("CapHoldsModeAmt()", num_hold_rows)
    worksheet.write_formula(row, COL_CAP_Y0, sal_formula, roster_formats["money"])

    # Future columns are empty for now as cap_holds_warehouse is tall and filtered by SelectedYear
    # (If we want to show future holds, we'd need a different filter per column)
    for yi in range(1, 6):
        worksheet.write_formula(row, COL_CAP_Y0 + yi, '=""', roster_formats["money"])

    # Move past spill zone
    row += num_hold_rows

    # Subtotal row
    worksheet.write(row, COL_NAME, "Cap Holds Subtotal:", roster_formats["subtotal_label"])
    
    worksheet.write_formula(
        row,
        COL_CAP_Y0,
        f"={_cap_holds_sumproduct()}",
        roster_formats["subtotal"],
    )
    worksheet.write_formula(
        row,
        COL_BUCKET,
        f"={_cap_holds_countproduct()}",
        roster_formats["subtotal_label"],
    )

    row += 2  # Blank row

    return row
