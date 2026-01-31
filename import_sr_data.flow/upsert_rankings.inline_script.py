# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.rankings from SportRadar API.
"""
import asyncio
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import extract_rankings, extract_seasons, resolve_season_year_type
from sr_fetch import (
    FetchError,
    NCAA_POLL_NAMES,
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

    if source_api != "ncaa":
        return {
            "dry_run": dry_run,
            "source_api": source_api,
            "started_at": started_at,
            "finished_at": datetime.now().isoformat(),
            "tables": [{"table": "sr.rankings", "attempted": 0, "success": True}],
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

        rankings_payloads: dict[str, dict] = {}
        async def fetch_rankings() -> dict[str, dict]:
            async with httpx.AsyncClient() as client:
                payloads: dict[str, dict] = {}
                if resolved_year:
                    for poll_name in NCAA_POLL_NAMES:
                        poll_url = (
                            f"{base_url}/{locale}/polls/{poll_name}/{resolved_year}/rankings.json"
                        )
                        payloads[f"poll_{poll_name}"] = await fetch_json(client, poll_url, params)

                    rpi_url = f"{base_url}/{locale}/rpi/{resolved_year}/rankings.json"
                    payloads["rpi"] = await fetch_json(client, rpi_url, params)

                if resolved_year and resolved_type:
                    net_url = (
                        f"{base_url}/{locale}/seasons/{resolved_year}/{resolved_type}/netrankings.json"
                    )
                    payloads["net"] = await fetch_json(client, net_url, params)
                return payloads

        rankings_payloads = asyncio.run(fetch_rankings()) if resolved_year else {}

        for key, payload in rankings_payloads.items():
            if key.startswith("poll_"):
                poll_name = key.split("_", 1)[1]
                rows.extend(extract_rankings(payload, source_api, "poll", poll_name, season_lookup))
            elif key == "net":
                rows.extend(extract_rankings(payload, source_api, "net", "NET", season_lookup))
            elif key == "rpi":
                rows.extend(extract_rankings(payload, source_api, "rpi", "RPI", season_lookup))

        rows = [
            row
            for row in rows
            if row.get("source_api")
            and row.get("season_id")
            and row.get("sr_team_id")
            and row.get("type")
            and row.get("name")
            and row.get("week")
        ]
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(
                    conn,
                    "sr.rankings",
                    rows,
                    ["source_api", "season_id", "type", "name", "week", "sr_team_id"],
                )
                tables.append({"table": "sr.rankings", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.rankings", "attempted": len(rows), "success": True})
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
