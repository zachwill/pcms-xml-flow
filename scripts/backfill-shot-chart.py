#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx"]
# ///
"""
Backfill nba.shot_chart for all final games that don't have shot data yet.

Uses batched GameId requests (up to 50 games per API call) so the full
season backfill takes ~40 seconds instead of ~25 minutes.

Usage:
    # dry-run (just shows what would be fetched)
    uv run scripts/backfill-shot-chart.py

    # actually write
    uv run scripts/backfill-shot-chart.py --write

    # specific season
    uv run scripts/backfill-shot-chart.py --write --season-label 2024-25

    # limit to N games (for testing)
    uv run scripts/backfill-shot-chart.py --write --limit 5
"""
import argparse
import os
import sys
import time
from datetime import datetime, timezone

import httpx
import psycopg

QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"
BATCH_SIZE = 50  # ~180 shots/game × 50 = ~9000, safely under 10k API limit


def now_utc():
    return datetime.now(timezone.utc)


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


def parse_date(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        try:
            return datetime.strptime(value, "%Y-%m-%d").date()
        except ValueError:
            return None


def parse_season_year(label):
    if not label:
        return None
    try:
        return int(label[:4])
    except (ValueError, TypeError):
        return None


def derive_shot_type(stats: dict) -> str | None:
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


def request_json(client, path, params, retries=3):
    headers = {"X-NBA-Api-Key": os.environ["NBA_API_KEY"]}
    url = f"{QUERY_TOOL_URL}{path}"
    for attempt in range(retries):
        try:
            resp = client.get(url, params=params, headers=headers)
        except httpx.TimeoutException:
            if attempt == retries - 1:
                raise
            time.sleep(2 + attempt * 2)
            continue
        if resp.status_code in {429, 500, 502, 503, 504}:
            if attempt == retries - 1:
                resp.raise_for_status()
            wait = 3 + attempt * 3
            if resp.status_code == 429:
                wait = 10 + attempt * 5
            time.sleep(wait)
            continue
        if resp.status_code == 404:
            return {}
        resp.raise_for_status()
        return resp.json()
    raise RuntimeError(f"Failed to fetch {url}")


def upsert_shot_chart(conn, rows):
    if not rows:
        return 0
    cols = [
        "game_id", "event_number", "nba_id", "team_id", "period", "game_clock",
        "x", "y", "shot_made", "is_three", "shot_type", "shot_zone_area",
        "shot_zone_range", "assisted_by_id", "assisted_by_name", "player_name",
        "position", "opponent_name", "game_date", "season_year", "season_label",
        "season_type", "created_at", "updated_at", "fetched_at",
    ]
    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)
    update_cols = [c for c in cols if c not in ("game_id", "event_number", "created_at")]
    updates = ", ".join(f"{c} = EXCLUDED.{c}" for c in update_cols)
    sql = f"INSERT INTO nba.shot_chart ({col_list}) VALUES ({placeholders}) ON CONFLICT (game_id, event_number) DO UPDATE SET {updates}"
    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(r.get(c) for c in cols) for r in rows])
    conn.commit()
    return len(rows)


def parse_shot_rows(players_data: list, fallback_season_label: str, fallback_season_type: str, fetched_at) -> list[dict]:
    """Parse API response rows into shot_chart dicts."""
    rows = []
    for player in players_data:
        stats = player.get("stats") or {}
        event_num = parse_int(player.get("eventNumber"))
        if event_num is None:
            continue
        season_label_shot = player.get("seasonYear") or fallback_season_label
        team_id_shot = parse_int(player.get("teamId"))
        if team_id_shot == 0:
            team_id_shot = None
        assisted_id = parse_int(stats.get("AST_BY_PLAYER_ID"))
        if assisted_id == 0:
            assisted_id = None
        assisted_name = stats.get("AST_BY_PLAYER_NAME")
        if assisted_name in (None, "", "0"):
            assisted_name = None
        rows.append({
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
            "season_type": player.get("seasonType") or fallback_season_type,
            "created_at": fetched_at,
            "updated_at": fetched_at,
            "fetched_at": fetched_at,
        })
    return rows


