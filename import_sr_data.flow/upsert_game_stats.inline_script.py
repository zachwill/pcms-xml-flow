# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx", "psycopg[binary]", "typing-extensions"]
# ///
"""
Upsert sr.game_team_stats, sr.game_player_stats, sr.game_period_scores from SportRadar API.
"""
import asyncio
import os
from datetime import datetime

import httpx
import psycopg

from sr_extract import (
    extract_game_id,
    extract_period_scores,
    extract_player_stats,
    extract_schedule_games,
    extract_team_stats,
)
from sr_fetch import (
    FetchError,
    build_schedule_url,
    fetch_json,
    fetch_many,
    get_api_key,
    get_base_url,
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


def minutes_to_seconds(value: str | None) -> int | None:
    if not value or ":" not in value:
        return None
    try:
        minutes, seconds = value.split(":")
        return int(minutes) * 60 + int(seconds)
    except (ValueError, TypeError):
        return None


def ensure_fg2_fields(row: dict) -> None:
    if row.get("fg2m") is None and row.get("fgm") is not None and row.get("fg3m") is not None:
        row["fg2m"] = row.get("fgm") - row.get("fg3m")
    if row.get("fg2a") is None and row.get("fga") is not None and row.get("fg3a") is not None:
        row["fg2a"] = row.get("fga") - row.get("fg3a")
    if row.get("fg2_pct") is None and row.get("fg2m") is not None and row.get("fg2a"):
        try:
            row["fg2_pct"] = round(float(row.get("fg2m")) / float(row.get("fg2a")), 4)
        except (TypeError, ValueError, ZeroDivisionError):
            row["fg2_pct"] = None


def prep_team_stats(rows: list[dict]) -> list[dict]:
    filtered = []
    for row in rows:
        if not row.get("source_api") or not row.get("game_id") or not row.get("sr_team_id"):
            continue
        ensure_fg2_fields(row)
        filtered.append(row)
    return filtered


def prep_player_stats(rows: list[dict]) -> list[dict]:
    filtered = []
    for row in rows:
        if not row.get("source_api") or not row.get("game_id") or not row.get("sr_id"):
            continue
        if row.get("seconds_played") is None:
            row["seconds_played"] = minutes_to_seconds(row.get("minutes"))
        ensure_fg2_fields(row)
        filtered.append(row)
    return filtered


def prep_period_scores(rows: list[dict]) -> list[dict]:
    return [
        row
        for row in rows
        if row.get("source_api")
        and row.get("game_id")
        and row.get("sr_team_id")
        and row.get("period_number") is not None
        and row.get("period_type")
    ]


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
    period_rows: list[dict] = []

    try:
        base_url = get_base_url(source_api)
        api_key = get_api_key()
        schedule_url, _ = build_schedule_url(base_url, locale, mode, date, season_year, season_type)
        params = {"api_key": api_key}

        async def run_fetch() -> dict[str, dict]:
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
                if not summary_requests:
                    return {}
                return await fetch_many(client, summary_requests, params, max_concurrency)

        summaries = asyncio.run(run_fetch())
        for game_id, summary in summaries.items():
            home_team = summary.get("home")
            away_team = summary.get("away")
            team_rows.extend(extract_team_stats(summary, source_api, game_id, home_team, away_team))
            player_rows.extend(extract_player_stats(summary, source_api, game_id, home_team))
            player_rows.extend(extract_player_stats(summary, source_api, game_id, away_team))
            period_rows.extend(
                extract_period_scores(
                    summary,
                    source_api,
                    game_id,
                    (home_team or {}).get("id"),
                    (away_team or {}).get("id"),
                )
            )

        team_rows = prep_team_stats(team_rows)
        player_rows = prep_player_stats(player_rows)
        period_rows = prep_period_scores(period_rows)
    except FetchError as exc:
        errors.append(str(exc))
    except Exception as exc:  # pragma: no cover - safety
        errors.append(str(exc))

    try:
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "sr.game_team_stats", team_rows, ["source_api", "game_id", "sr_team_id"])
                tables.append({"table": "sr.game_team_stats", "attempted": count, "success": True})

                count = upsert(conn, "sr.game_player_stats", player_rows, ["source_api", "game_id", "sr_id"])
                tables.append({"table": "sr.game_player_stats", "attempted": count, "success": True})

                count = upsert(
                    conn,
                    "sr.game_period_scores",
                    period_rows,
                    ["source_api", "game_id", "sr_team_id", "period_number", "period_type"],
                )
                tables.append({"table": "sr.game_period_scores", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "sr.game_team_stats", "attempted": len(team_rows), "success": True})
            tables.append({"table": "sr.game_player_stats", "attempted": len(player_rows), "success": True})
            tables.append({"table": "sr.game_period_scores", "attempted": len(period_rows), "success": True})
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
