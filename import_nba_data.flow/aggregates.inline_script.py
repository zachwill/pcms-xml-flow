# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
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
QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"

PLAYER_MEASURE_TYPES = ["Base", "Advanced", "Misc", "Scoring"]
TEAM_MEASURE_TYPES = ["Base", "Advanced", "Misc", "Scoring", "Opponent"]
PLAYER_PER_MODES = ["Totals", "PerGame", "Per36", "Per100Possessions"]
TEAM_PER_MODES = ["Totals", "PerGame"]
LINEUP_MEASURE_TYPES = ["Base", "Advanced"]
LINEUP_PER_MODES = ["Totals", "PerGame", "Per36Minutes", "Per100Possessions"]
LINEUP_GAME_PER_MODE = "Totals"
LINEUP_QUANTITY = 5
LINEUP_MAX_ROWS = 5000
LINEUP_GROUPING = "None"

EVENT_TYPES = ["FieldGoals", "TrackingShots", "TrackingPasses", "DefensiveEvents"]
EVENT_PER_MODE = "Totals"
EVENT_SUM_SCOPE = "Event"
EVENT_GROUPING = "None"
EVENT_TEAM_GROUPING = "Y"
EVENT_MAX_ROWS = 5000


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
    days_back: int | None,
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


PLAYER_STAT_MAP = {
    "gp": "games_played",
    "min": "minutes",
    "fgPct": "fg_pct",
    "fg3Pct": "fg3_pct",
    "ftPct": "ft_pct",
    "plusMinus": "plus_minus",
    "doubleDouble": "double_doubles",
    "tripleDouble": "triple_doubles",
    "astTo": "ast_tov",
    "tmTovPct": "tm_tov_pct",
    "efgPct": "efg_pct",
    "tsPct": "ts_pct",
    "usgPct": "usg_pct",
    "ftaRate": "fta_rate",
    "ptsOffTov": "pts_off_tov",
    "pts2ndChance": "pts_2nd_chance",
    "ptsFb": "pts_fb",
    "ptsPaint": "pts_paint",
    "oppPtsOffTov": "opp_pts_off_tov",
    "oppPts2ndChance": "opp_pts_2nd_chance",
    "oppPtsFb": "opp_pts_fb",
    "oppPtsPaint": "opp_pts_paint",
    "nbaFantasy": "nba_fantasy_pts",
}

TEAM_STAT_MAP = {
    "gp": "games_played",
    "winPct": "win_pct",
    "min": "minutes",
    "fgPct": "fg_pct",
    "fg3Pct": "fg3_pct",
    "ftPct": "ft_pct",
    "plusMinus": "plus_minus",
    "astTo": "ast_tov",
    "tmTovPct": "tm_tov_pct",
    "efgPct": "efg_pct",
    "tsPct": "ts_pct",
    "ftaRate": "fta_rate",
    "ptsOffTov": "pts_off_tov",
    "pts2ndChance": "pts_2nd_chance",
    "ptsFb": "pts_fb",
    "ptsPaint": "pts_paint",
    "oppPtsOffTov": "opp_pts_off_tov",
    "oppPts2ndChance": "opp_pts_2nd_chance",
    "oppPtsFb": "opp_pts_fb",
    "oppPtsPaint": "opp_pts_paint",
}

PLAYER_COLUMNS = {
    "games_played",
    "minutes",
    "fgm",
    "fga",
    "fg_pct",
    "fg3m",
    "fg3a",
    "fg3_pct",
    "fg2m",
    "fg2a",
    "fg2_pct",
    "ftm",
    "fta",
    "ft_pct",
    "oreb",
    "dreb",
    "reb",
    "ast",
    "stl",
    "blk",
    "tov",
    "pf",
    "pts",
    "plus_minus",
    "double_doubles",
    "triple_doubles",
    "off_rating",
    "def_rating",
    "net_rating",
    "ast_pct",
    "ast_tov",
    "ast_ratio",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "usg_pct",
    "pace",
    "pie",
    "poss",
    "fta_rate",
    "pts_off_tov",
    "pts_2nd_chance",
    "pts_fb",
    "pts_paint",
    "opp_pts_off_tov",
    "opp_pts_2nd_chance",
    "opp_pts_fb",
    "opp_pts_paint",
    "nba_fantasy_pts",
}

