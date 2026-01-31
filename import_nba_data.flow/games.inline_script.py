# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "typing-extensions"]
# ///
import os
import time
from datetime import datetime, timezone, timedelta, date

import httpx
import psycopg
from psycopg.types.json import Json

BASE_URL = "https://api.nba.com/v0"
PLAYOFF_SERIES_ROUNDS = {
    1: 8,
    2: 4,
    3: 2,
    4: 1,
}


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


def date_range(start: date, end: date):
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


def extract_broadcasters(broadcasters: dict | None, key: str) -> list[str] | None:
    if not broadcasters:
        return None
    items = broadcasters.get(key) or []
    names = [b.get("broadcastDisplay") for b in items if b.get("broadcastDisplay")]
    return names or None


def fetch_playoff_series(
    client: httpx.Client,
    league_id: str,
    season_label: str | None,
    season_type: str | None,
    fetched_at: datetime,
) -> list[dict]:
    if not season_label:
        return []
    season_year = parse_season_year(season_label)
    rows: list[dict] = []

    for po_round, series_count in PLAYOFF_SERIES_ROUNDS.items():
        for series_number in range(series_count):
            payload = request_json(
                client,
                "/api/scores/playoff/seriessummary",
                {
                    "leagueId": league_id,
                    "season": season_label,
                    "series": series_number,
                    "poRound": po_round,
                },
            )
            series = payload.get("series") or {}
            series_id = series.get("seriesId")
            if not series_id:
                continue
            series_status = series.get("seriesStatus")
            rows.append(
                {
                    "series_id": series_id,
                    "league_id": league_id,
                    "season_year": season_year,
                    "season_label": season_label,
                    "season_type": season_type,
                    "round_number": series.get("roundNumber"),
                    "series_number": series.get("seriesNumber"),
                    "series_conference": series.get("seriesConference"),
                    "series_text": series.get("seriesText"),
                    "series_status": str(series_status) if series_status is not None else None,
                    "high_seed_id": series.get("highSeedId"),
                    "low_seed_id": series.get("lowSeedId"),
                    "high_seed_rank": series.get("highSeedRank"),
                    "low_seed_rank": series.get("lowSeedRank"),
                    "high_seed_series_wins": series.get("highSeedSeriesWins"),
                    "low_seed_series_wins": series.get("lowSeedSeriesWins"),
                    "series_winner_team_id": series.get("seriesWinner"),
                    "next_series_id": series.get("nextSeriesId"),
                    "next_game_id": series.get("nextGameId"),
                    "series_game_id_prefix": series.get("seriesGameIdsFirst9Digits"),
                    "series_json": Json(payload),
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
    only_final_games: bool = True,
) -> dict:
    started_at = now_utc()
    if not include_games:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [],
        }

    try:
        start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date)
        fetched_at = now_utc()
        season_label_value = season_label
        rows: list[dict] = []
        series_rows: list[dict] = []

        with httpx.Client(timeout=30) as client:
            for day in date_range(start_dt, end_dt):
                payload = request_json(
                    client,
                    "/api/scores/scoreboard/date",
                    {"leagueId": league_id, "gameDate": day.isoformat()},
                )
                scoreboard = payload.get("scoreboard") or {}
                games = scoreboard.get("games") or []
                league_id_value = scoreboard.get("leagueId") or league_id
                game_date = parse_date(scoreboard.get("gameDate")) or day

                for game in games:
                    game_id_value = game.get("gameId")
                    if not game_id_value:
                        continue

                    season_label_value = game.get("seasonYear") or season_label_value
                    season_year = parse_season_year(season_label_value)

                    game_time_utc = parse_datetime(game.get("gameTimeUTC"))
                    game_time_et = parse_datetime(game.get("gameEt"))

                    arena = game.get("arena") or {}
                    broadcasters = game.get("broadcasters") or {}
                    home_team = game.get("homeTeam") or {}
                    away_team = game.get("awayTeam") or {}

                    rows.append(
                        {
                            "game_id": game_id_value,
                            "league_id": league_id_value,
                            "season_year": season_year,
                            "season_label": season_label_value,
                            "season_type": game.get("seasonType") or season_type,
                            "game_date": game_date,
                            "game_sequence": None,
                            "postponed_status": None,
                            "game_date_est": game_time_et,
                            "game_date_utc": game_time_utc,
                            "game_time_utc": game_time_utc,
                            "game_datetime_utc": game_time_utc,
                            "game_code": game.get("gameCode"),
                            "game_status": game.get("gameStatus"),
                            "game_status_text": game.get("gameStatusText"),
                            "period": game.get("period"),
                            "game_clock": game.get("gameClock"),
                            "home_team_id": home_team.get("teamId"),
                            "away_team_id": away_team.get("teamId"),
                            "home_score": home_team.get("score"),
                            "away_score": away_team.get("score"),
                            "home_wins": home_team.get("wins"),
                            "home_losses": home_team.get("losses"),
                            "away_wins": away_team.get("wins"),
                            "away_losses": away_team.get("losses"),
                            "arena_name": arena.get("arenaName"),
                            "arena_city": arena.get("arenaCity"),
                            "arena_state": arena.get("arenaState"),
                            "arena_timezone": arena.get("arenaTimezone"),
                            "attendance": None,
                            "game_duration_minutes": None,
                            "week_number": None,
                            "week_name": None,
                            "game_label": game.get("gameLabel"),
                            "game_sublabel": game.get("gameSublabel"),
                            "game_subtype": game.get("gameSubtype"),
                            "series_game_number": game.get("seriesGameNumber"),
                            "series_text": game.get("seriesText"),
                            "series_conference": game.get("seriesConference"),
                            "po_round": game.get("poRound"),
                            "if_necessary": game.get("ifNecessary"),
                            "is_neutral": game.get("isNeutral"),
                            "is_target_score_ending": game.get("targetScoreEnding"),
                            "target_score_period": game.get("targetScorePeriod"),
                            "target_score": game.get("targetScore"),
                            "national_broadcasters": extract_broadcasters(broadcasters, "nationalBroadcasters"),
                            "home_tv_broadcasters": extract_broadcasters(broadcasters, "homeTvBroadcasters"),
                            "home_radio_broadcasters": extract_broadcasters(broadcasters, "homeRadioBroadcasters"),
                            "away_tv_broadcasters": extract_broadcasters(broadcasters, "awayTvBroadcasters"),
                            "away_radio_broadcasters": extract_broadcasters(broadcasters, "awayRadioBroadcasters"),
                            "game_json": Json(game),
                            "ngss_game_id": None,
                            "created_at": fetched_at,
                            "updated_at": fetched_at,
                            "fetched_at": fetched_at,
                        }
                    )

            if season_type and "play" in season_type.lower():
                series_rows = fetch_playoff_series(
                    client,
                    league_id,
                    season_label_value,
                    season_type,
                    fetched_at,
                )

        inserted = 0
        inserted_series = 0
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            if rows:
                inserted = upsert(conn, "nba.games", rows, ["game_id"], update_exclude=["created_at"])
            if series_rows:
                inserted_series = upsert(
                    conn,
                    "nba.playoff_series",
                    series_rows,
                    ["series_id"],
                    update_exclude=["created_at"],
                )
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {
                    "table": "nba.games",
                    "rows": len(rows),
                    "upserted": inserted,
                },
                {
                    "table": "nba.playoff_series",
                    "rows": len(series_rows),
                    "upserted": inserted_series,
                },
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
