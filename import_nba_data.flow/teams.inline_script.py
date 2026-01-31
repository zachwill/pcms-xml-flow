# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "typing-extensions"]
# ///
import os
import time
from datetime import datetime, timezone

import httpx
import psycopg

BASE_URL = "https://api.nba.com/v0"


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


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
    if not include_reference:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [],
        }

    try:
        with httpx.Client(timeout=30) as client:
            payload = request_json(client, "/api/stats/team/index", {"leagueId": league_id})

        teams = payload.get("teams") or payload.get("data", {}).get("teams") or []
        fetched_at = now_utc()
        rows: list[dict] = []

        for team in teams:
            team_id = team.get("teamId")
            if team_id is None:
                continue

            team_city = team.get("teamCity")
            team_name = team.get("teamName")
            team_abbreviation = team.get("teamAbbreviation")

            rows.append(
                {
                    "team_id": team_id,
                    "team_name": team_name,
                    "team_city": team_city,
                    "team_full_name": f"{team_city} {team_name}" if team_city and team_name else None,
                    "team_tricode": team_abbreviation,
                    "team_slug": team.get("teamSlug"),
                    "team_abbreviation": team_abbreviation,
                    "league_id": payload.get("leagueId") or league_id,
                    "conference": team.get("conference"),
                    "division": team.get("division"),
                    "state": team.get("teamState"),
                    "arena_name": team.get("homeArena"),
                    "arena_city": team.get("arenaCity"),
                    "arena_state": team.get("arenaState"),
                    "arena_timezone": team.get("arenaTimezone"),
                    "is_active": True,
                    "ngss_team_id": None,
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
            )

        inserted = 0
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            inserted = upsert(conn, "nba.teams", rows, ["team_id"], update_exclude=["created_at"])
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {
                    "table": "nba.teams",
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