TEAM_COLUMNS = {
    "games_played",
    "wins",
    "losses",
    "win_pct",
    "minutes",
    "fgm",
    "fga",
    "fg_pct",
    "fg3m",
    "fg3a",
    "fg3_pct",
    "fg2m",
    "fg2a",
    "fg2_pct",
    "ftm",
    "fta",
    "ft_pct",
    "oreb",
    "dreb",
    "reb",
    "ast",
    "stl",
    "blk",
    "tov",
    "pf",
    "pts",
    "plus_minus",
    "off_rating",
    "def_rating",
    "net_rating",
    "ast_pct",
    "ast_tov",
    "ast_ratio",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "pace",
    "pie",
    "poss",
    "fta_rate",
    "pts_off_tov",
    "pts_2nd_chance",
    "pts_fb",
    "pts_paint",
    "opp_pts_off_tov",
    "opp_pts_2nd_chance",
    "opp_pts_fb",
    "opp_pts_paint",
}

LINEUP_STAT_COLUMNS = [
    "gp",
    "minutes",
    "off_rating",
    "def_rating",
    "net_rating",
    "ast_pct",
    "ast_tov",
    "ast_ratio",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "usg_pct",
    "pace",
    "pie",
]

LINEUP_STAT_PREFIXES = (
    "BASE_",
    "ADV_",
    "MISC_",
    "SCORING_",
    "OPP_",
    "TRACKING_",
    "DEF_",
    "DEFENSIVE_",
)

LINEUP_STAT_MAP = {
    "GP": "gp",
    "G": "gp",
    "GAMES_PLAYED": "gp",
    "MIN": "minutes",
    "MINUTES": "minutes",
    "OFF_RATING": "off_rating",
    "OFFRTG": "off_rating",
    "DEF_RATING": "def_rating",
    "DEFRTG": "def_rating",
    "NET_RATING": "net_rating",
    "NETRTG": "net_rating",
    "AST_PCT": "ast_pct",
    "AST_TO": "ast_tov",
    "AST_TOV": "ast_tov",
    "AST_RATIO": "ast_ratio",
    "OREB_PCT": "oreb_pct",
    "DREB_PCT": "dreb_pct",
    "REB_PCT": "reb_pct",
    "TM_TOV_PCT": "tm_tov_pct",
    "TEAM_TOV_PCT": "tm_tov_pct",
    "EFG_PCT": "efg_pct",
    "TS_PCT": "ts_pct",
    "USG_PCT": "usg_pct",
    "PACE": "pace",
    "PIE": "pie",
}


AGG_INT_COLUMNS = {"games_played", "wins", "losses", "double_doubles", "triple_doubles"}


def map_stats(stats: dict, mapping: dict, allowed_columns: set[str]) -> dict:
    row: dict = {}
    for key, value in stats.items():
        column = mapping.get(key)
        if not column:
            column = "".join(["_" + c.lower() if c.isupper() else c for c in key]).lstrip("_")
        if column not in allowed_columns:
            continue

        if column in AGG_INT_COLUMNS:
            parsed = parse_int(value)
        else:
            parsed = parse_float(value)

        if parsed is None:
            continue

        if column == "tm_tov_pct" and abs(parsed) > 1:
            parsed = parsed / 100

        row[column] = parsed
    return row


def compute_fg2(row: dict):
    fgm = row.get("fgm")
    fga = row.get("fga")
    fg3m = row.get("fg3m")
    fg3a = row.get("fg3a")
    if fgm is not None and fg3m is not None:
        row["fg2m"] = fgm - fg3m
    if fga is not None and fg3a is not None:
        row["fg2a"] = fga - fg3a
    fg2a = row.get("fg2a")
    fg2m = row.get("fg2m")
    if fg2a and fg2m is not None and fg2a > 0:
        row["fg2_pct"] = fg2m / fg2a


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


def stable_hash(payload) -> str:
    return hashlib.sha1(json.dumps(payload, sort_keys=True, default=str).encode()).hexdigest()


