# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.injuries from SportRadar API.
"""
import asyncio
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import extract_injuries
from sr_fetch import FetchError, fetch_json, get_api_key, get_base_url


def normalize_rows(rows: list[dict]) -> tuple[list[dict], list[str]]:
    if not rows:
        return [], []
    columns = sorted({key for row in rows for key in row.keys()})
    normalized = [{col: row.get(col) for col in columns} for row in rows]
    return normalized, columns


def upsert(conn, table: str, rows: list[dict], conflict_keys: list[str]) -> int:
    if not rows:
        return 0
    rows, columns = normalize_rows(rows)
    update_cols = [c for c in columns if c not in conflict_keys]

    placeholders = ", ".join(["%s"] * len(columns))
    col_list = ", ".join(columns)
    conflict = ", ".join(conflict_keys)

    if update_cols:
        updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])
        sql = (
            f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) "
            f"ON CONFLICT ({conflict}) DO UPDATE SET {updates}"
        )
    else:
        sql = (
            f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) "
            f"ON CONFLICT ({conflict}) DO NOTHING"
        )

    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(row[col] for col in columns) for row in rows])
    conn.commit()
    return len(rows)


def mark_inactive(conn, source_api: str, injury_ids: list[str]) -> None:
    with conn.cursor() as cur:
        if injury_ids:
            cur.execute(
                "UPDATE sr.injuries SET is_active = false WHERE source_api = %s AND NOT (injury_id = ANY(%s))",
                (source_api, injury_ids),
            )
        else:
            cur.execute(
                "UPDATE sr.injuries SET is_active = false WHERE source_api = %s",
                (source_api,),
            )
    conn.commit()


def main(
    dry_run: bool = False,
    source_api: str = "nba",
    mode: str = "daily",
    date: str | None = None,
    season_year: int | None = None,
    season_type: str | None = None,
    include_pbp: bool = True,
    locale: str = "en",
    max_concurrency: int = 6,
) -> dict:
    started_at = datetime.now().isoformat()
    errors: list[str] = []
    tables: list[dict] = []
    rows: list[dict] = []

    try:
        base_url = get_base_url(source_api)
        api_key = get_api_key()
        injuries_url = f"{base_url}/{locale}/league/injuries.json"
        params = {"api_key": api_key}

        async def run_fetch() -> dict:
            async with httpx.AsyncClient() as client:
                return await fetch_json(client, injuries_url, params)

        injuries_payload = asyncio.run(run_fetch())
        rows = extract_injuries(injuries_payload or {}, source_api)
        rows = [
            row
            for row in rows
            if row.get("source_api")
            and row.get("injury_id")
            and row.get("sr_id")
            and row.get("sr_team_id")
        ]
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "sr.injuries", rows, ["source_api", "injury_id"])
                tables.append({"table": "sr.injuries", "attempted": count, "success": True})
                injury_ids = [row["injury_id"] for row in rows]
                mark_inactive(conn, source_api, injury_ids)
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.injuries", "attempted": len(rows), "success": True})
    except Exception as exc:
        errors.append(str(exc))

    return {
        "dry_run": dry_run,
        "source_api": source_api,
        "started_at": started_at,
        "finished_at": datetime.now().isoformat(),
        "tables": tables,
        "errors": errors,
    }
