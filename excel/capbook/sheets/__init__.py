"""
Sheet writer modules for the Excel cap workbook.

Each sheet writer follows the pattern:
    write_<sheet_name>(worksheet, formats, build_meta, ...)
    
For sheets with shared command bar (most UI sheets):
    write_<sheet_name>(workbook, worksheet, formats, ...)
"""

from .audit import write_audit_and_reconcile
from .budget_ledger import write_budget_ledger
from .cockpit import (
    write_team_cockpit_with_command_bar,
    get_command_bar_cell_refs,
)
from .command_bar import (
    write_command_bar_editable,
    write_command_bar_readonly,
    define_meta_named_ranges,
    get_content_start_row,
    get_command_bar_height,
    NAMED_RANGES,
    COCKPIT_SHEET_NAME,
)
from .meta import write_meta_sheet
from .roster_grid import write_roster_grid
from .ui_stubs import (
    UI_STUB_WRITERS,
    write_home_stub,
    write_team_cockpit_stub,
    write_roster_grid_stub,
    write_budget_ledger_stub,
    write_plan_manager_stub,
    write_plan_journal_stub,
    write_trade_machine_stub,
    write_signings_stub,
    write_waive_buyout_stub,
    write_assets_stub,
    write_audit_stub,
    write_rules_reference_stub,
)

__all__ = [
    # Audit
    "write_audit_and_reconcile",
    # Budget ledger
    "write_budget_ledger",
    # Cockpit
    "write_team_cockpit_with_command_bar",
    "get_command_bar_cell_refs",
    # Command bar (shared)
    "write_command_bar_editable",
    "write_command_bar_readonly",
    "define_meta_named_ranges",
    "get_content_start_row",
    "get_command_bar_height",
    "NAMED_RANGES",
    "COCKPIT_SHEET_NAME",
    # Meta
    "write_meta_sheet",
    # Roster grid
    "write_roster_grid",
    # UI stubs
    "UI_STUB_WRITERS",
    "write_home_stub",
    "write_team_cockpit_stub",
    "write_roster_grid_stub",
    "write_budget_ledger_stub",
    "write_plan_manager_stub",
    "write_plan_journal_stub",
    "write_trade_machine_stub",
    "write_signings_stub",
    "write_waive_buyout_stub",
    "write_assets_stub",
    "write_audit_stub",
    "write_rules_reference_stub",
]
