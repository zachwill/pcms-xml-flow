# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.standings from SportRadar API.
"""
import asyncio
import json
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import extract_seasons, extract_standings, resolve_season_year_type
from sr_fetch import (
    FetchError,
    build_schedule_url,
    fetch_json,
    get_api_key,
    get_base_url,
    get_seasons_url,
)

JSON_COLUMNS = {"records_json"}


def normalize_json(value):
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return json.dumps(value)


def normalize_rows(rows: list[dict]) -> tuple[list[dict], list[str]]:
    if not rows:
        return [], []
    columns = sorted({key for row in rows for key in row.keys()})
    normalized = []
    for row in rows:
        normalized_row = {col: row.get(col) for col in columns}
        for col in JSON_COLUMNS:
            if col in normalized_row:
                normalized_row[col] = normalize_json(normalized_row[col])
        normalized.append(normalized_row)
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
        resolved_year, resolved_type = resolve_season_year_type(
            seasons_payload, schedule_payload, season_year, season_type
        )

        standings_payload = {}
        if resolved_year and resolved_type:
            standings_url = (
                f"{base_url}/{locale}/seasons/{resolved_year}/{resolved_type}/standings.json"
            )
            async def fetch_standings() -> dict:
                async with httpx.AsyncClient() as client:
                    return await fetch_json(client, standings_url, params)

            standings_payload = asyncio.run(fetch_standings())

        rows = extract_standings(standings_payload or {}, source_api)
        rows = [
            row
            for row in rows
            if row.get("source_api") and row.get("season_id") and row.get("sr_team_id")
        ]
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "sr.standings", rows, ["source_api", "season_id", "sr_team_id"])
                tables.append({"table": "sr.standings", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.standings", "attempted": len(rows), "success": True})
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
