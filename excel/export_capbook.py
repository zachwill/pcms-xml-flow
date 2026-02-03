#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["xlsxwriter", "psycopg[binary]"]
# ///
"""Export the NBA cap workbook to Excel.

Generates a self-contained .xlsx workbook from Postgres (pcms.* warehouses).

Defaults are intentionally ergonomic:
- out:      shared/capbook.xlsx
- baseYear: 2025
- asOf:     today

Usage:
    uv run excel/export_capbook.py
    uv run excel/export_capbook.py --help

Examples:
    uv run excel/export_capbook.py
    uv run excel/export_capbook.py --out shared/capbook.xlsx
    uv run excel/export_capbook.py --base-year 2025 --as-of 2026-01-31

Design reference:
    reference/blueprints/README.md
    reference/blueprints/excel-cap-book-blueprint.md
    reference/blueprints/data-contract.md
"""

from __future__ import annotations

import argparse
import sys
from datetime import date
from pathlib import Path


DEFAULT_OUT = Path("shared/capbook.xlsx")
DEFAULT_BASE_YEAR = 2025


def parse_date(s: str) -> date:
    """Parse YYYY-MM-DD date string."""
    try:
        return date.fromisoformat(s)
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid date format: {s}. Use YYYY-MM-DD.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export NBA cap workbook to Excel.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Defaults:
    --out      {DEFAULT_OUT}
    --base-year {DEFAULT_BASE_YEAR}
    --as-of     today

Examples:
    uv run excel/export_capbook.py
    uv run excel/export_capbook.py --out shared/capbook.xlsx
    uv run excel/export_capbook.py --base-year 2025 --as-of 2026-01-31

Design reference:
    reference/blueprints/excel-cap-book-blueprint.md
""",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Output file path (.xlsx) (default: {DEFAULT_OUT})",
    )
    parser.add_argument(
        "--base-year",
        type=int,
        default=DEFAULT_BASE_YEAR,
        help=f"Base salary year (default: {DEFAULT_BASE_YEAR})",
    )
    parser.add_argument(
        "--as-of",
        type=str,
        default="today",
        help="As-of date (YYYY-MM-DD or 'today') (default: today)",
    )
    parser.add_argument(
        "--league",
        type=str,
        default="NBA",
        help="League code (default: NBA)",
    )
    parser.add_argument(
        "--skip-assertions",
        action="store_true",
        help="Skip SQL assertions (for testing/debugging)",
    )
    args = parser.parse_args()

    # Parse as-of date
    if str(args.as_of).lower() == "today":
        as_of_date = date.today()
    else:
        as_of_date = parse_date(str(args.as_of))

    # Ensure output directory exists
    args.out.parent.mkdir(parents=True, exist_ok=True)

    # Import build module (after parsing args to avoid import errors on --help)
    from capbook.build import build_capbook

    print("Building cap workbook...")
    print(f"  Output:    {args.out}")
    print(f"  Base year: {args.base_year}")
    print(f"  As-of:     {as_of_date}")
    print(f"  League:    {args.league}")
    print()

    meta = build_capbook(
        out_path=args.out,
        base_year=args.base_year,
        as_of=as_of_date,
        league=args.league,
        skip_assertions=args.skip_assertions,
    )

    print(f"Workbook generated: {args.out}")
    print(f"  Refreshed at: {meta['refreshed_at']}")
    print(f"  Git SHA:      {meta['exporter_git_sha']}")
    print(f"  Validation:   {meta['validation_status']}")

    if meta["validation_status"] != "PASS":
        print()
        print("VALIDATION FAILED:")
        for err in meta.get("validation_errors", []):
            print(f"  {err[:200]}...")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
