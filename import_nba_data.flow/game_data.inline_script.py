# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import os
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone

import httpx
import psycopg
from psycopg.types.json import Json

BASE_URL = "https://api.nba.com/v0"
HUSTLE_URL = "https://api.nba.com/v0/api/hustlestats"
QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"

GAME_DATA_CONCURRENCY = 4
GAME_DATA_INCLUDE_PER_GAME_METRICS = False
GAME_DATA_SKIP_EXISTING_ON_SEASON_BACKFILL = True

TRACKING_BATCH_SIZE = 100
TRACKING_MAX_ROWS_RETURNED = 10000
QUERY_TOOL_TRUNCATION_THRESHOLD = 9900

DEFENSIVE_BATCH_SIZE = 100
VIOLATIONS_BATCH_SIZE = 100
VIOLATIONS_TEAM_BATCH_SIZE = 200


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def elapsed_ms(started_perf: float) -> float:
    return round((time.perf_counter() - started_perf) * 1000, 2)


def parse_datetime(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


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


def parse_iso_duration(value: str | None):
    if not value:
        return None
    # Accept ISO 8601 PTmmMss.SS or MM:SS and return decimal minutes
    if value.startswith("PT"):
        minutes = 0
        seconds = 0.0
        try:
            body = value.replace("PT", "")
            if "M" in body:
                minutes_str, rest = body.split("M", 1)
                minutes = int(minutes_str)
            else:
                rest = body
            if "S" in rest:
                seconds = float(rest.replace("S", ""))
        except ValueError:
            return None
        total_seconds = minutes * 60 + seconds
        return round(total_seconds / 60.0, 2)
    if ":" in value:
        try:
            minutes_str, seconds_str = value.split(":", 1)
            total_seconds = int(minutes_str) * 60 + float(seconds_str)
            return round(total_seconds / 60.0, 2)
        except ValueError:
            return None
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


def parse_float(value):
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def parse_minutes_interval(value: str | None):
    if value is None or value == "":
        return None
    if isinstance(value, str):
        if value.startswith("PT") or ":" in value:
            return parse_iso_duration(value)
    try:
        minutes = float(value)
    except (ValueError, TypeError):
        return None
    return round(minutes, 2)


def empty_to_none(value):
    if value is None:
        return None
    if isinstance(value, str):
        value = value.strip()
        return value if value != "" else None
    return value


def to_bool(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    try:
        return bool(int(value))
    except (ValueError, TypeError):
        return None


def request_json(
    client: httpx.Client,
    path: str,
    params: dict | None = None,
    retries: int = 3,
    base_url: str = BASE_URL,
) -> dict:
    headers = {"X-NBA-Api-Key": os.environ["NBA_API_KEY"]}
    url = f"{base_url}{path}"

    for attempt in range(retries):
        try:
            resp = client.get(url, params=params, headers=headers)
        except httpx.TimeoutException:
            if attempt == retries - 1:
                raise
            time.sleep(1 + attempt)
            continue
        retryable_400 = resp.status_code == 400 and "Database Error" in resp.text
        if resp.status_code in {429, 500, 502, 503, 504} or retryable_400:
            if attempt == retries - 1:
                resp.raise_for_status()
            time.sleep(1 + attempt)
            continue
        if resp.status_code == 404:
            return {}
        resp.raise_for_status()
        return resp.json()

    raise RuntimeError(f"Failed to fetch {url}")


def request_xml(
    client: httpx.Client,
    path: str,
    params: dict | None = None,
    retries: int = 3,
    base_url: str = HUSTLE_URL,
) -> str | None:
    headers = {"X-NBA-Api-Key": os.environ["NBA_API_KEY"]}
    url = f"{base_url}{path}"

    for attempt in range(retries):
        try:
            resp = client.get(url, params=params, headers=headers)
        except httpx.TimeoutException:
            if attempt == retries - 1:
                raise
            time.sleep(1 + attempt)
            continue
        if resp.status_code in {429, 500, 502, 503, 504}:
            if attempt == retries - 1:
                resp.raise_for_status()
            time.sleep(1 + attempt)
            continue
        if resp.status_code in {403, 404}:
            return None
        resp.raise_for_status()
        return resp.text or None

    raise RuntimeError(f"Failed to fetch {url}")


def upsert(conn: psycopg.Connection, table: str, rows: list[dict], conflict_keys: list[str], update_exclude: list[str] | None = None) -> int:
    if not rows:
        return 0
    update_exclude = update_exclude or []

    cols: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for col in row.keys():
            if col not in seen:
                seen.add(col)
                cols.append(col)

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
        cur.executemany(sql, [tuple(r.get(c) for c in cols) for r in rows])
    conn.commit()
    return len(rows)


def fetch_existing_game_ids(
    conn: psycopg.Connection,
    table: str,
    game_ids: list[str],
    extra_where: str = "",
    extra_params: tuple | None = None,
) -> set[str]:
    if not game_ids:
        return set()

    extra_params = extra_params or ()
    sql = f"SELECT DISTINCT game_id FROM {table} WHERE game_id = ANY(%s::text[])"
    if extra_where:
        sql += f" AND {extra_where}"

    with conn.cursor() as cur:
        cur.execute(sql, (game_ids, *extra_params))
        return {row[0] for row in cur.fetchall() if row and row[0]}


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


PLAYER_STAT_MAP = {
    "points": "pts",
    "fieldGoalsMade": "fgm",
    "fieldGoalsAttempted": "fga",
    "fieldGoalsPercentage": "fg_pct",
    "threePointersMade": "fg3m",
    "threePointersAttempted": "fg3a",
    "threePointersPercentage": "fg3_pct",
    "freeThrowsMade": "ftm",
    "freeThrowsAttempted": "fta",
    "freeThrowsPercentage": "ft_pct",
    "reboundsOffensive": "oreb",
    "reboundsDefensive": "dreb",
    "reboundsTotal": "reb",
    "assists": "ast",
    "steals": "stl",
    "blocks": "blk",
    "turnovers": "tov",
    "foulsPersonal": "pf",
    "foulsDrawn": "fouls_drawn",
    "plusMinusPoints": "plus_minus",
}

TEAM_STAT_MAP = {
    "points": "points",
    "fieldGoalsMade": "fgm",
    "fieldGoalsAttempted": "fga",
    "fieldGoalsPercentage": "fg_pct",
    "threePointersMade": "fg3m",
    "threePointersAttempted": "fg3a",
    "threePointersPercentage": "fg3_pct",
    "freeThrowsMade": "ftm",
    "freeThrowsAttempted": "fta",
    "freeThrowsPercentage": "ft_pct",
    "reboundsOffensive": "oreb",
    "reboundsDefensive": "dreb",
    "reboundsTotal": "reb",
    "assists": "ast",
    "steals": "stl",
    "blocks": "blk",
    "turnovers": "tov",
    "foulsPersonal": "pf",
    "foulsTechnical": "fouls_technical",
    "foulsTeam": "fouls_team",
    "foulsTeamTechnical": "fouls_team_technical",
    "foulsDrawn": "fouls_drawn",
    "plusMinusPoints": "plus_minus",
    "pointsFastBreak": "pts_fast_break",
    "pointsInThePaint": "pts_paint",
    "pointsSecondChance": "pts_2nd_chance",
    "benchPoints": "bench_pts",
    "biggestLead": "biggest_lead",
    "biggestScoringRun": "biggest_scoring_run",
    "leadChanges": "lead_changes",
    "timesTied": "times_tied",
    "assistsTurnoverRatio": "ast_tov_ratio",
    "turnoversTeam": "tov_team",
    "turnoversTotal": "tov_total",
    "reboundsTeam": "reb_team",
    "reboundsPersonal": "reb_personal",
}

ADVANCED_COLUMNS = {
    "minutes",
    "off_rating",
    "def_rating",
    "net_rating",
    "ast_pct",
    "ast_to_ratio",
    "ast_ratio",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "usg_pct",
    "pace",
    "pace_per40",
    "poss",
    "pie",
}

ADVANCED_TEAM_ALLOWED_COLUMNS = {
    "game_id",
    "team_id",
    "minutes",
    "off_rating",
    "def_rating",
    "net_rating",
    "ast_pct",
    "ast_to_ratio",
    "ast_ratio",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "pace",
    "pace_per40",
    "poss",
    "pie",
    "created_at",
    "updated_at",
    "fetched_at",
}

HUSTLE_PLAYER_COLUMNS = [
    "contested_field_goals",
    "contested_2pt_field_goals",
    "contested_3pt_field_goals",
    "deflections",
    "loose_balls_recovered",
    "loose_balls_recovered_offensive",
    "loose_balls_recovered_defensive",
    "charges_drawn",
    "screen_assists",
    "screen_assists_pts",
    "boxouts",
    "boxouts_offensive",
    "boxouts_defensive",
    "boxout_player_rebound_pct",
    "boxout_team_rebound_pct",
    "forced_turnovers",
]

HUSTLE_TEAM_COLUMNS = [
    "contested_field_goals",
    "contested_2pt_field_goals",
    "contested_3pt_field_goals",
    "deflections",
    "loose_balls_recovered",
    "loose_balls_recovered_offensive",
    "loose_balls_recovered_defensive",
    "charges_drawn",
    "screen_assists",
    "screen_assists_pts",
    "boxouts",
    "boxouts_offensive",
    "boxouts_defensive",
    "boxout_team_rebound_pct",
    "forced_turnovers",
]

HUSTLE_PLAYER_MAP = {
    "CFG": ("contested_field_goals", parse_int),
    "C2FG": ("contested_2pt_field_goals", parse_int),
    "C3FG": ("contested_3pt_field_goals", parse_int),
    "DEFL": ("deflections", parse_int),
    "LBR": ("loose_balls_recovered", parse_int),
    "OLBR": ("loose_balls_recovered_offensive", parse_int),
    "DLBR": ("loose_balls_recovered_defensive", parse_int),
    "CHG_DR": ("charges_drawn", parse_int),
    "SA": ("screen_assists", parse_int),
    "PTSOFFSA": ("screen_assists_pts", parse_int),
    "BOXOUTS": ("boxouts", parse_int),
    "OBOXOUTS": ("boxouts_offensive", parse_int),
    "DBOXOUTS": ("boxouts_defensive", parse_int),
    "PCTBOXOUTSREB": ("boxout_player_rebound_pct", parse_float),
    "PCTBOXOUTSTMREB": ("boxout_team_rebound_pct", parse_float),
    "FORCEDTOV": ("forced_turnovers", parse_int),
}

HUSTLE_TEAM_MAP = {
    "CFG": ("contested_field_goals", parse_int),
    "C2FG": ("contested_2pt_field_goals", parse_int),
    "C3FG": ("contested_3pt_field_goals", parse_int),
    "DEFL": ("deflections", parse_int),
    "LBR": ("loose_balls_recovered", parse_int),
    "OLBR": ("loose_balls_recovered_offensive", parse_int),
    "DLBR": ("loose_balls_recovered_defensive", parse_int),
    "CHG_DR": ("charges_drawn", parse_int),
    "SA": ("screen_assists", parse_int),
    "PTSOFFSA": ("screen_assists_pts", parse_int),
    "BOXOUTS": ("boxouts", parse_int),
    "OBOXOUTS": ("boxouts_offensive", parse_int),
    "DBOXOUTS": ("boxouts_defensive", parse_int),
    "PCTBOXOUTSTMREB": ("boxout_team_rebound_pct", parse_float),
    "FORCEDTOV": ("forced_turnovers", parse_int),
}

TRACKING_QUERYTOOL_COLUMNS = [
    "shot",
    "shot_transition_fga",
    "shot_transition_fgm",
    "shot_transition_fg_pct",
    "shot_catch_and_shoot_fga",
    "shot_catch_and_shoot_fgm",
    "shot_catch_and_shoot_fg_pct",
    "shot_catch_and_shoot_three_fga",
    "shot_catch_and_shoot_three_fgm",
    "shot_catch_and_shoot_three_fg_pct",
    "shot_pull_up_fga",
    "shot_pull_up_fgm",
    "shot_pull_up_fg_pct",
    "shot_trailing_three_fga",
    "shot_trailing_three_fgm",
    "shot_trailing_three_fg_pct",
    "shot_tip_in_fga",
    "shot_tip_in_fgm",
    "shot_tip_in_fg_pct",
    "shot_long_heave_fga",
    "shot_long_heave_fgm",
    "shot_long_heave_fg_pct",
    "shot_after_screens_fga",
    "shot_after_screens_fgm",
    "shot_after_screens_fg_pct",
    "shot_lob_fga",
    "shot_lob_fgm",
    "shot_lob_fg_pct",
    "pass_ball_reversal",
    "pass_bounce",
    "pass_give_n_go",
    "pass_hand_off",
    "pass_inbound",
    "pass_in_paint",
    "pass_kick_out",
    "pass_outlet",
    "pass_pitch_ahead",
    "pass_skip",
    "pass_to_paint",
    "pass_touch",
    "post_up",
    "post_up_rim",
    "post_up_mid",
    "post_up_extended",
    "post_up_dribble_entry",
    "post_up_pass_entry",
    "drive",
    "drive_blow_by",
    "drive_traverse",
    "iso",
    "iso_foul",
    "iso_tov",
    "iso_shot",
    "iso_pass",
    "dribble",
]

TRACKING_QUERYTOOL_PCT_COLUMNS = {
    "shot_transition_fg_pct",
    "shot_catch_and_shoot_fg_pct",
    "shot_catch_and_shoot_three_fg_pct",
    "shot_pull_up_fg_pct",
    "shot_trailing_three_fg_pct",
    "shot_tip_in_fg_pct",
    "shot_long_heave_fg_pct",
    "shot_after_screens_fg_pct",
    "shot_lob_fg_pct",
}

TRACKING_QUERYTOOL_INT_COLUMNS = set(TRACKING_QUERYTOOL_COLUMNS) - TRACKING_QUERYTOOL_PCT_COLUMNS

TRACKING_COLUMNS = [
    "minutes",
    "dist_miles",
    "dist_miles_off",
    "dist_miles_def",
    "avg_speed",
    "avg_speed_off",
    "avg_speed_def",
    "touches",
    "secondary_ast",
    "ft_ast",
    "passes",
    "ast",
    "cfgm",
    "cfga",
    "cfg_pct",
    "uf_fgm",
    "uf_fga",
    "uf_fg_pct",
    "fg_pct",
    "fg2m",
    "fg2a",
    "fg2_pct",
    "dfgm",
    "dfga",
    "dfg_pct",
    *TRACKING_QUERYTOOL_COLUMNS,
]

TRACKING_INT_COLUMNS = {
    "touches",
    "secondary_ast",
    "ft_ast",
    "passes",
    "ast",
    "cfgm",
    "cfga",
    "uf_fgm",
    "uf_fga",
    "fg2m",
    "fg2a",
    "dfgm",
    "dfga",
    *TRACKING_QUERYTOOL_INT_COLUMNS,
}

TRACKING_PCT_COLUMNS = {
    "cfg_pct",
    "uf_fg_pct",
    "fg_pct",
    "fg2_pct",
    "dfg_pct",
    *TRACKING_QUERYTOOL_PCT_COLUMNS,
}

TRACKING_KEY_MAP = {
    "min": "minutes",
    "minutes": "minutes",
    "dist": "dist_miles",
    "distance": "dist_miles",
    "dist_miles": "dist_miles",
    "distance_miles": "dist_miles",
    "dist_off": "dist_miles_off",
    "distance_off": "dist_miles_off",
    "dist_miles_off": "dist_miles_off",
    "distance_miles_off": "dist_miles_off",
    "dist_def": "dist_miles_def",
    "distance_def": "dist_miles_def",
    "dist_miles_def": "dist_miles_def",
    "distance_miles_def": "dist_miles_def",
    "avg_speed": "avg_speed",
    "speed": "avg_speed",
    "avg_speed_off": "avg_speed_off",
    "speed_off": "avg_speed_off",
    "avg_speed_def": "avg_speed_def",
    "speed_def": "avg_speed_def",
    "touches": "touches",
    "secondary_ast": "secondary_ast",
    "secondary_assist": "secondary_ast",
    "secondary_assists": "secondary_ast",
    "sec_ast": "secondary_ast",
    "ft_ast": "ft_ast",
    "ft_assist": "ft_ast",
    "ft_assists": "ft_ast",
    "passes": "passes",
    "pass": "passes",
    "passes_made": "passes",
    "ast": "ast",
    "assists": "ast",
    "cfgm": "cfgm",
    "cfga": "cfga",
    "cfg_pct": "cfg_pct",
    "contested_fg_m": "cfgm",
    "contested_fg_a": "cfga",
    "contested_fg_pct": "cfg_pct",
    "ufgm": "uf_fgm",
    "ufga": "uf_fga",
    "ufg_pct": "uf_fg_pct",
    "uf_fg_pct": "uf_fg_pct",
    "uncontested_fg_m": "uf_fgm",
    "uncontested_fg_a": "uf_fga",
    "uncontested_fg_pct": "uf_fg_pct",
    "fg_pct": "fg_pct",
    "fg2m": "fg2m",
    "fg2a": "fg2a",
    "fg2_pct": "fg2_pct",
    "dfgm": "dfgm",
    "dfga": "dfga",
    "dfg_pct": "dfg_pct",
    "defended_fg_m": "dfgm",
    "defended_fg_a": "dfga",
    "defended_fg_pct": "dfg_pct",
    **{column: column for column in TRACKING_QUERYTOOL_COLUMNS},
}


DEFENSIVE_COLUMNS = [
    "minutes",
    "def_fgm",
    "def_fga",
    "def_fg_pct",
    "def_fg3m",
    "def_fg3a",
    "def_fg3_pct",
    "def_ftm",
    "def_fta",
    "def_ft_pct",
    "def_ast",
    "def_tov",
    "def_foul",
    "def_shooting_foul",
    "def_blk",
    "def_stl",
    "def_pts",
]

DEFENSIVE_INT_COLUMNS = {
    "def_fgm",
    "def_fga",
    "def_fg3m",
    "def_fg3a",
    "def_ftm",
    "def_fta",
    "def_ast",
    "def_tov",
    "def_foul",
    "def_shooting_foul",
    "def_blk",
    "def_stl",
    "def_pts",
}

DEFENSIVE_PCT_COLUMNS = {
    "def_fg_pct",
    "def_fg3_pct",
    "def_ft_pct",
}

DEFENSIVE_KEY_MAP = {
    "MIN": "minutes",
    "DEF_FGM": "def_fgm",
    "DEF_FGA": "def_fga",
    "DEF_FG_PCT": "def_fg_pct",
    "DEF_FG3M": "def_fg3m",
    "DEF_FG3A": "def_fg3a",
    "DEF_FG3_PCT": "def_fg3_pct",
    "DEF_FTM": "def_ftm",
    "DEF_FTA": "def_fta",
    "DEF_FT_PCT": "def_ft_pct",
    "DEF_AST": "def_ast",
    "DEF_TOV": "def_tov",
    "DEF_FOUL": "def_foul",
    "DEF_SHOOTING_FOUL": "def_shooting_foul",
    "DEF_BLK": "def_blk",
    "DEF_STL": "def_stl",
    "DEF_PTS": "def_pts",
}


def map_defensive_stats(stats: dict) -> dict:
    row: dict = {}
    for key, value in (stats or {}).items():
        column = DEFENSIVE_KEY_MAP.get(key)
        if not column:
            continue

        if column == "minutes":
            parsed = parse_minutes_interval(value)
        elif column in DEFENSIVE_INT_COLUMNS:
            parsed = parse_int(value)
        elif column in DEFENSIVE_PCT_COLUMNS:
            parsed = normalize_pct(value)
        else:
            parsed = parse_float(value)

        if parsed is None:
            continue

        row[column] = parsed
    return row


VIOLATIONS_PLAYER_COLUMNS = [
    "started",
    "minutes",
    "travel",
    "double_dribble",
    "discontinued_dribble",
    "off_three_sec",
    "def_three_sec",
    "inbound",
    "backcourt",
    "off_goaltending",
    "def_goaltending",
    "palming",
    "kicked_ball",
    "jump_ball",
    "lane",
    "charge",
    "off_foul",
]

VIOLATIONS_TEAM_COLUMNS = [
    "minutes",
    "travel",
    "double_dribble",
    "discontinued_dribble",
    "off_three_sec",
    "def_three_sec",
    "inbound",
    "backcourt",
    "off_goaltending",
    "def_goaltending",
    "palming",
    "kicked_ball",
    "jump_ball",
    "lane",
    "charge",
    "off_foul",
    "tm_delay_of_game",
    "tm_eight_sec",
    "tm_five_sec",
    "tm_shot_clock",
]

VIOLATIONS_COUNT_KEY_MAP = {
    "TRAVEL": "travel",
    "DOUBLE_DRIBBLE": "double_dribble",
    "DISCONTINUED_DRIBBLE": "discontinued_dribble",
    "OFF_THREE_SEC": "off_three_sec",
    "DEF_THREE_SEC": "def_three_sec",
    "INBOUND": "inbound",
    "BACKCOURT": "backcourt",
    "OFF_GOALTENDING": "off_goaltending",
    "DEF_GOALTENDING": "def_goaltending",
    "PALMING": "palming",
    "KICKED_BALL": "kicked_ball",
    "JUMP_BALL": "jump_ball",
    "LANE": "lane",
    "CHARGE": "charge",
    "OFF_FOUL": "off_foul",
}

VIOLATIONS_TEAM_KEY_MAP = {
    **VIOLATIONS_COUNT_KEY_MAP,
    "TM_DELAY_OF_GAME": "tm_delay_of_game",
    "TM_EIGHT_SEC": "tm_eight_sec",
    "TM_FIVE_SEC": "tm_five_sec",
    "TM_SHOT_CLOCK": "tm_shot_clock",
}


def map_violations_player_stats(stats: dict) -> dict:
    row: dict = {}
    if stats is None:
        return row

    started_value = stats.get("STARTED")
    if started_value is not None:
        row["started"] = to_bool(started_value)

    minutes_value = stats.get("MIN")
    if minutes_value is not None:
        row["minutes"] = parse_minutes_interval(minutes_value)

    for key, column in VIOLATIONS_COUNT_KEY_MAP.items():
        if key not in stats:
            continue
        parsed = parse_int(stats.get(key))
        if parsed is None:
            continue
        row[column] = parsed

    return row


def map_violations_team_stats(stats: dict) -> dict:
    row: dict = {}
    if stats is None:
        return row

    minutes_value = stats.get("MIN")
    if minutes_value is not None:
        row["minutes"] = parse_minutes_interval(minutes_value)

    for key, column in VIOLATIONS_TEAM_KEY_MAP.items():
        if key not in stats:
            continue
        parsed = parse_int(stats.get(key))
        if parsed is None:
            continue
        row[column] = parsed

    return row


def camel_to_snake(name: str) -> str:
    out = ""
    for char in name:
        if char.isupper():
            out += f"_{char.lower()}"
        else:
            out += char
    return out.lstrip("_")


ADVANCED_KEY_ALIASES = {
    "ast_to": "ast_to_ratio",
}

ADVANCED_PCT_NEEDS_NORMALIZE = {
    "tm_tov_pct",
}


def map_advanced_stats(stats: dict) -> dict:
    result: dict = {}
    for key, value in stats.items():
        column = camel_to_snake(key)
        column = ADVANCED_KEY_ALIASES.get(column, column)
        if column not in ADVANCED_COLUMNS:
            continue

        parsed = value
        if column == "minutes":
            parsed = parse_minutes_interval(value)
        elif column == "poss":
            parsed = parse_int(value)
        else:
            parsed = parse_float(value)

        if parsed is None:
            continue

        if column in ADVANCED_PCT_NEEDS_NORMALIZE and parsed > 1:
            parsed = parsed / 100

        result[column] = parsed
    return result


def fill_missing_advanced_team_pace(team_rows: list[dict]) -> None:
    """Fill pace fields when /api/stats/boxscore Advanced omits team pace."""
    if not team_rows:
        return

    # Preferred derivation uses both teams' possessions to mirror NBA pace.
    # pace = ((team_poss + opp_poss) / 2) * (240 / team_minutes)
    if len(team_rows) == 2:
        poss_values = [parse_float(row.get("poss")) for row in team_rows]
        if poss_values[0] is not None and poss_values[1] is not None:
            for idx, row in enumerate(team_rows):
                minutes = parse_float(row.get("minutes"))
                if minutes is None or minutes <= 0:
                    continue

                pace_value = ((poss_values[idx] + poss_values[1 - idx]) / 2.0) * (240.0 / minutes)
                if row.get("pace") is None:
                    row["pace"] = round(pace_value, 2)
                if row.get("pace_per40") is None:
                    row["pace_per40"] = round(pace_value * (40.0 / 48.0), 2)

    # Fallback (if only one side is available): possessions scaled to 48 minutes.
    for row in team_rows:
        if row.get("pace") is None:
            poss = parse_float(row.get("poss"))
            minutes = parse_float(row.get("minutes"))
            if poss is not None and minutes is not None and minutes > 0:
                row["pace"] = round(poss * (240.0 / minutes), 2)

        if row.get("pace_per40") is None:
            pace_value = parse_float(row.get("pace"))
            if pace_value is not None:
                row["pace_per40"] = round(pace_value * (40.0 / 48.0), 2)


def normalize_tracking_key(key: str) -> str:
    if not key:
        return ""
    cleaned = key.replace("%", "pct").replace("-", "_").replace(" ", "_")
    if cleaned.isupper() or "_" in cleaned:
        normalized = cleaned.lower()
    else:
        normalized = camel_to_snake(cleaned)
    if normalized.startswith("tracking_"):
        normalized = normalized[len("tracking_"):]
    return normalized


def normalize_pct(value):
    parsed = parse_float(value)
    if parsed is None:
        return None
    if parsed > 1:
        return parsed / 100
    return parsed


def map_tracking_stats(stats: dict) -> dict:
    row: dict = {}
    for key, value in stats.items():
        normalized = normalize_tracking_key(key)
        column = TRACKING_KEY_MAP.get(normalized)
        if not column:
            continue
        if column == "minutes":
            parsed = parse_minutes_interval(value)
        elif column in TRACKING_INT_COLUMNS:
            parsed = parse_int(value)
        elif column in TRACKING_PCT_COLUMNS:
            parsed = normalize_pct(value)
        else:
            parsed = parse_float(value)
        if parsed is None:
            continue

        row[column] = parsed

        # Query Tool currently emits PASS_TOUCH; keep the legacy touches column
        # populated for downstream compatibility.
        if column == "pass_touch" and row.get("touches") is None:
            row["touches"] = parsed
    return row


def compute_fg2(stats_row: dict):
    fgm = stats_row.get("fgm")
    fga = stats_row.get("fga")
    fg3m = stats_row.get("fg3m")
    fg3a = stats_row.get("fg3a")

    if fgm is not None and fg3m is not None:
        stats_row["fg2m"] = fgm - fg3m
    if fga is not None and fg3a is not None:
        stats_row["fg2a"] = fga - fg3a
    fg2a = stats_row.get("fg2a")
    fg2m = stats_row.get("fg2m")
    if fg2a and fg2m is not None and fg2a > 0:
        stats_row["fg2_pct"] = fg2m / fg2a


def get_attr(attrs: dict, *keys: str):
    for key in keys:
        value = attrs.get(key)
        if value not in (None, ""):
            return value
    return None


def parse_hustle_boxscore(xml_text: str | None, game_id: str, fetched_at: datetime) -> tuple[list[dict], list[dict]]:
    if not xml_text:
        return [], []
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return [], []

    player_rows: list[dict] = []
    team_rows: list[dict] = []

    for team in root.findall(".//Player_Stats/Team"):
        team_id = parse_int(get_attr(team.attrib, "Team_id", "TeamID", "TeamId"))
        if team_id is None:
            continue
        for player in team.findall("Player"):
            nba_id = parse_int(get_attr(player.attrib, "Person_id", "PersonID", "PersonId"))
            if nba_id is None:
                continue
            row = {
                "game_id": game_id,
                "nba_id": nba_id,
                "team_id": team_id,
                "minutes": parse_minutes_interval(
                    get_attr(player.attrib, "MIN", "MINUTES", "Minutes", "Min")
                ),
                "created_at": fetched_at,
                "updated_at": fetched_at,
                "fetched_at": fetched_at,
            }
            for column in HUSTLE_PLAYER_COLUMNS:
                row[column] = None
            for attr, (column, parser) in HUSTLE_PLAYER_MAP.items():
                value = player.attrib.get(attr)
                parsed = parser(value)
                if parsed is not None:
                    row[column] = parsed
            player_rows.append(row)

    for team_stat in root.findall(".//Team_Stats"):
        team_id = parse_int(get_attr(team_stat.attrib, "Team_id", "TeamID", "TeamId"))
        if team_id is None:
            continue
        row = {
            "game_id": game_id,
            "team_id": team_id,
            "created_at": fetched_at,
            "updated_at": fetched_at,
            "fetched_at": fetched_at,
        }
        for column in HUSTLE_TEAM_COLUMNS:
            row[column] = None
        for attr, (column, parser) in HUSTLE_TEAM_MAP.items():
            value = team_stat.attrib.get(attr)
            parsed = parser(value)
            if parsed is not None:
                row[column] = parsed
        team_rows.append(row)

    return player_rows, team_rows


def parse_hustle_events(xml_text: str | None) -> dict | None:
    if not xml_text:
        return None
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return None

    events = [event.attrib for event in root.findall(".//Event")]
    return {"attributes": root.attrib, "events": events}


def chunked(values: list[str], size: int) -> list[list[str]]:
    if size <= 0:
        size = 1
    return [values[i:i + size] for i in range(0, len(values), size)]


def split_batch(values: list[str]) -> tuple[list[str], list[str]]:
    midpoint = max(1, len(values) // 2)
    return values[:midpoint], values[midpoint:]


def fetch_querytool_batched_rows(
    client: httpx.Client,
    path: str,
    base_params: dict,
    game_ids: list[str],
    row_key: str,
    batch_size: int,
    max_rows_returned: int = TRACKING_MAX_ROWS_RETURNED,
    truncation_threshold: int = QUERY_TOOL_TRUNCATION_THRESHOLD,
    single_batch_max_attempts: int = 4,
) -> tuple[list[dict], list[str], dict]:
    pending_batches = chunked(game_ids, batch_size)
    all_rows: list[dict] = []
    warnings: list[str] = []
    single_batch_attempts: dict[str, int] = {}

    metrics = {
        "batch_size": batch_size,
        "initial_batch_count": len(pending_batches),
        "batch_attempt_count": 0,
        "completed_batch_count": 0,
        "split_batch_count": 0,
        "single_batch_retry_count": 0,
        "rows_seen": 0,
        "rows_emitted": 0,
        "truncation_warning_count": 0,
        "duration_ms": 0.0,
    }

    started_perf = time.perf_counter()

    while pending_batches:
        batch = pending_batches.pop(0)
        if not batch:
            continue

        metrics["batch_attempt_count"] += 1

        params = dict(base_params)
        params["GameId"] = ",".join(batch)
        params["MaxRowsReturned"] = max_rows_returned

        batch_key = ",".join(batch)

        try:
            payload = request_json(
                client,
                path,
                params,
                retries=1,
                base_url=QUERY_TOOL_URL,
            )
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code if exc.response is not None else None
            if status in {414, 429, 500, 502, 503, 504} and len(batch) > 1:
                left, right = split_batch(batch)
                pending_batches = [left, right, *pending_batches]
                metrics["split_batch_count"] += 1
                continue

            if status in {414, 429, 500, 502, 503, 504}:
                attempts = single_batch_attempts.get(batch_key, 0) + 1
                single_batch_attempts[batch_key] = attempts
                if attempts < single_batch_max_attempts:
                    time.sleep(min(5, attempts))
                    pending_batches.append(batch)
                    metrics["single_batch_retry_count"] += 1
                    continue

                warnings.append(
                    f"{path} batch ({batch[0]}...{batch[-1]}) failed with HTTP {status} "
                    f"after {attempts} attempts; skipping"
                )
                continue

            raise
        except httpx.HTTPError as exc:
            if len(batch) > 1:
                left, right = split_batch(batch)
                pending_batches = [left, right, *pending_batches]
                metrics["split_batch_count"] += 1
                continue

            attempts = single_batch_attempts.get(batch_key, 0) + 1
            single_batch_attempts[batch_key] = attempts
            if attempts < single_batch_max_attempts:
                time.sleep(min(5, attempts))
                pending_batches.append(batch)
                metrics["single_batch_retry_count"] += 1
                continue

            warnings.append(
                f"{path} batch ({batch[0]}...{batch[-1]}) transport error ({exc}) "
                f"after {attempts} attempts; skipping"
            )
            continue

        rows = payload.get(row_key) or []
        rows_returned = parse_int((payload.get("meta") or {}).get("rowsReturned"))
        metrics["rows_seen"] += len(rows)

        suspicious = (
            (rows_returned is not None and rows_returned >= truncation_threshold)
            or len(rows) >= truncation_threshold
        )

        if suspicious and len(batch) > 1:
            left, right = split_batch(batch)
            pending_batches = [left, right, *pending_batches]
            metrics["split_batch_count"] += 1
            continue

        if suspicious:
            warnings.append(
                f"{path} batch for game {batch[0]} may be truncated "
                f"(rows={len(rows)}, rowsReturned={rows_returned})"
            )
            metrics["truncation_warning_count"] += 1

        all_rows.extend(rows)
        metrics["rows_emitted"] += len(rows)
        metrics["completed_batch_count"] += 1

    metrics["duration_ms"] = elapsed_ms(started_perf)
    return all_rows, warnings, metrics


def build_tracking_row(player: dict, fallback_game_id: str, fetched_at: datetime) -> dict | None:
    nba_id = parse_int(player.get("playerId"))
    if nba_id is None:
        return None

    team_id = parse_int(player.get("teamId"))
    if team_id == 0:
        team_id = None

    row = {
        "game_id": player.get("gameId") or fallback_game_id,
        "nba_id": nba_id,
        "team_id": team_id,
        "created_at": fetched_at,
        "updated_at": fetched_at,
        "fetched_at": fetched_at,
    }
    for column in TRACKING_COLUMNS:
        row[column] = None

    raw_tracking_stats = player.get("stats") or {}
    row["tracking_stats_json"] = Json(raw_tracking_stats) if raw_tracking_stats else None
    row.update(map_tracking_stats(raw_tracking_stats))
    return row


def build_defensive_row(player: dict, fetched_at: datetime) -> dict | None:
    nba_id = parse_int(player.get("playerId"))
    if nba_id is None:
        return None

    team_id = parse_int(player.get("teamId"))
    if team_id == 0:
        team_id = None

    game_id = player.get("gameId")
    if not game_id:
        return None

    row = {
        "game_id": game_id,
        "nba_id": nba_id,
        "team_id": team_id,
        "created_at": fetched_at,
        "updated_at": fetched_at,
        "fetched_at": fetched_at,
    }
    for column in DEFENSIVE_COLUMNS:
        row[column] = None

    raw_stats = player.get("stats") or {}
    row["defensive_stats_json"] = Json(raw_stats) if raw_stats else None
    row.update(map_defensive_stats(raw_stats))
    return row


def build_violations_player_row(player: dict, fetched_at: datetime) -> dict | None:
    nba_id = parse_int(player.get("playerId"))
    if nba_id is None:
        return None

    team_id = parse_int(player.get("teamId"))
    if team_id == 0:
        team_id = None

    game_id = player.get("gameId")
    if not game_id:
        return None

    row = {
        "game_id": game_id,
        "nba_id": nba_id,
        "team_id": team_id,
        "created_at": fetched_at,
        "updated_at": fetched_at,
        "fetched_at": fetched_at,
    }
    for column in VIOLATIONS_PLAYER_COLUMNS:
        row[column] = None

    raw_stats = player.get("stats") or {}
    row["violations_stats_json"] = Json(raw_stats) if raw_stats else None
    row.update(map_violations_player_stats(raw_stats))
    return row


def build_violations_team_row(team: dict, fetched_at: datetime) -> dict | None:
    team_id = parse_int(team.get("teamId"))
    if team_id is None:
        return None

    game_id = team.get("gameId")
    if not game_id:
        return None

    row = {
        "game_id": game_id,
        "team_id": team_id,
        "created_at": fetched_at,
        "updated_at": fetched_at,
        "fetched_at": fetched_at,
    }
    for column in VIOLATIONS_TEAM_COLUMNS:
        row[column] = None

    raw_stats = team.get("stats") or {}
    row["violations_stats_json"] = Json(raw_stats) if raw_stats else None
    row.update(map_violations_team_stats(raw_stats))
    return row


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────


def fetch_legacy_game_payloads(
    game_id_value: str,
    status: int | None,
    allow_unknown_final: bool,
    fetched_at: datetime,
    fetch_plan: dict[str, bool],
) -> dict:
    is_final = status == 3 or (allow_unknown_final and status is None)

    fetch_traditional = bool(fetch_plan.get("traditional", True))
    fetch_advanced = bool(fetch_plan.get("advanced", is_final))
    fetch_pbp = bool(fetch_plan.get("pbp", True))
    fetch_poc = bool(fetch_plan.get("poc", True))
    fetch_hustle_boxscore = bool(fetch_plan.get("hustle_boxscore", is_final))
    fetch_hustle_events = bool(fetch_plan.get("hustle_events", is_final))

    if not is_final:
        fetch_advanced = False
        fetch_hustle_boxscore = False
        fetch_hustle_events = False

    api_calls = {
        "boxscore_traditional": 0,
        "boxscore_advanced": 0,
        "pbp": 0,
        "poc": 0,
        "hustle_boxscore": 0,
        "hustle_events": 0,
    }
    api_duration_ms = {
        "boxscore_traditional": 0.0,
        "boxscore_advanced": 0.0,
        "pbp": 0.0,
        "poc": 0.0,
        "hustle_boxscore": 0.0,
        "hustle_events": 0.0,
    }

    player_rows: list[dict] = []
    team_rows: list[dict] = []
    advanced_rows: list[dict] = []
    advanced_team_rows: list[dict] = []
    pbp_rows: list[dict] = []
    poc_rows: list[dict] = []
    hustle_player_rows: list[dict] = []
    hustle_team_rows: list[dict] = []
    hustle_event_rows: list[dict] = []
    endpoint_errors: list[str] = []

    game_started_perf = time.perf_counter()

    with httpx.Client(timeout=30) as client:
        # Traditional boxscore
        boxscore: dict = {}
        if fetch_traditional:
            try:
                call_started = time.perf_counter()
                boxscore = request_json(
                    client,
                    "/api/stats/boxscore",
                    {"gameId": game_id_value, "measureType": "Traditional"},
                )
                api_calls["boxscore_traditional"] += 1
                api_duration_ms["boxscore_traditional"] += elapsed_ms(call_started)
            except Exception as exc:
                endpoint_errors.append(f"boxscore_traditional: {exc}")

        home_team = boxscore.get("homeTeam") or {}
        away_team = boxscore.get("awayTeam") or {}

        for team in [home_team, away_team]:
            team_id = team.get("teamId")
            team_stats = team.get("statistics") or {}

            team_row = {
                "game_id": game_id_value,
                "team_id": team_id,
                "minutes": parse_iso_duration(team_stats.get("minutes")),
                "created_at": fetched_at,
                "updated_at": fetched_at,
                "fetched_at": fetched_at,
            }
            for key, column in TEAM_STAT_MAP.items():
                if key in team_stats:
                    team_row[column] = team_stats.get(key)

            compute_fg2(team_row)
            team_rows.append(team_row)

            for player in team.get("players") or []:
                stats = player.get("statistics") or {}
                row = {
                    "game_id": game_id_value,
                    "nba_id": player.get("personId"),
                    "team_id": team_id,
                    "status": empty_to_none(player.get("status")),
                    "not_playing_reason": empty_to_none(player.get("notPlayingReason")),
                    "not_playing_description": empty_to_none(player.get("notPlayingDescription")),
                    "order_sequence": player.get("order"),
                    "jersey_num": empty_to_none(player.get("jerseyNum")),
                    "position": empty_to_none(player.get("position")),
                    "is_starter": to_bool(player.get("starter")),
                    "is_on_court": to_bool(player.get("oncourt")),
                    "played": to_bool(player.get("played")),
                    "minutes": parse_iso_duration(stats.get("minutes")),
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
                for key, column in PLAYER_STAT_MAP.items():
                    if key in stats:
                        row[column] = stats.get(key)

                compute_fg2(row)
                player_rows.append(row)

        # Advanced boxscore (only if Final)
        if fetch_advanced:
            advanced: dict = {}
            try:
                call_started = time.perf_counter()
                advanced = request_json(
                    client,
                    "/api/stats/boxscore",
                    {"gameId": game_id_value, "measureType": "Advanced"},
                )
                api_calls["boxscore_advanced"] += 1
                api_duration_ms["boxscore_advanced"] += elapsed_ms(call_started)
            except Exception as exc:
                endpoint_errors.append(f"boxscore_advanced: {exc}")

            adv_home = advanced.get("homeTeam") or {}
            adv_away = advanced.get("awayTeam") or {}
            advanced_team_rows_for_game: list[dict] = []

            for team in [adv_home, adv_away]:
                team_id = team.get("teamId")
                team_stats = team.get("statistics") or {}

                if team_id is not None:
                    team_row = {
                        "game_id": game_id_value,
                        "team_id": team_id,
                        "minutes": parse_iso_duration(team_stats.get("minutes")),
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                    team_row.update(map_advanced_stats(team_stats))
                    team_row = {k: v for k, v in team_row.items() if k in ADVANCED_TEAM_ALLOWED_COLUMNS}
                    advanced_team_rows_for_game.append(team_row)

                for player in team.get("players") or []:
                    stats = player.get("statistics") or {}
                    row = {
                        "game_id": game_id_value,
                        "nba_id": player.get("personId"),
                        "team_id": team_id,
                        "minutes": parse_iso_duration(stats.get("minutes")),
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                    row.update(map_advanced_stats(stats))
                    advanced_rows.append(row)

            fill_missing_advanced_team_pace(advanced_team_rows_for_game)
            advanced_team_rows.extend(advanced_team_rows_for_game)

        # Play-by-play
        if fetch_pbp:
            try:
                call_started = time.perf_counter()
                pbp = request_json(client, "/api/stats/pbp", {"gameId": game_id_value})
                api_calls["pbp"] += 1
                api_duration_ms["pbp"] += elapsed_ms(call_started)
                pbp_rows.append(
                    {
                        "game_id": game_id_value,
                        "pbp_json": Json(pbp) if pbp else None,
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )
            except Exception as exc:
                endpoint_errors.append(f"pbp: {exc}")

        # Players on court
        if fetch_poc:
            try:
                call_started = time.perf_counter()
                poc = request_json(client, "/api/stats/poc", {"gameId": game_id_value})
                api_calls["poc"] += 1
                api_duration_ms["poc"] += elapsed_ms(call_started)
                poc_rows.append(
                    {
                        "game_id": game_id_value,
                        "poc_json": Json(poc) if poc else None,
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )
            except Exception as exc:
                endpoint_errors.append(f"poc: {exc}")

        # Hustle stats + events (final games only)
        if fetch_hustle_boxscore:
            try:
                call_started = time.perf_counter()
                hustle_box = request_xml(client, f"/{game_id_value}_hustlestats.xml")
                api_calls["hustle_boxscore"] += 1
                api_duration_ms["hustle_boxscore"] += elapsed_ms(call_started)
                player_stats, team_stats = parse_hustle_boxscore(hustle_box, game_id_value, fetched_at)
                hustle_player_rows.extend(player_stats)
                hustle_team_rows.extend(team_stats)
            except Exception as exc:
                endpoint_errors.append(f"hustle_boxscore: {exc}")

        if fetch_hustle_events:
            try:
                call_started = time.perf_counter()
                hustle_events_xml = request_xml(client, f"/{game_id_value}_HustleStatsGameEvents.xml")
                api_calls["hustle_events"] += 1
                api_duration_ms["hustle_events"] += elapsed_ms(call_started)
                hustle_events_payload = parse_hustle_events(hustle_events_xml)
                if hustle_events_payload is not None:
                    hustle_event_rows.append(
                        {
                            "game_id": game_id_value,
                            "hustle_events_json": Json(hustle_events_payload),
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                    )
            except Exception as exc:
                endpoint_errors.append(f"hustle_events: {exc}")

    return {
        "game_id": game_id_value,
        "is_final": is_final,
        "fetch_plan": {
            "traditional": fetch_traditional,
            "advanced": fetch_advanced,
            "pbp": fetch_pbp,
            "poc": fetch_poc,
            "hustle_boxscore": fetch_hustle_boxscore,
            "hustle_events": fetch_hustle_events,
        },
        "player_rows": player_rows,
        "team_rows": team_rows,
        "advanced_rows": advanced_rows,
        "advanced_team_rows": advanced_team_rows,
        "pbp_rows": pbp_rows,
        "poc_rows": poc_rows,
        "hustle_player_rows": hustle_player_rows,
        "hustle_team_rows": hustle_team_rows,
        "hustle_event_rows": hustle_event_rows,
        "api_calls": api_calls,
        "api_duration_ms": api_duration_ms,
        "errors": endpoint_errors,
        "duration_ms": elapsed_ms(game_started_perf),
    }

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
    started_perf = time.perf_counter()

    telemetry = {
        "config": {
            "concurrency": GAME_DATA_CONCURRENCY,
            "include_per_game_metrics": GAME_DATA_INCLUDE_PER_GAME_METRICS,
            "skip_existing_on_season_backfill": GAME_DATA_SKIP_EXISTING_ON_SEASON_BACKFILL,
            "tracking_batch_size": TRACKING_BATCH_SIZE,
            "defensive_batch_size": DEFENSIVE_BATCH_SIZE,
            "violations_batch_size": VIOLATIONS_BATCH_SIZE,
            "violations_team_batch_size": VIOLATIONS_TEAM_BATCH_SIZE,
            "querytool_max_rows": TRACKING_MAX_ROWS_RETURNED,
            "querytool_truncation_threshold": QUERY_TOOL_TRUNCATION_THRESHOLD,
            "event_streams_extracted": True,
        },
        "game_selection": {
            "source": "",
            "candidate_games": 0,
            "season_type_filtered_games": 0,
            "selected_games": 0,
            "final_games": 0,
            "duration_ms": 0.0,
        },
        "legacy_fetch": {
            "worker_count": 0,
            "scheduled_games": 0,
            "completed_games": 0,
            "failed_games": 0,
            "endpoint_error_count": 0,
            "duration_ms": 0.0,
            "api_calls": {
                "boxscore_traditional": 0,
                "boxscore_advanced": 0,
                "pbp": 0,
                "poc": 0,
                "hustle_boxscore": 0,
                "hustle_events": 0,
            },
            "api_duration_ms": {
                "boxscore_traditional": 0.0,
                "boxscore_advanced": 0.0,
                "pbp": 0.0,
                "poc": 0.0,
                "hustle_boxscore": 0.0,
                "hustle_events": 0.0,
            },
            "coverage": {},
            "per_game_metrics": [] if GAME_DATA_INCLUDE_PER_GAME_METRICS else None,
        },
        "querytool": {
            "game_id_count": 0,
            "coverage": {},
            "duration_ms": 0.0,
            "tracking": {},
            "defensive": {},
            "violations_player": {},
            "violations_team": {},
        },
        "upsert": {
            "executed": False,
            "duration_ms": 0.0,
        },
        "duration_ms": 0.0,
    }

    conn: psycopg.Connection | None = None
    try:
        season_label_value = season_label
        season_type_value = season_type or "Regular Season"
        normalized_mode = (mode or "refresh").strip().lower()
        desired_season_type = normalize_season_type(season_type_value)

        conn = psycopg.connect(os.environ["POSTGRES_URL"])

        errors: list[str] = []
        player_rows: list[dict] = []
        team_rows: list[dict] = []
        advanced_rows: list[dict] = []
        advanced_team_rows: list[dict] = []
        pbp_rows: list[dict] = []
        poc_rows: list[dict] = []
        hustle_player_rows: list[dict] = []
        hustle_team_rows: list[dict] = []
        hustle_event_rows: list[dict] = []
        tracking_rows: list[dict] = []
        defensive_rows: list[dict] = []
        violations_player_rows: list[dict] = []
        violations_team_rows: list[dict] = []

        game_list: list[tuple[str, int | None]] = []
        game_id_list: list[str] = []

        game_resolution_started = time.perf_counter()
        if game_ids:
            game_id_list = [gid.strip() for gid in game_ids.split(",") if gid.strip()]
            if game_id_list:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT game_id, game_status FROM nba.games WHERE game_id = ANY(%s)",
                        (game_id_list,),
                    )
                    status_map = {row[0]: row[1] for row in cur.fetchall()}
                game_list = [(gid, status_map.get(gid)) for gid in game_id_list]

            telemetry["game_selection"].update(
                {
                    "source": "game_ids",
                    "candidate_games": len(game_id_list),
                    "season_type_filtered_games": len(game_list),
                    "selected_games": len(game_list),
                }
            )
        else:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date, season_label)
            season_label_filter = season_label_value or None
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

            game_candidates = len(game_rows)
            if desired_season_type:
                game_rows = [
                    (gid, status, game_season_type)
                    for gid, status, game_season_type in game_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                ]

            game_list = [(gid, status) for gid, status, _ in game_rows]

            telemetry["game_selection"].update(
                {
                    "source": "nba.games",
                    "candidate_games": game_candidates,
                    "season_type_filtered_games": len(game_rows),
                    "selected_games": len(game_list),
                    "date_range": {
                        "start": start_dt.isoformat(),
                        "end": end_dt.isoformat(),
                    },
                    "only_final_games": bool(only_final_games),
                }
            )

        allow_unknown_final = bool(game_id_list)
        if only_final_games:
            if allow_unknown_final:
                game_list = [(gid, status) for gid, status in game_list if status in (None, 3)]
            else:
                game_list = [(gid, status) for gid, status in game_list if status == 3]

        telemetry["game_selection"]["selected_games"] = len(game_list)
        final_game_count = sum(
            1
            for _, status in game_list
            if status == 3 or (allow_unknown_final and status is None)
        )
        telemetry["game_selection"]["final_games"] = final_game_count
        telemetry["game_selection"]["duration_ms"] = elapsed_ms(game_resolution_started)

        fetched_at = now_utc()

        selected_game_ids = [gid for gid, _ in game_list]
        final_game_ids = [
            gid
            for gid, status in game_list
            if status == 3 or (allow_unknown_final and status is None)
        ]

        enable_skip_existing = (
            GAME_DATA_SKIP_EXISTING_ON_SEASON_BACKFILL
            and normalized_mode == "season_backfill"
            and not bool(game_id_list)
        )

        missing_traditional = set(selected_game_ids)
        missing_advanced = set(final_game_ids)
        missing_pbp = set(selected_game_ids)
        missing_poc = set(selected_game_ids)
        missing_hustle_boxscore = set(final_game_ids)
        missing_hustle_events = set(final_game_ids)

        if enable_skip_existing:
            missing_traditional = set(selected_game_ids) - fetch_existing_game_ids(
                conn,
                "nba.boxscores_traditional_team",
                selected_game_ids,
            )
            missing_advanced = set(final_game_ids) - fetch_existing_game_ids(
                conn,
                "nba.boxscores_advanced_team",
                final_game_ids,
            )
            missing_pbp = set(selected_game_ids) - fetch_existing_game_ids(
                conn,
                "nba.play_by_play",
                selected_game_ids,
            )
            missing_poc = set(selected_game_ids) - fetch_existing_game_ids(
                conn,
                "nba.players_on_court",
                selected_game_ids,
            )
            missing_hustle_boxscore = set(final_game_ids) - fetch_existing_game_ids(
                conn,
                "nba.hustle_stats_team",
                final_game_ids,
            )
            missing_hustle_events = set(final_game_ids) - fetch_existing_game_ids(
                conn,
                "nba.hustle_events",
                final_game_ids,
            )

        legacy_game_plans: list[tuple[str, int | None, dict[str, bool]]] = []
        for gid, status in game_list:
            is_final = status == 3 or (allow_unknown_final and status is None)
            plan = {
                "traditional": gid in missing_traditional,
                "advanced": is_final and gid in missing_advanced,
                "pbp": gid in missing_pbp,
                "poc": gid in missing_poc,
                "hustle_boxscore": is_final and gid in missing_hustle_boxscore,
                "hustle_events": is_final and gid in missing_hustle_events,
            }
            if any(plan.values()):
                legacy_game_plans.append((gid, status, plan))

        legacy_section_fetch_counts = {
            "traditional": 0,
            "advanced": 0,
            "pbp": 0,
            "poc": 0,
            "hustle_boxscore": 0,
            "hustle_events": 0,
        }
        for _, _, plan in legacy_game_plans:
            for section, should_fetch in plan.items():
                if should_fetch:
                    legacy_section_fetch_counts[section] += 1

        telemetry["legacy_fetch"]["coverage"] = {
            "skip_existing_enabled": enable_skip_existing,
            "selected_games": len(game_list),
            "games_to_fetch": len(legacy_game_plans),
            "games_skipped": len(game_list) - len(legacy_game_plans),
            "section_selected": {
                "traditional": len(selected_game_ids),
                "advanced": len(final_game_ids),
                "pbp": len(selected_game_ids),
                "poc": len(selected_game_ids),
                "hustle_boxscore": len(final_game_ids),
                "hustle_events": len(final_game_ids),
            },
            "section_to_fetch": legacy_section_fetch_counts,
        }

        # --- Legacy per-game payloads (concurrent) ---
        legacy_started = time.perf_counter()
        worker_count = 1
        if legacy_game_plans:
            worker_count = min(max(1, GAME_DATA_CONCURRENCY), len(legacy_game_plans))
        telemetry["legacy_fetch"]["worker_count"] = worker_count
        telemetry["legacy_fetch"]["scheduled_games"] = len(legacy_game_plans)

        if worker_count <= 1:
            for game_id_value, status, fetch_plan in legacy_game_plans:
                try:
                    result = fetch_legacy_game_payloads(
                        game_id_value,
                        status,
                        allow_unknown_final,
                        fetched_at,
                        fetch_plan,
                    )
                except Exception as exc:
                    telemetry["legacy_fetch"]["failed_games"] += 1
                    errors.append(f"legacy game {game_id_value}: {exc}")
                    continue

                player_rows.extend(result["player_rows"])
                team_rows.extend(result["team_rows"])
                advanced_rows.extend(result["advanced_rows"])
                advanced_team_rows.extend(result["advanced_team_rows"])
                pbp_rows.extend(result["pbp_rows"])
                poc_rows.extend(result["poc_rows"])
                hustle_player_rows.extend(result["hustle_player_rows"])
                hustle_team_rows.extend(result["hustle_team_rows"])
                hustle_event_rows.extend(result["hustle_event_rows"])

                if result["errors"]:
                    telemetry["legacy_fetch"]["endpoint_error_count"] += len(result["errors"])
                    errors.extend(
                        [f"legacy game {result['game_id']} {endpoint_error}" for endpoint_error in result["errors"]]
                    )

                telemetry["legacy_fetch"]["completed_games"] += 1
                for key, value in result["api_calls"].items():
                    telemetry["legacy_fetch"]["api_calls"][key] += value
                for key, value in result["api_duration_ms"].items():
                    telemetry["legacy_fetch"]["api_duration_ms"][key] += value

                if telemetry["legacy_fetch"]["per_game_metrics"] is not None:
                    telemetry["legacy_fetch"]["per_game_metrics"].append(
                        {
                            "game_id": result["game_id"],
                            "is_final": result["is_final"],
                            "duration_ms": result["duration_ms"],
                            "fetch_plan": result.get("fetch_plan") or {},
                        }
                    )
        else:
            with ThreadPoolExecutor(max_workers=worker_count) as executor:
                future_map = {
                    executor.submit(
                        fetch_legacy_game_payloads,
                        game_id_value,
                        status,
                        allow_unknown_final,
                        fetched_at,
                        fetch_plan,
                    ): game_id_value
                    for game_id_value, status, fetch_plan in legacy_game_plans
                }

                for future in as_completed(future_map):
                    game_id_value = future_map[future]
                    try:
                        result = future.result()
                    except Exception as exc:
                        telemetry["legacy_fetch"]["failed_games"] += 1
                        errors.append(f"legacy game {game_id_value}: {exc}")
                        continue

                    player_rows.extend(result["player_rows"])
                    team_rows.extend(result["team_rows"])
                    advanced_rows.extend(result["advanced_rows"])
                    advanced_team_rows.extend(result["advanced_team_rows"])
                    pbp_rows.extend(result["pbp_rows"])
                    poc_rows.extend(result["poc_rows"])
                    hustle_player_rows.extend(result["hustle_player_rows"])
                    hustle_team_rows.extend(result["hustle_team_rows"])
                    hustle_event_rows.extend(result["hustle_event_rows"])

                    if result["errors"]:
                        telemetry["legacy_fetch"]["endpoint_error_count"] += len(result["errors"])
                        errors.extend(
                            [f"legacy game {result['game_id']} {endpoint_error}" for endpoint_error in result["errors"]]
                        )

                    telemetry["legacy_fetch"]["completed_games"] += 1
                    for key, value in result["api_calls"].items():
                        telemetry["legacy_fetch"]["api_calls"][key] += value
                    for key, value in result["api_duration_ms"].items():
                        telemetry["legacy_fetch"]["api_duration_ms"][key] += value

                    if telemetry["legacy_fetch"]["per_game_metrics"] is not None:
                        telemetry["legacy_fetch"]["per_game_metrics"].append(
                            {
                                "game_id": result["game_id"],
                                "is_final": result["is_final"],
                                "duration_ms": result["duration_ms"],
                                "fetch_plan": result.get("fetch_plan") or {},
                            }
                        )

        telemetry["legacy_fetch"]["duration_ms"] = elapsed_ms(legacy_started)

        # --- Query Tool batched tables (final games only) ---
        querytool_started = time.perf_counter()
        querytool_game_ids: list[str] = []
        if season_label_value and season_type_value:
            querytool_game_ids = list(final_game_ids)
        telemetry["querytool"]["game_id_count"] = len(querytool_game_ids)

        tracking_game_ids = list(querytool_game_ids)
        defensive_game_ids = list(querytool_game_ids)
        violations_player_game_ids = list(querytool_game_ids)
        violations_team_game_ids = list(querytool_game_ids)

        if enable_skip_existing and querytool_game_ids:
            existing_tracking = fetch_existing_game_ids(conn, "nba.tracking_stats", querytool_game_ids)
            existing_defensive = fetch_existing_game_ids(conn, "nba.defensive_stats", querytool_game_ids)
            existing_violations_player = fetch_existing_game_ids(conn, "nba.violations_player", querytool_game_ids)
            existing_violations_team = fetch_existing_game_ids(conn, "nba.violations_team", querytool_game_ids)

            tracking_game_ids = [gid for gid in querytool_game_ids if gid not in existing_tracking]
            defensive_game_ids = [gid for gid in querytool_game_ids if gid not in existing_defensive]
            violations_player_game_ids = [gid for gid in querytool_game_ids if gid not in existing_violations_player]
            violations_team_game_ids = [gid for gid in querytool_game_ids if gid not in existing_violations_team]

        telemetry["querytool"]["coverage"] = {
            "skip_existing_enabled": enable_skip_existing,
            "selected_final_games": len(querytool_game_ids),
            "to_fetch": {
                "tracking": len(tracking_game_ids),
                "defensive": len(defensive_game_ids),
                "violations_player": len(violations_player_game_ids),
                "violations_team": len(violations_team_game_ids),
            },
        }

        if season_label_value and season_type_value:
            with httpx.Client(timeout=60) as client:
                if tracking_game_ids:
                    tracking_payload_rows, tracking_warnings, tracking_metrics = fetch_querytool_batched_rows(
                        client=client,
                        path="/game/player",
                        base_params={
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type_value,
                            "Grouping": "None",
                            "TeamGrouping": "Y",
                            "MeasureType": "Tracking",
                        },
                        game_ids=tracking_game_ids,
                        row_key="players",
                        batch_size=TRACKING_BATCH_SIZE,
                        max_rows_returned=TRACKING_MAX_ROWS_RETURNED,
                    )
                    errors.extend([f"tracking_stats: {warning}" for warning in tracking_warnings])
                    for player in tracking_payload_rows:
                        row = build_tracking_row(player, fallback_game_id="", fetched_at=fetched_at)
                        if row is None or not row.get("game_id"):
                            continue
                        tracking_rows.append(row)
                    tracking_metrics["warnings"] = len(tracking_warnings)
                    tracking_metrics["rows_built"] = len(tracking_rows)
                    telemetry["querytool"]["tracking"] = tracking_metrics
                else:
                    telemetry["querytool"]["tracking"] = {
                        "skipped": True,
                        "reason": "coverage_complete",
                        "game_id_count": 0,
                    }

                if defensive_game_ids:
                    defensive_payload_rows, defensive_warnings, defensive_metrics = fetch_querytool_batched_rows(
                        client=client,
                        path="/game/player",
                        base_params={
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type_value,
                            "Grouping": "None",
                            "TeamGrouping": "Y",
                            "MeasureType": "Defensive",
                        },
                        game_ids=defensive_game_ids,
                        row_key="players",
                        batch_size=DEFENSIVE_BATCH_SIZE,
                        max_rows_returned=TRACKING_MAX_ROWS_RETURNED,
                    )
                    errors.extend([f"defensive_stats: {warning}" for warning in defensive_warnings])
                    for player in defensive_payload_rows:
                        row = build_defensive_row(player, fetched_at=fetched_at)
                        if row is None:
                            continue
                        defensive_rows.append(row)
                    defensive_metrics["warnings"] = len(defensive_warnings)
                    defensive_metrics["rows_built"] = len(defensive_rows)
                    telemetry["querytool"]["defensive"] = defensive_metrics
                else:
                    telemetry["querytool"]["defensive"] = {
                        "skipped": True,
                        "reason": "coverage_complete",
                        "game_id_count": 0,
                    }

                if violations_player_game_ids:
                    violations_payload_rows, violations_warnings, violations_metrics = fetch_querytool_batched_rows(
                        client=client,
                        path="/game/player",
                        base_params={
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type_value,
                            "Grouping": "None",
                            "TeamGrouping": "Y",
                            "MeasureType": "Violations",
                        },
                        game_ids=violations_player_game_ids,
                        row_key="players",
                        batch_size=VIOLATIONS_BATCH_SIZE,
                        max_rows_returned=TRACKING_MAX_ROWS_RETURNED,
                    )
                    errors.extend([f"violations_player: {warning}" for warning in violations_warnings])
                    for player in violations_payload_rows:
                        row = build_violations_player_row(player, fetched_at=fetched_at)
                        if row is None:
                            continue
                        violations_player_rows.append(row)
                    violations_metrics["warnings"] = len(violations_warnings)
                    violations_metrics["rows_built"] = len(violations_player_rows)
                    telemetry["querytool"]["violations_player"] = violations_metrics
                else:
                    telemetry["querytool"]["violations_player"] = {
                        "skipped": True,
                        "reason": "coverage_complete",
                        "game_id_count": 0,
                    }

                if violations_team_game_ids:
                    violations_team_payload_rows, violations_team_warnings, violations_team_metrics = fetch_querytool_batched_rows(
                        client=client,
                        path="/game/team",
                        base_params={
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type_value,
                            "Grouping": "None",
                            "MeasureType": "Violations",
                        },
                        game_ids=violations_team_game_ids,
                        row_key="teams",
                        batch_size=VIOLATIONS_TEAM_BATCH_SIZE,
                        max_rows_returned=TRACKING_MAX_ROWS_RETURNED,
                    )
                    errors.extend([f"violations_team: {warning}" for warning in violations_team_warnings])
                    for team in violations_team_payload_rows:
                        row = build_violations_team_row(team, fetched_at=fetched_at)
                        if row is None:
                            continue
                        violations_team_rows.append(row)
                    violations_team_metrics["warnings"] = len(violations_team_warnings)
                    violations_team_metrics["rows_built"] = len(violations_team_rows)
                    telemetry["querytool"]["violations_team"] = violations_team_metrics
                else:
                    telemetry["querytool"]["violations_team"] = {
                        "skipped": True,
                        "reason": "coverage_complete",
                        "game_id_count": 0,
                    }

        telemetry["querytool"]["duration_ms"] = elapsed_ms(querytool_started)

        inserted_players = 0
        inserted_teams = 0
        inserted_advanced = 0
        inserted_advanced_team = 0
        inserted_pbp = 0
        inserted_poc = 0
        inserted_hustle_players = 0
        inserted_hustle_teams = 0
        inserted_hustle_events = 0
        inserted_tracking = 0
        inserted_defensive = 0
        inserted_violations_player = 0
        inserted_violations_team = 0

        upsert_started = time.perf_counter()
        if not dry_run:
            telemetry["upsert"]["executed"] = True
            inserted_players = upsert(conn, "nba.boxscores_traditional", player_rows, ["game_id", "nba_id"], update_exclude=["created_at"])
            inserted_teams = upsert(conn, "nba.boxscores_traditional_team", team_rows, ["game_id", "team_id"], update_exclude=["created_at"])
            if advanced_rows:
                inserted_advanced = upsert(conn, "nba.boxscores_advanced", advanced_rows, ["game_id", "nba_id"], update_exclude=["created_at"])
            if advanced_team_rows:
                inserted_advanced_team = upsert(conn, "nba.boxscores_advanced_team", advanced_team_rows, ["game_id", "team_id"], update_exclude=["created_at"])
            inserted_pbp = upsert(conn, "nba.play_by_play", pbp_rows, ["game_id"], update_exclude=["created_at"])
            inserted_poc = upsert(conn, "nba.players_on_court", poc_rows, ["game_id"], update_exclude=["created_at"])
            if hustle_player_rows:
                inserted_hustle_players = upsert(
                    conn,
                    "nba.hustle_stats",
                    hustle_player_rows,
                    ["game_id", "nba_id"],
                    update_exclude=["created_at"],
                )
            if hustle_team_rows:
                inserted_hustle_teams = upsert(
                    conn,
                    "nba.hustle_stats_team",
                    hustle_team_rows,
                    ["game_id", "team_id"],
                    update_exclude=["created_at"],
                )
            if hustle_event_rows:
                inserted_hustle_events = upsert(
                    conn,
                    "nba.hustle_events",
                    hustle_event_rows,
                    ["game_id"],
                    update_exclude=["created_at"],
                )
            if tracking_rows:
                inserted_tracking = upsert(
                    conn,
                    "nba.tracking_stats",
                    tracking_rows,
                    ["game_id", "nba_id"],
                    update_exclude=["created_at"],
                )
            if defensive_rows:
                inserted_defensive = upsert(
                    conn,
                    "nba.defensive_stats",
                    defensive_rows,
                    ["game_id", "nba_id"],
                    update_exclude=["created_at"],
                )
            if violations_player_rows:
                inserted_violations_player = upsert(
                    conn,
                    "nba.violations_player",
                    violations_player_rows,
                    ["game_id", "nba_id"],
                    update_exclude=["created_at"],
                )
            if violations_team_rows:
                inserted_violations_team = upsert(
                    conn,
                    "nba.violations_team",
                    violations_team_rows,
                    ["game_id", "team_id"],
                    update_exclude=["created_at"],
                )
        telemetry["upsert"]["duration_ms"] = elapsed_ms(upsert_started)

        if conn:
            conn.close()

        telemetry["duration_ms"] = elapsed_ms(started_perf)

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {"table": "nba.boxscores_traditional", "rows": len(player_rows), "upserted": inserted_players},
                {"table": "nba.boxscores_traditional_team", "rows": len(team_rows), "upserted": inserted_teams},
                {"table": "nba.boxscores_advanced", "rows": len(advanced_rows), "upserted": inserted_advanced},
                {"table": "nba.boxscores_advanced_team", "rows": len(advanced_team_rows), "upserted": inserted_advanced_team},
                {"table": "nba.play_by_play", "rows": len(pbp_rows), "upserted": inserted_pbp},
                {"table": "nba.players_on_court", "rows": len(poc_rows), "upserted": inserted_poc},
                {"table": "nba.hustle_stats", "rows": len(hustle_player_rows), "upserted": inserted_hustle_players},
                {"table": "nba.hustle_stats_team", "rows": len(hustle_team_rows), "upserted": inserted_hustle_teams},
                {"table": "nba.hustle_events", "rows": len(hustle_event_rows), "upserted": inserted_hustle_events},
                {"table": "nba.tracking_stats", "rows": len(tracking_rows), "upserted": inserted_tracking},
                {"table": "nba.defensive_stats", "rows": len(defensive_rows), "upserted": inserted_defensive},
                {"table": "nba.violations_player", "rows": len(violations_player_rows), "upserted": inserted_violations_player},
                {"table": "nba.violations_team", "rows": len(violations_team_rows), "upserted": inserted_violations_team},
            ],
            "telemetry": telemetry,
            "errors": errors,
        }
    except Exception as exc:
        if conn:
            conn.close()

        telemetry["duration_ms"] = elapsed_ms(started_perf)

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "telemetry": telemetry,
            "errors": [str(exc)],
        }


if __name__ == "__main__":
    main()
