# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import os
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta, date

import httpx
import psycopg
from psycopg.types.json import Json

BASE_URL = "https://api.nba.com/v0"
HUSTLE_URL = "https://api.nba.com/v0/api/hustlestats"
QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"

TRACKING_BATCH_SIZE = 100
TRACKING_MAX_ROWS_RETURNED = 10000
QUERY_TOOL_TRUNCATION_THRESHOLD = 9900

DEFENSIVE_BATCH_SIZE = 100
VIOLATIONS_BATCH_SIZE = 100
VIOLATIONS_TEAM_BATCH_SIZE = 200

QUERYTOOL_EVENT_STREAM_MAX_ROWS_RETURNED = 10000
QUERYTOOL_EVENT_STREAM_BATCH_SIZES = {
    "TrackingPasses": 15,
    "DefensiveEvents": 30,
    "TrackingDrives": 50,
    "TrackingIsolations": 200,
    "TrackingPostUps": 200,
}
QUERYTOOL_EVENT_STREAM_TYPES = list(QUERYTOOL_EVENT_STREAM_BATCH_SIZES.keys())

QUERYTOOL_EVENT_STREAM_PER_MODE = "Totals"
QUERYTOOL_EVENT_STREAM_SUM_SCOPE = "Event"
QUERYTOOL_EVENT_STREAM_GROUPING = "None"
QUERYTOOL_EVENT_STREAM_TEAM_GROUPING = "Y"


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


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


