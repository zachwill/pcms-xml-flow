# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import hashlib
import json
import os
import re
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


def normalize_season_type(value: str | None) -> str:
    if not value:
        return ""

    normalized = " ".join(str(value).strip().lower().replace("-", " ").split())
    aliases = {
        "regular": "regular season",
        "regular season": "regular season",
        "pre season": "pre season",
        "preseason": "pre season",
        "playoff": "playoffs",
        "playoffs": "playoffs",
        "play in": "playin",
        "playin": "playin",
        "all star": "all star",
    }
    return aliases.get(normalized, normalized)


def parse_datetime(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        try:
            return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        except ValueError:
            return None


def parse_season_year(label: str | None) -> int | None:
    if not label:
        return None
    try:
        return int(str(label)[:4])
    except (ValueError, TypeError):
        return None


def parse_int(value):
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (ValueError, TypeError):
        try:
            return int(float(value))
        except (ValueError, TypeError):
            return None


def parse_bool(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(int(value))
    text = str(value).strip().lower()
    if text in {"1", "true", "t", "y", "yes"}:
        return True
    if text in {"0", "false", "f", "n", "no"}:
        return False
    return None


def empty_to_none(value):
    if value is None:
        return None
    if isinstance(value, str):
        text = value.strip()
        return text if text != "" else None
    return value


def parse_coach_is_assistant(assistant_role_code: int | None, coach_type: str | None) -> bool | None:
    if coach_type:
        lowered = str(coach_type).strip().lower()
        if "assistant" in lowered:
            return True

    if assistant_role_code is None:
        return None

    if assistant_role_code in {2, 4, 9, 12, 13}:
        return True
    if assistant_role_code in {1, 3, 5, 10, 15}:
        return False
    return None


def stable_hash(payload: dict) -> str:
    return hashlib.sha1(json.dumps(payload, sort_keys=True, default=str).encode()).hexdigest()


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


def resolve_season_date_range(season_label: str | None) -> tuple[date, date]:
    if not season_label:
        raise ValueError("season_backfill mode requires season_label")

    text = str(season_label).strip()
    try:
        start_year = int(text[:4])
    except (TypeError, ValueError):
        raise ValueError("season_label must look like YYYY-YY (e.g. 2024-25)")

    end_year = start_year + 1
    if "-" in text:
        suffix = text.split("-", 1)[1].strip()
        if suffix:
            if len(suffix) == 2 and suffix.isdigit():
                century = start_year // 100
                end_year = century * 100 + int(suffix)
                if end_year < start_year:
                    end_year += 100
            else:
                try:
                    end_year = int(suffix)
                except ValueError:
                    end_year = start_year + 1

    start = date(start_year, 9, 1)
    end = date(end_year, 7, 31)
    today = now_utc().date()
    if end > today:
        end = today
    return start, end


def resolve_date_range(
    mode: str,
    days_back: int,
    start_date: str | None,
    end_date: str | None,
    season_label: str | None,
) -> tuple[date, date]:
    if start_date or end_date:
        if not (start_date and end_date):
            raise ValueError("start_date and end_date must both be provided")
        start = parse_date(start_date)
        end = parse_date(end_date)
        if not start or not end:
            raise ValueError("start_date/end_date must be YYYY-MM-DD")
        return start, end

    normalized_mode = (mode or "refresh").strip().lower()

    if normalized_mode == "refresh":
        today = now_utc().date()
        start = today - timedelta(days=days_back or 2)
        return start, today

    if normalized_mode in {"backfill", "date_backfill"}:
        raise ValueError("date_backfill mode requires start_date and end_date (or game_ids)")

    if normalized_mode == "season_backfill":
        return resolve_season_date_range(season_label)

    raise ValueError("mode must be one of: refresh, date_backfill, season_backfill")


def extract_alerts(payload) -> list[dict]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]

    if isinstance(payload, dict):
        for key in ["alerts", "topAlerts", "topNAlerts", "items", "alertList"]:
            value = payload.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]

        # Common shape for /api/alerts/topNAlerts:
        # {"Alert1": {...}, "Alert2": {...}, ...}
        keyed_alerts: list[tuple[int, str, dict]] = []
        for key, value in payload.items():
            if not (isinstance(key, str) and key.lower().startswith("alert") and isinstance(value, dict)):
                continue
            match = re.search(r"(\d+)$", key)
            rank = int(match.group(1)) if match else 999
            item = dict(value)
            item.setdefault("_rank", rank)
            keyed_alerts.append((rank, key, item))

        if keyed_alerts:
            keyed_alerts.sort(key=lambda row: (row[0], row[1]))
            return [row[2] for row in keyed_alerts]

        # Single-alert object fallback
        if any(k in payload for k in ["alert", "alertType", "alertText"]):
            return [payload]

    return []


