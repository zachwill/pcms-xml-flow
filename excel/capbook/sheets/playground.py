"""
PLAYGROUND sheet - the core working surface.

Dense, reactive layout for salary cap analysis.
"""

from __future__ import annotations

from typing import Any

import xlsxwriter
from xlsxwriter.workbook import Workbook
from xlsxwriter.worksheet import Worksheet


# Input slots
TRADE_OUT_SLOTS = 6
TRADE_IN_SLOTS = 6
WAIVE_SLOTS = 3
SIGN_SLOTS = 2


def write_playground_sheet(
    workbook: Workbook,
    worksheet: Worksheet,
    formats: dict[str, Any],
    team_codes: list[str],
) -> None:
    """Write the PLAYGROUND sheet."""
    
    # -------------------------------------------------------------------------
    # Formats
    # -------------------------------------------------------------------------
    base_font = {"font_name": "Aptos Narrow", "font_size": 11}
    
    fmt_section = workbook.add_format({
        **base_font,
        "bold": True,
        "font_color": "#374151",
        "font_size": 9,
    })
    
    fmt_kpi_label = workbook.add_format({
        **base_font,
        "font_color": "#6B7280",
        "font_size": 9,
        "align": "right",
    })
    
    fmt_kpi_value = workbook.add_format({
        **base_font,
        "bold": True,
        "font_size": 13,
        "num_format": "[<0]-$#,##0,K;$#,##0,K",
        "align": "left",
    })
    
    fmt_trade_out = workbook.add_format({
        **base_font,
        "font_color": "#9CA3AF",
        "font_strikeout": True,
    })
    
    fmt_trade_in = workbook.add_format({
        **base_font,
        "font_color": "#7C3AED",
        "bold": True,
    })
    
    fmt_roster_header = workbook.add_format({
        **base_font,
        "bold": True,
        "bg_color": "#F3F4F6",
        "bottom": 1,
        "bottom_color": "#D1D5DB",
        "font_size": 10,
    })
    
    fmt_money = workbook.add_format({
        **base_font,
        "num_format": "$#,##0",
        "align": "right",
    })
    
    fmt_pct = workbook.add_format({
        **base_font,
        "num_format": "0.0%",
        "align": "right",
    })
    
    fmt_totals_label = workbook.add_format({
        **base_font,
        "bold": True,
        "top": 1,
        "top_color": "#D1D5DB",
    })
    
    fmt_totals_value = workbook.add_format({
        **base_font,
        "bold": True,
        "num_format": "$#,##0",
        "top": 1,
        "top_color": "#D1D5DB",
        "align": "right",
    })
    
    fmt_depth_pos = workbook.add_format({
        **base_font,
        "bold": True,
        "font_color": "#6B7280",
        "font_size": 9,
    })
    
    fmt_trade_math_label = workbook.add_format({
        **base_font,
        "font_color": "#6B7280",
        "font_size": 9,
    })
    
    fmt_trade_math_value = workbook.add_format({
        **base_font,
        "num_format": "$#,##0",
        "font_size": 9,
    })
    
    # -------------------------------------------------------------------------
    # Column widths and pre-formatting
    # -------------------------------------------------------------------------
    worksheet.set_column("A:A", 10)   # Labels
    worksheet.set_column("B:B", 16)   # Inputs
    worksheet.set_column("C:C", 10)   # Spacer / input salaries
    worksheet.set_column("D:D", 3)    # Rank
    worksheet.set_column("E:E", 18)   # Player
    worksheet.set_column("F:F", 13, fmt_money)   # Salary - PRE-FORMAT entire column
    worksheet.set_column("G:G", 7, fmt_pct)      # % Cap - PRE-FORMAT entire column
    worksheet.set_column("H:H", 7)    # Status
    worksheet.set_column("I:I", 2)    # Spacer
    worksheet.set_column("J:J", 3)    # Depth pos
    worksheet.set_column("K:K", 14)   # Depth player 1
    worksheet.set_column("L:L", 14)   # Depth player 2
    
    # -------------------------------------------------------------------------
    # Row 1: Team selector (KPIs moved below)
    # -------------------------------------------------------------------------
    worksheet.write("A1", "Team", fmt_section)
    worksheet.write("B1", "POR", formats["input"])
    
    if team_codes:
        worksheet.data_validation("B1", {"validate": "list", "source": team_codes})
    
    workbook.define_name("SelectedTeam", "=PLAYGROUND!$B$1")
    
    # Depth header
    worksheet.write("J1", "Depth", fmt_section)
    
    # -------------------------------------------------------------------------
    # Row 2: Roster header + Depth positions start
    # -------------------------------------------------------------------------
    worksheet.write("D2", "#", fmt_roster_header)
    worksheet.write("E2", "Player", fmt_roster_header)
    worksheet.write("F2", "Salary", fmt_roster_header)
    worksheet.write("G2", "%", fmt_roster_header)
    worksheet.write("H2", "Status", fmt_roster_header)
    
    worksheet.write("J2", "PG", fmt_depth_pos)
    worksheet.write("J3", "SG", fmt_depth_pos)
    worksheet.write("J4", "SF", fmt_depth_pos)
    worksheet.write("J5", "PF", fmt_depth_pos)
    worksheet.write("J6", "C", fmt_depth_pos)
    
    # -------------------------------------------------------------------------
    # Left column: Playground inputs (compact)
    # -------------------------------------------------------------------------
    worksheet.write("A2", "TRADE OUT", fmt_section)
    for i in range(TRADE_OUT_SLOTS):
        worksheet.write(2 + i, 1, "", formats["input"])  # B3:B8
    
    workbook.define_name("TradeOutNames", "=PLAYGROUND!$B$3:$B$8")
    
    worksheet.write("A9", "TRADE IN", fmt_section)
    for i in range(TRADE_IN_SLOTS):
        worksheet.write(9 + i, 1, "", formats["input"])  # B10:B15
    
    workbook.define_name("TradeInNames", "=PLAYGROUND!$B$10:$B$15")
    
    worksheet.write("A16", "WAIVE", fmt_section)
    for i in range(WAIVE_SLOTS):
        worksheet.write(16 + i, 1, "", formats["input"])  # B17:B19
    
    workbook.define_name("WaivedNames", "=PLAYGROUND!$B$17:$B$19")
    
    worksheet.write("A20", "SIGN", fmt_section)
    for i in range(SIGN_SLOTS):
        worksheet.write(20 + i, 1, "", formats["input"])  # B21:B22 (name)
        worksheet.write(20 + i, 2, "", formats["input_money"])  # C21:C22 (salary)
    
    workbook.define_name("SignNames", "=PLAYGROUND!$B$21:$B$22")
    workbook.define_name("SignSalaries", "=PLAYGROUND!$C$21:$C$22")
    
    # Trade math (compact, below sign)
    worksheet.write("A24", "Out:", fmt_trade_math_label)
    worksheet.write_formula(
        "B24",
        '=SUMPRODUCT((tbl_salary_book_yearly[team_code]=SelectedTeam)*(tbl_salary_book_yearly[salary_year]=MetaBaseYear)*(COUNTIF(TradeOutNames,tbl_salary_book_yearly[player_name])>0)*tbl_salary_book_yearly[cap_amount])',
        fmt_trade_math_value
    )
    
    worksheet.write("A25", "In:", fmt_trade_math_label)
    worksheet.write_formula(
        "B25",
        '=LET(_xlpm.y,MetaBaseYear,_xlpm.names,FILTER(tbl_salary_book_yearly[player_name],tbl_salary_book_yearly[salary_year]=_xlpm.y),_xlpm.sals,FILTER(tbl_salary_book_yearly[cap_amount],tbl_salary_book_yearly[salary_year]=_xlpm.y),SUMPRODUCT((TradeInNames<>"")*IFERROR(XLOOKUP(TradeInNames,_xlpm.names,_xlpm.sals),0)))',
        fmt_trade_math_value
    )
    
    worksheet.write("A26", "Match:", fmt_trade_math_label)
    worksheet.write_formula("B26", '=IF(B24=0,"-",TEXT(B25/B24,"0%"))')
    
    # -------------------------------------------------------------------------
    # Roster data (row 3+)
    # -------------------------------------------------------------------------
    
    # Player names: base roster + trade-ins, sorted by salary
    roster_formula = '''=LET(
_xlpm.team,SelectedTeam,
_xlpm.y,MetaBaseYear,
_xlpm.allNames,FILTER(tbl_salary_book_yearly[player_name],tbl_salary_book_yearly[salary_year]=_xlpm.y),
_xlpm.allTeams,FILTER(tbl_salary_book_yearly[team_code],tbl_salary_book_yearly[salary_year]=_xlpm.y),
_xlpm.allSalaries,FILTER(tbl_salary_book_yearly[cap_amount],tbl_salary_book_yearly[salary_year]=_xlpm.y),
_xlpm.baseNames,FILTER(_xlpm.allNames,_xlpm.allTeams=_xlpm.team),
_xlpm.baseSalaries,FILTER(_xlpm.allSalaries,_xlpm.allTeams=_xlpm.team),
_xlpm.inNames,FILTER(TradeInNames,TradeInNames<>"",NA()),
_xlpm.hasTradeIns,NOT(ISNA(_xlpm.inNames)),
_xlpm.inSalaries,IF(_xlpm.hasTradeIns,MAP(_xlpm.inNames,LAMBDA(_xlpm.n,IFERROR(XLOOKUP(_xlpm.n,_xlpm.allNames,_xlpm.allSalaries),0))),NA()),
_xlpm.combinedNames,IF(_xlpm.hasTradeIns,VSTACK(_xlpm.baseNames,_xlpm.inNames),_xlpm.baseNames),
_xlpm.combinedSalaries,IF(_xlpm.hasTradeIns,VSTACK(_xlpm.baseSalaries,_xlpm.inSalaries),_xlpm.baseSalaries),
SORTBY(_xlpm.combinedNames,_xlpm.combinedSalaries,-1)
)'''
    
    worksheet.write_dynamic_array_formula("E3", roster_formula.replace("\n", ""))
    
    # Salary column
    salary_formula = '=LET(_xlpm.y,MetaBaseYear,_xlpm.names,FILTER(tbl_salary_book_yearly[player_name],tbl_salary_book_yearly[salary_year]=_xlpm.y),_xlpm.sals,FILTER(tbl_salary_book_yearly[cap_amount],tbl_salary_book_yearly[salary_year]=_xlpm.y),MAP(ANCHORARRAY(E3),LAMBDA(_xlpm.p,IFERROR(XLOOKUP(_xlpm.p,_xlpm.names,_xlpm.sals),0))))'
    worksheet.write_dynamic_array_formula("F3", salary_formula)
    
    # Rank column
    worksheet.write_dynamic_array_formula("D3", "=SEQUENCE(ROWS(ANCHORARRAY(E3)))")
    
    # % of cap
    pct_formula = '=ANCHORARRAY(F3)/XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])'
    worksheet.write_dynamic_array_formula("G3", pct_formula)
    
    # Status column - use _xlpm.p parameter (not cell ref) inside LAMBDA
    status_formula = '=MAP(ANCHORARRAY(E3),LAMBDA(_xlpm.p,IF(COUNTIF(TradeOutNames,_xlpm.p)>0,"OUT",IF(COUNTIF(WaivedNames,_xlpm.p)>0,"WAIVED",IF(COUNTIF(TradeInNames,_xlpm.p)>0,"IN","")))))'
    worksheet.write_dynamic_array_formula("H3", status_formula)
    
    # -------------------------------------------------------------------------
    # Conditional formatting for roster (E3:H25 range)
    # -------------------------------------------------------------------------
    
    # Trade-out: gray strikethrough
    worksheet.conditional_format("E3:G25", {
        "type": "formula",
        "criteria": '=COUNTIF(TradeOutNames,$E3)>0',
        "format": fmt_trade_out,
    })
    
    # Waived: gray strikethrough
    worksheet.conditional_format("E3:G25", {
        "type": "formula",
        "criteria": '=COUNTIF(WaivedNames,$E3)>0',
        "format": fmt_trade_out,
    })
    
    # Trade-in: purple bold
    worksheet.conditional_format("E3:G25", {
        "type": "formula",
        "criteria": '=COUNTIF(TradeInNames,$E3)>0',
        "format": fmt_trade_in,
    })
    
    # -------------------------------------------------------------------------
    # Totals section (rows 20-24)
    # -------------------------------------------------------------------------
    TOTALS_START = 20
    
    # Team Salary - authoritative sum from warehouse
    worksheet.write(TOTALS_START, 4, "Team Salary", fmt_totals_label)  # E21
    team_salary_formula = '=XLOOKUP(SelectedTeam,tbl_team_salary_warehouse[team_code],tbl_team_salary_warehouse[cap_total])'
    worksheet.write_formula(TOTALS_START, 5, team_salary_formula, fmt_totals_value)  # F21
    workbook.define_name("TeamSalary", "=PLAYGROUND!$F$21")
    
    # Roster fill count - how many slots to fill to reach 14
    # Uses roster_row_count from warehouse + any trade-ins/signings - trade-outs/waives
    roster_fill_formula = '''=LET(
_xlpm.baseCount,XLOOKUP(SelectedTeam&MetaBaseYear,tbl_team_salary_warehouse[team_code]&tbl_team_salary_warehouse[salary_year],tbl_team_salary_warehouse[roster_row_count]),
_xlpm.tradeOuts,SUMPRODUCT((TradeOutNames<>"")*1),
_xlpm.tradeIns,SUMPRODUCT((TradeInNames<>"")*1),
_xlpm.waived,SUMPRODUCT((WaivedNames<>"")*1),
_xlpm.signed,SUMPRODUCT((SignNames<>"")*1),
_xlpm.modifiedCount,_xlpm.baseCount-_xlpm.tradeOuts-_xlpm.waived+_xlpm.tradeIns+_xlpm.signed,
MAX(0,14-_xlpm.modifiedCount)
)'''
    workbook.define_name("RosterFillCount", "=" + roster_fill_formula.replace("\n", ""))
    
    # Rookie minimum (years_of_service = 0) for fill calculation
    rookie_min_formula = '=XLOOKUP(MetaBaseYear&0,tbl_minimum_scale[salary_year]&tbl_minimum_scale[years_of_service],tbl_minimum_scale[minimum_salary_amount])'
    workbook.define_name("RookieMinSalary", "=" + rookie_min_formula)
    
    # Roster fill amount = fills needed * rookie min
    workbook.define_name("RosterFillAmount", "=RosterFillCount*RookieMinSalary")
    
    # Team Salary (fill to 14) - Team Salary + roster fills
    fmt_totals_label_indent = workbook.add_format({
        **base_font,
        "bold": False,
        "font_color": "#6B7280",
        "indent": 1,
    })
    worksheet.write(TOTALS_START + 1, 4, "(fill to 14)", fmt_totals_label_indent)  # E22
    fill_salary_formula = '=TeamSalary+RosterFillAmount'
    worksheet.write_formula(TOTALS_START + 1, 5, fill_salary_formula, fmt_totals_value)  # F22
    workbook.define_name("TeamSalaryFilled", "=PLAYGROUND!$F$22")
    
    # Show fill count inline (e.g., "+2 fills")
    fmt_fill_note = workbook.add_format({
        **base_font,
        "font_color": "#9CA3AF",
        "font_size": 9,
    })
    fill_note_formula = '=IF(RosterFillCount>0,"+"&RosterFillCount&" × "&TEXT(RookieMinSalary,"$#,##0"),"")'
    worksheet.write_formula(TOTALS_START + 1, 6, fill_note_formula, fmt_fill_note)  # G22
    
    # Modified = filled salary - trade out - waived + trade in + signings
    worksheet.write(TOTALS_START + 2, 4, "Modified", fmt_totals_label)  # E23
    # Modified uses filled salary as base, then applies trade adjustments
    # Trade out/in/waived salaries are already calculated via the trade math formulas at B24/B25
    modified_formula = '''=LET(
_xlpm.base,TeamSalaryFilled,
_xlpm.out,B24,
_xlpm.in,B25,
_xlpm.waived,SUMPRODUCT((tbl_salary_book_yearly[team_code]=SelectedTeam)*(tbl_salary_book_yearly[salary_year]=MetaBaseYear)*(COUNTIF(WaivedNames,tbl_salary_book_yearly[player_name])>0)*tbl_salary_book_yearly[cap_amount]),
_xlpm.signed,SUM(SignSalaries),
_xlpm.base-_xlpm.out-_xlpm.waived+_xlpm.in+_xlpm.signed
)'''
    worksheet.write_formula(TOTALS_START + 2, 5, modified_formula.replace("\n", ""), fmt_totals_value)  # F23
    workbook.define_name("ModifiedSalary", "=PLAYGROUND!$F$23")
    
    # -------------------------------------------------------------------------
    # KPIs - in left panel below trade math (rows 28-30)
    # Uses ModifiedSalary (F22) for scenario-adjusted comparisons
    # -------------------------------------------------------------------------
    worksheet.write("A28", "Cap:", fmt_kpi_label)
    worksheet.write_formula(
        "B28",
        '=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[salary_cap_amount])-ModifiedSalary',
        fmt_kpi_value
    )
    
    worksheet.write("A29", "Tax:", fmt_kpi_label)
    worksheet.write_formula(
        "B29",
        '=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_level_amount])-ModifiedSalary',
        fmt_kpi_value
    )
    
    worksheet.write("A30", "Apron:", fmt_kpi_label)
    worksheet.write_formula(
        "B30",
        '=XLOOKUP(MetaBaseYear,tbl_system_values[salary_year],tbl_system_values[tax_apron_amount])-ModifiedSalary',
        fmt_kpi_value
    )
