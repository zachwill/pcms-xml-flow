"""
Named Formulas (LAMBDA/LET helpers) for the Excel Cap Workbook.

This module defines reusable named formulas that centralize repeated logic,
per backlog item #2 in .ralph/EXCEL.md.

**Excel 365/2021 Required:** These formulas use LAMBDA which requires Excel 365
or Excel 2021. Earlier versions will show #NAME? errors.

Named formulas defined here:

1. ModeYearIndex
   - Returns the 1-based relative year index: SelectedYear - MetaBaseYear + 1
   - Values: 1 (base year) through 6 (base year + 5)
   - Used by: CHOOSE formulas for selecting cap_y0..cap_y5 columns

2. PlanRowMask (LAMBDA)
   - Returns TRUE for plan_journal rows matching ActivePlanId + SelectedYear + enabled
   - Handles blank salary_year (means "applies to all years")
   - Used by: PLAN_JOURNAL running totals, BUDGET_LEDGER plan deltas, AUDIT

3. TeamYearMask (LAMBDA)
   - Returns TRUE for rows matching SelectedTeam + SelectedYear
   - Used by: Drilldown aggregations, roster counts

4. CapYearAmount (LAMBDA)
   - Selects the appropriate cap amount column based on ModeYearIndex
   - Takes row reference and returns the cap value for SelectedYear

5. AmountByMode (LAMBDA)
   - Selects cap/tax/apron amount based on SelectedMode + ModeYearIndex
   - Used by: Mode-aware displays in ROSTER_GRID, COCKPIT

Usage in formulas:
    Instead of:  CHOOSE(SelectedYear-MetaBaseYear+1, cap_y0, cap_y1, ...)
    Use:         CapYearAmount([@cap_y0]:[@cap_y5])
    
    Instead of:  SUMPRODUCT((plan_id=ActivePlanId)*((salary_year=SelectedYear)+(salary_year=""))*(enabled="Yes")*delta_cap)
    Use:         SUMPRODUCT(PlanRowMask(tbl_plan_journal[plan_id],tbl_plan_journal[salary_year],tbl_plan_journal[enabled])*tbl_plan_journal[delta_cap])

Design notes:
- These are Excel 365+ features (LAMBDA requires Excel 365 or 2021)
- All formulas are workbook-scoped (not sheet-scoped)
- Formulas reference other named ranges (SelectedYear, MetaBaseYear, etc.)
- LAMBDA formulas take parameters and can be called like functions
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.workbook import Workbook


# =============================================================================
# Named Formula Definitions
# =============================================================================

# Simple named formulas (single expressions, no parameters)
SIMPLE_NAMED_FORMULAS: dict[str, str] = {
    # ModeYearIndex: 1-based year offset (1..6)
    # Use: CHOOSE(ModeYearIndex, cap_y0, cap_y1, ...)
    # or:  INDEX(array, ModeYearIndex)
    "ModeYearIndex": "=SelectedYear-MetaBaseYear+1",
}

# LAMBDA-based named formulas (reusable functions with parameters)
# These are more powerful but require Excel 365/2021+
#
# Note: XlsxWriter's define_name handles LAMBDA formulas correctly.
# The formula string must start with '=' and use proper LAMBDA syntax.
LAMBDA_NAMED_FORMULAS: dict[str, tuple[str, str]] = {
    # PlanRowMask: Filter mask for plan_journal rows
    # Parameters:
    #   plan_id_col:    The plan_id column (e.g., tbl_plan_journal[plan_id])
    #   salary_year_col: The salary_year column
    #   enabled_col:    The enabled column
    # Returns: Array of TRUE/FALSE matching ActivePlanId + SelectedYear + enabled
    # Logic: (plan_id = ActivePlanId OR plan_id = "") AND 
    #        (salary_year = SelectedYear OR salary_year = "") AND
    #        (enabled = "Yes")
    "PlanRowMask": (
        "=LAMBDA(plan_id_col,salary_year_col,enabled_col,"
        "((plan_id_col=ActivePlanId)+(plan_id_col=\"\"))*"
        "((salary_year_col=SelectedYear)+(salary_year_col=\"\"))*"
        "(enabled_col=\"Yes\"))",
        "Filter mask for plan_journal rows matching ActivePlanId + SelectedYear + enabled=Yes",
    ),
    
    # TeamYearMask: Filter mask for team+year filtering
    # Parameters:
    #   team_col: Team code column
    #   year_col: Salary year column
    # Returns: Array of TRUE/FALSE for matching rows
    "TeamYearMask": (
        "=LAMBDA(team_col,year_col,"
        "(team_col=SelectedTeam)*(year_col=SelectedYear))",
        "Filter mask for rows matching SelectedTeam + SelectedYear",
    ),
    
    # CapYearAmount: Select cap amount for SelectedYear from wide table row
    # Parameters:
    #   y0: cap_y0 value
    #   y1: cap_y1 value
    #   y2: cap_y2 value
    #   y3: cap_y3 value
    #   y4: cap_y4 value
    #   y5: cap_y5 value
    # Returns: The cap value for SelectedYear
    # Note: Uses CHOOSE with ModeYearIndex (1-based)
    "CapYearAmount": (
        "=LAMBDA(y0,y1,y2,y3,y4,y5,"
        "CHOOSE(ModeYearIndex,y0,y1,y2,y3,y4,y5))",
        "Select cap_yN value based on SelectedYear (uses ModeYearIndex)",
    ),
    
    # TaxYearAmount: Select tax amount for SelectedYear from wide table row
    "TaxYearAmount": (
        "=LAMBDA(y0,y1,y2,y3,y4,y5,"
        "CHOOSE(ModeYearIndex,y0,y1,y2,y3,y4,y5))",
        "Select tax_yN value based on SelectedYear (uses ModeYearIndex)",
    ),
    
    # ApronYearAmount: Select apron amount for SelectedYear from wide table row
    "ApronYearAmount": (
        "=LAMBDA(y0,y1,y2,y3,y4,y5,"
        "CHOOSE(ModeYearIndex,y0,y1,y2,y3,y4,y5))",
        "Select apron_yN value based on SelectedYear (uses ModeYearIndex)",
    ),
    
    # AmountByMode: Select cap/tax/apron amount based on SelectedMode
    # Parameters:
    #   cap_val: Cap amount
    #   tax_val: Tax amount
    #   apron_val: Apron amount
    # Returns: The amount for the current SelectedMode (Cap/Tax/Apron)
    "AmountByMode": (
        "=LAMBDA(cap_val,tax_val,apron_val,"
        'IF(SelectedMode="Cap",cap_val,'
        'IF(SelectedMode="Tax",tax_val,'
        "apron_val)))",
        "Select cap/tax/apron value based on SelectedMode",
    ),
    
    # YearAmountByMode: Combines CapYearAmount + AmountByMode
    # Parameters:
    #   cap_y0..cap_y5: Cap amounts for years 0-5
    #   tax_y0..tax_y5: Tax amounts for years 0-5
    #   apron_y0..apron_y5: Apron amounts for years 0-5
    # This is complex with many params - in practice, we may use the simpler
    # formulas and compose them. Included for completeness.
    # Note: Due to LAMBDA's 253-char limit for define_name in some contexts,
    # this longer formula is split for readability but defined as one string.
    "YearAmountByMode": (
        "=LAMBDA(cap_y0,cap_y1,cap_y2,cap_y3,cap_y4,cap_y5,"
        "tax_y0,tax_y1,tax_y2,tax_y3,tax_y4,tax_y5,"
        "apron_y0,apron_y1,apron_y2,apron_y3,apron_y4,apron_y5,"
        "LET("
        "cap_amt,CHOOSE(ModeYearIndex,cap_y0,cap_y1,cap_y2,cap_y3,cap_y4,cap_y5),"
        "tax_amt,CHOOSE(ModeYearIndex,tax_y0,tax_y1,tax_y2,tax_y3,tax_y4,tax_y5),"
        "apron_amt,CHOOSE(ModeYearIndex,apron_y0,apron_y1,apron_y2,apron_y3,apron_y4,apron_y5),"
        'IF(SelectedMode="Cap",cap_amt,IF(SelectedMode="Tax",tax_amt,apron_amt))))',
        "Select cap/tax/apron amount for SelectedYear based on SelectedMode",
    ),
}


def define_named_formulas(workbook: Workbook) -> dict[str, str]:
    """
    Define all named formulas in the workbook.
    
    These are workbook-scoped named ranges that contain formulas (not cell refs).
    They enable formula reuse and make complex formulas more readable.
    
    Call this early in the build process, after META named ranges are defined
    but before UI sheets are written.
    
    Args:
        workbook: The XlsxWriter Workbook
        
    Returns:
        dict mapping formula name -> formula expression (for reference/logging)
    """
    defined: dict[str, str] = {}
    
    # Define simple named formulas
    for name, formula in SIMPLE_NAMED_FORMULAS.items():
        workbook.define_name(name, formula)
        defined[name] = formula
    
    # Define LAMBDA-based named formulas
    for name, (formula, _description) in LAMBDA_NAMED_FORMULAS.items():
        workbook.define_name(name, formula)
        defined[name] = formula
    
    return defined


def get_formula_documentation() -> list[dict[str, Any]]:
    """
    Return documentation for all named formulas.
    
    This can be used to populate a reference section or documentation sheet.
    
    Returns:
        List of dicts with keys: name, formula, description, type
    """
    docs: list[dict[str, Any]] = []
    
    for name, formula in SIMPLE_NAMED_FORMULAS.items():
        docs.append({
            "name": name,
            "formula": formula,
            "description": "Simple expression (no parameters)",
            "type": "simple",
        })
    
    for name, (formula, description) in LAMBDA_NAMED_FORMULAS.items():
        docs.append({
            "name": name,
            "formula": formula,
            "description": description,
            "type": "lambda",
        })
    
    return docs


# =============================================================================
# Formula Usage Helpers
# =============================================================================

def formula_plan_row_mask(plan_id_col: str, year_col: str, enabled_col: str) -> str:
    """
    Return a formula that calls PlanRowMask with the given column references.
    
    Example:
        formula_plan_row_mask(
            "tbl_plan_journal[plan_id]",
            "tbl_plan_journal[salary_year]",
            "tbl_plan_journal[enabled]"
        )
        -> "PlanRowMask(tbl_plan_journal[plan_id],tbl_plan_journal[salary_year],tbl_plan_journal[enabled])"
    """
    return f"PlanRowMask({plan_id_col},{year_col},{enabled_col})"


def formula_team_year_mask(team_col: str, year_col: str) -> str:
    """
    Return a formula that calls TeamYearMask with the given column references.
    
    Example:
        formula_team_year_mask("tbl_salary_book_yearly[team_code]", "tbl_salary_book_yearly[salary_year]")
        -> "TeamYearMask(tbl_salary_book_yearly[team_code],tbl_salary_book_yearly[salary_year])"
    """
    return f"TeamYearMask({team_col},{year_col})"


def formula_cap_year_amount_structured_ref() -> str:
    """
    Return a structured reference formula for CapYearAmount on salary_book_warehouse.
    
    Returns:
        "CapYearAmount([@cap_y0],[@cap_y1],[@cap_y2],[@cap_y3],[@cap_y4],[@cap_y5])"
    """
    return "CapYearAmount([@cap_y0],[@cap_y1],[@cap_y2],[@cap_y3],[@cap_y4],[@cap_y5])"


def formula_tax_year_amount_structured_ref() -> str:
    """Return structured reference formula for TaxYearAmount on salary_book_warehouse."""
    return "TaxYearAmount([@tax_y0],[@tax_y1],[@tax_y2],[@tax_y3],[@tax_y4],[@tax_y5])"


def formula_apron_year_amount_structured_ref() -> str:
    """Return structured reference formula for ApronYearAmount on salary_book_warehouse."""
    return "ApronYearAmount([@apron_y0],[@apron_y1],[@apron_y2],[@apron_y3],[@apron_y4],[@apron_y5])"


def formula_amount_by_mode(cap_expr: str, tax_expr: str, apron_expr: str) -> str:
    """
    Return a formula that calls AmountByMode with the given expressions.
    
    Example:
        formula_amount_by_mode("cap_total", "tax_total", "apron_total")
        -> "AmountByMode(cap_total,tax_total,apron_total)"
    """
    return f"AmountByMode({cap_expr},{tax_expr},{apron_expr})"
