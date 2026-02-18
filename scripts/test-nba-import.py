#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx"]
# ///
"""
Test runner for NBA import scripts.

Usage:
    uv run scripts/test-nba-import.py teams
    uv run scripts/test-nba-import.py games --run-mode date_backfill --start-date 2024-10-01 --end-date 2024-10-02 --write
    uv run scripts/test-nba-import.py all --run-mode season_backfill --season-label 2023-24 --write
"""

import argparse
import importlib.util
import inspect
import json
import sys
from pathlib import Path

SCRIPTS = {
    "teams": "teams.inline_script.py",
    "players": "players.inline_script.py",
    "schedules": "schedules.inline_script.py",
    "standings": "standings.inline_script.py",
    "games": "games.inline_script.py",
    "game_data": "game_data.inline_script.py",
    "querytool_event_streams": "querytool_event_streams.inline_script.py",
    "aggregates": "aggregates.inline_script.py",
    "lineups": "lineups.inline_script.py",
    "shot_chart": "shot_chart.inline_script.py",
    "supplemental": "supplemental.inline_script.py",
    "ngss": "ngss.inline_script.py",
}

SCRIPT_DIR = Path("import_nba_data.flow")


def load_script(name: str):
    """Dynamically load a script and return its main function."""
    script_path = SCRIPT_DIR / SCRIPTS[name]
    spec = importlib.util.spec_from_file_location(name, script_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.main


def build_params(args: argparse.Namespace) -> dict:
    return {
        "league_id": args.league_id,
        "season_label": args.season_label,
        "season_type": args.season_type,
        "mode": args.run_mode,
        "days_back": args.days_back,
        "start_date": args.start_date,
        "end_date": args.end_date,
        "game_ids": args.game_ids,
        "only_final_games": args.only_final_games,
    }


def run_script(name: str, dry_run: bool, params: dict):
    """Run a single import script."""
    print(f"\n{'=' * 60}")
    print(f"Running: {name} (dry_run={dry_run})")
    print(f"{'=' * 60}\n")

    main = load_script(name)
    script_params = params.copy()
    script_params["dry_run"] = dry_run

    accepted = set(inspect.signature(main).parameters.keys())
    filtered_params = {k: v for k, v in script_params.items() if k in accepted}

    result = main(**filtered_params)
    print(json.dumps(result, indent=2))
    return result


def main():
    parser = argparse.ArgumentParser(description="Test NBA import scripts")
    parser.add_argument(
        "script",
        choices=list(SCRIPTS.keys()) + ["all"],
        help="Script to run (or 'all')",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Actually write to the database",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Force dry-run preview (overrides --write)",
    )

    parser.add_argument("--league-id", default="00", help="League ID (00=NBA)")
    parser.add_argument("--season-label", default="2025-26", help="Season label (e.g., 2025-26)")
    parser.add_argument("--season-type", default="Regular Season", help="Season type")

    parser.add_argument(
        "--run-mode",
        choices=["refresh", "date_backfill", "season_backfill"],
        default="refresh",
        help="refresh (last N days), date_backfill (explicit dates), or season_backfill (full season)",
    )
    parser.add_argument(
        "--mode",
        dest="run_mode",
        choices=["refresh", "date_backfill", "season_backfill", "backfill"],
        help="Backward-compatible alias for --run-mode",
    )

    parser.add_argument("--days-back", type=int, default=2, help="Days back for refresh mode")
    parser.add_argument("--start-date", default="", help="YYYY-MM-DD (date_backfill)")
    parser.add_argument("--end-date", default="", help="YYYY-MM-DD (date_backfill)")
    parser.add_argument("--game-ids", default="", help="Comma-separated game IDs (advanced override)")
    parser.add_argument(
        "--only-final-games",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Only fetch final games for game-data style endpoints",
    )

    args = parser.parse_args()

    # Ensure progress output is visible immediately even when piped (e.g. to `tee`).
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(line_buffering=True)
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(line_buffering=True)
    except Exception:
        pass

    if args.run_mode == "backfill":
        args.run_mode = "date_backfill"

    if bool(args.start_date) ^ bool(args.end_date):
        parser.error("--start-date and --end-date must be provided together")

    if args.run_mode == "date_backfill" and not (args.start_date and args.end_date):
        if args.script == "all":
            parser.error("date_backfill with script=all requires --start-date and --end-date")
        if not args.game_ids:
            parser.error("date_backfill requires --start-date and --end-date (or --game-ids for game-level scripts)")

    if args.run_mode == "season_backfill" and not args.season_label:
        parser.error("season_backfill requires --season-label")

    dry_run = True
    if args.write:
        dry_run = False
    if args.dry_run:
        dry_run = True

    params = build_params(args)

    if args.script == "all":
        results = {}
        for name in SCRIPTS:
            results[name] = run_script(name, dry_run=dry_run, params=params)

        print(f"\n{'=' * 60}")
        print("SUMMARY")
        print(f"{'=' * 60}")
        for name, result in results.items():
            errors = result.get("errors", [])
            tables = result.get("tables", [])
            status = "✓" if not errors else "✗"
            print(f"{status} {name}: {len(tables)} tables, {len(errors)} errors")
    else:
        run_script(args.script, dry_run=dry_run, params=params)


if __name__ == "__main__":
    main()
