# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.draft from SportRadar API.
"""
import asyncio
import json
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import extract_draft, extract_seasons, resolve_season_year_type
from sr_fetch import (
    DRAFT_BASE_URL,
    FetchError,
    build_schedule_url,
    fetch_json,
    get_api_key,
    get_base_url,
    get_seasons_url,
)

JSON_COLUMNS = {"trades_json"}


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

    if source_api != "nba":
        return {
            "dry_run": dry_run,
            "source_api": source_api,
            "started_at": started_at,
            "finished_at": datetime.now().isoformat(),
            "tables": [{"table": "sr.draft", "attempted": 0, "success": True}],
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
        resolved_year, _resolved_type = resolve_season_year_type(
            seasons_payload, schedule_payload, season_year, season_type
        )

        draft_year = resolved_year + 1 if resolved_year else None
        payloads: dict[str, dict] = {}
        if draft_year:
            draft_urls = {
                "draft": f"{DRAFT_BASE_URL}/{locale}/{draft_year}/draft.json",
                "prospects": f"{DRAFT_BASE_URL}/{locale}/{draft_year}/prospects.json",
                "top_prospects": f"{DRAFT_BASE_URL}/{locale}/{draft_year}/top_prospects.json",
                "trades": f"{DRAFT_BASE_URL}/{locale}/{draft_year}/trades.json",
            }

            async def fetch_draft_payloads() -> dict[str, dict]:
                async with httpx.AsyncClient() as client:
                    data: dict[str, dict] = {}
                    for key, url in draft_urls.items():
                        data[key] = await fetch_json(client, url, params)
                    return data

            payloads = asyncio.run(fetch_draft_payloads())

        rows = extract_draft(payloads, source_api, draft_year)
        rows = [row for row in rows if row.get("source_api") and row.get("draft_id")]
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "sr.draft", rows, ["source_api", "draft_id"])
                tables.append({"table": "sr.draft", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.draft", "attempted": len(rows), "success": True})
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
