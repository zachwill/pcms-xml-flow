# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "typing-extensions"]
# ///
import os
import time
from datetime import datetime, timezone

import httpx
import psycopg
from psycopg.types.json import Json

BASE_URL = "https://api.nba.com/v0"


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def parse_season_year(label: str | None) -> int | None:
    if not label:
        return None
    try:
        return int(label[:4])
    except (ValueError, TypeError):
        return None


def request_json(client: httpx.Client, path: str, params: dict | None = None, retries: int = 3) -> dict:
    headers = {"X-NBA-Api-Key": os.environ["NBA_API_KEY"]}
    url = f"{BASE_URL}{path}"

    for attempt in range(retries):
        resp = client.get(url, params=params, headers=headers)
        if resp.status_code in {429, 500, 502, 503, 504}:
            if attempt == retries - 1:
                resp.raise_for_status()
            time.sleep(1 + attempt)
            continue
        resp.raise_for_status()
        return resp.json()

    raise RuntimeError(f"Failed to fetch {url}")


def upsert(conn: psycopg.Connection, table: str, rows: list[dict], conflict_keys: list[str], update_exclude: list[str] | None = None) -> int:
    if not rows:
        return 0
    update_exclude = update_exclude or []
    cols = list(rows[0].keys())
    update_cols = [c for c in cols if c not in conflict_keys and c not in update_exclude]

    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)
    conflict = ", ".join(conflict_keys)

    if update_cols:
        updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])
        sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO UPDATE SET {updates}"
    else:
        sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO NOTHING"

    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(r[c] for c in cols) for r in rows])
    conn.commit()
    return len(rows)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(
    dry_run: bool = False,
    league_id: str = "00",
    season_label: str | None = None,
    season_type: str | None = None,
    mode: str | None = None,
    days_back: int | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    game_ids: str | None = None,
    include_reference: bool = True,
    include_schedule_and_standings: bool = True,
    include_games: bool = True,
    include_game_data: bool = True,
    include_aggregates: bool = False,
    include_supplemental: bool = False,
    only_final_games: bool = True,
) -> dict:
    started_at = now_utc()
    if not include_schedule_and_standings:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [],
        }

    try:
        today = now_utc().date().isoformat()
        season_calendar = None
        full_schedule = None
        broadcasters = None

        with httpx.Client(timeout=30) as client:
            season_calendar = request_json(
                client,
                "/api/schedule/seasoncalendar",
                {"leagueId": league_id, "gameDate": today},
            )

            if season_label:
                full_schedule = request_json(
                    client,
                    "/api/schedule/full",
                    {"leagueId": league_id, "season": season_label},
                )
                broadcasters = request_json(
                    client,
                    "/api/schedule/broadcasters",
                    {"leagueId": league_id, "season": season_label},
                )

        season_label_value = season_label or season_calendar.get("statsSeasonYear")
        season_year = parse_season_year(season_label_value)
        weeks_json = None
        if full_schedule:
            weeks_json = full_schedule.get("leagueSchedule", {}).get("weeks")

        fetched_at = now_utc()
        rows = [
            {
                "season_year": season_year,
                "season_label": season_label_value,
                "league_id": league_id,
                "stats_season_id": season_calendar.get("statsSeasonId"),
                "roster_season_id": season_calendar.get("rosterSeasonId"),
                "schedule_season_id": season_calendar.get("scheduleSeasonId"),
                "standings_season_id": season_calendar.get("standingsSeasonId"),
                "ngss_season_id": None,
                "weeks_json": Json(weeks_json) if weeks_json is not None else None,
                "full_schedule_json": Json(full_schedule) if full_schedule is not None else None,
                "broadcasters_json": Json(broadcasters) if broadcasters is not None else None,
                "season_calendar_json": Json(season_calendar) if season_calendar is not None else None,
                "created_at": fetched_at,
                "updated_at": fetched_at,
                "fetched_at": fetched_at,
            }
        ]

        inserted = 0
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            inserted = upsert(conn, "nba.schedules", rows, ["season_year", "league_id"], update_exclude=["created_at"])
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {
                    "table": "nba.schedules",
                    "rows": len(rows),
                    "upserted": inserted,
                }
            ],
            "errors": [],
        }
    except Exception as exc:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [str(exc)],
        }


if __name__ == "__main__":
    main()
