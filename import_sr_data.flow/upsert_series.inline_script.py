# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.series from SportRadar API.
"""
import asyncio
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import extract_seasons, extract_series, resolve_season_year_type
from sr_fetch import (
    FetchError,
    build_schedule_url,
    fetch_json,
    get_api_key,
    get_base_url,
    get_seasons_url,
)


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

    if source_api not in {"nba", "gleague"}:
        return {
            "dry_run": dry_run,
            "source_api": source_api,
            "started_at": started_at,
            "finished_at": datetime.now().isoformat(),
            "tables": [{"table": "sr.series", "attempted": 0, "success": True}],
            "errors": [],
        }

    try:
        base_url = get_base_url(source_api)
        api_key = get_api_key()
        seasons_url = get_seasons_url(source_api, base_url, locale)
        schedule_url, _ = build_schedule_url(base_url, locale, mode, date, season_year, season_type)
        params = {"api_key": api_key}

        async def run_fetch() -> tuple[dict, dict]:
            async with httpx.AsyncClient() as client:
                seasons_payload = await fetch_json(client, seasons_url, params)
                schedule_payload = await fetch_json(client, schedule_url, params)
                return seasons_payload, schedule_payload

        seasons_payload, schedule_payload = asyncio.run(run_fetch())
        seasons_rows = extract_seasons(seasons_payload, source_api)
        season_lookup = {
            (row["season_year"], row["season_type"]): row["season_id"]
            for row in seasons_rows
            if row.get("season_year") is not None and row.get("season_type")
        }
        resolved_year, resolved_type = resolve_season_year_type(
            seasons_payload, schedule_payload, season_year, season_type
        )

        if resolved_year and resolved_type:
            series_url = f"{base_url}/{locale}/series/{resolved_year}/{resolved_type}/schedule.json"

            async def fetch_series() -> dict:
                async with httpx.AsyncClient() as client:
                    return await fetch_json(client, series_url, params)

            series_payload = asyncio.run(fetch_series())
            rows, _ = extract_series(series_payload, source_api, season_lookup)

        rows = [row for row in rows if row.get("source_api") and row.get("series_id")]
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "sr.series", rows, ["source_api", "series_id"])
                tables.append({"table": "sr.series", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.series", "attempted": len(rows), "success": True})
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
