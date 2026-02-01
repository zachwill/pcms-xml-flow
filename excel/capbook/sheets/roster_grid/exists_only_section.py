from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .helpers import (
    COL_BUCKET, COL_COUNTS_TOTAL, COL_COUNTS_ROSTER, COL_NAME,
    COL_OPTION, COL_GUARANTEE, COL_TRADE, COL_MIN_LABEL,
    COL_CAP_Y0, COL_PCT_CAP,
    num_exists_rows
)
from ...named_formulas import (
    exists_only_col_formula,
    exists_only_derived_formula,
    exists_only_salary_formula,
)


def _write_exists_only_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the EXISTS_ONLY section (non-counting rows for analyst reference).

    This section shows players who:
    - Belong to SelectedTeam
    - Have $0 in SelectedYear (across all modes: cap/tax/apron all zero)
    - But have non-zero amounts in a future year

    These rows "exist" in the salary book but do NOT count toward current year totals.
    They're useful for planning context (e.g., future-year commitments, option years).

    The section is controlled by ShowExistsOnlyRows toggle:
    - When "No" (default): shows a collapsed message explaining the section is hidden
    - When "Yes": shows the full listing of exists-only rows

    Per the blueprint (mental-models-and-design-principles.md):
    - EXISTS_ONLY rows are labeled as "visible artifacts that do not count (for reference only)"
    - Ct$ = N, CtR = N (never counted)

    Uses Excel 365 dynamic arrays: LET, FILTER, SORTBY, TAKE, BYROW (or MAP for per-row computation).
    The future_total is computed per-player as the sum of future-year amounts (any mode).

    Returns next row.
    """
    section_fmt = roster_formats["section_header_exists_only"]

    # Section header with explanatory text
    worksheet.merge_range(
        row, COL_BUCKET, row, COL_PCT_CAP,
        "EXISTS_ONLY (Future-Year Contracts - does NOT count in SelectedYear)",
        section_fmt
    )
    row += 1

    # Explanatory note
    note_fmt = workbook.add_format({
        "italic": True,
        "font_size": 9,
        "font_color": "#6B7280",  # gray-500
    })
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "", note_fmt)
    worksheet.write(
        row, COL_BUCKET,
        "Players with $0 this year but future-year amounts. For analyst reference only - excluded from totals.",
        note_fmt
    )
    row += 1

    # Note about dynamic arrays
    worksheet.write(row, COL_BUCKET, "Dynamic array: EXISTS_ONLY players filtered by future-year amounts (uses LET/FILTER/SORTBY)", roster_formats["reconcile_label"])
    row += 1

    # Column headers (only shown when ShowExistsOnlyRows = "Yes")
    fmt = roster_formats["col_header"]
    hidden_text_fmt = workbook.add_format({
        "italic": True,
        "font_color": "#9CA3AF",  # gray-400
        "font_size": 9,
    })

    # Write conditional header row
    # When ShowExistsOnlyRows = "Yes", show column headers; otherwise show toggle hint
    worksheet.write_formula(
        row, COL_BUCKET,
        '=IF(ShowExistsOnlyRows="Yes","Bucket","Set ShowExistsOnlyRows=Yes to display")',
        fmt
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, '=IF(ShowExistsOnlyRows="Yes","Ct$","")', fmt)
    worksheet.write_formula(row, COL_COUNTS_ROSTER, '=IF(ShowExistsOnlyRows="Yes","CtR","")', fmt)
    worksheet.write_formula(row, COL_NAME, '=IF(ShowExistsOnlyRows="Yes","Name","")', fmt)
    worksheet.write_formula(row, COL_OPTION, '=IF(ShowExistsOnlyRows="Yes","","")', fmt)
    worksheet.write_formula(row, COL_GUARANTEE, '=IF(ShowExistsOnlyRows="Yes","","")', fmt)
    worksheet.write_formula(row, COL_TRADE, '=IF(ShowExistsOnlyRows="Yes","","")', fmt)
    worksheet.write_formula(row, COL_MIN_LABEL, '=IF(ShowExistsOnlyRows="Yes","Future Total","")', fmt)

    # Year column headers (show year when active)
    for yi in range(6):
        worksheet.write_formula(
            row, COL_CAP_Y0 + yi,
            f'=IF(ShowExistsOnlyRows="Yes",SelectedMode&" "&(MetaBaseYear+{yi}),"")',
            fmt
        )
    worksheet.write_formula(row, COL_PCT_CAP, '=IF(ShowExistsOnlyRows="Yes","Note","")', fmt)
    row += 1

    # =========================================================================
    # Dynamic Array Formulas: using named formula helpers
    # =========================================================================

    # -------------------------------------------------------------------------
    # Player Name column (spills down)
    # -------------------------------------------------------------------------
    # When ShowExistsOnlyRows="No", returns empty array; otherwise spills names
    worksheet.write_formula(
        row, COL_NAME,
        exists_only_col_formula("tbl_salary_book_warehouse[player_name]", num_exists_rows)
    )

    # -------------------------------------------------------------------------
    # Bucket column (EXISTS for non-empty rows)
    # -------------------------------------------------------------------------
    worksheet.write_formula(
        row, COL_BUCKET,
        exists_only_derived_formula(
            "tbl_salary_book_warehouse[player_name]",
            'IF({result}<>"","EXISTS","")',
            num_exists_rows
        ),
        roster_formats["bucket_exists_only"]
    )

    # -------------------------------------------------------------------------
    # CountsTowardTotal column (N for EXISTS_ONLY - never counts)
    # -------------------------------------------------------------------------
    worksheet.write_formula(
        row, COL_COUNTS_TOTAL,
        exists_only_derived_formula(
            "tbl_salary_book_warehouse[player_name]",
            'IF({result}<>"","N","")',
            num_exists_rows
        ),
        roster_formats["counts_no"]
    )

    # -------------------------------------------------------------------------
    # CountsTowardRoster column (N for EXISTS_ONLY - never counts)
    # -------------------------------------------------------------------------
    worksheet.write_formula(
        row, COL_COUNTS_ROSTER,
        exists_only_derived_formula(
            "tbl_salary_book_warehouse[player_name]",
            'IF({result}<>"","N","")',
            num_exists_rows
        ),
        roster_formats["counts_no"]
    )

    # Option/Guarantee/Trade - empty for EXISTS_ONLY (these are future contracts)
    worksheet.write(row, COL_OPTION, "")
    worksheet.write(row, COL_GUARANTEE, "")
    worksheet.write(row, COL_TRADE, "")

    # -------------------------------------------------------------------------
    # Future Total column (shows mode-aware future sum for context)
    # -------------------------------------------------------------------------
    worksheet.write_formula(
        row, COL_MIN_LABEL,
        exists_only_col_formula("SalaryBookExistsFutureAmt()", num_exists_rows),
        roster_formats["money"]
    )

    # -------------------------------------------------------------------------
    # Salary columns - show all years (mode-aware) so analyst can see future money
    # -------------------------------------------------------------------------
    for yi in range(6):
        worksheet.write_formula(
            row, COL_CAP_Y0 + yi,
            exists_only_salary_formula(yi, num_exists_rows),
            roster_formats["money"]
        )

    # -------------------------------------------------------------------------
    # Note column - display "Future $" for non-empty rows
    # -------------------------------------------------------------------------
    worksheet.write_formula(
        row, COL_PCT_CAP,
        exists_only_derived_formula(
            "tbl_salary_book_warehouse[player_name]",
            'IF({result}<>"","Future $","")',
            num_exists_rows
        ),
        hidden_text_fmt
    )

    # Move past spill zone
    row += num_exists_rows

    # -------------------------------------------------------------------------
    # Count of exists-only rows (informational only, not part of totals)
    # -------------------------------------------------------------------------
    # Using LET + SUM(FILTER) pattern instead of SUMPRODUCT
    count_label_formula = '=IF(ShowExistsOnlyRows="Yes","Exists-Only Count:","")'
    worksheet.write_formula(row, COL_NAME, count_label_formula, roster_formats["subtotal_label"])

    # Count formula using LET + ROWS(FILTER)
    count_value_formula = (
        '=IF(ShowExistsOnlyRows<>"Yes","",IFERROR(ROWS(FILTER(tbl_salary_book_warehouse[player_name],SalaryBookExistsFilter())),0))'
    )
    worksheet.write_formula(row, COL_BUCKET, count_value_formula, roster_formats["subtotal_label"])

    row += 2

    return row

    row += 2

    return row
