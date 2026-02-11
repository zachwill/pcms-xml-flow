# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import os
import re
import time
from datetime import datetime, timezone

import httpx
import psycopg
from psycopg.types.json import Json

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
    "team_tricode",
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

BRACKET_STATES = ["PlayoffPicture", "PlayIn", "PlayoffBracket", "IST"]


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(
    dry_run: bool = False,
    league_id: str = "00",
    season_label: str | None = None,
    season_type: str = "Regular Season",
) -> dict:
    started_at = now_utc()

    try:
        params = {"leagueId": league_id, "season": season_label, "seasonType": season_type}
        fetched_at = now_utc()

        rows: list[dict] = []
        bracket_rows: list[dict] = []
        ist_rows: list[dict] = []

        with httpx.Client(timeout=30) as client:
            # League standings
            payload = request_json(client, "/api/standings/league", params)

            meta_time = payload.get("meta", {}).get("time")
            standing_dt = parse_datetime(meta_time)
            standing_date = standing_dt.date() if standing_dt else now_utc().date()

            league_standings = payload.get("leagueStandings", {})
            teams = league_standings.get("teams") or []
            season_label_value = season_label or league_standings.get("seasonYear") or ""
            season_year = parse_season_year(season_label_value)

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
                    "team_tricode": team.get("teamTricode") or team.get("teamAbbreviation"),
                    "conference": team.get("conference"),
                    "division": team.get("division"),
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }

                for key, value in team.items():
                    if key in {"teamId", "teamCity", "teamName", "teamSlug", "teamTricode", "teamAbbreviation", "conference", "division"}:
                        continue
                    column = FIELD_MAP.get(key) or camel_to_snake(key)
                    if column not in STANDINGS_COLUMNS:
                        continue
                    if column in BOOL_FIELDS:
                        row[column] = to_bool(value)
                    else:
                        row[column] = value

                rows.append(row)

            # Playoff bracket snapshots by bracket state
            for bracket_state in BRACKET_STATES:
                bracket_payload = request_json(
                    client,
                    "/api/standings/playoff/bracket",
                    {
                        "leagueId": league_id,
                        "season": season_label_value or season_label,
                        "bracketState": bracket_state,
                    },
                )
                bracket = bracket_payload.get("bracket") or {}
                if not bracket:
                    continue

                bracket_meta_time = (bracket_payload.get("meta") or {}).get("time")
                bracket_dt = parse_datetime(bracket_meta_time)
                bracket_date = bracket_dt.date() if bracket_dt else standing_date
                bracket_season_label = bracket.get("seasonYear") or season_label_value or season_label or ""

                bracket_rows.append(
                    {
                        "league_id": bracket.get("leagueId") or league_id,
                        "season_year": parse_season_year(bracket_season_label),
                        "season_label": bracket_season_label,
                        "bracket_state": bracket_state,
                        "bracket_type": bracket.get("bracketType"),
                        "standing_date": bracket_date,
                        "meta_time": bracket_dt,
                        "playoff_picture_series_count": len(bracket.get("playoffPictureSeries") or []),
                        "play_in_bracket_series_count": len(bracket.get("playInBracketSeries") or []),
                        "playoff_bracket_series_count": len(bracket.get("playoffBracketSeries") or []),
                        "ist_bracket_series_count": len(bracket.get("istBracketSeries") or []),
                        "bracket_json": Json(bracket),
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )

            # In-season tournament standings snapshot
            ist_payload = request_json(
                client,
                "/api/standings/ist",
                {
                    "leagueId": league_id,
                    "season": season_label_value or season_label,
                },
            )

            ist_season_label = ist_payload.get("seasonYear") or season_label_value or season_label or ""
            ist_season_year = parse_season_year(ist_season_label)
            ist_standing_date = standing_date

            for team in ist_payload.get("teams") or []:
                team_id = parse_int(team.get("teamId"))
                if team_id is None:
                    continue

                ist_rows.append(
                    {
                        "league_id": ist_payload.get("leagueId") or league_id,
                        "season_year": ist_season_year,
                        "season_label": ist_season_label,
                        "team_id": team_id,
                        "standing_date": ist_standing_date,
                        "team_city": team.get("teamCity"),
                        "team_name": team.get("teamName"),
                        "team_tricode": team.get("teamTricode") or team.get("teamAbbreviation"),
                        "team_slug": team.get("teamSlug"),
                        "conference": team.get("conference"),
                        "ist_group": team.get("istGroup"),
                        "clinch_indicator": team.get("clinchIndicator"),
                        "is_clinched_ist_knockout": to_bool(team.get("clinchedIstKnockout")),
                        "is_clinched_ist_group": to_bool(team.get("clinchedIstGroup")),
                        "is_clinched_ist_wildcard": to_bool(team.get("clinchedIstWildcard")),
                        "ist_wildcard_rank": parse_int(team.get("istWildcardRank")),
                        "ist_group_rank": parse_int(team.get("istGroupRank")),
                        "ist_knockout_rank": parse_int(team.get("istKnockoutRank")),
                        "wins": parse_int(team.get("wins")),
                        "losses": parse_int(team.get("losses")),
                        "win_pct": parse_float(team.get("pct")),
                        "ist_group_gb": parse_float(team.get("istGroupGb")),
                        "ist_wildcard_gb": parse_float(team.get("istWildcardGb")),
                        "diff": parse_int(team.get("diff")),
                        "pts": parse_int(team.get("pts")),
                        "opp_pts": parse_int(team.get("oppPts")),
                        "games_json": Json(team.get("games") or []),
                        "created_at": fetched_at,
                        "updated_at": fetched_at,
                        "fetched_at": fetched_at,
                    }
                )

        inserted = 0
        inserted_brackets = 0
        inserted_ist = 0
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            if rows:
                inserted = upsert(
                    conn,
                    "nba.standings",
                    rows,
                    ["league_id", "season_year", "season_type", "team_id", "standing_date"],
                    update_exclude=["created_at"],
                )
            if bracket_rows:
                inserted_brackets = upsert(
                    conn,
                    "nba.standings_playoff_bracket",
                    bracket_rows,
                    ["league_id", "season_label", "bracket_state", "standing_date"],
                    update_exclude=["created_at"],
                )
            if ist_rows:
                inserted_ist = upsert(
                    conn,
                    "nba.standings_ist",
                    ist_rows,
                    ["league_id", "season_label", "team_id", "standing_date"],
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
                },
                {
                    "table": "nba.standings_playoff_bracket",
                    "rows": len(bracket_rows),
                    "upserted": inserted_brackets,
                },
                {
                    "table": "nba.standings_ist",
                    "rows": len(ist_rows),
                    "upserted": inserted_ist,
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