def fetch_shot_chart_batch(client, game_ids: list[str], season_label: str, season_type: str):
    """Fetch shot chart for multiple games in a single API call."""
    fetched_at = now_utc()
    params = {
        "LeagueId": "00",
        "SeasonYear": season_label,
        "SeasonType": season_type,
        "PerMode": "Totals",
        "SumScope": "Event",
        "Grouping": "None",
        "TeamGrouping": "Y",
        "EventType": "FieldGoals",
        "GameId": ",".join(game_ids),
        "MaxRowsReturned": 10000,
    }
    payload = request_json(client, "/event/player", params)
    return parse_shot_rows(
        payload.get("players") or [],
        fallback_season_label=season_label,
        fallback_season_type=season_type,
        fetched_at=fetched_at,
    )


def main():
    parser = argparse.ArgumentParser(description="Backfill nba.shot_chart")
    parser.add_argument("--write", action="store_true", help="Write to database")
    parser.add_argument("--season-label", default="2025-26")
    parser.add_argument("--season-type", default="Regular Season")
    parser.add_argument("--limit", type=int, default=0, help="Max games to process (0=all)")
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE, help="Games per API call (default 50)")
    parser.add_argument("--sleep", type=float, default=0.5, help="Seconds between API calls")
    args = parser.parse_args()

    conn = psycopg.connect(os.environ["POSTGRES_URL"])

    # Find final games that have no shot chart data yet
    with conn.cursor() as cur:
        cur.execute("""
            SELECT g.game_id, g.season_label, g.season_type
            FROM nba.games g
            LEFT JOIN (
                SELECT DISTINCT game_id FROM nba.shot_chart
            ) sc ON sc.game_id = g.game_id
            WHERE g.game_status = 3
              AND g.season_label = %s
              AND g.season_type = %s
              AND sc.game_id IS NULL
            ORDER BY g.game_date, g.game_id
        """, (args.season_label, args.season_type))
        games = cur.fetchall()

    if args.limit > 0:
        games = games[:args.limit]

    print(f"Found {len(games)} final games without shot chart data")
    if not games:
        conn.close()
        return

    if not args.write:
        print("DRY RUN — pass --write to actually fetch and insert")
        for gid, sl, st in games[:20]:
            print(f"  {gid}  {sl}  {st}")
        if len(games) > 20:
            print(f"  ... and {len(games) - 20} more")
        conn.close()
        return

    # Batch games into groups
    game_ids = [g[0] for g in games]
    season_label = games[0][1]
    season_type = games[0][2]
    batches = [game_ids[i:i + args.batch_size] for i in range(0, len(game_ids), args.batch_size)]

    total_rows = 0
    total_games_done = 0
    errors = []
    start_time = time.time()

    with httpx.Client(timeout=120) as client:
        for batch_idx, batch in enumerate(batches):
            try:
                rows = fetch_shot_chart_batch(client, batch, season_label, season_type)

                # Sanity check: did we hit the 10k cap?
                if len(rows) >= 9900:
                    print(f"  WARNING: batch {batch_idx+1} returned {len(rows)} rows — may be truncated!", file=sys.stderr)

                if rows:
                    upsert_shot_chart(conn, rows)

                # Count unique games in response
                games_in_response = len(set(r["game_id"] for r in rows))
                total_rows += len(rows)
                total_games_done += len(batch)

                elapsed = time.time() - start_time
                print(f"  batch {batch_idx+1}/{len(batches)}: {len(batch)} games, {len(rows)} shots ({games_in_response} games in response), {elapsed:.1f}s elapsed")

                if args.sleep > 0 and batch_idx < len(batches) - 1:
                    time.sleep(args.sleep)

            except Exception as exc:
                errors.append(f"batch {batch_idx+1} ({batch[0]}..{batch[-1]}): {exc}")
                print(f"  batch {batch_idx+1}/{len(batches)}: ERROR {exc}", file=sys.stderr)

    conn.close()
    elapsed = time.time() - start_time
    print(f"\nDone: {total_rows} total shots across {total_games_done} games in {elapsed:.1f}s, {len(errors)} errors")
    if errors:
        print("Errors:")
        for e in errors:
            print(f"  {e}")


if __name__ == "__main__":
    main()
