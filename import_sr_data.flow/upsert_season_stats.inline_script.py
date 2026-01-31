# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.season_team_statistics and sr.season_player_statistics from SportRadar API.
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
    extract_team_statistics_payload,
    extract_teams,
    iter_series_entries,
    normalize_records,
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


def upsert(conn, table: str, rows: list[dict], conflict_target: str, conflict_columns: list[str]) -> int:
    if not rows:
        return 0
    rows, columns = normalize_rows(rows)
    update_cols = [c for c in columns if c not in conflict_columns]

    placeholders = ", ".join(["%s"] * len(columns))
    col_list = ", ".join(columns)

    if update_cols:
        updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])
        sql = (
            f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) "
            f"ON CONFLICT {conflict_target} DO UPDATE SET {updates}"
        )
    else:
        sql = (
            f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) "
            f"ON CONFLICT {conflict_target} DO NOTHING"
        )

    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(row[col] for col in columns) for row in rows])
    conn.commit()
    return len(rows)


def prep_team_rows(rows: list[dict]) -> list[dict]:
    cleaned = []
    for row in rows:
        if not row.get("source_api") or not row.get("season_id") or not row.get("sr_team_id"):
            continue
        row["series_id"] = row.get("series_id") or None
        row["tournament_id"] = row.get("tournament_id") or None
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
        ):
            continue
        row["series_id"] = row.get("series_id") or None
        row["tournament_id"] = row.get("tournament_id") or None
        cleaned.append(row)
    return cleaned


def split_team_rows(rows: list[dict]) -> tuple[list[dict], list[dict], list[dict]]:
    base, series, tournament = [], [], []
    for row in rows:
        if row.get("series_id"):
            series.append(row)
        elif row.get("tournament_id"):
            tournament.append(row)
        else:
            base.append(row)
    return base, series, tournament


