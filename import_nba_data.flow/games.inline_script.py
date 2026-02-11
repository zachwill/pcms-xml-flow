# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
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


def build_team_seed_row(team: dict, league_id: str, fetched_at: datetime) -> dict | None:
    team_id = parse_int(team.get("teamId"))
    if team_id is None:
        return None

    team_city = team.get("teamCity")
    team_name = team.get("teamName")
    team_tricode = team.get("teamTricode") or team.get("teamAbbreviation")

    return {
        "team_id": team_id,
        "team_name": team_name,
        "team_city": team_city,
        "team_full_name": f"{team_city} {team_name}" if team_city and team_name else None,
        "team_tricode": team_tricode,
        "team_slug": team.get("teamSlug"),
        "league_id": league_id,
        "conference": team.get("conference"),
        "division": team.get("division"),
        "state": team.get("teamState"),
        "arena_name": None,
        "arena_city": None,
        "arena_state": None,
        "arena_timezone": None,
        "is_active": True,
        "created_at": fetched_at,
        "updated_at": fetched_at,
        "fetched_at": fetched_at,
    }


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
        raise ValueError("date_backfill mode requires start_date and end_date")

    if normalized_mode == "season_backfill":
        return resolve_season_date_range(season_label)

    raise ValueError("mode must be one of: refresh, date_backfill, season_backfill")


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
                    "high_seed_id": parse_int(series.get("highSeedId")),
                    "low_seed_id": parse_int(series.get("lowSeedId")),
                    "high_seed_rank": parse_int(series.get("highSeedRank")),
                    "low_seed_rank": parse_int(series.get("lowSeedRank")),
                    "high_seed_series_wins": parse_int(series.get("highSeedSeriesWins")),
                    "low_seed_series_wins": parse_int(series.get("lowSeedSeriesWins")),
                    "series_winner_team_id": parse_int(series.get("seriesWinner")),
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
) -> dict:
    started_at = now_utc()

    try:
        start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date, season_label)
        fetched_at = now_utc()
        season_label_value = season_label
        rows: list[dict] = []
        series_rows: list[dict] = []
        team_seed_rows_by_id: dict[int, dict] = {}
        desired_season_type = normalize_season_type(season_type)
        skipped_by_season_type = 0

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

                    game_season_type = game.get("seasonType") or season_type
                    if desired_season_type and normalize_season_type(game_season_type) != desired_season_type:
                        skipped_by_season_type += 1
                        continue

                    game_time_utc = parse_datetime(game.get("gameTimeUTC"))
                    game_time_et = parse_datetime(game.get("gameEt"))

                    arena = game.get("arena") or {}
                    broadcasters = game.get("broadcasters") or {}
                    home_team = game.get("homeTeam") or {}
                    away_team = game.get("awayTeam") or {}

                    for team in [home_team, away_team]:
                        seed_row = build_team_seed_row(team, league_id_value, fetched_at)
                        if not seed_row:
                            continue
                        team_seed_rows_by_id.setdefault(seed_row["team_id"], seed_row)

                    rows.append(
                        {
                            "game_id": game_id_value,
                            "league_id": league_id_value,
                            "season_year": season_year,
                            "season_label": season_label_value,
                            "season_type": game_season_type,
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
                            "home_team_id": parse_int(home_team.get("teamId")),
                            "away_team_id": parse_int(away_team.get("teamId")),
                            "home_score": parse_int(home_team.get("score")),
                            "away_score": parse_int(away_team.get("score")),
                            "home_wins": parse_int(home_team.get("wins")),
                            "home_losses": parse_int(home_team.get("losses")),
                            "away_wins": parse_int(away_team.get("wins")),
                            "away_losses": parse_int(away_team.get("losses")),
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
        inserted_seeded_teams = 0
        seeded_team_rows = 0
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            if rows:
                referenced_team_ids = list(
                    {
                        team_id
                        for row in rows
                        for team_id in (row.get("home_team_id"), row.get("away_team_id"))
                        if team_id is not None
                    }
                )

                existing_team_ids: set[int] = set()
                if referenced_team_ids:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT team_id FROM nba.teams WHERE team_id = ANY(%s)",
                            (referenced_team_ids,),
                        )
                        existing_team_ids = {row[0] for row in cur.fetchall()}

                missing_team_ids = [team_id for team_id in referenced_team_ids if team_id not in existing_team_ids]
                if missing_team_ids:
                    seeded_rows: list[dict] = []
                    for team_id in missing_team_ids:
                        seed_row = team_seed_rows_by_id.get(team_id)
                        if seed_row:
                            seeded_rows.append(seed_row)
                            continue

                        seeded_rows.append(
                            {
                                "team_id": team_id,
                                "team_name": None,
                                "team_city": None,
                                "team_full_name": None,
                                "team_tricode": None,
                                "team_slug": None,
                                "league_id": league_id,
                                "conference": None,
                                "division": None,
                                "state": None,
                                "arena_name": None,
                                "arena_city": None,
                                "arena_state": None,
                                "arena_timezone": None,
                                "is_active": True,
                                "created_at": fetched_at,
                                "updated_at": fetched_at,
                                "fetched_at": fetched_at,
                            }
                        )

                    seeded_team_rows = len(seeded_rows)
                    inserted_seeded_teams = upsert(
                        conn,
                        "nba.teams",
                        seeded_rows,
                        ["team_id"],
                        update_exclude=["created_at"],
                    )

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
                {
                    "table": "nba.teams",
                    "rows": seeded_team_rows,
                    "upserted": inserted_seeded_teams,
                },
            ],
            "skipped_games_by_season_type": skipped_by_season_type,
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
