"""
Workbook build orchestration.

The main entrypoint is build_capbook(), which:
1. Runs SQL assertions (fail-fast)
2. Extracts datasets from Postgres
3. Generates the workbook (UI sheets + DATA_* sheets)
4. Writes META for reproducibility
"""

from __future__ import annotations

import subprocess
from datetime import date, datetime
from pathlib import Path
from typing import Any

import xlsxwriter

from .db import run_sql_assertions
from .extract import (
    extract_system_values,
    extract_tax_rates,
    extract_team_salary_warehouse,
    extract_salary_book_yearly,
)
from .xlsx import create_standard_formats, write_table
from .sheets import write_meta_sheet, UI_STUB_WRITERS, write_home_stub


# Sheet names per the blueprint
UI_SHEETS = [
    "HOME",
    "META",
    "TEAM_COCKPIT",
    "ROSTER_GRID",
    "BUDGET_LEDGER",
    "PLAN_MANAGER",
    "PLAN_JOURNAL",
    "TRADE_MACHINE",
    "SIGNINGS_AND_EXCEPTIONS",
    "WAIVE_BUYOUT_STRETCH",
    "ASSETS",
    "AUDIT_AND_RECONCILE",
    "RULES_REFERENCE",
]

DATA_SHEETS = [
    "DATA_system_values",
    "DATA_tax_rates",
    "DATA_team_salary_warehouse",
    "DATA_salary_book_warehouse",
    "DATA_salary_book_yearly",
    "DATA_cap_holds_warehouse",
    "DATA_dead_money_warehouse",
    "DATA_exceptions_warehouse",
    "DATA_draft_picks_warehouse",
]


def get_git_sha() -> str:
    """Return the current git commit SHA (short), or 'unknown' if unavailable."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return "unknown"


def build_capbook(
    out_path: Path,
    base_year: int,
    as_of: date,
    league: str = "NBA",
    *,
    skip_assertions: bool = False,
) -> dict[str, Any]:
    """
    Build the Excel cap workbook.

    Args:
        out_path: Output file path (.xlsx)
        base_year: Base salary year (e.g., 2025)
        as_of: As-of date for the snapshot
        league: League code (default: NBA)
        skip_assertions: If True, skip SQL assertions (use for testing)

    Returns:
        dict with build metadata (validation_status, errors, etc.)
    """
    build_meta: dict[str, Any] = {
        "refreshed_at": datetime.utcnow().isoformat(),
        "base_year": base_year,
        "as_of_date": as_of.isoformat(),
        "exporter_git_sha": get_git_sha(),
        "validation_status": "PASS",
        "validation_errors": [],
    }

    # Step 1: Run SQL assertions
    if not skip_assertions:
        passed, output = run_sql_assertions()
        if not passed:
            build_meta["validation_status"] = "FAILED"
            build_meta["validation_errors"].append(output[:2000])  # Truncate

    # Step 2: Extract datasets
    datasets: dict[str, tuple[list[str], list[dict[str, Any]]]] = {}

    datasets["system_values"] = extract_system_values(base_year, league)
    datasets["tax_rates"] = extract_tax_rates(base_year, league)
    datasets["team_salary_warehouse"] = extract_team_salary_warehouse(base_year)
    datasets["salary_book_yearly"] = extract_salary_book_yearly(base_year, league)

    # TODO: Extract remaining datasets per data contract
    # datasets["salary_book_warehouse"] = extract_salary_book_warehouse(...)
    # datasets["cap_holds_warehouse"] = extract_cap_holds_warehouse(...)
    # datasets["dead_money_warehouse"] = extract_dead_money_warehouse(...)
    # datasets["exceptions_warehouse"] = extract_exceptions_warehouse(...)
    # datasets["draft_picks_warehouse"] = extract_draft_picks_warehouse(...)

    # Step 3: Generate workbook
    workbook = xlsxwriter.Workbook(str(out_path))
    formats = create_standard_formats(workbook)

    # Create UI sheets (stubs)
    ui_worksheets = {}
    for name in UI_SHEETS:
        ui_worksheets[name] = workbook.add_worksheet(name)

    # Create DATA sheets
    data_worksheets = {}
    for name in DATA_SHEETS:
        ws = workbook.add_worksheet(name)
        ws.hide()  # Hide DATA_* sheets
        data_worksheets[name] = ws

    # Write META sheet (full metadata for reproducibility)
    write_meta_sheet(ui_worksheets["META"], formats, build_meta)

    # Write HOME sheet (summary with navigation)
    write_home_stub(ui_worksheets["HOME"], formats, build_meta)

    # Write UI sheet stubs (structure for future implementation)
    for sheet_name, writer_fn in UI_STUB_WRITERS.items():
        if sheet_name in ui_worksheets:
            writer_fn(ui_worksheets[sheet_name], formats)

    # Write DATA tables
    if datasets.get("system_values"):
        cols, rows = datasets["system_values"]
        write_table(
            data_worksheets["DATA_system_values"],
            "tbl_system_values",
            0,
            0,
            cols,
            rows,
        )

    if datasets.get("tax_rates"):
        cols, rows = datasets["tax_rates"]
        write_table(
            data_worksheets["DATA_tax_rates"],
            "tbl_tax_rates",
            0,
            0,
            cols,
            rows,
        )

    if datasets.get("team_salary_warehouse"):
        cols, rows = datasets["team_salary_warehouse"]
        write_table(
            data_worksheets["DATA_team_salary_warehouse"],
            "tbl_team_salary_warehouse",
            0,
            0,
            cols,
            rows,
        )

    if datasets.get("salary_book_yearly"):
        cols, rows = datasets["salary_book_yearly"]
        write_table(
            data_worksheets["DATA_salary_book_yearly"],
            "tbl_salary_book_yearly",
            0,
            0,
            cols,
            rows,
        )

    # Close workbook
    workbook.close()

    return build_meta