def reduce_querytool_event_row(payload_row: dict) -> dict:
    stats = payload_row.get("stats") or {}
    team_id = parse_int(payload_row.get("teamId"))
    if team_id == 0:
        team_id = None

    return {
        "event_number": parse_int(payload_row.get("eventNumber")),
        "nba_id": parse_int(payload_row.get("playerId")),
        "team_id": team_id,
        "period": parse_int(payload_row.get("period")),
        "game_clock": parse_float(payload_row.get("gameClock")),
        "x": parse_int(payload_row.get("x")),
        "y": parse_int(payload_row.get("y")),
        "stats": stats,
    }


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
) -> tuple[list[dict], list[str]]:
    pending_batches = chunked(game_ids, batch_size)
    all_rows: list[dict] = []
    warnings: list[str] = []

    while pending_batches:
        batch = pending_batches.pop(0)
        if not batch:
            continue

        params = dict(base_params)
        params["GameId"] = ",".join(batch)
        params["MaxRowsReturned"] = max_rows_returned

        try:
            payload = request_json(
                client,
                path,
                params,
                base_url=QUERY_TOOL_URL,
            )
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code if exc.response is not None else None
            if status == 414 and len(batch) > 1:
                left, right = split_batch(batch)
                pending_batches = [left, right, *pending_batches]
                continue
            raise

        rows = payload.get(row_key) or []
        rows_returned = parse_int((payload.get("meta") or {}).get("rowsReturned"))
        suspicious = (
            (rows_returned is not None and rows_returned >= truncation_threshold)
            or len(rows) >= truncation_threshold
        )

        if suspicious and len(batch) > 1:
            left, right = split_batch(batch)
            pending_batches = [left, right, *pending_batches]
            continue

        if suspicious:
            warnings.append(
                f"{path} batch for game {batch[0]} may be truncated "
                f"(rows={len(rows)}, rowsReturned={rows_returned})"
            )

        all_rows.extend(rows)

    return all_rows, warnings


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

    try:
        season_label_value = season_label
        season_type_value = season_type or "Regular Season"
        desired_season_type = normalize_season_type(season_type_value)
        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        game_list: list[tuple[str, int | None]] = []
        game_id_list: list[str] = []
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

            if desired_season_type:
                game_rows = [
                    (gid, status, game_season_type)
                    for gid, status, game_season_type in game_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                ]

            game_list = [(gid, status) for gid, status, _ in game_rows]

        allow_unknown_final = bool(game_id_list)
        if only_final_games:
            if allow_unknown_final:
                game_list = [(gid, status) for gid, status in game_list if status in (None, 3)]
            else:
                game_list = [(gid, status) for gid, status in game_list if status == 3]

        fetched_at = now_utc()
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
        querytool_event_stream_rows_total = 0
        querytool_event_stream_upserted_total = 0
        querytool_game_ids: list[str] = []

        with httpx.Client(timeout=30) as client:
            for game_id_value, status in game_list:
                is_final = status == 3 or (allow_unknown_final and status is None)
                # Traditional boxscore
                boxscore = request_json(
                    client,
                    "/api/stats/boxscore",
                    {"gameId": game_id_value, "measureType": "Traditional"},
                )

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
                if is_final:
                    advanced = request_json(
                        client,
                        "/api/stats/boxscore",
                        {"gameId": game_id_value, "measureType": "Advanced"},
                    )
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
                pbp = request_json(client, "/api/stats/pbp", {"gameId": game_id_value})
                pbp_rows.append(
                    {
                        "game_id": game_id_value,
                        "pbp_json": Json(pbp) if pbp else None,
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )

                # Players on court
                poc = request_json(client, "/api/stats/poc", {"gameId": game_id_value})
                poc_rows.append(
                    {
                        "game_id": game_id_value,
                        "poc_json": Json(poc) if poc else None,
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )

                # Hustle stats + events (final games only)
                if is_final:
                    hustle_box = request_xml(client, f"/{game_id_value}_hustlestats.xml")
                    player_stats, team_stats = parse_hustle_boxscore(hustle_box, game_id_value, fetched_at)
                    hustle_player_rows.extend(player_stats)
                    hustle_team_rows.extend(team_stats)

                    hustle_events_xml = request_xml(client, f"/{game_id_value}_HustleStatsGameEvents.xml")
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

                # Query Tool game-level data (final games only, fetched in batched pass)
                if is_final and season_label_value and season_type_value:
                    querytool_game_ids.append(game_id_value)

            if querytool_game_ids and season_label_value and season_type_value:
                # --- Tracking stats (MeasureType=Tracking) ---
                tracking_payload_rows, tracking_warnings = fetch_querytool_batched_rows(
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
                    game_ids=querytool_game_ids,
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

                # --- Defensive attribution (MeasureType=Defensive) ---
                defensive_payload_rows, defensive_warnings = fetch_querytool_batched_rows(
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
                    game_ids=querytool_game_ids,
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

                # --- Violations (player) (MeasureType=Violations) ---
                violations_payload_rows, violations_warnings = fetch_querytool_batched_rows(
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
                    game_ids=querytool_game_ids,
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

                # --- Violations (team) (MeasureType=Violations) ---
                violations_team_payload_rows, violations_team_warnings = fetch_querytool_batched_rows(
                    client=client,
                    path="/game/team",
                    base_params={
                        "LeagueId": league_id,
                        "SeasonYear": season_label_value,
                        "SeasonType": season_type_value,
                        "Grouping": "None",
                        "MeasureType": "Violations",
                    },
                    game_ids=querytool_game_ids,
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

                # --- Query Tool event streams (store per-game JSONB) ---
                for event_type in QUERYTOOL_EVENT_STREAM_TYPES:
                    batch_size = QUERYTOOL_EVENT_STREAM_BATCH_SIZES.get(event_type, 25)
                    pending_batches = chunked(querytool_game_ids, batch_size)

                    while pending_batches:
                        batch = pending_batches.pop(0)
                        if not batch:
                            continue

                        params = {
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type_value,
                            "PerMode": QUERYTOOL_EVENT_STREAM_PER_MODE,
                            "SumScope": QUERYTOOL_EVENT_STREAM_SUM_SCOPE,
                            "Grouping": QUERYTOOL_EVENT_STREAM_GROUPING,
                            "TeamGrouping": QUERYTOOL_EVENT_STREAM_TEAM_GROUPING,
                            "EventType": event_type,
                            "GameId": ",".join(batch),
                            "MaxRowsReturned": QUERYTOOL_EVENT_STREAM_MAX_ROWS_RETURNED,
                        }

                        try:
                            payload = request_json(
                                client,
                                "/event/player",
                                params,
                                base_url=QUERY_TOOL_URL,
                            )
                        except httpx.HTTPStatusError as exc:
                            status = exc.response.status_code if exc.response is not None else None
                            if status in {414, 504} and len(batch) > 1:
                                left, right = split_batch(batch)
                                pending_batches = [left, right, *pending_batches]
                                continue
                            raise

                        rows = payload.get("players") or []
                        rows_returned = parse_int((payload.get("meta") or {}).get("rowsReturned"))
                        suspicious = (
                            (rows_returned is not None and rows_returned >= QUERY_TOOL_TRUNCATION_THRESHOLD)
                            or len(rows) >= QUERY_TOOL_TRUNCATION_THRESHOLD
                        )

                        if suspicious and len(batch) > 1:
                            left, right = split_batch(batch)
                            pending_batches = [left, right, *pending_batches]
                            continue

                        if suspicious:
                            errors.append(
                                f"querytool_event_streams {event_type}: batch for game {batch[0]} may be truncated "
                                f"(rows={len(rows)}, rowsReturned={rows_returned})"
                            )

                        grouped: dict[str, list[dict]] = {gid: [] for gid in batch}
                        for payload_row in rows:
                            game_id_row = payload_row.get("gameId")
                            if not game_id_row or game_id_row not in grouped:
                                continue
                            grouped[game_id_row].append(reduce_querytool_event_row(payload_row))

                        stream_rows: list[dict] = []
                        for gid in batch:
                            stream_rows.append(
                                {
                                    "game_id": gid,
                                    "event_type": event_type,
                                    "events_json": Json(grouped.get(gid) or []),
                                    "created_at": fetched_at,
                                    "updated_at": fetched_at,
                                    "fetched_at": fetched_at,
                                }
                            )

                        querytool_event_stream_rows_total += len(stream_rows)
                        if not dry_run:
                            querytool_event_stream_upserted_total += upsert(
                                conn,
                                "nba.querytool_event_streams",
                                stream_rows,
                                ["game_id", "event_type"],
                                update_exclude=["created_at"],
                            )

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
        inserted_querytool_event_streams = 0

        if not dry_run:
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

            # Event streams are upserted incrementally during fetch.
            inserted_querytool_event_streams = querytool_event_stream_upserted_total

        conn.close()

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
                {
                    "table": "nba.querytool_event_streams",
                    "rows": querytool_event_stream_rows_total,
                    "upserted": inserted_querytool_event_streams,
                },
            ],
            "errors": errors,
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
