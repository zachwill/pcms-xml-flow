"""excel.capbook.build

Workbook build orchestration.

The main entrypoint is build_capbook(), which:
1) (Optionally) runs SQL assertions (validations)
2) Extracts datasets from Postgres
3) Generates a self-contained workbook (UI sheets + DATA_* tables)
4) Writes META so every snapshot is reproducible

Supervisor rule (see reference/blueprints/*):
- On validation or export failure, we still emit a workbook artifact and mark it
  loudly as FAILED in META + HOME.
"""

from __future__ import annotations

import subprocess
import traceback
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Callable

import xlsxwriter

from .db import run_sql_assertions
from .extract import (
    DatasetExtractError,
    extract_system_values,
    extract_tax_rates,
    extract_rookie_scale,
    extract_minimum_scale,
    extract_team_salary_warehouse,
    extract_salary_book_warehouse,
    extract_salary_book_yearly,
    extract_cap_holds_warehouse,
    extract_dead_money_warehouse,
    extract_exceptions_warehouse,
    extract_draft_picks_warehouse,
)
from .reconcile import reconcile_team_salary_warehouse, reconcile_drilldowns_vs_totals
from .xlsx import create_standard_formats, write_table
from .named_formulas import define_named_formulas
from .sheets import (
    UI_STUB_WRITERS,
    write_audit_and_reconcile,
    write_budget_ledger,
    write_home_sheet,
    write_meta_sheet,
    write_team_cockpit_with_command_bar,
    write_roster_grid,
    write_plan_manager,
    write_plan_journal,
    define_meta_named_ranges,
    write_trade_machine,
    write_signings_and_exceptions,
    write_waive_buyout_stretch,
    write_assets,
    write_rules_reference,
)


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
    "DATA_rookie_scale",
    "DATA_minimum_scale",
    "DATA_team_salary_warehouse",
    "DATA_salary_book_warehouse",
    "DATA_salary_book_yearly",
    "DATA_cap_holds_warehouse",
    "DATA_dead_money_warehouse",
    "DATA_exceptions_warehouse",
    "DATA_draft_picks_warehouse",
]

# See: reference/blueprints/excel-workbook-data-contract.md
DATA_CONTRACT_VERSION = "v2-2026-01-31"


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
    except Exception:  # noqa: BLE001
        pass
    return "unknown"


def _truncate(s: str, limit: int = 2000) -> str:
    s = s or ""
    return s if len(s) <= limit else s[:limit] + "…"


def _mark_failed(build_meta: dict[str, Any], message: str) -> None:
    build_meta["validation_status"] = "FAILED"
    build_meta.setdefault("validation_errors", []).append(_truncate(message))


