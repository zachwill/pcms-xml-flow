"""excel.capbook.build

Workbook build orchestration.

The main entrypoint is build_capbook(), which:
1) (Optionally) runs SQL assertions (validations)
2) Extracts datasets from Postgres
3) Generates a self-contained workbook with DATA_* tables
4) Writes UI sheets (META, PLAYGROUND)
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
from .xlsx import create_standard_formats, write_table, set_workbook_default_font
from .sheets import write_meta_sheet, write_playground_sheet


# UI sheets
UI_SHEETS = [
    "PLAYGROUND",
    "META",
    "CALC",  # hidden helper sheet for named-formula cells (avoids future funcs in defined names)
]

# DATA sheets (hidden, contain authoritative data)
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

DATA_CONTRACT_VERSION = "v5-2026-02-03"


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


def _truncate(s: str, limit: int = 2000) -> str:
    s = s or ""
    return s if len(s) <= limit else s[:limit] + "…"


def _mark_failed(build_meta: dict[str, Any], message: str) -> None:
    build_meta["validation_status"] = "FAILED"
    build_meta.setdefault("validation_errors", []).append(_truncate(message))


def build_capbook(
    out_path: Path,
    base_year: int = 2025,
    as_of: date | None = None,
    league: str = "NBA",
    *,
    skip_assertions: bool = False,
) -> dict[str, Any]:
    """Build the Excel cap workbook.

    Args:
        out_path: Output path for the .xlsx file
        base_year: Base salary year (e.g., 2025)
        as_of: As-of date for the snapshot
        league: League code (default: "NBA")
        skip_assertions: Skip SQL assertions for faster iteration

    Returns:
        Build metadata dict with validation status
    """

    if as_of is None:
        as_of = date.today()

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

    # Create workbook early so we always emit an artifact
    # use_future_functions ensures LET, FILTER, XLOOKUP get proper _xlfn. prefixes
    workbook = xlsxwriter.Workbook(str(out_path), {
        "remove_timezone": True,
        "use_future_functions": True,
    })

    # Set default font (must be before adding sheets)
    set_workbook_default_font(workbook)

    try:
        formats = create_standard_formats(workbook)

        # Create UI sheets first (so they appear at the front)
        ui_worksheets: dict[str, Any] = {}
        for name in UI_SHEETS:
            ws = workbook.add_worksheet(name)
            # CALC is a hidden helper sheet used for scalar calculations that we
            # reference via defined names. This avoids putting dynamic-array
            # functions inside <definedName> formulas (Excel may warn/repair).
            if name == "CALC":
                ws.hide()
            ui_worksheets[name] = ws

        # Create DATA sheets (hidden)
        data_worksheets: dict[str, Any] = {}
        for name in DATA_SHEETS:
            ws = workbook.add_worksheet(name)
            ws.hide()
            data_worksheets[name] = ws

        # Workbook-scoped named ranges for META fields.
        # These are used by UI formulas so we never hardcode the year/date.
        workbook.define_name("MetaValidationStatus", "=META!$B$3")
        workbook.define_name("MetaRefreshedAt", "=META!$B$4")
        workbook.define_name("MetaBaseYear", "=META!$B$5")
        workbook.define_name("MetaAsOfDate", "=META!$B$6")
        workbook.define_name("MetaDataContractVersion", "=META!$B$7")

        # Step 1: SQL assertions (optional)
        if not skip_assertions:
            try:
                passed, output = run_sql_assertions()
                if not passed:
                    _mark_failed(build_meta, f"SQL assertions failed:\n{output}")
            except Exception as e:
                _mark_failed(build_meta, f"SQL assertions crashed: {e}\n{traceback.format_exc()}")

        # Step 2: Extract datasets
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
            extract_fn = spec["extract"]
            try:
                cols, rows = extract_fn()
                extracted[key] = (cols, rows)
            except DatasetExtractError as e:
                _mark_failed(build_meta, f"Dataset extract failed: {e.dataset_name}: {e.original}")
                extracted[key] = (e.columns, [])
            except Exception as e:
                _mark_failed(build_meta, f"Dataset extract crashed: {key}: {e}\n{traceback.format_exc()}")
                extracted[key] = ([], [])

        # Step 3: Write DATA tables
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
            except Exception as e:
                _mark_failed(
                    build_meta,
                    f"Failed writing table {table_name} on sheet {sheet_name}: {e}\n{traceback.format_exc()}",
                )

        # Step 4: Write UI sheets

        # Extract team codes for PLAYGROUND dropdown
        team_codes = sorted(
            set(
                row.get("team_code")
                for row in extracted.get("team_salary_warehouse", ([], []))[1]
                if row.get("team_code")
            )
        )

        # PLAYGROUND - the reactive working surface
        try:
            # Performance: shrink any fixed-range formulas (conditional formatting,
            # validation lists) to the actual extracted table sizes instead of
            # hard-coded headroom.
            salary_book_yearly_nrows = max(len(extracted.get("salary_book_yearly", ([], []))[1]), 1)
            salary_book_warehouse_nrows = max(len(extracted.get("salary_book_warehouse", ([], []))[1]), 1)

            write_playground_sheet(
                workbook,
                ui_worksheets["PLAYGROUND"],
                formats,
                team_codes=team_codes,
                calc_worksheet=ui_worksheets["CALC"],
                base_year=base_year,
                salary_book_yearly_nrows=salary_book_yearly_nrows,
                salary_book_warehouse_nrows=salary_book_warehouse_nrows,
            )
        except Exception as e:
            _mark_failed(build_meta, f"PLAYGROUND writer crashed: {e}\n{traceback.format_exc()}")

        # META - build metadata (write last to capture any failures)
        try:
            write_meta_sheet(ui_worksheets["META"], formats, build_meta)
        except Exception as e:
            _mark_failed(build_meta, f"META writer crashed: {e}\n{traceback.format_exc()}")

    except Exception as e:
        _mark_failed(build_meta, f"Unhandled exporter crash: {e}\n{traceback.format_exc()}")

    finally:
        workbook.close()

    return build_meta
