# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import importlib.util
import os
import time
from datetime import datetime, timezone, timedelta, date
from pathlib import Path

import httpx
import psycopg

BASE_URL = "https://api.nba.com/v0"
QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"

PLAYER_MEASURE_TYPES = ["Base", "Advanced", "Misc", "Scoring"]
TEAM_MEASURE_TYPES = ["Base", "Advanced", "Misc", "Scoring", "Opponent"]
PLAYER_PER_MODES = ["Totals", "PerGame", "Per36", "Per100Possessions"]
TEAM_PER_MODES = ["Totals", "PerGame"]
QUERY_TOOL_TRUNCATION_THRESHOLD = 9900


def _load_lineup_utils_module():
    candidates: list[Path] = []
    if "__file__" in globals():
        candidates.append(Path(__file__).with_name("lineup_utils.py"))
    candidates.append(Path("import_nba_data.flow/lineup_utils.py"))

    for path in candidates:
        if not path.exists():
            continue
        spec = importlib.util.spec_from_file_location("nba_lineup_utils", path)
        if spec is None or spec.loader is None:
            continue
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    raise FileNotFoundError("Unable to load lineup_utils.py")


_lineup_utils = _load_lineup_utils_module()
LINEUP_MEASURE_TYPES = _lineup_utils.LINEUP_MEASURE_TYPES
LINEUP_PER_MODES = _lineup_utils.LINEUP_PER_MODES
LINEUP_GAME_PER_MODE = _lineup_utils.LINEUP_GAME_PER_MODE
LINEUP_QUANTITY = _lineup_utils.LINEUP_QUANTITY
LINEUP_MAX_ROWS = _lineup_utils.LINEUP_MAX_ROWS
LINEUP_GROUPING = _lineup_utils.LINEUP_GROUPING
LINEUP_GAME_BATCH_SIZE = _lineup_utils.LINEUP_GAME_BATCH_SIZE
LINEUP_SEASON_TEAM_BATCH_SIZE = _lineup_utils.LINEUP_SEASON_TEAM_BATCH_SIZE
LINEUP_STAT_COLUMNS = _lineup_utils.LINEUP_STAT_COLUMNS
map_lineup_stats = _lineup_utils.map_lineup_stats
extract_lineup_player_ids = _lineup_utils.extract_lineup_player_ids
fetch_querytool_batched_rows = _lineup_utils.fetch_querytool_batched_rows

SHOT_CHART_PER_MODE = "Totals"
SHOT_CHART_SUM_SCOPE = "Event"
SHOT_CHART_GROUPING = "None"
SHOT_CHART_TEAM_GROUPING = "Y"
SHOT_CHART_MAX_ROWS = 10000
SHOT_CHART_BATCH_SIZE = 50  # ~180 shots/game × 50 = ~9000, safely under 10k API limit


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


def merge_aggregate_row(store: dict[tuple, dict], key: tuple, base_row: dict, stat_values: dict):
    existing = store.get(key)
    if existing is None:
        existing = dict(base_row)
        store[key] = existing
    else:
        if not existing.get("season_label") and base_row.get("season_label"):
            existing["season_label"] = base_row["season_label"]
        existing["updated_at"] = base_row.get("updated_at")
        existing["fetched_at"] = base_row.get("fetched_at")

    for column, value in stat_values.items():
        if value is not None:
            existing[column] = value


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


def derive_shot_type(stats: dict) -> str | None:
    """Derive a human-readable shot type from the FieldGoals stats flags.

    The API sets exactly one category flag to 1.0 per event row.  We check in
    priority order so compound flags (e.g. dunk + alley_oop) resolve to the
    more specific label.
    """
    if parse_float(stats.get("FG_ALLEY_OOP")) == 1.0:
        return "alley_oop"
    if parse_float(stats.get("FG_FINGER_ROLL")) == 1.0:
        return "finger_roll"
    if parse_float(stats.get("FG_DUNK")) == 1.0:
        return "dunk"
    if parse_float(stats.get("FG_TIP")) == 1.0:
        return "tip"
    if parse_float(stats.get("FG_HOOK")) == 1.0:
        return "hook"
    if parse_float(stats.get("FG_LAYUP")) == 1.0:
        return "layup"
    if parse_float(stats.get("FG_JUMPER")) == 1.0:
        return "jumper"
    return None