def build_capbook(
    out_path: Path,
    base_year: int,
    as_of: date,
    league: str = "NBA",
    *,
    skip_assertions: bool = False,
) -> dict[str, Any]:
    """Build the Excel cap workbook.

    Important behavior:
    - If any validation/extract/write step fails, we *still emit* a workbook and
      mark META.validation_status = FAILED.
    """

    build_meta: dict[str, Any] = {
        "refreshed_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "base_year": base_year,
        "as_of_date": as_of.isoformat(),
        "league_lk": league,
        "data_contract_version": DATA_CONTRACT_VERSION,
        "exporter_git_sha": get_git_sha(),
        "validation_status": "PASS",
        "validation_errors": [],
    }

    # We create the workbook early so we can always emit an artifact.
    # remove_timezone avoids XlsxWriter errors when DB timestamps include tzinfo.
    workbook = xlsxwriter.Workbook(str(out_path), {"remove_timezone": True})

    try:
        formats = create_standard_formats(workbook)

        # Create UI sheets
        ui_worksheets: dict[str, Any] = {}
        for name in UI_SHEETS:
            ui_worksheets[name] = workbook.add_worksheet(name)

        # Create DATA sheets (hidden + protected)
        data_worksheets: dict[str, Any] = {}
        for name in DATA_SHEETS:
            ws = workbook.add_worksheet(name)
            ws.hide()
            ws.protect()
            data_worksheets[name] = ws

        # Step 1: SQL assertions
        if not skip_assertions:
            try:
                passed, output = run_sql_assertions()
                if not passed:
                    _mark_failed(build_meta, f"SQL assertions failed:\n{output}")
            except Exception as e:  # noqa: BLE001
                _mark_failed(build_meta, f"SQL assertions crashed: {e}\n{traceback.format_exc()}")

        # Step 2: Extract datasets (continue-on-error; create empty tables on failure)
        DatasetExtractor = Callable[[], tuple[list[str], list[dict[str, Any]]]]

        dataset_specs: list[dict[str, Any]] = [
            {
                "key": "system_values",
                "sheet": "DATA_system_values",
                "table": "tbl_system_values",
                "extract": lambda: extract_system_values(base_year, league),
            },
            {
                "key": "tax_rates",
                "sheet": "DATA_tax_rates",
                "table": "tbl_tax_rates",
                "extract": lambda: extract_tax_rates(base_year, league),
            },
            {
                "key": "rookie_scale",
                "sheet": "DATA_rookie_scale",
                "table": "tbl_rookie_scale",
                "extract": lambda: extract_rookie_scale(base_year, league),
            },
            {
                "key": "minimum_scale",
                "sheet": "DATA_minimum_scale",
                "table": "tbl_minimum_scale",
                "extract": lambda: extract_minimum_scale(base_year, league),
            },
            {
                "key": "team_salary_warehouse",
                "sheet": "DATA_team_salary_warehouse",
                "table": "tbl_team_salary_warehouse",
                "extract": lambda: extract_team_salary_warehouse(base_year),
            },
            {
                "key": "salary_book_warehouse",
                "sheet": "DATA_salary_book_warehouse",
                "table": "tbl_salary_book_warehouse",
                "extract": lambda: extract_salary_book_warehouse(base_year, league),
            },
            {
                "key": "salary_book_yearly",
                "sheet": "DATA_salary_book_yearly",
                "table": "tbl_salary_book_yearly",
                "extract": lambda: extract_salary_book_yearly(base_year, league),
            },
            {
                "key": "cap_holds_warehouse",
                "sheet": "DATA_cap_holds_warehouse",
                "table": "tbl_cap_holds_warehouse",
                "extract": lambda: extract_cap_holds_warehouse(base_year),
            },
            {
                "key": "dead_money_warehouse",
                "sheet": "DATA_dead_money_warehouse",
                "table": "tbl_dead_money_warehouse",
                "extract": lambda: extract_dead_money_warehouse(base_year),
            },
            {
                "key": "exceptions_warehouse",
                "sheet": "DATA_exceptions_warehouse",
                "table": "tbl_exceptions_warehouse",
                "extract": lambda: extract_exceptions_warehouse(base_year),
            },
            {
                "key": "draft_picks_warehouse",
                "sheet": "DATA_draft_picks_warehouse",
                "table": "tbl_draft_picks_warehouse",
                "extract": lambda: extract_draft_picks_warehouse(base_year),
            },
        ]

        extracted: dict[str, tuple[list[str], list[dict[str, Any]]]] = {}

        for spec in dataset_specs:
            key = spec["key"]
            extract_fn: DatasetExtractor = spec["extract"]
            try:
                cols, rows = extract_fn()
                extracted[key] = (cols, rows)
            except DatasetExtractError as e:
                _mark_failed(build_meta, f"Dataset extract failed: {e.dataset_name}: {e.original}")
                extracted[key] = (e.columns, [])
            except Exception as e:  # noqa: BLE001
                _mark_failed(build_meta, f"Dataset extract crashed: {key}: {e}\n{traceback.format_exc()}")
                extracted[key] = ([], [])

        # Step 2.5: Lightweight reconciliation (v1)
        # Verify that totals match bucket sums in team_salary_warehouse
        team_salary_data = extracted.get("team_salary_warehouse", ([], []))
        if team_salary_data[1]:  # We have rows to reconcile
            try:
                reconcile_summary = reconcile_team_salary_warehouse(team_salary_data[1])
                build_meta.update(reconcile_summary.as_dict())
                if not reconcile_summary.passed:
                    _mark_failed(
                        build_meta,
                        f"Reconciliation failed: {reconcile_summary.failed_checks}/{reconcile_summary.total_checks} checks failed",
                    )
            except Exception as e:  # noqa: BLE001
                _mark_failed(build_meta, f"Reconciliation crashed: {e}\n{traceback.format_exc()}")
        else:
            # No data to reconcile - mark as not run
            build_meta["reconcile_passed"] = None

        # Step 2.6: Reconciliation v2 (drilldowns vs team totals)
        # Verify that warehouse totals match the sum of drilldown rows:
        #   salary_book_yearly + cap_holds_warehouse + dead_money_warehouse
        salary_book_data = extracted.get("salary_book_yearly", ([], []))
        cap_holds_data = extracted.get("cap_holds_warehouse", ([], []))
        dead_money_data = extracted.get("dead_money_warehouse", ([], []))

        if team_salary_data[1]:  # We have warehouse totals to check against
            try:
                reconcile_v2_summary = reconcile_drilldowns_vs_totals(
                    team_salary_rows=team_salary_data[1],
                    salary_book_rows=salary_book_data[1],
                    cap_holds_rows=cap_holds_data[1],
                    dead_money_rows=dead_money_data[1],
                )
                # Store v2 results with distinct keys
                v2_dict = reconcile_v2_summary.as_dict()
                build_meta["reconcile_v2_passed"] = v2_dict["reconcile_passed"]
                build_meta["reconcile_v2_total_checks"] = v2_dict["reconcile_total_checks"]
                build_meta["reconcile_v2_passed_checks"] = v2_dict["reconcile_passed_checks"]
                build_meta["reconcile_v2_failed_checks"] = v2_dict["reconcile_failed_checks"]
                build_meta["reconcile_v2_failures"] = v2_dict["reconcile_failures"]
                build_meta["reconcile_v2_sample_checks"] = v2_dict["reconcile_sample_checks"]

                if not reconcile_v2_summary.passed:
                    _mark_failed(
                        build_meta,
                        f"Reconciliation v2 (drilldowns) failed: {reconcile_v2_summary.failed_checks}/{reconcile_v2_summary.total_checks} checks failed",
                    )
            except Exception as e:  # noqa: BLE001
                _mark_failed(build_meta, f"Reconciliation v2 crashed: {e}\n{traceback.format_exc()}")
        else:
            # No data to reconcile
            build_meta["reconcile_v2_passed"] = None

        # Step 3: Write DATA tables (continue-on-error; ensure stable table names when possible)
        for spec in dataset_specs:
            key = spec["key"]
            sheet_name = spec["sheet"]
            table_name = spec["table"]

            cols, rows = extracted.get(key, ([], []))
            if not cols:
                _mark_failed(build_meta, f"Missing schema for dataset {key}; cannot create table {table_name}.")
                continue

            try:
                write_table(
                    data_worksheets[sheet_name],
                    table_name,
                    0,
                    0,
                    cols,
                    rows,
                )
            except Exception as e:  # noqa: BLE001
                _mark_failed(
                    build_meta,
                    f"Failed writing table {table_name} on sheet {sheet_name}: {e}\n{traceback.format_exc()}",
                )

        # Step 4: Write UI sheets
        # TEAM_COCKPIT gets special treatment - it has command bar inputs with defined names
        try:
            # Extract distinct team_codes from team_salary_warehouse for validation dropdown (future task)
            team_codes = sorted(
                set(row.get("team_code") for row in extracted.get("team_salary_warehouse", ([], []))[1] if row.get("team_code"))
            )
            write_team_cockpit_with_command_bar(
                workbook,
                ui_worksheets["TEAM_COCKPIT"],
                formats,
                build_meta,
                team_codes=team_codes,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"TEAM_COCKPIT writer crashed: {e}\n{traceback.format_exc()}")

        # AUDIT_AND_RECONCILE gets special treatment - it has formula-driven reconciliation
        try:
            write_audit_and_reconcile(
                workbook,
                ui_worksheets["AUDIT_AND_RECONCILE"],
                formats,
                build_meta,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"AUDIT_AND_RECONCILE writer crashed: {e}\n{traceback.format_exc()}")

        # ROSTER_GRID gets special treatment - full roster ledger with reconciliation
        try:
            write_roster_grid(
                workbook,
                ui_worksheets["ROSTER_GRID"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"ROSTER_GRID writer crashed: {e}\n{traceback.format_exc()}")

        # BUDGET_LEDGER gets special treatment - authoritative totals + plan deltas
        try:
            write_budget_ledger(
                workbook,
                ui_worksheets["BUDGET_LEDGER"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"BUDGET_LEDGER writer crashed: {e}\n{traceback.format_exc()}")

        # PLAN_MANAGER - plan definitions table that feeds ActivePlan dropdown
        try:
            write_plan_manager(
                workbook,
                ui_worksheets["PLAN_MANAGER"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"PLAN_MANAGER writer crashed: {e}\n{traceback.format_exc()}")

        # PLAN_JOURNAL - ordered action journal for scenario modeling
        try:
            write_plan_journal(
                workbook,
                ui_worksheets["PLAN_JOURNAL"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"PLAN_JOURNAL writer crashed: {e}\n{traceback.format_exc()}")

        # TRADE_MACHINE - lane-based trade iteration (v1 layout)
        try:
            write_trade_machine(
                workbook,
                ui_worksheets["TRADE_MACHINE"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"TRADE_MACHINE writer crashed: {e}\n{traceback.format_exc()}")

        # SIGNINGS_AND_EXCEPTIONS - signing inputs with exception tracking (v1 layout)
        try:
            write_signings_and_exceptions(
                workbook,
                ui_worksheets["SIGNINGS_AND_EXCEPTIONS"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"SIGNINGS_AND_EXCEPTIONS writer crashed: {e}\n{traceback.format_exc()}")

        # WAIVE_BUYOUT_STRETCH - dead money modeling inputs (v1 layout)
        try:
            write_waive_buyout_stretch(
                workbook,
                ui_worksheets["WAIVE_BUYOUT_STRETCH"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"WAIVE_BUYOUT_STRETCH writer crashed: {e}\n{traceback.format_exc()}")

        # ASSETS - exception/TPE + draft pick inventory (v1 layout)
        try:
            write_assets(
                workbook,
                ui_worksheets["ASSETS"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"ASSETS writer crashed: {e}\n{traceback.format_exc()}")

        # RULES_REFERENCE - quick reference tables for CBA rules
        try:
            write_rules_reference(
                workbook,
                ui_worksheets["RULES_REFERENCE"],
                formats,
            )
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"RULES_REFERENCE writer crashed: {e}\n{traceback.format_exc()}")

        # Write remaining UI sheet stubs (skip sheets we've already handled)
        # NOTE: UI stub writers now require (workbook, worksheet, formats) signature
        # because they include the shared command bar.
        for sheet_name, writer_fn in UI_STUB_WRITERS.items():
            if sheet_name in ("TEAM_COCKPIT", "AUDIT_AND_RECONCILE", "ROSTER_GRID", "BUDGET_LEDGER", "PLAN_MANAGER", "PLAN_JOURNAL", "TRADE_MACHINE", "SIGNINGS_AND_EXCEPTIONS", "WAIVE_BUYOUT_STRETCH", "ASSETS", "RULES_REFERENCE"):
                continue  # Already handled above
            if sheet_name in ui_worksheets:
                try:
                    writer_fn(workbook, ui_worksheets[sheet_name], formats)
                except Exception as e:  # noqa: BLE001
                    _mark_failed(build_meta, f"UI stub writer crashed for {sheet_name}: {e}")

        # Define META named ranges (for formulas that reference build metadata)
        try:
            define_meta_named_ranges(workbook, "META")
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"Failed to define META named ranges: {e}")

        # Define named formulas (LAMBDA helpers for repeated logic)
        # Must be defined after META named ranges since they reference MetaBaseYear
        try:
            defined_formulas = define_named_formulas(workbook)
            build_meta["named_formulas_count"] = len(defined_formulas)
        except Exception as e:  # noqa: BLE001
            _mark_failed(build_meta, f"Failed to define named formulas: {e}")

        # META + HOME (write last so they reflect failures above)
        write_meta_sheet(ui_worksheets["META"], formats, build_meta)
        write_home_sheet(workbook, ui_worksheets["HOME"], formats, build_meta)

    except Exception as e:  # noqa: BLE001
        # Last-resort: ensure we mark failed. We may not be able to fully render
        # the UI, but we still want the workbook to close cleanly.
        _mark_failed(build_meta, f"Unhandled exporter crash: {e}\n{traceback.format_exc()}")
        try:
            # If sheets exist, attempt to write META/HOME.
            ws_meta = workbook.get_worksheet_by_name("META")
            ws_home = workbook.get_worksheet_by_name("HOME")
            formats = create_standard_formats(workbook)
            if ws_meta is not None:
                write_meta_sheet(ws_meta, formats, build_meta)
            if ws_home is not None:
                write_home_sheet(workbook, ws_home, formats, build_meta)
        except Exception:
            pass

    finally:
        workbook.close()

    return build_meta
