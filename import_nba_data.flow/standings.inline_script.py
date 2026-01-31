# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "typing-extensions"]
# ///
import os
import re
import time
from datetime import datetime, timezone

import httpx
import psycopg

BASE_URL = "https://api.nba.com/v0"
CAMEL_TO_SNAKE_RE = re.compile(r"(?<!^)(?=[A-Z])")


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


def camel_to_snake(name: str) -> str:
    return CAMEL_TO_SNAKE_RE.sub("_", name).lower()


def to_bool(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    try:
        return bool(int(value))
    except (ValueError, TypeError):
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


STANDINGS_COLUMNS = {
    "league_id",
    "season_year",
    "season_label",
    "season_type",
    "team_id",
    "standing_date",
    "team_city",
    "team_name",
    "team_slug",
    "team_abbreviation",
    "conference",
    "division",
    "playoff_rank",
    "playoff_seeding",
    "clinch_indicator",
    "wins",
    "losses",
    "win_pct",
    "league_rank",
    "division_rank",
    "record",
    "home",
    "road",
    "neutral",
    "l10",
    "l10_home",
    "l10_road",
    "ot",
    "three_pts_or_less",
    "ten_pts_or_more",
    "current_streak",
    "current_streak_text",
    "current_home_streak",
    "current_home_streak_text",
    "current_road_streak",
    "current_road_streak_text",
    "long_win_streak",
    "long_loss_streak",
    "long_home_streak",
    "long_home_streak_text",
    "long_road_streak",
    "long_road_streak_text",
    "conference_games_back",
    "division_games_back",
    "league_games_back",
    "is_clinched_conference",
    "is_clinched_division",
    "is_clinched_playoffs",
    "is_clinched_postseason",
    "is_clinched_play_in",
    "is_eliminated_conference",
    "is_eliminated_division",
    "ahead_at_half",
    "behind_at_half",
    "tied_at_half",
    "ahead_at_third",
    "behind_at_third",
    "tied_at_third",
    "score_100_plus",
    "opp_score_100_plus",
    "opp_over_500",
    "lead_in_fg_pct",
    "lead_in_reb",
    "fewer_tov",
    "pts_per_game",
    "opp_pts_per_game",
    "diff_pts_per_game",
    "vs_east",
    "vs_west",
    "vs_atlantic",
    "vs_central",
    "vs_southeast",
    "vs_northwest",
    "vs_pacific",
    "vs_southwest",
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec",
    "sort_order",
}

FIELD_MAP = {
    "playoffRank": "playoff_rank",
    "playoffSeeding": "playoff_seeding",
    "clinchIndicator": "clinch_indicator",
    "winPct": "win_pct",
    "leagueRank": "league_rank",
    "divisionRank": "division_rank",
    "l10Home": "l10_home",
    "l10Road": "l10_road",
    "threePtsOrLess": "three_pts_or_less",
    "tenPtsOrMore": "ten_pts_or_more",
    "currentStreak": "current_streak",
    "currentStreakText": "current_streak_text",
    "currentHomeStreak": "current_home_streak",
    "currentHomeStreakText": "current_home_streak_text",
    "currentRoadStreak": "current_road_streak",
    "currentRoadStreakText": "current_road_streak_text",
    "longWinStreak": "long_win_streak",
    "longLossStreak": "long_loss_streak",
    "longHomeStreak": "long_home_streak",
    "longHomeStreakText": "long_home_streak_text",
    "longRoadStreak": "long_road_streak",
    "longRoadStreakText": "long_road_streak_text",
    "conferenceGamesBack": "conference_games_back",
    "divisionGamesBack": "division_games_back",
    "leagueGamesBack": "league_games_back",
    "score100Pts": "score_100_plus",
    "oppScore100Pts": "opp_score_100_plus",
    "oppOver500": "opp_over_500",
    "leadInFgPct": "lead_in_fg_pct",
    "leadInReb": "lead_in_reb",
    "fewerTurnovers": "fewer_tov",
    "pointsPg": "pts_per_game",
    "oppPointsPg": "opp_pts_per_game",
    "diffPtsPg": "diff_pts_per_game",
    "aheadAtHalf": "ahead_at_half",
    "behindAtHalf": "behind_at_half",
    "tiedAtHalf": "tied_at_half",
    "aheadAtThird": "ahead_at_third",
    "behindAtThird": "behind_at_third",
    "tiedAtThird": "tied_at_third",
    "sortOrder": "sort_order",
}

BOOL_FIELDS = {
    "is_clinched_conference",
    "is_clinched_division",
    "is_clinched_playoffs",
    "is_clinched_postseason",
    "is_clinched_play_in",
    "is_eliminated_conference",
    "is_eliminated_division",
}


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(
    dry_run: bool = False,
    league_id: str = "00",
    season_label: str | None = None,
    season_type: str = "Regular Season",
    mode: str | None = None,
    days_back: int | None = None,
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
    if not include_schedule_and_standings:
        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "errors": [],
        }

    try:
        params = {"leagueId": league_id, "season": season_label, "seasonType": season_type}
        with httpx.Client(timeout=30) as client:
            payload = request_json(client, "/api/standings/league", params)

        meta_time = payload.get("meta", {}).get("time")
        standing_dt = parse_datetime(meta_time)
        standing_date = standing_dt.date() if standing_dt else now_utc().date()

        league_standings = payload.get("leagueStandings", {})
        teams = league_standings.get("teams") or []
        season_label_value = season_label or league_standings.get("seasonYear")
        season_year = parse_season_year(season_label_value)
        fetched_at = now_utc()

        rows: list[dict] = []
        for team in teams:
            team_id = team.get("teamId")
            if team_id is None:
                continue

            row = {
                "league_id": league_id,
                "season_year": season_year,
                "season_label": season_label_value,
                "season_type": season_type,
                "team_id": team_id,
                "standing_date": standing_date,
                "team_city": team.get("teamCity"),
                "team_name": team.get("teamName"),
                "team_slug": team.get("teamSlug"),
                "team_abbreviation": team.get("teamAbbreviation"),
                "conference": team.get("conference"),
                "division": team.get("division"),
                "created_at": fetched_at,
                "updated_at": fetched_at,
                "fetched_at": fetched_at,
            }

            for key, value in team.items():
                if key in {"teamId", "teamCity", "teamName", "teamSlug", "teamAbbreviation", "conference", "division"}:
                    continue
                column = FIELD_MAP.get(key) or camel_to_snake(key)
                if column not in STANDINGS_COLUMNS:
                    continue
                if column in BOOL_FIELDS:
                    row[column] = to_bool(value)
                else:
                    row[column] = value

            rows.append(row)

        inserted = 0
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            inserted = upsert(
                conn,
                "nba.standings",
                rows,
                ["league_id", "season_year", "season_type", "team_id", "standing_date"],
                update_exclude=["created_at"],
            )
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {
                    "table": "nba.standings",
                    "rows": len(rows),
                    "upserted": inserted,
                }
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
