# /// script
# requires-python = ">=3.11"
# dependencies = ["xlsxwriter", "psycopg[binary]"]
# ///
"""
Windmill step: Export cap workbook after PCMS refresh.

Builds a self-contained Excel workbook from pcms.* warehouses.
Runs after refresh_caches (step h) so all warehouses are up-to-date.

Output: ./shared/capbook.xlsx
"""

from datetime import date
from pathlib import Path


def main(dry_run: bool = False, base_year: int | None = None):
    """Build Excel cap workbook.

    Args:
        dry_run: If True, skip actual workbook generation.
        base_year: Salary year to use as base (default: current year).

    Returns:
        dict with build metadata (refreshed_at, validation_status, etc.)
    """
    import sys

    # Add parent to path so we can import capbook module
    script_dir = Path(__file__).parent.parent
    if str(script_dir) not in sys.path:
        sys.path.insert(0, str(script_dir))

    from excel.capbook.build import build_capbook

    # Default base_year to current year if not provided
    if base_year is None:
        base_year = date.today().year

    as_of = date.today()
    out_path = Path("./shared/capbook.xlsx")

    if dry_run:
        return {
            "dry_run": True,
            "would_build": str(out_path),
            "base_year": base_year,
            "as_of": as_of.isoformat(),
        }

    # Ensure output directory exists
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Building cap workbook...")
    print(f"  Output:    {out_path}")
    print(f"  Base year: {base_year}")
    print(f"  As-of:     {as_of}")
    print()

    # Build the workbook (skip assertions since flow runs them separately if needed)
    meta = build_capbook(
        out_path=out_path,
        base_year=base_year,
        as_of=as_of,
        league="NBA",
        skip_assertions=True,  # Assertions already ran if configured
    )

    print(f"Workbook generated: {out_path}")
    print(f"  Refreshed at: {meta['refreshed_at']}")
    print(f"  Git SHA:      {meta['exporter_git_sha']}")
    print(f"  Validation:   {meta['validation_status']}")

    if meta["validation_status"] != "PASS":
        print()
        print("VALIDATION ISSUES:")
        for err in meta.get("validation_errors", [])[:5]:
            print(f"  {err[:200]}...")

    return {
        "out_path": str(out_path),
        "base_year": base_year,
        "as_of": as_of.isoformat(),
        "refreshed_at": meta["refreshed_at"],
        "validation_status": meta["validation_status"],
        "exporter_git_sha": meta["exporter_git_sha"],
        "data_contract_version": meta["data_contract_version"],
        "error_count": len(meta.get("validation_errors", [])),
    }
