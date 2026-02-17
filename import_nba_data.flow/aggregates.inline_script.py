# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import os
import time
from datetime import datetime, timezone

import httpx
import psycopg

BASE_URL = "https://api.nba.com/v0"

PLAYER_MEASURE_TYPES = ["Base", "Advanced", "Misc", "Scoring"]
TEAM_MEASURE_TYPES = ["Base", "Advanced", "Misc", "Scoring", "Opponent"]
PLAYER_PER_MODES = ["Totals", "PerGame", "Per36", "Per100Possessions"]
TEAM_PER_MODES = ["Totals", "PerGame"]


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


def upsert(
    conn: psycopg.Connection,
    table: str,
    rows: list[dict],
    conflict_keys: list[str],
    update_exclude: list[str] | None = None,
) -> int:
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
    # mode/days_back/start_date/end_date/game_ids/only_final_games are accepted
    # for compatibility with flow input transforms and local runner params.
    _ = (mode, days_back, start_date, end_date, game_ids, only_final_games)

    started_at = now_utc()

    conn: psycopg.Connection | None = None
    try:
        fetched_at = now_utc()
        season_label_value = season_label
        season_year = parse_season_year(season_label_value)

        player_rows_by_key: dict[tuple, dict] = {}
        team_rows_by_key: dict[tuple, dict] = {}
        section_errors: list[str] = []

        conn = psycopg.connect(os.environ["POSTGRES_URL"])

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

        player_rows = list(player_rows_by_key.values())
        team_rows = list(team_rows_by_key.values())

        inserted_players = 0
        inserted_teams = 0
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

        if conn:
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {"table": "nba.player_stats_aggregated", "rows": len(player_rows), "upserted": inserted_players},
                {"table": "nba.team_stats_aggregated", "rows": len(team_rows), "upserted": inserted_teams},
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