def parse_minutes_interval(value: str | None):
    if value is None or value == "":
        return None
    if isinstance(value, str):
        if value.startswith("PT"):
            minutes = 0
            seconds = 0.0
            try:
                body = value.replace("PT", "")
                if "M" in body:
                    minutes_str, rest = body.split("M", 1)
                    minutes = int(minutes_str) if minutes_str else 0
                else:
                    rest = body
                if "S" in rest:
                    seconds = float(rest.replace("S", ""))
            except ValueError:
                return None
            return round((minutes * 60 + seconds) / 60.0, 2)
        if ":" in value:
            try:
                minutes_str, seconds_str = value.split(":", 1)
                return round((int(minutes_str) * 60 + float(seconds_str)) / 60.0, 2)
            except ValueError:
                return None
    try:
        minutes = float(value)
    except (ValueError, TypeError):
        return None
    return round(minutes, 2)


def normalize_lineup_stat_key(key: str) -> str:
    if not key:
        return ""
    normalized = key.upper()
    for prefix in LINEUP_STAT_PREFIXES:
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix):]
            break
    return normalized


LINEUP_RATE_COLUMNS = {
    "ast_pct",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "usg_pct",
    "pie",
}


def map_lineup_stats(stats: dict) -> dict:
    row: dict = {}
    for key, value in stats.items():
        normalized = normalize_lineup_stat_key(key)
        column = LINEUP_STAT_MAP.get(normalized)
        if not column:
            continue
        if column == "gp":
            parsed = parse_int(value)
        elif column == "minutes":
            parsed = parse_minutes_interval(value)
        else:
            parsed = parse_float(value)
        if parsed is None:
            continue
        if column == "pie":
            if abs(parsed) > 100:
                parsed = parsed / 10000
            elif abs(parsed) > 1:
                parsed = parsed / 100
        elif column in LINEUP_RATE_COLUMNS and abs(parsed) > 1:
            parsed = parsed / 100
        row[column] = parsed
    return row


