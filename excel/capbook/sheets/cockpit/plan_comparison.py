"""
Plan comparison panel for TEAM_COCKPIT sheet.

Implements the ComparePlan A/B/C/D deltas display per the blueprint.

Per the blueprint (mental-models-and-design-principles.md):
- Comparison is a first-class workflow
- Analysts compare 2-4 deal candidates side-by-side (lane-based branching)

This panel shows:
- For each ComparePlan (A/B/C/D): delta vs Baseline (cap/tax/apron)
- Warning if ComparePlan is blank or equals Baseline
- Link to PLAN_JOURNAL for details
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet

from ...xlsx import FMT_MONEY
from .constants import COL_READOUT_LABEL, COL_READOUT_VALUE, COL_READOUT_DESC


# =============================================================================
# Plan Comparison Panel
# =============================================================================


def _plan_delta_formula(compare_plan_range: str, delta_col: str) -> str:
    """Build LET+XLOOKUP+FILTER+SUM formula to get delta for a ComparePlan.
    
    Logic:
    - Use XLOOKUP to resolve plan_name → plan_id from tbl_plan_manager
    - Filter tbl_plan_journal rows where:
      - (plan_id = resolved_plan_id OR plan_id = "")
      - (salary_year = SelectedYear OR salary_year = "")
      - enabled = "Yes"
    - Sum the delta column for matching rows
    
    Returns 0 if the compare plan is blank or not found.
    
    Uses Excel 365+ dynamic arrays (LET + XLOOKUP + FILTER + SUM) per
    the formula standard in AGENTS.md.
    """
    # LET structure:
    #   plan_name: the selected compare plan name
    #   plan_id: XLOOKUP to resolve plan_name → plan_id
    #   mask: filter condition for matching journal rows
    #   result: SUM(FILTER(...)) or 0
    return (
        f'=LET('
        f'_xlpm.plan_name,{compare_plan_range},'
        f'_xlpm.plan_id,XLOOKUP(_xlpm.plan_name,tbl_plan_manager[plan_name],tbl_plan_manager[plan_id],""),'
        f'_xlpm.mask,(tbl_plan_journal[enabled]="Yes")*'
        f'((tbl_plan_journal[plan_id]=_xlpm.plan_id)+(tbl_plan_journal[plan_id]=""))*'
        f'((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]="")),'
        f'IF(_xlpm.plan_name="",'
        f'0,'
        f'IFERROR(SUM(FILTER(tbl_plan_journal[{delta_col}],_xlpm.mask,0)),0)))'
    )


def _plan_status_formula(compare_plan_range: str) -> str:
    """Build LET+XLOOKUP+FILTER+ROWS formula to show status/warning for a ComparePlan.
    
    Shows:
    - "(not selected)" if the compare plan is blank
    - "(same as Baseline)" if compare plan equals "Baseline"
    - Action count and link to PLAN_JOURNAL otherwise
    
    Uses Excel 365+ dynamic arrays (LET + XLOOKUP + FILTER + ROWS) per
    the formula standard in AGENTS.md.
    """
    # LET structure:
    #   plan_name: the selected compare plan name
    #   plan_id: XLOOKUP to resolve plan_name → plan_id
    #   mask: filter condition for matching journal rows
    #   action_count: ROWS(FILTER(...)) to count matching rows
    return (
        f'=LET('
        f'_xlpm.plan_name,{compare_plan_range},'
        f'_xlpm.plan_id,XLOOKUP(_xlpm.plan_name,tbl_plan_manager[plan_name],tbl_plan_manager[plan_id],""),'
        f'_xlpm.mask,(tbl_plan_journal[enabled]="Yes")*'
        f'((tbl_plan_journal[plan_id]=_xlpm.plan_id)+(tbl_plan_journal[plan_id]=""))*'
        f'((tbl_plan_journal[salary_year]=SelectedYear)+(tbl_plan_journal[salary_year]="")),'
        f'_xlpm.action_count,IFERROR(ROWS(FILTER(tbl_plan_journal[step],_xlpm.mask)),0),'
        f'IF(_xlpm.plan_name="",'
        f'"(not selected)",'
        f'IF(_xlpm.plan_name="Baseline",'
        f'"(same as Baseline)",'
        f'_xlpm.action_count&" actions → see PLAN_JOURNAL")))'
    )


def write_plan_comparison_panel(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    row: int,
) -> int:
    """Write the plan comparison panel showing ComparePlan A/B/C/D deltas.
    
    Per the blueprint (mental-models-and-design-principles.md):
    - Comparison is a first-class workflow
    - Analysts compare 2-4 deal candidates side-by-side (lane-based branching)
    
    This panel shows:
    - For each ComparePlan (A/B/C/D): delta vs Baseline (cap/tax/apron)
    - Warning if ComparePlan is blank or equals Baseline
    - Link to PLAN_JOURNAL for details
    
    Plan delta formulas filter by:
    - plan_id = lookup(ComparePlanX -> tbl_plan_manager[plan_id])
    - salary_year = SelectedYear (or blank)
    - enabled = "Yes"
    
    Returns:
        Next available row
    """
    # Formats
    section_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 9,
        "font_color": "#616161",
    })
    panel_header_fmt = workbook.add_format({
        "bold": True,
        "font_size": 10,
        "bg_color": "#3B82F6",  # blue-500
        "font_color": "#FFFFFF",
        "border": 1,
    })
    plan_label_fmt = workbook.add_format({
        "bold": True,
        "font_size": 10,
    })
    money_fmt = workbook.add_format({"num_format": FMT_MONEY})
    money_delta_pos_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#DC2626",  # red-600 (cost increase)
    })
    money_delta_neg_fmt = workbook.add_format({
        "num_format": FMT_MONEY,
        "font_color": "#059669",  # green-600 (savings)
    })
    note_fmt = workbook.add_format({
        "font_size": 9,
        "font_color": "#6B7280",
        "italic": True,
    })
    warning_fmt = workbook.add_format({
        "font_size": 9,
        "font_color": "#92400E",  # amber-800
        "bg_color": "#FEF3C7",  # amber-100
    })
    
    # Section header
    worksheet.write(row, COL_READOUT_LABEL, "PLAN COMPARISON", section_header_fmt)
    worksheet.write(row, COL_READOUT_DESC, "(ComparePlan A/B/C/D vs Baseline)")
    row += 1
    
    # Column headers
    worksheet.write(row, COL_READOUT_LABEL, "Plan", panel_header_fmt)
    worksheet.write(row, COL_READOUT_VALUE, "Δ Cap", panel_header_fmt)
    worksheet.write(row, COL_READOUT_DESC, "Status / Notes", panel_header_fmt)
    row += 1
    
    # Write rows for each ComparePlan
    compare_plans = [
        ("ComparePlanA", "Compare A:"),
        ("ComparePlanB", "Compare B:"),
        ("ComparePlanC", "Compare C:"),
        ("ComparePlanD", "Compare D:"),
    ]
    
    for plan_range, label in compare_plans:
        # Plan name label (shows the selected plan name)
        worksheet.write(row, COL_READOUT_LABEL, label, plan_label_fmt)
        
        # Delta Cap (for now, show cap delta; could expand to show tax/apron)
        cap_formula = _plan_delta_formula(plan_range, "delta_cap")
        worksheet.write_formula(row, COL_READOUT_VALUE, cap_formula, money_fmt)
        
        # Status/notes
        status_formula = _plan_status_formula(plan_range)
        worksheet.write_formula(row, COL_READOUT_DESC, status_formula, note_fmt)
        
        # Conditional formatting: delta values
        worksheet.conditional_format(row, COL_READOUT_VALUE, row, COL_READOUT_VALUE, {
            "type": "cell",
            "criteria": ">",
            "value": 0,
            "format": money_delta_pos_fmt,
        })
        worksheet.conditional_format(row, COL_READOUT_VALUE, row, COL_READOUT_VALUE, {
            "type": "cell",
            "criteria": "<",
            "value": 0,
            "format": money_delta_neg_fmt,
        })
        
        # Conditional formatting: warn if blank or Baseline
        worksheet.conditional_format(row, COL_READOUT_DESC, row, COL_READOUT_DESC, {
            "type": "formula",
            "criteria": f'=OR({plan_range}="",{plan_range}="Baseline")',
            "format": warning_fmt,
        })
        
        row += 1
    
    # Blank row
    row += 1
    
    # Link note
    worksheet.write(
        row, COL_READOUT_LABEL,
        "→ Edit plans in PLAN_MANAGER, actions in PLAN_JOURNAL",
        note_fmt
    )
    row += 2
    
    return row
