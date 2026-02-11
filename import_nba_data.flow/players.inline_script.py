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


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def parse_date(value: str | None):
    if not value:
        return None
    try:
        # NBA API uses MM/DD/YYYY for birthdate
        return datetime.strptime(value, "%m/%d/%Y").date()
    except ValueError:
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
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


def roster_status_to_active(value: int | None):
    if value is None:
        return None
    return value == 1


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(
    dry_run: bool = False,
    league_id: str = "00",
    season_label: str | None = None,
) -> dict:
    started_at = now_utc()

    try:
        params = {"leagueId": league_id}
        if season_label:
            params["season"] = season_label

        with httpx.Client(timeout=30) as client:
            payload = request_json(client, "/api/stats/player/index", params)

        players = payload.get("players") or payload.get("data", {}).get("players") or []
        fetched_at = now_utc()
        rows: list[dict] = []

        for player in players:
            nba_id = player.get("playerId")
            if nba_id is None:
                continue

            first_name = player.get("firstName")
            last_name = player.get("lastName")
            roster_status = player.get("rosterStatus")

            rows.append(
                {
                    "nba_id": nba_id,
                    "first_name": first_name,
                    "last_name": last_name,
                    "full_name": player.get("name") or (f"{first_name} {last_name}" if first_name and last_name else None),
                    "player_slug": player.get("playerSlug"),
                    "is_active": roster_status_to_active(roster_status),
                    "status": "Active" if roster_status == 1 else "Inactive" if roster_status == 2 else None,
                    "position": player.get("position"),
                    "jersey": player.get("jerseyNum"),
                    "height": player.get("height"),
                    "weight": player.get("weight"),
                    "birthdate": parse_date(player.get("birthdate")),
                    "country": player.get("country"),
                    "last_affiliation": player.get("lastAffiliation"),
                    "draft_year": player.get("draftYear"),
                    "draft_round": player.get("draftRound"),
                    "draft_number": player.get("draftNumber"),
                    "season_exp": player.get("seasonExperience"),
                    "from_year": player.get("fromYear"),
                    "to_year": player.get("toYear"),
                    "current_team_id": player.get("teamId"),
                    "current_team_tricode": player.get("teamTricode") or player.get("teamAbbreviation"),
                    "league_id": payload.get("leagueId") or league_id,
                    "dleague_flag": None,
                    "nba_flag": None,
                    "games_played_flag": None,
                    "draft_flag": None,
                    "greatest_75_flag": None,
                    "roster_status": str(roster_status) if roster_status is not None else None,
                    "created_at": fetched_at,
                    "updated_at": fetched_at,
                    "fetched_at": fetched_at,
                }
            )

        inserted = 0
        if not dry_run and rows:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            inserted = upsert(conn, "nba.players", rows, ["nba_id"], update_exclude=["created_at"])
            conn.close()

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {
                    "table": "nba.players",
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