def extract_lineup_player_ids(lineup: dict) -> list[int]:
    ids: list[int] = []
    for idx in range(1, 6):
        player_id = parse_int(lineup.get(f"player{idx}Id"))
        if player_id:
            ids.append(player_id)
    ids.sort()
    return ids


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(
    dry_run: bool = False,
    league_id: str = "00",
    season_label: str | None = None,
    season_type: str = "Regular Season",
    mode: str = "refresh",
    days_back: int | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    game_ids: str | None = None,
    only_final_games: bool = True,
) -> dict:
    started_at = now_utc()

    conn: psycopg.Connection | None = None
    try:
        fetched_at = now_utc()
        season_label_value = season_label
        season_year = parse_season_year(season_label_value)

        player_rows: list[dict] = []
        team_rows: list[dict] = []
        lineup_season_rows: list[dict] = []
        lineup_game_rows: list[dict] = []
        event_player_rows: list[dict] = []
        event_team_rows: list[dict] = []
        event_league_rows: list[dict] = []

        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        game_list: list[str] = []
        if game_ids:
            game_list = [gid.strip() for gid in game_ids.split(",") if gid.strip()]
        else:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date, season_label)
            query = """
                SELECT game_id, game_status
                FROM nba.games
                WHERE game_date BETWEEN %s AND %s
                ORDER BY game_date, game_id
            """
            with conn.cursor() as cur:
                cur.execute(query, (start_dt, end_dt))
                game_status_rows = cur.fetchall()
            if only_final_games:
                game_list = [gid for gid, status in game_status_rows if status == 3]
            else:
                game_list = [gid for gid, _ in game_status_rows]

        with httpx.Client(timeout=60) as client:
            for per_mode in PLAYER_PER_MODES:
                for measure_type in PLAYER_MEASURE_TYPES:
                    payload = request_json(
                        client,
                        "/api/stats/player",
                        {
                            "leagueId": league_id,
                            "season": season_label_value,
                            "seasonType": season_type,
                            "perMode": per_mode,
                            "measureType": measure_type,
                        },
                    )
                    players = payload.get("players") or []
                    for player in players:
                        stats = player.get("stats") or {}
                        nba_id = player.get("personId")
                        if nba_id is None:
                            continue
                        row = map_stats(stats, PLAYER_STAT_MAP, PLAYER_COLUMNS)
                        row.update(
                            {
                                "nba_id": nba_id,
                                "team_id": stats.get("teamId"),
                                "season_year": season_year,
                                "season_label": stats.get("season") or season_label_value,
                                "season_type": stats.get("seasonType") or season_type,
                                "per_mode": per_mode,
                                "measure_type": measure_type,
                                "created_at": fetched_at,
                                "updated_at": fetched_at,
                                "fetched_at": fetched_at,
                            }
                        )
                        compute_fg2(row)
                        player_rows.append(row)

            for per_mode in TEAM_PER_MODES:
                for measure_type in TEAM_MEASURE_TYPES:
                    payload = request_json(
                        client,
                        "/api/stats/team",
                        {
                            "leagueId": league_id,
                            "season": season_label_value,
                            "seasonType": season_type,
                            "perMode": per_mode,
                            "measureType": measure_type,
                        },
                    )
                    teams = payload.get("teams") or []
                    for team in teams:
                        stats = team.get("stats") or {}
                        team_id = team.get("teamId")
                        if team_id is None:
                            continue
                        row = map_stats(stats, TEAM_STAT_MAP, TEAM_COLUMNS)
                        row.update(
                            {
                                "team_id": team_id,
                                "season_year": season_year,
                                "season_label": stats.get("season") or season_label_value,
                                "season_type": stats.get("seasonType") or season_type,
                                "per_mode": per_mode,
                                "measure_type": measure_type,
                                "created_at": fetched_at,
                                "updated_at": fetched_at,
                                "fetched_at": fetched_at,
                            }
                        )
                        compute_fg2(row)
                        team_rows.append(row)

            if season_label_value:
                for per_mode in LINEUP_PER_MODES:
                    for measure_type in LINEUP_MEASURE_TYPES:
                        payload = request_json(
                            client,
                            "/season/lineups",
                            {
                                "LeagueId": league_id,
                                "SeasonYear": season_label_value,
                                "SeasonType": season_type,
                                "PerMode": per_mode,
                                "Grouping": LINEUP_GROUPING,
                                "MeasureType": measure_type,
                                "LineupQuantity": LINEUP_QUANTITY,
                                "MaxRowsReturned": LINEUP_MAX_ROWS,
                            },
                            base_url=QUERY_TOOL_URL,
                        )
                        lineups = payload.get("lineups") or []
                        for lineup in lineups:
                            player_ids = extract_lineup_player_ids(lineup)
                            if not player_ids:
                                continue
                            team_id = parse_int(lineup.get("teamId"))
                            if team_id is None:
                                continue
                            season_label_lineup = lineup.get("seasonYear") or season_label_value
                            season_year_lineup = parse_season_year(season_label_lineup) or season_year
                            row = {
                                "league_id": lineup.get("leagueId") or league_id,
                                "season_year": season_year_lineup,
                                "season_label": season_label_lineup,
                                "season_type": lineup.get("seasonType") or season_type,
                                "team_id": team_id,
                                "player_ids": player_ids,
                                "per_mode": per_mode,
                                "measure_type": measure_type,
                                "created_at": fetched_at,
                                "updated_at": fetched_at,
                                "fetched_at": fetched_at,
                            }
                            for column in LINEUP_STAT_COLUMNS:
                                row[column] = None
                            row.update(map_lineup_stats(lineup.get("stats") or {}))
                            lineup_season_rows.append(row)

            if season_label_value and game_list:
                for game_id_value in game_list:
                    for measure_type in LINEUP_MEASURE_TYPES:
                        payload = request_json(
                            client,
                            "/game/lineups",
                            {
                                "LeagueId": league_id,
                                "SeasonYear": season_label_value,
                                "SeasonType": season_type,
                                "Grouping": LINEUP_GROUPING,
                                "MeasureType": measure_type,
                                "LineupQuantity": LINEUP_QUANTITY,
                                "GameId": game_id_value,
                                "MaxRowsReturned": LINEUP_MAX_ROWS,
                            },
                            base_url=QUERY_TOOL_URL,
                        )
                        lineups = payload.get("lineups") or []
                        for lineup in lineups:
                            player_ids = extract_lineup_player_ids(lineup)
                            if not player_ids:
                                continue
                            team_id = parse_int(lineup.get("teamId"))
                            if team_id is None:
                                continue
                            season_label_lineup = lineup.get("seasonYear") or season_label_value
                            season_year_lineup = parse_season_year(season_label_lineup) or season_year
                            row = {
                                "game_id": lineup.get("gameId") or game_id_value,
                                "league_id": lineup.get("leagueId") or league_id,
                                "season_year": season_year_lineup,
                                "season_label": season_label_lineup,
                                "season_type": lineup.get("seasonType") or season_type,
                                "team_id": team_id,
                                "player_ids": player_ids,
                                "per_mode": LINEUP_GAME_PER_MODE,
                                "measure_type": measure_type,
                                "created_at": fetched_at,
                                "updated_at": fetched_at,
                                "fetched_at": fetched_at,
                            }
                            for column in LINEUP_STAT_COLUMNS:
                                row[column] = None
                            row.update(map_lineup_stats(lineup.get("stats") or {}))
                            lineup_game_rows.append(row)

                    # Query Tool event-level datasets (player/team/league)
                    for event_type in EVENT_TYPES:
                        player_params = {
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type,
                            "PerMode": EVENT_PER_MODE,
                            "SumScope": EVENT_SUM_SCOPE,
                            "Grouping": EVENT_GROUPING,
                            "TeamGrouping": EVENT_TEAM_GROUPING,
                            "EventType": event_type,
                            "GameId": game_id_value,
                            "MaxRowsReturned": EVENT_MAX_ROWS,
                        }
                        player_payload = request_json(
                            client,
                            "/event/player",
                            player_params,
                            base_url=QUERY_TOOL_URL,
                        )
                        player_query_params = (player_payload.get("meta") or {}).get("queryParams") or player_params
                        player_query_hash = stable_hash(
                            {
                                "path": "/event/player",
                                "params": player_query_params,
                            }
                        )
                        for player in player_payload.get("players") or []:
                            season_label_event = player.get("seasonYear") or season_label_value
                            team_id_event = parse_int(player.get("teamId"))
                            if team_id_event == 0:
                                team_id_event = None
                            row_hash = stable_hash(player)
                            event_player_rows.append(
                                {
                                    "query_hash": player_query_hash,
                                    "row_hash": row_hash,
                                    "league_id": player.get("leagueId") or league_id,
                                    "season_year": parse_season_year(season_label_event),
                                    "season_label": season_label_event,
                                    "season_type": player.get("seasonType") or season_type,
                                    "game_id": player.get("gameId") or game_id_value,
                                    "game_date": parse_date(player.get("gameDate")),
                                    "nba_id": parse_int(player.get("playerId")),
                                    "team_id": team_id_event,
                                    "team_name": player.get("teamName"),
                                    "team_tricode": player.get("teamTricode") or player.get("teamAbbreviation"),
                                    "opponent_name": player.get("opponentName"),
                                    "event_number": parse_int(player.get("eventNumber")),
                                    "period": parse_int(player.get("period")),
                                    "game_clock": parse_float(player.get("gameClock")),
                                    "x": parse_int(player.get("x")),
                                    "y": parse_int(player.get("y")),
                                    "event_type": player_query_params.get("eventType") or event_type,
                                    "per_mode": player_query_params.get("perMode") or EVENT_PER_MODE,
                                    "sum_scope": player_query_params.get("sumScope") or EVENT_SUM_SCOPE,
                                    "query_grouping": player_query_params.get("grouping") or EVENT_GROUPING,
                                    "team_grouping": player_query_params.get("teamGrouping") or EVENT_TEAM_GROUPING,
                                    "stats_json": Json(player.get("stats") or {}),
                                    "row_json": Json(player),
                                    "query_params_json": Json(player_query_params),
                                    "first_seen_at": fetched_at,
                                    "last_seen_at": fetched_at,
                                    "created_at": fetched_at,
                                    "updated_at": fetched_at,
                                    "fetched_at": fetched_at,
                                }
                            )

                        team_params = {
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type,
                            "PerMode": EVENT_PER_MODE,
                            "SumScope": EVENT_SUM_SCOPE,
                            "Grouping": EVENT_GROUPING,
                            "EventType": event_type,
                            "GameId": game_id_value,
                            "MaxRowsReturned": EVENT_MAX_ROWS,
                        }
                        team_payload = request_json(
                            client,
                            "/event/team",
                            team_params,
                            base_url=QUERY_TOOL_URL,
                        )
                        team_query_params = (team_payload.get("meta") or {}).get("queryParams") or team_params
                        team_query_hash = stable_hash(
                            {
                                "path": "/event/team",
                                "params": team_query_params,
                            }
                        )
                        for team in team_payload.get("teams") or []:
                            season_label_event = team.get("seasonYear") or season_label_value
                            team_id_event = parse_int(team.get("teamId"))
                            if team_id_event == 0:
                                team_id_event = None
                            row_hash = stable_hash(team)
                            event_team_rows.append(
                                {
                                    "query_hash": team_query_hash,
                                    "row_hash": row_hash,
                                    "league_id": team.get("leagueId") or league_id,
                                    "season_year": parse_season_year(season_label_event),
                                    "season_label": season_label_event,
                                    "season_type": team.get("seasonType") or season_type,
                                    "game_id": team.get("gameId") or game_id_value,
                                    "game_date": parse_date(team.get("gameDate")),
                                    "team_id": team_id_event,
                                    "team_name": team.get("teamName"),
                                    "team_tricode": team.get("teamTricode") or team.get("teamAbbreviation"),
                                    "opponent_name": team.get("opponentName"),
                                    "event_number": parse_int(team.get("eventNumber")),
                                    "period": parse_int(team.get("period")),
                                    "game_clock": parse_float(team.get("gameClock")),
                                    "x": parse_int(team.get("x")),
                                    "y": parse_int(team.get("y")),
                                    "event_type": team_query_params.get("eventType") or event_type,
                                    "per_mode": team_query_params.get("perMode") or EVENT_PER_MODE,
                                    "sum_scope": team_query_params.get("sumScope") or EVENT_SUM_SCOPE,
                                    "query_grouping": team_query_params.get("grouping") or EVENT_GROUPING,
                                    "stats_json": Json(team.get("stats") or {}),
                                    "row_json": Json(team),
                                    "query_params_json": Json(team_query_params),
                                    "first_seen_at": fetched_at,
                                    "last_seen_at": fetched_at,
                                    "created_at": fetched_at,
                                    "updated_at": fetched_at,
                                    "fetched_at": fetched_at,
                                }
                            )

                        league_params = {
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type,
                            "PerMode": EVENT_PER_MODE,
                            "SumScope": EVENT_SUM_SCOPE,
                            "Grouping": EVENT_GROUPING,
                            "EventType": event_type,
                            "GameId": game_id_value,
                            "MaxRowsReturned": EVENT_MAX_ROWS,
                        }
                        league_payload = request_json(
                            client,
                            "/event/league",
                            league_params,
                            base_url=QUERY_TOOL_URL,
                        )
                        league_query_params = (league_payload.get("meta") or {}).get("queryParams") or league_params
                        league_query_hash = stable_hash(
                            {
                                "path": "/event/league",
                                "params": league_query_params,
                            }
                        )
                        for league in league_payload.get("leagues") or []:
                            season_label_event = league.get("seasonYear") or season_label_value
                            row_hash = stable_hash(league)
                            event_league_rows.append(
                                {
                                    "query_hash": league_query_hash,
                                    "row_hash": row_hash,
                                    "league_id": league.get("leagueId") or league_id,
                                    "season_year": parse_season_year(season_label_event),
                                    "season_label": season_label_event,
                                    "season_type": league.get("seasonType") or season_type,
                                    "game_id": league.get("gameId") or game_id_value,
                                    "game_date": parse_date(league.get("gameDate")),
                                    "visitor_team_name": league.get("visitorTeamName"),
                                    "home_team_name": league.get("homeTeamName"),
                                    "game_score": league.get("gameScore"),
                                    "event_number": parse_int(league.get("eventNumber")),
                                    "period": parse_int(league.get("period")),
                                    "game_clock": parse_float(league.get("gameClock")),
                                    "x": parse_int(league.get("x")),
                                    "y": parse_int(league.get("y")),
                                    "event_type": league_query_params.get("eventType") or event_type,
                                    "per_mode": league_query_params.get("perMode") or EVENT_PER_MODE,
                                    "sum_scope": league_query_params.get("sumScope") or EVENT_SUM_SCOPE,
                                    "query_grouping": league_query_params.get("grouping") or EVENT_GROUPING,
                                    "stats_json": Json(league.get("stats") or {}),
                                    "row_json": Json(league),
                                    "query_params_json": Json(league_query_params),
                                    "first_seen_at": fetched_at,
                                    "last_seen_at": fetched_at,
                                    "created_at": fetched_at,
                                    "updated_at": fetched_at,
                                    "fetched_at": fetched_at,
                                }
                            )

        inserted_players = 0
        inserted_teams = 0
        inserted_lineup_season = 0
        inserted_lineup_game = 0
        inserted_event_players = 0
        inserted_event_teams = 0
        inserted_event_league = 0
        if not dry_run:
            inserted_players = upsert(
                conn,
                "nba.player_stats_aggregated",
                player_rows,
                ["nba_id", "team_id", "season_year", "season_type", "per_mode", "measure_type"],
                update_exclude=["created_at"],
            )
            inserted_teams = upsert(
                conn,
                "nba.team_stats_aggregated",
                team_rows,
                ["team_id", "season_year", "season_type", "per_mode", "measure_type"],
                update_exclude=["created_at"],
            )
            if lineup_season_rows:
                inserted_lineup_season = upsert(
                    conn,
                    "nba.lineup_stats_season",
                    lineup_season_rows,
                    [
                        "league_id",
                        "season_year",
                        "season_type",
                        "team_id",
                        "player_ids",
                        "per_mode",
                        "measure_type",
                    ],
                    update_exclude=["created_at"],
                )
            if lineup_game_rows:
                inserted_lineup_game = upsert(
                    conn,
                    "nba.lineup_stats_game",
                    lineup_game_rows,
                    ["game_id", "team_id", "player_ids", "per_mode", "measure_type"],
                    update_exclude=["created_at"],
                )
            if event_player_rows:
                inserted_event_players = upsert(
                    conn,
                    "nba.querytool_event_player",
                    event_player_rows,
                    ["query_hash", "row_hash"],
                    update_exclude=["created_at", "first_seen_at"],
                )
            if event_team_rows:
                inserted_event_teams = upsert(
                    conn,
                    "nba.querytool_event_team",
                    event_team_rows,
                    ["query_hash", "row_hash"],
                    update_exclude=["created_at", "first_seen_at"],
                )
            if event_league_rows:
                inserted_event_league = upsert(
                    conn,
                    "nba.querytool_event_league",
                    event_league_rows,
                    ["query_hash", "row_hash"],
                    update_exclude=["created_at", "first_seen_at"],
                )

        if conn:
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {"table": "nba.player_stats_aggregated", "rows": len(player_rows), "upserted": inserted_players},
                {"table": "nba.team_stats_aggregated", "rows": len(team_rows), "upserted": inserted_teams},
                {
                    "table": "nba.lineup_stats_season",
                    "rows": len(lineup_season_rows),
                    "upserted": inserted_lineup_season,
                },
                {
                    "table": "nba.lineup_stats_game",
                    "rows": len(lineup_game_rows),
                    "upserted": inserted_lineup_game,
                },
                {
                    "table": "nba.querytool_event_player",
                    "rows": len(event_player_rows),
                    "upserted": inserted_event_players,
                },
                {
                    "table": "nba.querytool_event_team",
                    "rows": len(event_team_rows),
                    "upserted": inserted_event_teams,
                },
                {
                    "table": "nba.querytool_event_league",
                    "rows": len(event_league_rows),
                    "upserted": inserted_event_league,
                },
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
