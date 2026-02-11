# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import os
import time
from datetime import datetime, timezone, timedelta, date, time as dt_time

import httpx
import psycopg
from psycopg.types.json import Json


NGSS_BASE_URL = "https://api.ngss.nba.com:10000"

SEASON_TYPE_MAP = {
    "All": 0,
    "PreSeason": 1,
    "Regular": 2,
    "Playoff": 3,
    "AllStar": 4,
    "Exhibition": 5,
}

GAME_STATUS_MAP = {
    "Bye": 0,
    "Scheduled": 1,
    "Inprogress": 2,
    "Finished": 3,
    "Postponed": 4,
    "Cancelled": 5,
    "Suspended": 6,
}

WINNER_MAP = {
    "None": 0,
    "Home": 1,
    "Away": 2,
}


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def parse_datetime(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_date(value: str | None):
    if not value:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    dt = parse_datetime(value)
    if dt:
        return dt.date()
    try:
        return datetime.strptime(str(value), "%Y-%m-%d").date()
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


def parse_time(value: str | None):
    if not value:
        return None
    if isinstance(value, dt_time):
        return value
    if isinstance(value, datetime):
        return value.time()
    text = str(value).strip()
    if "T" in text:
        dt = parse_datetime(text)
        if dt:
            return dt.time()
    text = text.replace("Z", "")
    parts = text.split()
    if len(parts) > 2 and parts[-1].isalpha():
        text = " ".join(parts[:-1])
    try:
        return dt_time.fromisoformat(text)
    except ValueError:
        for fmt in ["%H:%M", "%H:%M:%S", "%I:%M %p", "%I:%M:%S %p"]:
            try:
                return datetime.strptime(text, fmt).time()
            except ValueError:
                continue
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


def unwrap_data(payload):
    if isinstance(payload, dict) and "data" in payload:
        data = payload.get("data")
        if data is not None:
            return data
    return payload


def get_field(payload: dict | None, *keys: str):
    if not isinstance(payload, dict):
        return None
    for key in keys:
        value = payload.get(key)
        if value not in (None, ""):
            return value
    return None


def normalize_enum_token(value: str) -> str:
    return "".join(ch for ch in str(value) if ch.isalnum()).lower()


def parse_enum_int(value, mapping: dict[str, int]):
    if value is None or value == "":
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        if value.isdigit():
            return int(value)

        token = normalize_enum_token(value)
        for key, mapped in mapping.items():
            if normalize_enum_token(key) == token:
                return mapped

    return None


def parse_yes_no(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    text = str(value).strip()
    if text.isdigit():
        return bool(int(text))
    if text.lower() in {"yes", "y", "true"}:
        return True
    if text.lower() in {"no", "n", "false"}:
        return False
    return None


def to_bool(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "y"}:
        return True
    if text in {"false", "0", "no", "n"}:
        return False
    return None


def normalize_memos(value):
    if value is None:
        return None
    if isinstance(value, list):
        return value
    return [str(value)]


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


def request_json(
    client: httpx.Client,
    path: str,
    params: dict | None = None,
    retries: int = 3,
    base_url: str | None = None,
    api_key: str | None = None,
) -> dict | list:
    if not api_key:
        raise ValueError("NGSS_API_KEY is not set")

    base = base_url or os.environ.get("NGSS_BASE_URL") or NGSS_BASE_URL
    url = f"{base.rstrip('/')}{path}"
    headers = {"x-api-key": api_key, "Accept": "text/plain"}
    params = params.copy() if params else {}
    params.setdefault("Format", "Json")

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


def extract_person_name(person: dict) -> tuple[str | None, str | None, str | None]:
    full_name = get_field(person, "name", "Name", "fullName", "FullName")
    first_name = get_field(person, "firstName", "FirstName")
    family_name = get_field(person, "familyName", "FamilyName", "lastName", "LastName")
    if not full_name and (first_name or family_name):
        full_name = " ".join(part for part in [first_name, family_name] if part)
    return full_name, first_name, family_name


def build_roster_rows(
    team: dict,
    game_id: str,
    fetched_at: datetime,
) -> list[dict]:
    rows: list[dict] = []
    team_id_raw = get_field(team, "teamId", "TeamId")
    team_id = parse_int(team_id_raw)

    players = get_field(team, "players", "PlayersList") or []
    for player in players:
        person_id = get_field(player, "personId", "PersonId")
        nba_id = parse_int(person_id)
        if nba_id is None:
            continue
        full_name, first_name, family_name = extract_person_name(player)
        row = {
            "game_id": game_id,
            "team_id": parse_int(get_field(player, "teamId", "TeamId")) or team_id,
            "nba_id": nba_id,
            "full_name": full_name,
            "first_name": first_name,
            "family_name": family_name,
            "jersey_number": get_field(player, "jerseyNum", "JerseyNumber"),
            "position": get_field(player, "position", "Position"),
            "is_player": True,
            "is_official": False,
            "is_team_staff": False,
            "team_role": None,
            "player_status": get_field(player, "status", "Status"),
            "not_playing_reason": get_field(player, "notPlayingReason", "NotPlayingReason"),
            "not_playing_description": get_field(player, "notPlayingDescription", "NotPlayingDescription"),
            "created_at": fetched_at,
            "updated_at": fetched_at,
            "fetched_at": fetched_at,
        }
        rows.append(row)

    staff_members = get_field(team, "staff", "StaffList") or []
    for staff in staff_members:
        person_id = get_field(staff, "personId", "PersonId")
        nba_id = parse_int(person_id)
        if nba_id is None:
            continue
        full_name, first_name, family_name = extract_person_name(staff)
        row = {
            "game_id": game_id,
            "team_id": team_id,
            "nba_id": nba_id,
            "full_name": full_name,
            "first_name": first_name,
            "family_name": family_name,
            "jersey_number": None,
            "position": None,
            "is_player": False,
            "is_official": False,
            "is_team_staff": True,
            "team_role": get_field(staff, "role", "Role", "position", "Position"),
            "player_status": None,
            "not_playing_reason": None,
            "not_playing_description": None,
            "created_at": fetched_at,
            "updated_at": fetched_at,
            "fetched_at": fetched_at,
        }
        rows.append(row)

    return rows


def build_official_rows(
    officials: list[dict],
    game_id: str,
    fetched_at: datetime,
) -> list[dict]:
    rows: list[dict] = []
    for official in officials:
        person_id = get_field(official, "personId", "PersonId")
        if person_id is None:
            continue
        rows.append(
            {
                "game_id": game_id,
                "ngss_official_id": str(person_id),
                "first_name": get_field(official, "firstName", "FirstName"),
                "last_name": get_field(official, "familyName", "FamilyName", "lastName", "LastName"),
                "jersey_num": get_field(official, "jerseyNum", "JerseyNumber"),
                "official_type": get_field(official, "type", "Type"),
                "assignment": get_field(official, "assignment", "Assignment"),
                "created_at": fetched_at,
                "updated_at": fetched_at,
                "fetched_at": fetched_at,
            }
        )
    return rows


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
    only_final_games: bool = True,
) -> dict:
    started_at = now_utc()

    api_key = os.environ.get("NGSS_API_KEY")
    if not api_key:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": ["NGSS_API_KEY must be set"],
        }

    conn: psycopg.Connection | None = None
    try:
        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        desired_season_type = normalize_season_type(season_type)
        season_label_filter = season_label or None
        game_list: list[tuple[str, int | None]] = []
        if game_ids:
            game_list = [(gid.strip(), None) for gid in game_ids.split(",") if gid.strip()]
        else:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date, season_label)
            query = """
                SELECT game_id, game_status, season_type
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
                    (gid, status, game_season_type)
                    for gid, status, game_season_type in game_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                ]

            game_list = [(gid, status) for gid, status, _ in game_rows]

        if only_final_games:
            game_list = [(gid, status) for gid, status in game_list if status in (None, 3)]

        fetched_at = now_utc()

        game_rows: list[dict] = []
        roster_rows: list[dict] = []
        boxscore_rows: list[dict] = []
        pbp_rows: list[dict] = []
        official_rows: list[dict] = []

        with httpx.Client(timeout=30) as client:
            for game_id_value, status in game_list:
                game_response = request_json(client, f"/Games/{game_id_value}", api_key=api_key)
                game_payload = unwrap_data(game_response)
                if not isinstance(game_payload, dict) or not game_payload:
                    continue

                ruleset_response = request_json(
                    client,
                    f"/Games/{game_id_value}/ruleset",
                    api_key=api_key,
                )
                ruleset_payload = unwrap_data(ruleset_response)
                arena = get_field(game_payload, "arena", "Arena") or {}

                game_rows.append(
                    {
                        "game_id": game_id_value,
                        "league_code": get_field(game_payload, "leagueCode", "LeagueCode"),
                        "league_name": get_field(game_payload, "leagueName", "LeagueName"),
                        "season_id": get_field(game_payload, "seasonId", "SeasonId"),
                        "season_name": get_field(game_payload, "seasonName", "SeasonName"),
                        "season_type": parse_enum_int(get_field(game_payload, "seasonType", "SeasonType"), SEASON_TYPE_MAP),
                        "game_status": parse_enum_int(get_field(game_payload, "gameStatus", "GameStatus"), GAME_STATUS_MAP),
                        "winner_type": parse_enum_int(get_field(game_payload, "winner", "Winner"), WINNER_MAP),
                        "game_date_local": parse_date(get_field(game_payload, "gameTimeLocal", "GameDateTimeLocal", "GameTimeLocal")),
                        "game_time_local": parse_time(get_field(game_payload, "gameTimeLocal", "GameTimeLocal")),
                        "game_date_time_local": parse_datetime(get_field(game_payload, "gameTimeLocal", "GameDateTimeLocal", "GameTimeHome")),
                        "game_date_time_utc": parse_datetime(get_field(game_payload, "gameTimeUTC", "GameDateTimeUtc", "GameTimeUTC")),
                        "game_time_home": parse_time(get_field(game_payload, "gameTimeHome", "GameTimeHome")),
                        "game_time_away": parse_time(get_field(game_payload, "gameTimeAway", "GameTimeAway")),
                        "game_time_et": parse_time(get_field(game_payload, "gameEt", "GameEt")),
                        "time_actual": parse_datetime(get_field(game_payload, "timeActual", "TimeActual")),
                        "time_end_actual": parse_datetime(get_field(game_payload, "timeEndActual", "TimeEndActual")),
                        "attendance": parse_int(get_field(game_payload, "attendance", "Attendance")),
                        "duration_minutes": parse_int(get_field(game_payload, "duration", "Duration")),
                        "home_team_id": parse_int(get_field(game_payload, "homeId", "HomeId")),
                        "home_score": parse_int(get_field(game_payload, "homeScore", "HomeScore")),
                        "away_team_id": parse_int(get_field(game_payload, "awayId", "AwayId")),
                        "away_score": parse_int(get_field(game_payload, "awayScore", "AwayScore")),
                        "arena_id": parse_int(get_field(arena, "arenaId", "ArenaId")),
                        "arena_name": get_field(arena, "arenaName", "ArenaName"),
                        "last_game_data_update": parse_datetime(get_field(game_payload, "lastGameDataUpdate", "LastGameDataUpdate")),
                        "needs_reprocessing": parse_datetime(get_field(game_payload, "needsReprocessing", "NeedsReprocessing")),
                        "is_sold_out": parse_yes_no(get_field(game_payload, "isSoldOut", "IsSoldOut")),
                        "memos": normalize_memos(get_field(game_payload, "memos", "Memos")),
                        "is_target_score_ending": to_bool(get_field(game_payload, "targetScoreEnding", "TargetScoreEnding")),
                        "target_score_period": parse_int(get_field(game_payload, "targetScorePeriod", "TargetScorePeriod")),
                        "ruleset_id": parse_int(get_field(ruleset_payload, "rulesetId", "RulesetId")) if isinstance(ruleset_payload, dict) else None,
                        "ruleset_json": Json(ruleset_payload) if ruleset_payload else None,
                        "game_json": Json(game_payload),
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )

                roster_response = request_json(
                    client,
                    f"/Games/{game_id_value}/rosters",
                    api_key=api_key,
                )
                roster_payload = unwrap_data(roster_response)
                if isinstance(roster_payload, dict):
                    roster_rows.extend(
                        build_roster_rows(
                            get_field(roster_payload, "homeTeam", "HomeTeam") or {},
                            game_id_value,
                            fetched_at,
                        )
                    )
                    roster_rows.extend(
                        build_roster_rows(
                            get_field(roster_payload, "awayTeam", "AwayTeam") or {},
                            game_id_value,
                            fetched_at,
                        )
                    )

                officials_response = request_json(
                    client,
                    f"/Games/{game_id_value}/officials",
                    api_key=api_key,
                )
                officials_payload = unwrap_data(officials_response)
                if isinstance(officials_payload, dict):
                    officials_list = get_field(officials_payload, "officials", "OfficialsList") or []
                    official_rows.extend(build_official_rows(officials_list, game_id_value, fetched_at))

                boxscore_response = request_json(
                    client,
                    f"/games/{game_id_value}/boxscore",
                    api_key=api_key,
                )
                boxscore_payload = unwrap_data(boxscore_response)
                if boxscore_payload:
                    boxscore_rows.append(
                        {
                            "game_id": game_id_value,
                            "boxscore_json": Json(boxscore_payload),
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                    )

                pbp_response = request_json(
                    client,
                    f"/games/{game_id_value}/playbyplay",
                    api_key=api_key,
                )
                pbp_payload = unwrap_data(pbp_response)
                if pbp_payload:
                    pbp_rows.append(
                        {
                            "game_id": game_id_value,
                            "ngss_pbp_json": Json(pbp_payload),
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                    )

        inserted_games = 0
        inserted_rosters = 0
        inserted_boxscores = 0
        inserted_pbp = 0
        inserted_officials = 0

        if not dry_run:
            if game_rows:
                inserted_games = upsert(conn, "nba.ngss_games", game_rows, ["game_id"], update_exclude=["created_at"])
            if roster_rows:
                inserted_rosters = upsert(
                    conn,
                    "nba.ngss_rosters",
                    roster_rows,
                    ["game_id", "nba_id"],
                    update_exclude=["created_at"],
                )
            if boxscore_rows:
                inserted_boxscores = upsert(conn, "nba.ngss_boxscores", boxscore_rows, ["game_id"], update_exclude=["created_at"])
            if pbp_rows:
                inserted_pbp = upsert(conn, "nba.ngss_pbp", pbp_rows, ["game_id"], update_exclude=["created_at"])
            if official_rows:
                inserted_officials = upsert(
                    conn,
                    "nba.ngss_officials",
                    official_rows,
                    ["game_id", "ngss_official_id"],
                    update_exclude=["created_at"],
                )

        if conn:
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {"table": "nba.ngss_games", "rows": len(game_rows), "upserted": inserted_games},
                {"table": "nba.ngss_rosters", "rows": len(roster_rows), "upserted": inserted_rosters},
                {"table": "nba.ngss_boxscores", "rows": len(boxscore_rows), "upserted": inserted_boxscores},
                {"table": "nba.ngss_pbp", "rows": len(pbp_rows), "upserted": inserted_pbp},
                {"table": "nba.ngss_officials", "rows": len(official_rows), "upserted": inserted_officials},
            ],
            "errors": [],
        }
    except Exception as exc:
        if conn:
            conn.close()
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [str(exc)],
        }


if __name__ == "__main__":
    main()
