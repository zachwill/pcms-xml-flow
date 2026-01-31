"""
Sheet writer modules for the Excel cap workbook.

Each sheet writer follows the pattern:
    write_<sheet_name>(worksheet, formats, build_meta, ...)
"""

from .meta import write_meta_sheet
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
    "write_meta_sheet",
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
