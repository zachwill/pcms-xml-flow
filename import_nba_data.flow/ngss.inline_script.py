# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "typing-extensions"]
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


def parse_enum_int(value, mapping: dict[str, int]):
    if value is None or value == "":
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        if value.isdigit():
            return int(value)
        mapped = mapping.get(value)
        if mapped is not None:
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


def resolve_date_range(mode: str, days_back: int, start_date: str | None, end_date: str | None) -> tuple[date, date]:
    if start_date and end_date:
        return parse_date(start_date), parse_date(end_date)

    if mode == "refresh":
        today = now_utc().date()
        start = today - timedelta(days=days_back or 2)
        return start, today

    raise ValueError("backfill mode requires start_date and end_date (or game_ids)")


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


def load_nba_id_lookup(conn: psycopg.Connection) -> dict[str, int]:
    lookup: dict[str, int] = {}
    with conn.cursor() as cur:
        cur.execute("SELECT nba_id, ngss_person_id FROM nba.players")
        for nba_id, ngss_person_id in cur.fetchall():
            if nba_id is None:
                continue
            lookup[str(nba_id)] = nba_id
            if ngss_person_id:
                lookup[str(ngss_person_id)] = nba_id
    return lookup


def extract_person_name(person: dict) -> tuple[str | None, str | None, str | None]:
    full_name = person.get("Name") or person.get("name")
    first_name = person.get("FirstName") or person.get("firstName")
    family_name = person.get("FamilyName") or person.get("lastName")
    if not full_name and (first_name or family_name):
        full_name = " ".join(part for part in [first_name, family_name] if part)
    return full_name, first_name, family_name