TRACKING_SHOT_FLAG_MAP = {
    "SHOT_AFTER_SCREENS": "tracking_shot_after_screens",
    "SHOT_CATCH_AND_SHOOT": "tracking_shot_catch_and_shoot",
    "SHOT_LOB": "tracking_shot_lob",
    "SHOT_LONG_HEAVE": "tracking_shot_long_heave",
    "SHOT_PULL_UP": "tracking_shot_pull_up",
    "SHOT_TIP_IN": "tracking_shot_tip_in",
    "SHOT_TRAILING_THREE": "tracking_shot_trailing_three",
    "SHOT_TRANSITION": "tracking_shot_transition",
}


def map_tracking_shot_flags(stats: dict) -> dict:
    """Map TrackingShots (0/1) flags to nba.shot_chart boolean columns."""
    out: dict = {}
    for key, column in TRACKING_SHOT_FLAG_MAP.items():
        value = parse_float(stats.get(key))
        if value is None:
            out[column] = None
        else:
            out[column] = value == 1.0
    return out


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
        desired_season_type = normalize_season_type(season_type)

        player_rows_by_key: dict[tuple, dict] = {}
        team_rows_by_key: dict[tuple, dict] = {}
        lineup_season_rows: list[dict] = []
        lineup_game_rows: list[dict] = []
        shot_chart_rows: list[dict] = []

        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        game_list: list[str] = []
        section_errors: list[str] = []
        if game_ids:
            game_list = [gid.strip() for gid in game_ids.split(",") if gid.strip()]
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
                game_status_rows = cur.fetchall()

            if desired_season_type:
                game_status_rows = [
                    (gid, status, game_season_type)
                    for gid, status, game_season_type in game_status_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                ]

            if only_final_games:
                game_list = [gid for gid, status, _ in game_status_rows if status == 3]
            else:
                game_list = [gid for gid, _, _ in game_status_rows]

        with httpx.Client(timeout=60) as client:
            # --- Player aggregates ---
            for per_mode in PLAYER_PER_MODES:
                for measure_type in PLAYER_MEASURE_TYPES:
                    try:
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
                    except Exception as exc:
                        section_errors.append(
                            f"player_aggregates per_mode={per_mode} measure={measure_type}: {exc}"
                        )
                        continue

                    players = payload.get("players") or []
                    for player in players:
                        stats = player.get("stats") or {}
                        nba_id = player.get("personId")
                        if nba_id is None:
                            continue
                        player_stats = map_stats(stats, PLAYER_STAT_MAP, PLAYER_COLUMNS)
                        compute_fg2(player_stats)

                        team_id = stats.get("teamId")
                        row_season_type = stats.get("seasonType") or season_type
                        key = (nba_id, team_id, season_year, row_season_type, per_mode)
                        base_row = {
                            "nba_id": nba_id,
                            "team_id": team_id,
                            "season_year": season_year,
                            "season_label": stats.get("season") or season_label_value,
                            "season_type": row_season_type,
                            "per_mode": per_mode,
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                        merge_aggregate_row(player_rows_by_key, key, base_row, player_stats)

            # --- Team aggregates ---
            for per_mode in TEAM_PER_MODES:
                for measure_type in TEAM_MEASURE_TYPES:
                    try:
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
                    except Exception as exc:
                        section_errors.append(
                            f"team_aggregates per_mode={per_mode} measure={measure_type}: {exc}"
                        )
                        continue

                    teams = payload.get("teams") or []
                    for team in teams:
                        stats = team.get("stats") or {}
                        team_id = team.get("teamId")
                        if team_id is None:
                            continue
                        team_stats = map_stats(stats, TEAM_STAT_MAP, TEAM_COLUMNS)
                        compute_fg2(team_stats)

                        row_season_type = stats.get("seasonType") or season_type
                        key = (team_id, season_year, row_season_type, per_mode)
                        base_row = {
                            "team_id": team_id,
                            "season_year": season_year,
                            "season_label": stats.get("season") or season_label_value,
                            "season_type": row_season_type,
                            "per_mode": per_mode,
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                        merge_aggregate_row(team_rows_by_key, key, base_row, team_stats)

            # --- Season lineups ---
            try:
                if season_label_value:
                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            SELECT team_id
                            FROM nba.teams
                            WHERE league_id = %s
                              AND COALESCE(is_active, true) = true
                            ORDER BY team_id
                            """,
                            (league_id,),
                        )
                        lineup_team_ids = [row[0] for row in cur.fetchall() if row and row[0] is not None]

                    if not lineup_team_ids:
                        with conn.cursor() as cur:
                            cur.execute(
                                """
                                SELECT DISTINCT team_id
                                FROM (
                                    SELECT home_team_id AS team_id
                                    FROM nba.games
                                    WHERE league_id = %s
                                      AND (%s::text IS NULL OR season_label = %s)
                                    UNION ALL
                                    SELECT away_team_id AS team_id
                                    FROM nba.games
                                    WHERE league_id = %s
                                      AND (%s::text IS NULL OR season_label = %s)
                                ) teams
                                WHERE team_id IS NOT NULL
                                ORDER BY team_id
                                """,
                                (
                                    league_id,
                                    season_label_value,
                                    season_label_value,
                                    league_id,
                                    season_label_value,
                                    season_label_value,
                                ),
                            )
                            lineup_team_ids = [row[0] for row in cur.fetchall() if row and row[0] is not None]

                    if not lineup_team_ids:
                        section_errors.append("lineup_season: no team ids found; skipping season lineup fetch")

                    team_filters: list[int] = lineup_team_ids
                    team_filter_values = [str(team_id) for team_id in team_filters]

                    for per_mode in LINEUP_PER_MODES:
                        for measure_type in LINEUP_MEASURE_TYPES:
                            lineup_payload_rows, lineup_warnings = fetch_querytool_batched_rows(
                                client=client,
                                request_json=request_json,
                                path="/season/lineups",
                                base_params={
                                    "LeagueId": league_id,
                                    "SeasonYear": season_label_value,
                                    "SeasonType": season_type,
                                    "PerMode": per_mode,
                                    "Grouping": LINEUP_GROUPING,
                                    "MeasureType": measure_type,
                                    "LineupQuantity": LINEUP_QUANTITY,
                                },
                                ids=team_filter_values,
                                row_key="lineups",
                                batch_size=LINEUP_SEASON_TEAM_BATCH_SIZE,
                                max_rows_returned=LINEUP_MAX_ROWS,
                                truncation_threshold=QUERY_TOOL_TRUNCATION_THRESHOLD,
                                batch_param="TeamId",
                            )
                            for warning in lineup_warnings:
                                section_errors.append(
                                    f"lineup_season per_mode={per_mode} measure={measure_type}: {warning}"
                                )

                            for lineup in lineup_payload_rows:
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
                                minutes = row.get("minutes")
                                if minutes is None or minutes <= 0:
                                    continue
                                lineup_season_rows.append(row)
            except Exception as exc:
                section_errors.append(f"lineup_season: {exc}")

            # --- Per-game lineups (batched GameId) ---
            if season_label_value and game_list:
                for measure_type in LINEUP_MEASURE_TYPES:
                    try:
                        batch_size = LINEUP_GAME_BATCH_SIZE.get(measure_type, 100)
                        lineup_payload_rows, lineup_warnings = fetch_querytool_batched_rows(
                            client=client,
                            request_json=request_json,
                            path="/game/lineups",
                            base_params={
                                "LeagueId": league_id,
                                "SeasonYear": season_label_value,
                                "SeasonType": season_type,
                                "Grouping": LINEUP_GROUPING,
                                "MeasureType": measure_type,
                                "LineupQuantity": LINEUP_QUANTITY,
                            },
                            ids=game_list,
                            row_key="lineups",
                            batch_size=batch_size,
                            max_rows_returned=LINEUP_MAX_ROWS,
                            truncation_threshold=QUERY_TOOL_TRUNCATION_THRESHOLD,
                        )
                        for warning in lineup_warnings:
                            section_errors.append(f"game_lineup {measure_type}: {warning}")

                        for lineup in lineup_payload_rows:
                            player_ids = extract_lineup_player_ids(lineup)
                            if not player_ids:
                                continue
                            team_id = parse_int(lineup.get("teamId"))
                            if team_id is None:
                                continue
                            season_label_lineup = lineup.get("seasonYear") or season_label_value
                            season_year_lineup = parse_season_year(season_label_lineup) or season_year
                            row = {
                                "game_id": lineup.get("gameId"),
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
                            if not row["game_id"]:
                                continue
                            for column in LINEUP_STAT_COLUMNS:
                                row[column] = None
                            row.update(map_lineup_stats(lineup.get("stats") or {}))
                            minutes = row.get("minutes")
                            if minutes is None or minutes <= 0:
                                continue
                            lineup_game_rows.append(row)
                    except Exception as exc:
                        section_errors.append(f"game_lineup {measure_type}: {exc}")

            # --- Shot chart (batched — up to 50 games per API call) ---
            try:
                if season_label_value and game_list:
                    shot_fetched_at = now_utc()
                    for batch_start in range(0, len(game_list), SHOT_CHART_BATCH_SIZE):
                        batch = game_list[batch_start:batch_start + SHOT_CHART_BATCH_SIZE]
                        shot_params = {
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type,
                            "PerMode": SHOT_CHART_PER_MODE,
                            "SumScope": SHOT_CHART_SUM_SCOPE,
                            "Grouping": SHOT_CHART_GROUPING,
                            "TeamGrouping": SHOT_CHART_TEAM_GROUPING,
                            "EventType": "FieldGoals",
                            "GameId": ",".join(batch),
                            "MaxRowsReturned": SHOT_CHART_MAX_ROWS,
                        }
                        shot_payload = request_json(
                            client,
                            "/event/player",
                            shot_params,
                            base_url=QUERY_TOOL_URL,
                        )
                        shot_players = shot_payload.get("players") or []
                        shot_rows_returned = parse_int((shot_payload.get("meta") or {}).get("rowsReturned"))
                        if (
                            (shot_rows_returned is not None and shot_rows_returned >= QUERY_TOOL_TRUNCATION_THRESHOLD)
                            or len(shot_players) >= QUERY_TOOL_TRUNCATION_THRESHOLD
                        ):
                            section_errors.append(
                                f"shot_chart batch starting {batch[0]} may be truncated "
                                f"(rows={len(shot_players)}, rowsReturned={shot_rows_returned})"
                            )

                        tracking_params = dict(shot_params)
                        tracking_params["EventType"] = "TrackingShots"
                        tracking_payload = request_json(
                            client,
                            "/event/player",
                            tracking_params,
                            base_url=QUERY_TOOL_URL,
                        )
                        tracking_players = tracking_payload.get("players") or []
                        tracking_rows_returned = parse_int((tracking_payload.get("meta") or {}).get("rowsReturned"))
                        if (
                            (tracking_rows_returned is not None and tracking_rows_returned >= QUERY_TOOL_TRUNCATION_THRESHOLD)
                            or len(tracking_players) >= QUERY_TOOL_TRUNCATION_THRESHOLD
                        ):
                            section_errors.append(
                                f"shot_chart TrackingShots batch starting {batch[0]} may be truncated "
                                f"(rows={len(tracking_players)}, rowsReturned={tracking_rows_returned})"
                            )

                        tracking_flags_by_key: dict[tuple[str, int], dict] = {}
                        for tracking_row in tracking_players:
                            tracking_event_num = parse_int(tracking_row.get("eventNumber"))
                            if tracking_event_num is None:
                                continue
                            game_id_tracking = tracking_row.get("gameId")
                            if not game_id_tracking:
                                continue
                            tracking_flags_by_key[(game_id_tracking, tracking_event_num)] = map_tracking_shot_flags(
                                tracking_row.get("stats") or {}
                            )

                        for player in shot_players:
                            stats = player.get("stats") or {}
                            event_num = parse_int(player.get("eventNumber"))
                            if event_num is None:
                                continue
                            season_label_shot = player.get("seasonYear") or season_label_value
                            team_id_shot = parse_int(player.get("teamId"))
                            if team_id_shot == 0:
                                team_id_shot = None
                            assisted_id = parse_int(stats.get("AST_BY_PLAYER_ID"))
                            if assisted_id == 0:
                                assisted_id = None
                            assisted_name = stats.get("AST_BY_PLAYER_NAME")
                            if assisted_name in (None, "", "0"):
                                assisted_name = None
                            shot_chart_rows.append(
                                {
                                    "game_id": player.get("gameId"),
                                    "event_number": event_num,
                                    "nba_id": parse_int(player.get("playerId")),
                                    "team_id": team_id_shot,
                                    "period": parse_int(player.get("period")),
                                    "game_clock": parse_float(player.get("gameClock")),
                                    "x": parse_int(player.get("x")),
                                    "y": parse_int(player.get("y")),
                                    "shot_made": parse_float(stats.get("FGM")) == 1.0,
                                    "is_three": parse_float(stats.get("FG3")) == 1.0,
                                    "shot_type": derive_shot_type(stats),
                                    "shot_zone_area": stats.get("SHOT_ZONE_AREA"),
                                    "shot_zone_range": stats.get("SHOT_ZONE_RANGE"),
                                    "assisted_by_id": assisted_id,
                                    "assisted_by_name": assisted_name,
                                    "player_name": player.get("name"),
                                    "position": player.get("position"),
                                    "opponent_name": player.get("opponentName"),
                                    "game_date": parse_date(player.get("gameDate")),
                                    "season_year": parse_season_year(season_label_shot),
                                    "season_label": season_label_shot,
                                    "season_type": player.get("seasonType") or season_type,
                                    "created_at": shot_fetched_at,
                                    "updated_at": shot_fetched_at,
                                    "fetched_at": shot_fetched_at,
                                    **(tracking_flags_by_key.get((player.get("gameId"), event_num)) or {}),
                                }
                            )
            except Exception as exc:
                section_errors.append(f"shot_chart: {exc}")

        player_rows = list(player_rows_by_key.values())
        team_rows = list(team_rows_by_key.values())

        inserted_players = 0
        inserted_teams = 0
        inserted_lineup_season = 0
        inserted_lineup_game = 0
        inserted_shot_chart = 0
        if not dry_run:
            inserted_players = upsert(
                conn,
                "nba.player_stats_aggregated",
                player_rows,
                ["nba_id", "team_id", "season_year", "season_type", "per_mode"],
                update_exclude=["created_at"],
            )
            inserted_teams = upsert(
                conn,
                "nba.team_stats_aggregated",
                team_rows,
                ["team_id", "season_year", "season_type", "per_mode"],
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
            if shot_chart_rows:
                inserted_shot_chart = upsert(
                    conn,
                    "nba.shot_chart",
                    shot_chart_rows,
                    ["game_id", "event_number"],
                    update_exclude=["created_at"],
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
                    "table": "nba.shot_chart",
                    "rows": len(shot_chart_rows),
                    "upserted": inserted_shot_chart,
                },
            ],
            "errors": section_errors,
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
