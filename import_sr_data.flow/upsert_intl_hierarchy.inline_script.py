# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.competitions, sr.season_stages, sr.season_groups from SportRadar API.
"""
import asyncio
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import (
    extract_competitions,
    extract_intl_season_hierarchy,
    normalize_records,
    parse_season_year,
)
from sr_fetch import FetchError, fetch_json, fetch_many, get_api_key, get_base_url, get_seasons_url


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
    competitions: list[dict] = []
    stages: list[dict] = []
    groups: list[dict] = []

    if source_api != "intl":
        return {
            "dry_run": dry_run,
            "source_api": source_api,
            "started_at": started_at,
            "finished_at": datetime.now().isoformat(),
            "tables": [
                {"table": "sr.competitions", "attempted": 0, "success": True},
                {"table": "sr.season_stages", "attempted": 0, "success": True},
                {"table": "sr.season_groups", "attempted": 0, "success": True},
            ],
            "errors": [],
        }

    try:
        base_url = get_base_url(source_api)
        api_key = get_api_key()
        seasons_url = get_seasons_url(source_api, base_url, locale)
        competitions_url = f"{base_url}/{locale}/competitions.json"
        params = {"api_key": api_key}

        async def run_fetch() -> tuple[dict, dict, dict[str, dict]]:
            async with httpx.AsyncClient() as client:
                seasons_payload = await fetch_json(client, seasons_url, params)
                competitions_payload = await fetch_json(client, competitions_url, params)

                seasons = normalize_records(seasons_payload.get("seasons"))
                latest_by_competition: dict[str, dict] = {}
                for season in seasons:
                    season_id = season.get("id")
                    competition_id = season.get("competition_id") or (season.get("competition") or {}).get("id")
                    if not season_id or not competition_id:
                        continue
                    year = parse_season_year(season.get("year")) or 0
                    existing = latest_by_competition.get(competition_id)
                    if existing is None or year > existing.get("year", 0):
                        latest_by_competition[competition_id] = {"id": season_id, "year": year}

                season_info_requests = [
                    (season_id, f"{base_url}/{locale}/seasons/{season_id}/info.json")
                    for season_id in [entry["id"] for entry in latest_by_competition.values()]
                ]
                season_infos = {}
                if season_info_requests:
                    season_infos = await fetch_many(client, season_info_requests, params, max_concurrency)

                return seasons_payload, competitions_payload, season_infos

        _seasons_payload, competitions_payload, season_infos = asyncio.run(run_fetch())

        competitions = extract_competitions(competitions_payload or {}, source_api)
        for payload in season_infos.values():
            stage_rows, group_rows = extract_intl_season_hierarchy(payload, source_api)
            stages.extend(stage_rows)
            groups.extend(group_rows)

        competitions = [row for row in competitions if row.get("source_api") and row.get("competition_id")]
        stages = [row for row in stages if row.get("source_api") and row.get("stage_id")]
        groups = [row for row in groups if row.get("source_api") and row.get("group_id")]
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "sr.competitions", competitions, ["source_api", "competition_id"])
                tables.append({"table": "sr.competitions", "attempted": count, "success": True})

                count = upsert(conn, "sr.season_stages", stages, ["source_api", "stage_id"])
                tables.append({"table": "sr.season_stages", "attempted": count, "success": True})

                count = upsert(conn, "sr.season_groups", groups, ["source_api", "group_id"])
                tables.append({"table": "sr.season_groups", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.competitions", "attempted": len(competitions), "success": True})
            tables.append({"table": "sr.season_stages", "attempted": len(stages), "success": True})
            tables.append({"table": "sr.season_groups", "attempted": len(groups), "success": True})
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