def build_roster_rows(
    team: dict,
    game_id: str,
    ngss_game_id: str,
    nba_id_lookup: dict[str, int],
    fetched_at: datetime,
) -> list[dict]:
    rows: list[dict] = []
    team_id = parse_int(team.get("TeamId"))
    ngss_team_id = team.get("TeamId")
    ngss_team_id_str = str(ngss_team_id) if ngss_team_id is not None else None

    for player in team.get("PlayersList") or []:
        person_id = player.get("PersonId")
        if person_id is None:
            continue
        ngss_person_id = str(person_id)
        nba_id = nba_id_lookup.get(ngss_person_id)
        full_name, first_name, family_name = extract_person_name(player)
        row = {
            "game_id": game_id,
            "ngss_game_id": ngss_game_id,
            "team_id": parse_int(player.get("TeamId")) or team_id,
            "ngss_team_id": ngss_team_id_str,
            "nba_id": nba_id,
            "ngss_person_id": ngss_person_id,
            "full_name": full_name,
            "first_name": first_name,
            "family_name": family_name,
            "jersey_number": player.get("JerseyNumber"),
            "position": player.get("Position"),
            "is_player": True,
            "is_official": False,
            "is_team_staff": False,
            "team_role": None,
            "player_status": player.get("Status"),
            "not_playing_reason": player.get("NotPlayingReason"),
            "not_playing_description": player.get("NotPlayingDescription"),
            "created_at": fetched_at,
            "updated_at": fetched_at,
            "fetched_at": fetched_at,
        }
        rows.append(row)

    for staff in team.get("StaffList") or []:
        person_id = staff.get("PersonId")
        if person_id is None:
            continue
        ngss_person_id = str(person_id)
        nba_id = nba_id_lookup.get(ngss_person_id)
        full_name, first_name, family_name = extract_person_name(staff)
        row = {
            "game_id": game_id,
            "ngss_game_id": ngss_game_id,
            "team_id": team_id,
            "ngss_team_id": ngss_team_id_str,
            "nba_id": nba_id,
            "ngss_person_id": ngss_person_id,
            "full_name": full_name,
            "first_name": first_name,
            "family_name": family_name,
            "jersey_number": None,
            "position": None,
            "is_player": False,
            "is_official": False,
            "is_team_staff": True,
            "team_role": staff.get("Role"),
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
        person_id = official.get("PersonId")
        if person_id is None:
            continue
        rows.append(
            {
                "game_id": game_id,
                "ngss_official_id": str(person_id),
                "first_name": official.get("FirstName"),
                "last_name": official.get("FamilyName"),
                "jersey_num": official.get("JerseyNumber"),
                "official_type": official.get("Type"),
                "assignment": official.get("Assignment"),
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
    include_reference: bool = True,
    include_schedule_and_standings: bool = True,
    include_games: bool = True,
    include_game_data: bool = True,
    include_aggregates: bool = False,
    include_supplemental: bool = False,
    include_ngss: bool = False,
    only_final_games: bool = True,
) -> dict:
    started_at = now_utc()
    if not include_ngss:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [],
        }

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
        game_list: list[tuple[str, int | None]] = []
        if game_ids:
            game_list = [(gid.strip(), None) for gid in game_ids.split(",") if gid.strip()]
        else:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date)
            query = """
                SELECT game_id, game_status
                FROM nba.games
                WHERE game_date BETWEEN %s AND %s
                ORDER BY game_date, game_id
            """
            with conn.cursor() as cur:
                cur.execute(query, (start_dt, end_dt))
                game_list = cur.fetchall()

        if only_final_games:
            game_list = [(gid, status) for gid, status in game_list if status in (None, 3)]

        fetched_at = now_utc()
        nba_id_lookup = load_nba_id_lookup(conn)

        game_rows: list[dict] = []
        roster_rows: list[dict] = []
        boxscore_rows: list[dict] = []
        pbp_rows: list[dict] = []
        official_rows: list[dict] = []

        with httpx.Client(timeout=30) as client:
            for game_id_value, status in game_list:
                game_payload = request_json(client, f"/Games/{game_id_value}", api_key=api_key)
                if not isinstance(game_payload, dict) or not game_payload:
                    continue

                ngss_game_id = game_payload.get("GameId") or game_id_value
                ruleset_payload = request_json(
                    client,
                    f"/Games/{game_id_value}/ruleset",
                    api_key=api_key,
                )
                arena = game_payload.get("Arena") or {}

                game_rows.append(
                    {
                        "game_id": game_id_value,
                        "ngss_game_id": ngss_game_id,
                        "league_code": game_payload.get("LeagueCode"),
                        "league_name": game_payload.get("LeagueName"),
                        "season_id": game_payload.get("SeasonId"),
                        "season_name": game_payload.get("SeasonName"),
                        "season_type": parse_enum_int(game_payload.get("SeasonType"), SEASON_TYPE_MAP),
                        "game_status": parse_enum_int(game_payload.get("GameStatus"), GAME_STATUS_MAP),
                        "winner_type": parse_enum_int(game_payload.get("Winner"), WINNER_MAP),
                        "game_date_local": parse_date(game_payload.get("GameDateTimeLocal")),
                        "game_time_local": parse_time(game_payload.get("GameTimeLocal")),
                        "game_date_time_local": parse_datetime(game_payload.get("GameDateTimeLocal")),
                        "game_date_time_utc": parse_datetime(game_payload.get("GameDateTimeUtc")),
                        "game_time_home": parse_time(game_payload.get("GameTimeHome")),
                        "game_time_away": parse_time(game_payload.get("GameTimeAway")),
                        "game_time_et": parse_time(game_payload.get("GameEt")),
                        "time_actual": parse_datetime(game_payload.get("TimeActual")),
                        "time_end_actual": parse_datetime(game_payload.get("TimeEndActual")),
                        "attendance": parse_int(game_payload.get("Attendance")),
                        "duration_minutes": parse_int(game_payload.get("Duration")),
                        "home_team_id": parse_int(game_payload.get("HomeId")),
                        "home_score": parse_int(game_payload.get("HomeScore")),
                        "away_team_id": parse_int(game_payload.get("AwayId")),
                        "away_score": parse_int(game_payload.get("AwayScore")),
                        "arena_id": parse_int(arena.get("ArenaId")),
                        "arena_name": arena.get("ArenaName"),
                        "last_game_data_update": parse_datetime(game_payload.get("LastGameDataUpdate")),
                        "needs_reprocessing": parse_datetime(game_payload.get("NeedsReprocessing")),
                        "is_sold_out": parse_yes_no(game_payload.get("IsSoldOut")),
                        "memos": normalize_memos(game_payload.get("Memos")),
                        "is_target_score_ending": to_bool(game_payload.get("TargetScoreEnding")),
                        "target_score_period": parse_int(game_payload.get("TargetScorePeriod")),
                        "ruleset_id": parse_int(ruleset_payload.get("RulesetId")) if isinstance(ruleset_payload, dict) else None,
                        "ruleset_json": Json(ruleset_payload) if ruleset_payload else None,
                        "game_json": Json(game_payload),
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )

                roster_payload = request_json(
                    client,
                    f"/Games/{game_id_value}/rosters",
                    api_key=api_key,
                )
                if isinstance(roster_payload, dict):
                    roster_rows.extend(
                        build_roster_rows(
                            roster_payload.get("HomeTeam") or {},
                            game_id_value,
                            ngss_game_id,
                            nba_id_lookup,
                            fetched_at,
                        )
                    )
                    roster_rows.extend(
                        build_roster_rows(
                            roster_payload.get("AwayTeam") or {},
                            game_id_value,
                            ngss_game_id,
                            nba_id_lookup,
                            fetched_at,
                        )
                    )

                officials_payload = request_json(
                    client,
                    f"/Games/{game_id_value}/officials",
                    api_key=api_key,
                )
                if isinstance(officials_payload, dict):
                    officials_list = officials_payload.get("OfficialsList") or []
                    official_rows.extend(build_official_rows(officials_list, game_id_value, fetched_at))

                boxscore_payload = request_json(
                    client,
                    f"/games/{game_id_value}/boxscore",
                    api_key=api_key,
                )
                if boxscore_payload:
                    boxscore_rows.append(
                        {
                            "game_id": game_id_value,
                            "ngss_game_id": ngss_game_id,
                            "boxscore_json": Json(boxscore_payload),
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                    )

                pbp_payload = request_json(
                    client,
                    f"/games/{game_id_value}/playbyplay",
                    api_key=api_key,
                )
                if pbp_payload:
                    pbp_rows.append(
                        {
                            "game_id": game_id_value,
                            "ngss_game_id": ngss_game_id,
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
                    ["ngss_game_id", "ngss_person_id"],
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
