# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.season_team_splits and sr.season_player_splits from SportRadar API.
"""
import asyncio
import json
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import (
    extract_home_away,
    extract_schedule_games,
    extract_seasons,
    extract_splits,
    extract_teams,
    resolve_season_year_type,
)
from sr_fetch import (
    FetchError,
    build_schedule_url,
    fetch_json,
    fetch_many,
    get_api_key,
    get_base_url,
    get_seasons_url,
    get_teams_url,
)

JSON_COLUMNS = {"statistics_json"}


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


def prep_team_rows(rows: list[dict]) -> list[dict]:
    cleaned = []
    for row in rows:
        if (
            not row.get("source_api")
            or not row.get("season_id")
            or not row.get("sr_team_id")
            or not row.get("split_type")
            or not row.get("split_value")
        ):
            continue
        row["is_opponent"] = bool(row.get("is_opponent"))
        cleaned.append(row)
    return cleaned


def prep_player_rows(rows: list[dict]) -> list[dict]:
    cleaned = []
    for row in rows:
        if (
            not row.get("source_api")
            or not row.get("season_id")
            or not row.get("sr_team_id")
            or not row.get("sr_id")
            or not row.get("split_type")
            or not row.get("split_value")
        ):
            continue
        cleaned.append(row)
    return cleaned


def collect_team_ids(schedule_payload: dict, teams_payload: dict, source_api: str) -> list[str]:
    team_ids: set[str] = set()
    for game in extract_schedule_games(schedule_payload):
        home_team, away_team = extract_home_away(game)
        for team in (home_team, away_team):
            team_id = (team or {}).get("id")
            if team_id:
                team_ids.add(team_id)

    if not team_ids and teams_payload:
        for team_row in extract_teams(teams_payload, source_api):
            if team_row.get("sr_team_id"):
                team_ids.add(team_row["sr_team_id"])

    return sorted(team_ids)


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

    team_rows: list[dict] = []
    player_rows: list[dict] = []

    try:
        base_url = get_base_url(source_api)
        api_key = get_api_key()
        seasons_url = get_seasons_url(source_api, base_url, locale)
        teams_url = get_teams_url(source_api, base_url, locale)
        schedule_url, _ = build_schedule_url(base_url, locale, mode, date, season_year, season_type)
        params = {"api_key": api_key}

        async def run_fetch() -> tuple[dict, dict, dict, dict[str, dict]]:
            async with httpx.AsyncClient() as client:
                seasons_payload = await fetch_json(client, seasons_url, params)
                schedule_payload = await fetch_json(client, schedule_url, params)
                teams_payload = await fetch_json(client, teams_url, params) if teams_url else {}

                resolved_year, resolved_type = resolve_season_year_type(
                    seasons_payload, schedule_payload, season_year, season_type
                )
                team_ids = collect_team_ids(schedule_payload, teams_payload, source_api)

                team_splits_payloads: dict[str, dict] = {}
                if (
                    resolved_year
                    and resolved_type
                    and team_ids
                    and source_api in {"nba", "gleague"}
                ):
                    split_requests = []
                    for team_id in team_ids:
                        for split_kind in ("game", "hierarchy", "ingame", "schedule"):
                            split_requests.append(
                                (
                                    f"{team_id}:{split_kind}",
                                    f"{base_url}/{locale}/seasons/{resolved_year}/{resolved_type}/teams/{team_id}/splits/{split_kind}.json",
                                )
                            )
                    if split_requests:
                        team_splits_payloads = await fetch_many(
                            client, split_requests, params, max_concurrency
                        )

                return seasons_payload, schedule_payload, teams_payload, team_splits_payloads

        seasons_payload, _schedule_payload, _teams_payload, team_splits_payloads = asyncio.run(run_fetch())

        seasons_rows = extract_seasons(seasons_payload, source_api)
        season_lookup = {
            (row["season_year"], row["season_type"]): row["season_id"]
            for row in seasons_rows
            if row.get("season_year") is not None and row.get("season_type")
        }

        for key, payload in team_splits_payloads.items():
            split_kind = key.split(":", 1)[1] if ":" in key else None
            team_split_rows, player_split_rows = extract_splits(
                payload, source_api, season_lookup, split_kind
            )
            team_rows.extend(team_split_rows)
            player_rows.extend(player_split_rows)

        team_rows = prep_team_rows(team_rows)
        player_rows = prep_player_rows(player_rows)
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(
                    conn,
                    "sr.season_team_splits",
                    team_rows,
                    ["source_api", "season_id", "sr_team_id", "split_type", "split_value", "is_opponent"],
                )
                tables.append({"table": "sr.season_team_splits", "attempted": count, "success": True})

                count = upsert(
                    conn,
                    "sr.season_player_splits",
                    player_rows,
                    ["source_api", "season_id", "sr_team_id", "sr_id", "split_type", "split_value"],
                )
                tables.append({"table": "sr.season_player_splits", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.season_team_splits", "attempted": len(team_rows), "success": True})
            tables.append({"table": "sr.season_player_splits", "attempted": len(player_rows), "success": True})
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
