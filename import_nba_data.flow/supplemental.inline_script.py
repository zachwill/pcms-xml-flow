# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "typing-extensions"]
# ///
import hashlib
import json
import os
import time
from datetime import datetime, timezone, timedelta, date

import httpx
import psycopg
from psycopg.types.json import Json

BASE_URL = "https://api.nba.com/v0"
TRACKING_URL = "https://api.nba.com/v0/api/tracking"


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def parse_date(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        try:
            return datetime.strptime(value, "%Y-%m-%d").date()
        except ValueError:
            return None


def parse_datetime(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def request_json(client: httpx.Client, path: str, params: dict | None = None, retries: int = 3, base_url: str = BASE_URL) -> dict:
    headers = {"X-NBA-Api-Key": os.environ["NBA_API_KEY"]}
    url = f"{base_url}{path}"

    for attempt in range(retries):
        resp = client.get(url, params=params, headers=headers)
        if resp.status_code in {429, 500, 502, 503, 504}:
            if attempt == retries - 1:
                resp.raise_for_status()
            time.sleep(1 + attempt)
            continue
        if resp.status_code == 404:
            return {}
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


def resolve_date_range(mode: str, days_back: int, start_date: str | None, end_date: str | None) -> tuple[date, date]:
    if start_date and end_date:
        return parse_date(start_date), parse_date(end_date)

    if mode == "refresh":
        today = now_utc().date()
        start = today - timedelta(days=days_back or 2)
        return start, today

    raise ValueError("backfill mode requires start_date and end_date (or game_ids)")


def extract_alerts(payload) -> list[dict]:
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ["alerts", "topAlerts", "topNAlerts", "items", "alertList"]:
            value = payload.get(key)
            if isinstance(value, list):
                return value
    return []


def build_alert_id(alert: dict, game_id: str | None):
    alert_id = alert.get("alertId") or alert.get("id") or alert.get("alert_id")
    if alert_id:
        return str(alert_id)
    payload = {"game_id": game_id, "alert": alert}
    return hashlib.sha1(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def extract_storylines(payload: dict) -> list[dict]:
    storylines: list[dict] = []
    if not isinstance(payload, dict):
        return storylines

    for key in ["homeTeamStorylines", "awayTeamStorylines", "storylines", "pregameStorylines"]:
        value = payload.get(key)
        if isinstance(value, list):
            storylines.extend(value)

    return storylines


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(
    dry_run: bool = False,
    league_id: str = "00",
    season_label: str | None = None,
    season_type: str | None = None,
    mode: str = "refresh",
    days_back: int = 2,
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
    if not include_supplemental:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [],
        }

    try:
        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        fetched_at = now_utc()
        tables = []

        # Injuries (snapshot table)
        with httpx.Client(timeout=30) as client:
            injury_payload = request_json(client, "/api/stats/injury", {"leagueId": league_id})
        injuries = injury_payload.get("players") or []
        injury_rows = []
        for player in injuries:
            nba_id = player.get("personId")
            team_id = player.get("teamId")
            if nba_id is None or team_id is None:
                continue
            injury_rows.append(
                {
                    "nba_id": nba_id,
                    "team_id": team_id,
                    "injury_status": player.get("injuryStatus"),
                    "injury_type": player.get("injuryType"),
                    "injury_location": player.get("injuryLocation"),
                    "injury_details": player.get("injuryDetails"),
                    "injury_side": player.get("injurySide"),
                    "return_date": player.get("returnDate"),
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
            )

        if not dry_run:
            with conn.cursor() as cur:
                cur.execute("TRUNCATE nba.injuries")
            conn.commit()
            upsert(conn, "nba.injuries", injury_rows, ["nba_id", "team_id"], update_exclude=["created_at"])
        tables.append({"table": "nba.injuries", "rows": len(injury_rows)})

        # Alerts + Pregame storylines (per game)
        game_list: list[str] = []
        if game_ids:
            game_list = [gid.strip() for gid in game_ids.split(",") if gid.strip()]
        else:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date)
            query = """
                SELECT game_id
                FROM nba.games
                WHERE game_date BETWEEN %s AND %s
                ORDER BY game_date, game_id
            """
            with conn.cursor() as cur:
                cur.execute(query, (start_dt, end_dt))
                game_list = [row[0] for row in cur.fetchall()]

        alert_rows: list[dict] = []
        storyline_rows: list[dict] = []
        with httpx.Client(timeout=30) as client:
            for game_id_value in game_list:
                alerts_payload = request_json(
                    client,
                    "/api/alerts/topNAlerts",
                    {"gameId": game_id_value, "alertCount": 10},
                )
                for alert in extract_alerts(alerts_payload):
                    alert_rows.append(
                        {
                            "alert_id": build_alert_id(alert, game_id_value),
                            "game_id": alert.get("gameId") or game_id_value,
                            "team_id": alert.get("teamId"),
                            "alert_type": alert.get("alertType") or alert.get("type"),
                            "alert_text": alert.get("alertText") or alert.get("text") or alert.get("description"),
                            "alert_priority": alert.get("alertPriority") or alert.get("priority"),
                            "alert_json": Json(alert),
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                    )

                story_payload = request_json(
                    client,
                    "/api/alerts/topNPregameStorylines",
                    {"gameId": game_id_value, "storylineCount": 10},
                )
                storylines = extract_storylines(story_payload)
                for idx, storyline in enumerate(storylines, start=1):
                    team_id = storyline.get("teamId") or storyline.get("team_id")
                    if team_id is None:
                        continue
                    storyline_rows.append(
                        {
                            "game_id": game_id_value,
                            "team_id": team_id,
                            "storyline_text": storyline.get("storylineText") or storyline.get("text"),
                            "storyline_order": storyline.get("storylineOrder") or idx,
                            "storyline_json": Json(storyline),
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                    )

        if not dry_run:
            upsert(conn, "nba.alerts", alert_rows, ["alert_id"], update_exclude=["created_at"])
            upsert(conn, "nba.pregame_storylines", storyline_rows, ["game_id", "team_id", "storyline_order"], update_exclude=["created_at"])

        tables.append({"table": "nba.alerts", "rows": len(alert_rows)})
        tables.append({"table": "nba.pregame_storylines", "rows": len(storyline_rows)})

        # Tracking streams
        with httpx.Client(timeout=30) as client:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date)
            streams_payload = request_json(
                client,
                "/game_streams",
                {
                    "from_date": start_dt.isoformat(),
                    "to_date": end_dt.isoformat(),
                },
                base_url=TRACKING_URL,
            )

        streams = streams_payload.get("game_streams") or []
        stream_rows = []
        for stream in streams:
            stream_id = stream.get("stream_id")
            if not stream_id:
                continue
            game_info = stream.get("game_info") or {}
            stream_rows.append(
                {
                    "stream_id": stream_id,
                    "game_id": stream.get("game_id"),
                    "stream_name": stream.get("stream_name"),
                    "processor_name": stream.get("processor_name"),
                    "status": stream.get("status"),
                    "stream_created_at": parse_datetime(game_info.get("game_start_time")),
                    "expires_at": None,
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
            )

        if not dry_run:
            upsert(conn, "nba.tracking_streams", stream_rows, ["stream_id"], update_exclude=["created_at"])

        tables.append({"table": "nba.tracking_streams", "rows": len(stream_rows)})

        conn.close()
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": tables,
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
