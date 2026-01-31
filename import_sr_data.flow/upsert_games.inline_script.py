# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.games from SportRadar API.
"""
import asyncio
import json
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import (
    build_game_row_from_schedule,
    build_game_row_from_summary,
    extract_game_id,
    extract_schedule_games,
    extract_season_context,
)
from sr_fetch import (
    FetchError,
    build_schedule_url,
    fetch_json,
    fetch_many,
    get_api_key,
    get_base_url,
)

JSON_COLUMNS = {"broadcast_json", "time_zones_json", "summary_json"}


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
        schedule_url, _ = build_schedule_url(base_url, locale, mode, date, season_year, season_type)
        params = {"api_key": api_key}

        async def run_fetch() -> tuple[dict, dict[str, dict]]:
            async with httpx.AsyncClient() as client:
                schedule_payload = await fetch_json(client, schedule_url, params)
                schedule_games = extract_schedule_games(schedule_payload)
                summary_requests = []
                for game in schedule_games:
                    game_id = extract_game_id(game)
                    if not game_id:
                        continue
                    summary_requests.append(
                        (game_id, f"{base_url}/{locale}/games/{game_id}/summary.json")
                    )
                summaries = {}
                if summary_requests:
                    summaries = await fetch_many(client, summary_requests, params, max_concurrency)
                return schedule_payload, summaries

        schedule_payload, summaries = asyncio.run(run_fetch())
        schedule_games = extract_schedule_games(schedule_payload)
        season_ctx = extract_season_context(schedule_payload)

        games_by_id: dict[str, dict] = {}
        for game in schedule_games:
            row = build_game_row_from_schedule(game, source_api, season_ctx)
            if row:
                games_by_id[row["game_id"]] = row

        for game_id, summary in summaries.items():
            game_row = build_game_row_from_summary(summary, source_api)
            if not game_row:
                continue
            existing = games_by_id.get(game_id, {})
            existing.update({k: v for k, v in game_row.items() if v is not None})
            games_by_id[game_id] = existing

        rows = [row for row in games_by_id.values() if row.get("source_api") and row.get("game_id")]
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "sr.games", rows, ["source_api", "game_id"])
                tables.append({"table": "sr.games", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.games", "attempted": len(rows), "success": True})
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
