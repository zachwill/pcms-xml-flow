"""
UI sheet stub writers.

Each UI sheet gets a minimal stub with:
- Sheet title (row 0)
- Purpose description (row 1)
- Placeholder content indicating future functionality

These stubs establish the workbook structure before full implementation.
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.worksheet import Worksheet


def write_home_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
    build_meta: dict[str, Any],
) -> None:
    """
    Write HOME sheet stub.

    HOME is the workbook landing page with:
    - Version/refresh info
    - Data health indicator
    - Navigation links
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "NBA Cap Workbook", formats["header"])
    worksheet.write(0, 1, "", formats["header"])

    # Validation status banner
    if build_meta.get("validation_status") == "PASS":
        worksheet.write(2, 0, "Data Status:", formats["alert_ok"])
        worksheet.write(2, 1, "✓ PASS", formats["alert_ok"])
    else:
        worksheet.write(2, 0, "Data Status:", formats["alert_fail"])
        worksheet.write(2, 1, "✗ FAILED - See META sheet", formats["alert_fail"])

    # Build info
    worksheet.write(4, 0, "Base Year:")
    worksheet.write(4, 1, build_meta.get("base_year", ""))
    worksheet.write(5, 0, "As-Of Date:")
    worksheet.write(5, 1, build_meta.get("as_of_date", ""))
    worksheet.write(6, 0, "Refreshed:")
    worksheet.write(6, 1, build_meta.get("refreshed_at", ""))
    worksheet.write(7, 0, "Git SHA:")
    worksheet.write(7, 1, build_meta.get("exporter_git_sha", ""))

    # Navigation section
    worksheet.write(9, 0, "Sheets:", formats["header"])
    worksheet.write(10, 0, "• TEAM_COCKPIT")
    worksheet.write(10, 1, "Primary readouts + alerts")
    worksheet.write(11, 0, "• ROSTER_GRID")
    worksheet.write(11, 1, "Full roster ledger view")
    worksheet.write(12, 0, "• BUDGET_LEDGER")
    worksheet.write(12, 1, "Authoritative totals + deltas")
    worksheet.write(13, 0, "• TRADE_MACHINE")
    worksheet.write(13, 1, "Lane-based trade iteration")
    worksheet.write(14, 0, "• AUDIT_AND_RECONCILE")
    worksheet.write(14, 1, "Reconciliation + drilldowns")
    worksheet.write(15, 0, "• META")
    worksheet.write(15, 1, "Build metadata + validation")


