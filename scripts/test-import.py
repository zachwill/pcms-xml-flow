#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]"]
# ///
"""
Test runner for PCMS import scripts.

Usage:
    uv run scripts/test-import.py lookups
    uv run scripts/test-import.py contracts --dry-run
    uv run scripts/test-import.py all
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

SCRIPTS = {
    "lookups": "lookups.inline_script.py",
    "people": "people.inline_script.py",
    "contracts": "contracts.inline_script.py",
    "transactions": "transactions.inline_script.py",
    "league_config": "league_config.inline_script.py",
    "team_financials": "team_financials.inline_script.py",
}

EXTRACT_DIR = "shared/pcms/nba_pcms_full_extract"


def load_script(name: str):
    """Dynamically load a script and return its main function."""
    script_path = Path("import_pcms_data.flow") / SCRIPTS[name]
    spec = importlib.util.spec_from_file_location(name, script_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.main


def run_script(name: str, dry_run: bool = True):
    """Run a single import script."""
    print(f"\n{'='*60}")
    print(f"Running: {name} (dry_run={dry_run})")
    print(f"{'='*60}\n")

    main = load_script(name)
    result = main(dry_run=dry_run, extract_dir=EXTRACT_DIR)

    print(json.dumps(result, indent=2))
    return result


def main():
    parser = argparse.ArgumentParser(description="Test PCMS import scripts")
    parser.add_argument(
        "script",
        choices=list(SCRIPTS.keys()) + ["all"],
        help="Script to run (or 'all')",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=True,
        help="Preview changes without writing to DB (default: True)",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Actually write to the database",
    )
    args = parser.parse_args()

    dry_run = not args.write

    if args.script == "all":
        results = {}
        for name in SCRIPTS:
            results[name] = run_script(name, dry_run=dry_run)

        # Summary
        print(f"\n{'='*60}")
        print("SUMMARY")
        print(f"{'='*60}")
        for name, result in results.items():
            errors = result.get("errors", [])
            tables = result.get("tables", [])
            status = "✓" if not errors else "✗"
            print(f"{status} {name}: {len(tables)} tables, {len(errors)} errors")
    else:
        run_script(args.script, dry_run=dry_run)


if __name__ == "__main__":
    main()