def split_player_rows(rows: list[dict]) -> tuple[list[dict], list[dict], list[dict]]:
    base, series, tournament = [], [], []
    for row in rows:
        if row.get("series_id"):
            series.append(row)
        elif row.get("tournament_id"):
            tournament.append(row)
        else:
            base.append(row)
    return base, series, tournament


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

        async def run_fetch() -> tuple[
            dict,
            dict,
            dict,
            dict[str, dict],
            dict[str, dict],
            int | None,
            str | None,
        ]:
            async with httpx.AsyncClient() as client:
                seasons_payload = await fetch_json(client, seasons_url, params)
                schedule_payload = await fetch_json(client, schedule_url, params)
                teams_payload = await fetch_json(client, teams_url, params) if teams_url else {}

                resolved_year, resolved_type = resolve_season_year_type(
                    seasons_payload, schedule_payload, season_year, season_type
                )
                team_ids = collect_team_ids(schedule_payload, teams_payload, source_api)

                team_statistics_payloads: dict[str, dict] = {}
                if (
                    resolved_year
                    and resolved_type
                    and team_ids
                    and source_api in {"nba", "gleague", "ncaa"}
                ):
                    stats_requests = [
                        (
                            team_id,
                            f"{base_url}/{locale}/seasons/{resolved_year}/{resolved_type}/teams/{team_id}/statistics.json",
                        )
                        for team_id in team_ids
                    ]
                    if stats_requests:
                        team_statistics_payloads = await fetch_many(
                            client, stats_requests, params, max_concurrency
                        )

                series_payload = None
                series_stats_payloads: dict[str, dict] = {}
                if resolved_year and resolved_type and source_api in {"nba", "gleague"}:
                    series_url = f"{base_url}/{locale}/series/{resolved_year}/{resolved_type}/schedule.json"
                    series_payload = await fetch_json(client, series_url, params)

                    series_requests = []
                    for series, _ in iter_series_entries(series_payload or {}):
                        series_id = series.get("id") or series.get("series_id")
                        if not series_id:
                            continue
                        participants = normalize_records(
                            series.get("participants")
                            or series.get("teams")
                            or series.get("competitors")
                            or series.get("contenders")
                        )
                        for team in participants:
                            team_id = team.get("id")
                            if not team_id:
                                continue
                            series_requests.append(
                                (
                                    f"{series_id}:{team_id}",
                                    f"{base_url}/{locale}/series/{series_id}/teams/{team_id}/statistics.json",
                                )
                            )
                    if series_requests:
                        series_stats_payloads = await fetch_many(
                            client, series_requests, params, max_concurrency
                        )

                return (
                    seasons_payload,
                    teams_payload,
                    schedule_payload,
                    team_statistics_payloads,
                    series_stats_payloads,
                    resolved_year,
                    resolved_type,
                )

        (
            seasons_payload,
            _teams_payload,
            _schedule_payload,
            team_statistics_payloads,
            series_stats_payloads,
            _resolved_year,
            _resolved_type,
        ) = asyncio.run(run_fetch())

        seasons_rows = extract_seasons(seasons_payload, source_api)
        season_lookup = {
            (row["season_year"], row["season_type"]): row["season_id"]
            for row in seasons_rows
            if row.get("season_year") is not None and row.get("season_type")
        }

        for payload in team_statistics_payloads.values():
            team_stat_rows, player_stat_rows = extract_team_statistics_payload(
                payload,
                source_api,
                season_lookup,
            )
            team_rows.extend(team_stat_rows)
            player_rows.extend(player_stat_rows)

        for key, payload in series_stats_payloads.items():
            series_id = key.split(":", 1)[0] if ":" in key else None
            team_stat_rows, player_stat_rows = extract_team_statistics_payload(
                payload,
                source_api,
                season_lookup,
                series_id=series_id,
            )
            team_rows.extend(team_stat_rows)
            player_rows.extend(player_stat_rows)

        team_rows = prep_team_rows(team_rows)
        player_rows = prep_player_rows(player_rows)
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    team_base, team_series, team_tournament = split_team_rows(team_rows)
    player_base, player_series, player_tournament = split_player_rows(player_rows)

    try:
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                if team_base:
                    count = upsert(
                        conn,
                        "sr.season_team_statistics",
                        team_base,
                        "(source_api, season_id, sr_team_id, is_opponent) WHERE series_id IS NULL AND tournament_id IS NULL",
                        ["source_api", "season_id", "sr_team_id", "is_opponent"],
                    )
                    tables.append({"table": "sr.season_team_statistics", "attempted": count, "success": True})
                if team_series:
                    count = upsert(
                        conn,
                        "sr.season_team_statistics",
                        team_series,
                        "(source_api, season_id, sr_team_id, series_id, is_opponent) WHERE series_id IS NOT NULL",
                        ["source_api", "season_id", "sr_team_id", "series_id", "is_opponent"],
                    )
                    tables.append({"table": "sr.season_team_statistics", "attempted": count, "success": True})
                if team_tournament:
                    count = upsert(
                        conn,
                        "sr.season_team_statistics",
                        team_tournament,
                        "(source_api, season_id, sr_team_id, tournament_id, is_opponent) WHERE tournament_id IS NOT NULL",
                        ["source_api", "season_id", "sr_team_id", "tournament_id", "is_opponent"],
                    )
                    tables.append({"table": "sr.season_team_statistics", "attempted": count, "success": True})

                if player_base:
                    count = upsert(
                        conn,
                        "sr.season_player_statistics",
                        player_base,
                        "(source_api, season_id, sr_team_id, sr_id) WHERE series_id IS NULL AND tournament_id IS NULL",
                        ["source_api", "season_id", "sr_team_id", "sr_id"],
                    )
                    tables.append({"table": "sr.season_player_statistics", "attempted": count, "success": True})
                if player_series:
                    count = upsert(
                        conn,
                        "sr.season_player_statistics",
                        player_series,
                        "(source_api, season_id, sr_team_id, sr_id, series_id) WHERE series_id IS NOT NULL",
                        ["source_api", "season_id", "sr_team_id", "sr_id", "series_id"],
                    )
                    tables.append({"table": "sr.season_player_statistics", "attempted": count, "success": True})
                if player_tournament:
                    count = upsert(
                        conn,
                        "sr.season_player_statistics",
                        player_tournament,
                        "(source_api, season_id, sr_team_id, sr_id, tournament_id) WHERE tournament_id IS NOT NULL",
                        ["source_api", "season_id", "sr_team_id", "sr_id", "tournament_id"],
                    )
                    tables.append({"table": "sr.season_player_statistics", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            if team_base:
                tables.append({"table": "sr.season_team_statistics", "attempted": len(team_base), "success": True})
            if team_series:
                tables.append({"table": "sr.season_team_statistics", "attempted": len(team_series), "success": True})
            if team_tournament:
                tables.append({"table": "sr.season_team_statistics", "attempted": len(team_tournament), "success": True})
            if player_base:
                tables.append({"table": "sr.season_player_statistics", "attempted": len(player_base), "success": True})
            if player_series:
                tables.append({"table": "sr.season_player_statistics", "attempted": len(player_series), "success": True})
            if player_tournament:
                tables.append({"table": "sr.season_player_statistics", "attempted": len(player_tournament), "success": True})
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