def write_team_cockpit_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write TEAM_COCKPIT sheet stub.

    TEAM_COCKPIT is the primary flight display with:
    - Command bar (team/year/date/mode selection)
    - 4-7 primary readouts
    - Alert stack
    - Quick drivers panel
    """
    worksheet.set_column(0, 0, 20)
    worksheet.set_column(1, 1, 15)
    worksheet.set_column(2, 2, 15)
    worksheet.set_column(3, 3, 15)

    worksheet.write(0, 0, "TEAM COCKPIT", formats["header"])
    worksheet.write(1, 0, "Primary flight display for team cap position")

    # Command bar section (placeholder)
    worksheet.write(3, 0, "COMMAND BAR", formats["header"])
    worksheet.write(4, 0, "Team:")
    worksheet.write(4, 1, "(dropdown)")
    worksheet.write(5, 0, "Salary Year:")
    worksheet.write(5, 1, "(base_year)")
    worksheet.write(6, 0, "As-Of Date:")
    worksheet.write(6, 1, "(as_of)")
    worksheet.write(7, 0, "Mode:")
    worksheet.write(7, 1, "Cap / Tax / Apron")

    # Primary readouts section (placeholder)
    worksheet.write(9, 0, "PRIMARY READOUTS", formats["header"])
    worksheet.write(10, 0, "Cap Position:")
    worksheet.write(10, 1, "(TBD)")
    worksheet.write(11, 0, "Tax Position:")
    worksheet.write(11, 1, "(TBD)")
    worksheet.write(12, 0, "Room Under Apron 1:")
    worksheet.write(12, 1, "(TBD)")
    worksheet.write(13, 0, "Room Under Apron 2:")
    worksheet.write(13, 1, "(TBD)")
    worksheet.write(14, 0, "Roster Count:")
    worksheet.write(14, 1, "(TBD)")
    worksheet.write(15, 0, "Repeater Status:")
    worksheet.write(15, 1, "(TBD)")


def write_roster_grid_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write ROSTER_GRID sheet stub.

    ROSTER_GRID shows all rows with explicit counts vs exists truth.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "ROSTER GRID", formats["header"])
    worksheet.write(1, 0, "Full roster/ledger view with explicit bucket classification")

    worksheet.write(3, 0, "Columns (planned):")
    worksheet.write(4, 0, "• Player/Hold/Dead Money label")
    worksheet.write(5, 0, "• Bucket (ROST/FA/TERM/2WAY/GENERATED)")
    worksheet.write(6, 0, "• CountsTowardTotal? (Y/N)")
    worksheet.write(7, 0, "• CountsTowardRoster? (Y/N)")
    worksheet.write(8, 0, "• Contract/option/guarantee badges")
    worksheet.write(9, 0, "• Multi-year amounts (cap/tax/apron)")


def write_budget_ledger_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write BUDGET_LEDGER sheet stub.

    BUDGET_LEDGER is the single source of truth for totals and deltas.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "BUDGET LEDGER", formats["header"])
    worksheet.write(1, 0, "Authoritative accounting statement")

    worksheet.write(3, 0, "Sections (planned):")
    worksheet.write(4, 0, "1. Snapshot totals (by bucket)")
    worksheet.write(5, 0, "2. Plan deltas (journal actions)")
    worksheet.write(6, 0, "3. Policy-generated deltas")
    worksheet.write(7, 0, "4. Derived totals = snapshot + deltas")


def write_plan_manager_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write PLAN_MANAGER sheet stub.

    PLAN_MANAGER manages scenarios and comparisons.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "PLAN MANAGER", formats["header"])
    worksheet.write(1, 0, "Manage scenarios and comparisons")

    worksheet.write(3, 0, "Features (planned):")
    worksheet.write(4, 0, "• Plans table (ID, name, notes, created)")
    worksheet.write(5, 0, "• Baseline vs Plan selection")
    worksheet.write(6, 0, "• Compare selectors (A/B/C/D)")


def write_plan_journal_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write PLAN_JOURNAL sheet stub.

    PLAN_JOURNAL is the scenario engine with ordered actions.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "PLAN JOURNAL", formats["header"])
    worksheet.write(1, 0, "Ordered actions for scenario modeling")

    worksheet.write(3, 0, "Journal columns (planned):")
    worksheet.write(4, 0, "• Step # (order)")
    worksheet.write(5, 0, "• Enabled?")
    worksheet.write(6, 0, "• Effective date")
    worksheet.write(7, 0, "• Action type")
    worksheet.write(8, 0, "• Targets (players, picks, exceptions)")
    worksheet.write(9, 0, "• Computed deltas by year")
    worksheet.write(10, 0, "• Validation status (OK/Warning/Error)")


def write_trade_machine_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write TRADE_MACHINE sheet stub.

    TRADE_MACHINE supports lane-based rapid trade iteration.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 15)
    worksheet.set_column(2, 2, 15)
    worksheet.set_column(3, 3, 15)
    worksheet.set_column(4, 4, 15)

    worksheet.write(0, 0, "TRADE MACHINE", formats["header"])
    worksheet.write(1, 0, "Lane-based trade iteration and comparison")

    worksheet.write(3, 0, "Lanes:", formats["header"])
    worksheet.write(3, 1, "Lane A")
    worksheet.write(3, 2, "Lane B")
    worksheet.write(3, 3, "Lane C")
    worksheet.write(3, 4, "Lane D")

    worksheet.write(5, 0, "Features (planned):")
    worksheet.write(6, 0, "• Teams selection")
    worksheet.write(7, 0, "• Outgoing/incoming players")
    worksheet.write(8, 0, "• Salary matching mode")
    worksheet.write(9, 0, "• Legality check")
    worksheet.write(10, 0, "• Max incoming calculation")
    worksheet.write(11, 0, "• Apron gate flags")
    worksheet.write(12, 0, "• Publish to journal")


def write_signings_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write SIGNINGS_AND_EXCEPTIONS sheet stub.

    SIGNINGS_AND_EXCEPTIONS handles signings, minimums, exceptions.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "SIGNINGS & EXCEPTIONS", formats["header"])
    worksheet.write(1, 0, "Signings, minimums, exception usage")

    worksheet.write(3, 0, "Features (planned):")
    worksheet.write(4, 0, "• Player/slot selection")
    worksheet.write(5, 0, "• Contract structure")
    worksheet.write(6, 0, "• Signing method (cap room/exception/minimum)")
    worksheet.write(7, 0, "• Effective date")
    worksheet.write(8, 0, "• Per-year deltas output")
    worksheet.write(9, 0, "• Exception usage remaining")
    worksheet.write(10, 0, "• Hard-cap trigger flags")


def write_waive_buyout_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write WAIVE_BUYOUT_STRETCH sheet stub.

    WAIVE_BUYOUT_STRETCH handles dead money modeling.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "WAIVE / BUYOUT / STRETCH", formats["header"])
    worksheet.write(1, 0, "Guided dead money modeling")

    worksheet.write(3, 0, "Inputs (planned):")
    worksheet.write(4, 0, "• Player selection")
    worksheet.write(5, 0, "• Waive date")
    worksheet.write(6, 0, "• Give-back amount")
    worksheet.write(7, 0, "• Stretch toggle")
    worksheet.write(8, 0, "• Set-off assumptions")

    worksheet.write(10, 0, "Outputs (planned):")
    worksheet.write(11, 0, "• Cap/tax/apron distribution by year")
    worksheet.write(12, 0, "• Immediate savings vs future costs")


def write_assets_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write ASSETS sheet stub.

    ASSETS shows exception/TPE and draft pick inventory.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "ASSETS", formats["header"])
    worksheet.write(1, 0, "Exception/TPE and draft pick inventory")

    worksheet.write(3, 0, "Sections (planned):")
    worksheet.write(4, 0, "• Exceptions/TPEs (remaining, expiration, restrictions)")
    worksheet.write(5, 0, "• Draft picks (ownership grid, encumbrances)")


def write_audit_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write AUDIT_AND_RECONCILE sheet stub.

    AUDIT_AND_RECONCILE prevents "your number is wrong" fights.
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 40)

    worksheet.write(0, 0, "AUDIT & RECONCILE", formats["header"])
    worksheet.write(1, 0, "Reconciliation and explainability layer")

    worksheet.write(3, 0, "Sections (planned):")
    worksheet.write(4, 0, "• Totals reconciliation (snapshot vs counting rows)")
    worksheet.write(5, 0, "• Contributing rows drilldowns")
    worksheet.write(6, 0, "• Assumptions applied (fill rows, toggles)")
    worksheet.write(7, 0, "• Plan diff (baseline vs plan)")
    worksheet.write(8, 0, "• Journal step summary")


def write_rules_reference_stub(
    worksheet: Worksheet,
    formats: dict[str, Any],
) -> None:
    """
    Write RULES_REFERENCE sheet stub.

    RULES_REFERENCE provides inline memory aids (not a full CBA dump).
    """
    worksheet.set_column(0, 0, 25)
    worksheet.set_column(1, 1, 50)

    worksheet.write(0, 0, "RULES REFERENCE", formats["header"])
    worksheet.write(1, 0, "Quick reference for operating rules")

    worksheet.write(3, 0, "Topics (planned):")
    worksheet.write(4, 0, "• Salary matching tiers")
    worksheet.write(5, 0, "• Apron gates / hard-cap triggers")
    worksheet.write(6, 0, "• Minimum salary scales")
    worksheet.write(7, 0, "• Rookie scale")
    worksheet.write(8, 0, "• Proration helpers")


# Mapping of sheet names to their stub writers
UI_STUB_WRITERS = {
    "TEAM_COCKPIT": write_team_cockpit_stub,
    "ROSTER_GRID": write_roster_grid_stub,
    "BUDGET_LEDGER": write_budget_ledger_stub,
    "PLAN_MANAGER": write_plan_manager_stub,
    "PLAN_JOURNAL": write_plan_journal_stub,
    "TRADE_MACHINE": write_trade_machine_stub,
    "SIGNINGS_AND_EXCEPTIONS": write_signings_stub,
    "WAIVE_BUYOUT_STRETCH": write_waive_buyout_stub,
    "ASSETS": write_assets_stub,
    "AUDIT_AND_RECONCILE": write_audit_stub,
    "RULES_REFERENCE": write_rules_reference_stub,
}