def build_alert_id(alert: dict, game_id: str | None):
    alert_id = alert.get("alertId") or alert.get("id") or alert.get("alert_id")
    if alert_id:
        return str(alert_id)
    payload = {"game_id": game_id, "alert": alert}
    return hashlib.sha1(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def infer_team_id_from_text(text: str | None, game_context: dict | None) -> int | None:
    if not text or not game_context:
        return None

    text_upper = str(text).upper()
    matches: list[tuple[int, int]] = []
    for side in ["home", "away"]:
        team_id = parse_int(game_context.get(f"{side}_team_id"))
        tricode = game_context.get(f"{side}_team_tricode")
        if team_id is None or not tricode:
            continue

        pattern = rf"\b{re.escape(str(tricode).upper())}\b"
        found = re.search(pattern, text_upper)
        if found:
            matches.append((found.start(), team_id))

    if not matches:
        return None
    matches.sort(key=lambda row: row[0])
    return matches[0][1]


def extract_storylines(payload: dict) -> list[dict]:
    storylines: list[dict] = []
    if not isinstance(payload, dict):
        return storylines

    for key in ["homeTeamStorylines", "awayTeamStorylines", "storylines", "pregameStorylines"]:
        value = payload.get(key)
        if isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    storylines.append(item)
                elif item is not None:
                    storylines.append({"storylineText": str(item)})

    stories = payload.get("stories")
    if isinstance(stories, list):
        for item in stories:
            if isinstance(item, dict):
                storylines.append(item)
            elif item is not None:
                storylines.append({"storylineText": str(item)})

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
) -> dict:
    started_at = now_utc()

    try:
        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        fetched_at = now_utc()
        tables = []

        season_year = parse_season_year(season_label)
        desired_season_type = normalize_season_type(season_type)

        # Team roster snapshots (players + coaches)
        roster_player_rows: list[dict] = []
        roster_coach_rows: list[dict] = []
        team_ids: list[int] = []
        if season_label:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT team_id
                    FROM nba.teams
                    WHERE (%s::text IS NULL OR league_id = %s)
                    ORDER BY team_id
                    """,
                    (league_id, league_id),
                )
                team_ids = [row[0] for row in cur.fetchall()]

            with httpx.Client(timeout=30) as client:
                for team_id in team_ids:
                    payload = request_json(
                        client,
                        "/api/stats/team/roster",
                        {
                            "leagueId": league_id,
                            "season": season_label,
                            "teamId": team_id,
                        },
                    )
                    for player in payload.get("players") or []:
                        nba_id = parse_int(player.get("playerId"))
                        if nba_id is None:
                            continue
                        roster_player_rows.append(
                            {
                                "league_id": payload.get("leagueId") or league_id,
                                "season_year": parse_season_year(payload.get("season") or season_label) or season_year,
                                "season_label": payload.get("season") or season_label,
                                "team_id": parse_int(payload.get("teamId")) or team_id,
                                "team_city": payload.get("teamCity"),
                                "team_name": payload.get("teamName"),
                                "team_tricode": payload.get("teamTricode") or payload.get("teamAbbreviation"),
                                "nba_id": nba_id,
                                "player_name": player.get("playerName"),
                                "player_slug": player.get("playerSlug"),
                                "jersey_num": player.get("jerseyNum"),
                                "position": player.get("position"),
                                "height": player.get("height"),
                                "weight": player.get("weight"),
                                "birthdate": parse_date(player.get("birthdate")),
                                "age": parse_int(player.get("age")),
                                "season_experience": player.get("seasonExperience"),
                                "school": player.get("school"),
                                "is_two_way": parse_bool(player.get("isTwoWay")),
                                "is_ten_day": parse_bool(player.get("isTenDay")),
                                "roster_json": Json(player),
                                "created_at": fetched_at,
                                "updated_at": fetched_at,
                                "fetched_at": fetched_at,
                            }
                        )

                    for coach in payload.get("coaches") or []:
                        coach_id = parse_int(coach.get("coachId"))
                        if coach_id is None:
                            continue

                        assistant_role_code = parse_int(coach.get("isAssistant"))
                        coach_type = coach.get("coachType")

                        roster_coach_rows.append(
                            {
                                "league_id": payload.get("leagueId") or league_id,
                                "season_year": parse_season_year(payload.get("season") or season_label) or season_year,
                                "season_label": payload.get("season") or season_label,
                                "team_id": parse_int(payload.get("teamId")) or team_id,
                                "team_city": payload.get("teamCity"),
                                "team_name": payload.get("teamName"),
                                "team_tricode": payload.get("teamTricode") or payload.get("teamAbbreviation"),
                                "coach_id": coach_id,
                                "coach_name": coach.get("coachName"),
                                "coach_type": coach_type,
                                "assistant_role_code": assistant_role_code,
                                "is_assistant": parse_coach_is_assistant(assistant_role_code, coach_type),
                                "sort_sequence": parse_int(coach.get("sortSequence")),
                                "coach_json": Json(coach),
                                "created_at": fetched_at,
                                "updated_at": fetched_at,
                                "fetched_at": fetched_at,
                            }
                        )

            if not dry_run:
                if roster_player_rows:
                    upsert(
                        conn,
                        "nba.team_roster_players",
                        roster_player_rows,
                        ["league_id", "season_label", "team_id", "nba_id"],
                        update_exclude=["created_at"],
                    )
                if roster_coach_rows:
                    upsert(
                        conn,
                        "nba.team_roster_coaches",
                        roster_coach_rows,
                        ["league_id", "season_label", "team_id", "coach_id"],
                        update_exclude=["created_at"],
                    )

        tables.append({"table": "nba.team_roster_players", "rows": len(roster_player_rows)})
        tables.append({"table": "nba.team_roster_coaches", "rows": len(roster_coach_rows)})

        # Injuries: keep current snapshot table + additive status history
        with httpx.Client(timeout=30) as client:
            injury_payload = request_json(client, "/api/stats/injury", {"leagueId": league_id})
        injuries = injury_payload.get("players") or []
        injury_rows = []
        for player in injuries:
            nba_id = parse_int(player.get("personId"))
            team_id = parse_int(player.get("teamId"))
            if nba_id is None or team_id is None:
                continue
            injury_rows.append(
                {
                    "nba_id": nba_id,
                    "team_id": team_id,
                    "injury_status": empty_to_none(player.get("injuryStatus")),
                    "injury_type": empty_to_none(player.get("injuryType")),
                    "injury_location": empty_to_none(player.get("injuryLocation")),
                    "injury_details": empty_to_none(player.get("injuryDetails")),
                    "injury_side": empty_to_none(player.get("injurySide")),
                    "return_date": empty_to_none(player.get("returnDate")),
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
            )

        with conn.cursor() as cur:
            cur.execute("SELECT nba_id FROM nba.players")
            valid_player_ids = {row[0] for row in cur.fetchall()}
            cur.execute("SELECT team_id FROM nba.teams")
            valid_team_ids = {row[0] for row in cur.fetchall()}

        injury_rows = [
            row for row in injury_rows
            if row["nba_id"] in valid_player_ids and row["team_id"] in valid_team_ids
        ]

        injury_history_rows: list[dict] = []
        for row in injury_rows:
            status_payload = {
                "injury_status": row.get("injury_status"),
                "injury_type": row.get("injury_type"),
                "injury_location": row.get("injury_location"),
                "injury_details": row.get("injury_details"),
                "injury_side": row.get("injury_side"),
                "return_date": row.get("return_date"),
            }
            injury_history_rows.append(
                {
                    "nba_id": row["nba_id"],
                    "team_id": row["team_id"],
                    "status_hash": stable_hash(status_payload),
                    "injury_status": row.get("injury_status"),
                    "injury_type": row.get("injury_type"),
                    "injury_location": row.get("injury_location"),
                    "injury_details": row.get("injury_details"),
                    "injury_side": row.get("injury_side"),
                    "return_date": row.get("return_date"),
                    "first_seen_at": fetched_at,
                    "last_seen_at": fetched_at,
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
            )

        if not dry_run:
            with conn.cursor() as cur:
                cur.execute("CREATE TEMP TABLE _injury_keys (nba_id integer, team_id integer) ON COMMIT DROP")
                if injury_rows:
                    cur.executemany(
                        "INSERT INTO _injury_keys (nba_id, team_id) VALUES (%s, %s)",
                        [(row["nba_id"], row["team_id"]) for row in injury_rows],
                    )
                cur.execute(
                    """
                    DELETE FROM nba.injuries i
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM _injury_keys k
                        WHERE k.nba_id = i.nba_id
                          AND k.team_id = i.team_id
                    )
                    """
                )
            conn.commit()

            if injury_rows:
                upsert(conn, "nba.injuries", injury_rows, ["nba_id", "team_id"], update_exclude=["created_at"])
            if injury_history_rows:
                upsert(
                    conn,
                    "nba.injuries_history",
                    injury_history_rows,
                    ["nba_id", "team_id", "status_hash"],
                    update_exclude=["created_at", "first_seen_at"],
                )

        tables.append({"table": "nba.injuries", "rows": len(injury_rows)})
        tables.append({"table": "nba.injuries_history", "rows": len(injury_history_rows)})

        # Game data status log (incremental freshness + correction tracking)
        with httpx.Client(timeout=30) as client:
            status_payload = request_json(client, "/api/stats/gamedatastatuslog", {"leagueId": league_id})

        status_rows: list[dict] = []
        season_year_status = status_payload.get("seasonYear")
        for game in status_payload.get("games") or []:
            game_id_value = game.get("gameId")
            if not game_id_value:
                continue
            status_snapshot = {
                "last_update_game_schedule": game.get("lastUpdateGameSchedule"),
                "last_update_game_stats": game.get("lastUpdateGameStats"),
                "last_update_game_tracking": game.get("lastUpdateGameTracking"),
            }
            status_rows.append(
                {
                    "league_id": status_payload.get("leagueId") or league_id,
                    "season_year": season_year_status or "",
                    "game_id": str(game_id_value),
                    "status_hash": stable_hash(status_snapshot),
                    "generated_time": status_payload.get("time"),
                    "generated_time_utc": parse_datetime(status_payload.get("timeUTC")),
                    "last_update_season_stats": parse_datetime(status_payload.get("lastUpdateSeasonStats")),
                    "last_update_season_stats_utc": parse_datetime(status_payload.get("lastUpdateSeasonStatsUTC")),
                    "home_team_id": parse_int(game.get("homeTeamId")),
                    "visitor_team_id": parse_int(game.get("visitorTeamId")),
                    "game_date_est": parse_date(game.get("dateEst")),
                    "game_time_est": game.get("timeEst"),
                    "last_update_game_schedule": parse_datetime(game.get("lastUpdateGameSchedule")),
                    "last_update_game_stats": parse_datetime(game.get("lastUpdateGameStats")),
                    "last_update_game_tracking": parse_datetime(game.get("lastUpdateGameTracking")),
                    "first_seen_at": fetched_at,
                    "last_seen_at": fetched_at,
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
            )

        if not dry_run and status_rows:
            upsert(
                conn,
                "nba.game_data_status_log",
                status_rows,
                ["league_id", "season_year", "game_id", "status_hash"],
                update_exclude=["created_at", "first_seen_at"],
            )

        tables.append({"table": "nba.game_data_status_log", "rows": len(status_rows)})

        # Alerts + Pregame storylines (per game)
        game_list: list[str] = []
        if game_ids:
            game_list = [gid.strip() for gid in game_ids.split(",") if gid.strip()]
        else:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date, season_label)
            season_label_filter = season_label or None
            query = """
                SELECT game_id, season_type
                FROM nba.games
                WHERE game_date BETWEEN %s AND %s
                  AND league_id = %s
                  AND (%s::text IS NULL OR season_label = %s)
                ORDER BY game_date, game_id
            """
            with conn.cursor() as cur:
                cur.execute(query, (start_dt, end_dt, league_id, season_label_filter, season_label_filter))
                game_rows = cur.fetchall()

            if desired_season_type:
                game_rows = [
                    (game_id_value, game_season_type)
                    for game_id_value, game_season_type in game_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                ]

            game_list = [row[0] for row in game_rows]

        game_context_by_id: dict[str, dict] = {}
        if game_list:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT g.game_id,
                           g.home_team_id,
                           g.away_team_id,
                           ht.team_tricode AS home_team_tricode,
                           at.team_tricode AS away_team_tricode
                    FROM nba.games g
                    LEFT JOIN nba.teams ht ON ht.team_id = g.home_team_id
                    LEFT JOIN nba.teams at ON at.team_id = g.away_team_id
                    WHERE g.game_id = ANY(%s)
                    """,
                    (game_list,),
                )
                for game_id_value, home_team_id, away_team_id, home_team_tricode, away_team_tricode in cur.fetchall():
                    game_context_by_id[str(game_id_value)] = {
                        "home_team_id": home_team_id,
                        "away_team_id": away_team_id,
                        "home_team_tricode": home_team_tricode,
                        "away_team_tricode": away_team_tricode,
                    }

        alert_rows: list[dict] = []
        storyline_rows: list[dict] = []
        with httpx.Client(timeout=30) as client:
            for game_id_value in game_list:
                game_context = game_context_by_id.get(str(game_id_value))

                alerts_payload = request_json(
                    client,
                    "/api/alerts/topNAlerts",
                    {"gameId": game_id_value, "alertCount": 10},
                )
                for alert in extract_alerts(alerts_payload):
                    alert_text = (
                        alert.get("alertText")
                        or alert.get("alert")
                        or alert.get("text")
                        or alert.get("description")
                    )
                    team_id = parse_int(alert.get("teamId") or alert.get("team_id"))
                    if team_id is None:
                        team_id = infer_team_id_from_text(alert_text, game_context)

                    alert_rows.append(
                        {
                            "alert_id": build_alert_id(alert, game_id_value),
                            "game_id": str(alert.get("gameId") or game_id_value),
                            "team_id": team_id,
                            "alert_type": alert.get("alertType") or alert.get("type"),
                            "alert_text": alert_text,
                            "alert_priority": parse_int(alert.get("alertPriority") or alert.get("priority") or alert.get("_rank")),
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
                    storyline_text = storyline.get("storylineText") or storyline.get("text") or storyline.get("storyline")
                    if not storyline_text:
                        continue

                    team_id = parse_int(storyline.get("teamId") or storyline.get("team_id"))
                    if team_id is None:
                        team_id = infer_team_id_from_text(storyline_text, game_context)
                    if team_id is None:
                        continue

                    storyline_rows.append(
                        {
                            "game_id": str(game_id_value),
                            "team_id": team_id,
                            "storyline_text": storyline_text,
                            "storyline_order": parse_int(storyline.get("storylineOrder")) or idx,
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
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date, season_label)
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

        filtered_stream_rows = stream_rows
        stream_game_ids = list({row.get("game_id") for row in stream_rows if row.get("game_id")})
        if stream_game_ids:
            season_label_filter = season_label or None
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT game_id, season_type
                    FROM nba.games
                    WHERE game_id = ANY(%s)
                      AND league_id = %s
                      AND (%s::text IS NULL OR season_label = %s)
                    """,
                    (stream_game_ids, league_id, season_label_filter, season_label_filter),
                )
                stream_game_rows = cur.fetchall()

            if desired_season_type:
                allowed_game_ids = {
                    game_id_value
                    for game_id_value, game_season_type in stream_game_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                }
            else:
                allowed_game_ids = {game_id_value for game_id_value, _ in stream_game_rows}

            filtered_stream_rows = [
                row
                for row in stream_rows
                if row.get("game_id") is None or row.get("game_id") in allowed_game_ids
            ]

        if not dry_run:
            upsert(conn, "nba.tracking_streams", filtered_stream_rows, ["stream_id"], update_exclude=["created_at"])

        tables.append({"table": "nba.tracking_streams", "rows": len(filtered_stream_rows)})

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
