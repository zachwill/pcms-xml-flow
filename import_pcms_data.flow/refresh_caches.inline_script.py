# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]"]
# ///
"""Refresh post-ingestion cache tables.

This step runs after all PCMS base tables are imported.

Caches refreshed:
- pcms.salary_book_warehouse
- pcms.team_salary_warehouse
- pcms.exceptions_warehouse
- pcms.dead_money_warehouse
- pcms.cap_holds_warehouse
- pcms.draft_pick_trade_claims_warehouse
- pcms.draft_picks_warehouse
- pcms.draft_assets_warehouse

Notes:
- These refresh functions use TRUNCATE/INSERT.
- If dry_run=true, we skip refreshes.
"""

import os
from datetime import datetime
import psycopg


def main(dry_run: bool = False):
    started_at = datetime.now().isoformat()

    if dry_run:
        return {
            "ok": True,
            "dry_run": True,
            "started_at": started_at,
            "refreshed": [],
            "note": "dry_run=true, skipping cache refresh",
        }

    pg_url = os.environ.get("POSTGRES_URL")
    if not pg_url:
        raise RuntimeError("POSTGRES_URL env var is required")

    refreshed = []

    with psycopg.connect(pg_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT pcms.refresh_salary_book_warehouse();")
            refreshed.append("pcms.refresh_salary_book_warehouse")

            cur.execute("SELECT pcms.refresh_team_salary_warehouse();")
            refreshed.append("pcms.refresh_team_salary_warehouse")

            cur.execute("SELECT pcms.refresh_exceptions_warehouse();")
            refreshed.append("pcms.refresh_exceptions_warehouse")

            cur.execute("SELECT pcms.refresh_dead_money_warehouse();")
            refreshed.append("pcms.refresh_dead_money_warehouse")

            cur.execute("SELECT pcms.refresh_cap_holds_warehouse();")
            refreshed.append("pcms.refresh_cap_holds_warehouse")

            cur.execute("SELECT pcms.refresh_player_rights_warehouse();")
            refreshed.append("pcms.refresh_player_rights_warehouse")

            cur.execute("SELECT pcms.refresh_draft_pick_trade_claims_warehouse();")
            refreshed.append("pcms.refresh_draft_pick_trade_claims_warehouse")

            cur.execute("SELECT pcms.refresh_draft_picks_warehouse();")
            refreshed.append("pcms.refresh_draft_picks_warehouse")

            cur.execute("SELECT pcms.refresh_draft_assets_warehouse();")
            refreshed.append("pcms.refresh_draft_assets_warehouse")

        conn.commit()

    return {
        "ok": True,
        "dry_run": False,
        "started_at": started_at,
        "refreshed": refreshed,
    }
