from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from .helpers import (
    COL_BUCKET, COL_COUNTS_TOTAL, COL_COUNTS_ROSTER, COL_NAME,
    COL_OPTION, COL_GUARANTEE, COL_TRADE, COL_MIN_LABEL,
    COL_CAP_Y0, COL_PCT_CAP,
    num_generated_rows,
    _salary_book_choose_mode_aware
)
from ...xlsx import FMT_MONEY


def _write_generated_section(
    workbook: Workbook,
    worksheet: Worksheet,
    row: int,
    formats: dict[str, Any],
    roster_formats: dict[str, Any],
) -> int:
    """Write the GENERATED section (fill rows for roster assumptions).

    This section generates fill rows when RosterFillTarget is 12/14/15.
    The number of rows generated = RosterFillTarget - current_roster_count.

    Per mental-models-and-design-principles.md:
    - Generated rows must appear as GENERATED rows (visible bucket label)
    - They must be toggleable (RosterFillTarget=0 to disable)
    - They must be labeled as assumptions (not facts)

    Per the backlog:
    - RosterFillType controls the salary amount:
      - "Rookie Min" = rookie 1st-round min (pick 30) from tbl_rookie_scale
      - "Vet Min" = 0-year vet minimum from tbl_minimum_scale
      - "Cheapest" = MIN(rookie_min, vet_min)
    - Generated rows have Ct$=Y (count toward totals), CtR=Y (count toward roster)
    - Yellow/gold styling to distinguish from real contracts

    The section is controlled by RosterFillTarget toggle:
    - When 0 (default): section is collapsed with a message
    - When 12/14/15: shows generated fill rows

    Returns next row.
    """
    # Create special format for generated rows (gold/amber background)
    generated_section_fmt = workbook.add_format({
        "bold": True,
        "font_size": 11,
        "bg_color": "#FEF3C7",  # amber-100
        "font_color": "#92400E",  # amber-800
        "bottom": 1,
    })

    generated_row_fmt = workbook.add_format({
        "bg_color": "#FFFBEB",  # amber-50
        "font_color": "#78350F",  # amber-900
    })

    generated_money_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "bg_color": "#FFFBEB",  # amber-50
        "font_color": "#78350F",  # amber-900
    })

    generated_badge_fmt = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#B45309",  # amber-700
        "italic": True,
        "bg_color": "#FFFBEB",  # amber-50
    })

    generated_counts_fmt = workbook.add_format({
        "font_size": 9,
        "align": "center",
        "font_color": "#166534",  # green-800
        "bold": True,
        "bg_color": "#FFFBEB",  # amber-50
    })

    # Section header
    worksheet.merge_range(
        row, COL_BUCKET, row, COL_PCT_CAP,
        "GENERATED (Roster Fill Assumptions - policy-driven, NOT authoritative)",
        generated_section_fmt
    )
    row += 1

    # Explanatory note
    note_fmt = workbook.add_format({
        "italic": True,
        "font_size": 9,
        "font_color": "#92400E",  # amber-800
        "bg_color": "#FFFBEB",  # amber-50
    })
    worksheet.merge_range(row, COL_BUCKET, row, COL_PCT_CAP, "", note_fmt)
    worksheet.write(
        row, COL_BUCKET,
        "Generated fill rows based on RosterFillTarget/RosterFillType. Set RosterFillTarget=0 to disable.",
        note_fmt
    )
    row += 1

    # Conditional header row
    # When RosterFillTarget = 0, show "disabled" message; otherwise show column headers
    fmt = roster_formats["col_header"]

    worksheet.write_formula(
        row, COL_BUCKET,
        '=IF(RosterFillTarget=0,"RosterFillTarget=0 (disabled)","Bucket")',
        fmt
    )
    worksheet.write_formula(row, COL_COUNTS_TOTAL, '=IF(RosterFillTarget=0,"","Ct$")', fmt)
    worksheet.write_formula(row, COL_COUNTS_ROSTER, '=IF(RosterFillTarget=0,"","CtR")', fmt)
    worksheet.write_formula(row, COL_NAME, '=IF(RosterFillTarget=0,"","Name")', fmt)
    worksheet.write_formula(row, COL_OPTION, '=IF(RosterFillTarget=0,"","")', fmt)
    worksheet.write_formula(row, COL_GUARANTEE, '=IF(RosterFillTarget=0,"","")', fmt)
    worksheet.write_formula(row, COL_TRADE, '=IF(RosterFillTarget=0,"","")', fmt)
    worksheet.write_formula(row, COL_MIN_LABEL, '=IF(RosterFillTarget=0,"","Type")', fmt)

    # Year column headers (show year when active)
    for yi in range(6):
        worksheet.write_formula(
            row, COL_CAP_Y0 + yi,
            f'=IF(RosterFillTarget=0,"",SelectedMode&" "&(MetaBaseYear+{yi}))',
            fmt
        )
    worksheet.write_formula(row, COL_PCT_CAP, '=IF(RosterFillTarget=0,"","Note")', fmt)
    row += 1

    # =========================================================================
    # Fill amount formulas
    # =========================================================================
    # Rookie min formula (pick 30, year 1 salary for SelectedYear)
    rookie_min_formula = (
        "SUMIFS(tbl_rookie_scale[salary_year_1],"
        "tbl_rookie_scale[salary_year],SelectedYear,"
        "tbl_rookie_scale[pick_number],30)"
    )

    # Vet min formula (0 years of service for SelectedYear)
    vet_min_formula = (
        "SUMIFS(tbl_minimum_scale[minimum_salary_amount],"
        "tbl_minimum_scale[salary_year],SelectedYear,"
        "tbl_minimum_scale[years_of_service],0)"
    )

    # Fill amount formula (based on RosterFillType)
    fill_amount_formula = (
        f'IF(RosterFillType="Rookie Min",{rookie_min_formula},'
        f'IF(RosterFillType="Vet Min",{vet_min_formula},'
        f'MIN({rookie_min_formula},{vet_min_formula})))'  # Cheapest = MIN
    )

    # =========================================================================
    # Current roster count formula
    # =========================================================================
    # Count of roster players (non-two-way) with selected-year cap > 0
    cap_choose_expr = _salary_book_choose_mode_aware()
    current_roster_count_formula = (
        "SUMPRODUCT(--(tbl_salary_book_warehouse[team_code]=SelectedTeam),"
        "--(tbl_salary_book_warehouse[is_two_way]=FALSE),"
        f"--({cap_choose_expr}>0))"
    )

    # Number of fill rows needed = MAX(0, RosterFillTarget - current_roster_count)
    fill_rows_needed_formula = f"MAX(0,RosterFillTarget-{current_roster_count_formula})"

    # =========================================================================
    # Generated rows (up to 15 slots - max possible fills)
    # =========================================================================
    for i in range(1, num_generated_rows + 1):
        # This row is visible if: RosterFillTarget > 0 AND i <= fill_rows_needed
        row_active_formula = f"AND(RosterFillTarget>0,{i}<={fill_rows_needed_formula})"

        # Bucket (GENERATED)
        bucket_formula = f'=IF({row_active_formula},"GEN","")'
        worksheet.write_formula(row, COL_BUCKET, bucket_formula, generated_badge_fmt)

        # CountsTowardTotal: GENERATED rows count toward total (Y)
        counts_total_formula = f'=IF({row_active_formula},"Y","")'
        worksheet.write_formula(row, COL_COUNTS_TOTAL, counts_total_formula, generated_counts_fmt)

        # CountsTowardRoster: GENERATED rows count toward roster (Y)
        counts_roster_formula = f'=IF({row_active_formula},"Y","")'
        worksheet.write_formula(row, COL_COUNTS_ROSTER, counts_roster_formula, generated_counts_fmt)

        # Name (show fill type)
        name_formula = f'=IF({row_active_formula},"Fill Slot #"&{i}&" ("&RosterFillType&")","")'
        worksheet.write_formula(row, COL_NAME, name_formula, generated_row_fmt)

        # Option/Guarantee/Trade - empty for generated rows
        worksheet.write_formula(row, COL_OPTION, f'=IF({row_active_formula},"","")', generated_row_fmt)
        worksheet.write_formula(row, COL_GUARANTEE, f'=IF({row_active_formula},"","")', generated_row_fmt)
        worksheet.write_formula(row, COL_TRADE, f'=IF({row_active_formula},"","")', generated_row_fmt)

        # Type label (FILL)
        type_formula = f'=IF({row_active_formula},"FILL","")'
        worksheet.write_formula(row, COL_MIN_LABEL, type_formula, generated_badge_fmt)

        # Salary columns - show fill amount for y0 (SelectedYear relative offset)
        # Only y0 gets the fill amount (single-year assumption)
        for yi in range(6):
            sal_formula = (
                f'=IF(AND({row_active_formula},(MetaBaseYear+{yi})=SelectedYear),'
                f'{fill_amount_formula},"")'
            )
            worksheet.write_formula(row, COL_CAP_Y0 + yi, sal_formula, generated_money_fmt)

        # Note column
        note_formula = f'=IF({row_active_formula},"Assumption","")'
        worksheet.write_formula(row, COL_PCT_CAP, note_formula, generated_badge_fmt)

        row += 1

    # =========================================================================
    # Subtotals row
    # =========================================================================
    # Show count and total for generated rows
    worksheet.write_formula(
        row, COL_NAME,
        f'=IF(RosterFillTarget>0,"Generated Fill Total:","")',
        roster_formats["subtotal_label"]
    )

    # Total fill amount = fill_rows_needed * fill_amount
    total_fill_formula = (
        f'=IF(RosterFillTarget>0,'
        f'{fill_rows_needed_formula}*{fill_amount_formula},"")'
    )
    worksheet.write_formula(row, COL_CAP_Y0, total_fill_formula, roster_formats["subtotal"])

    # Count of generated rows
    worksheet.write_formula(
        row, COL_BUCKET,
        f'=IF(RosterFillTarget>0,{fill_rows_needed_formula},"")',
        roster_formats["subtotal_label"]
    )

    row += 2

    return row
