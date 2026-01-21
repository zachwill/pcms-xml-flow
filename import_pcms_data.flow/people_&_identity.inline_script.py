# /// script
# requires-python = ">=3.11"
# dependencies = ["polars", "psycopg[binary]"]
# ///
"""
People & Identity Import

Imports players, agencies, and agents from PCMS extract.
Agencies come from lookups.json, agents/people from players.json.

Order (FK-safe): agencies → agents → people

Upserts into:
- pcms.agencies
- pcms.agents
- pcms.people
"""
import os
import json
from pathlib import Path
from datetime import datetime

import polars as pl
import psycopg

# ─────────────────────────────────────────────────────────────────────────────
# Helpers (inline - no shared imports in Windmill)
# ─────────────────────────────────────────────────────────────────────────────

def upsert(conn, table: str, rows: list[dict], conflict_keys: list[str]) -> int:
    """Upsert rows. Auto-generates ON CONFLICT DO UPDATE for non-key columns."""
    if not rows:
        return 0
    cols = list(rows[0].keys())
    update_cols = [c for c in cols if c not in conflict_keys]

    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)
    conflict = ", ".join(conflict_keys)
    updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])

    sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO UPDATE SET {updates}"

    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(r[c] for c in cols) for r in rows])
    conn.commit()
    return len(rows)


def find_extract_dir(base: str = "./shared/pcms") -> Path:
    """Find the extract directory (handles nested subdirectory)."""
    base_path = Path(base)
    subdirs = [d for d in base_path.iterdir() if d.is_dir()]
    return subdirs[0] if subdirs else base_path


def to_int(val) -> int | None:
    """Convert to int or None."""
    if val is None or val == "":
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


def first_element(val):
    """Get first element if list, otherwise return val."""
    if isinstance(val, list):
        return val[0] if val else None
    return val


def build_full_name(first: str | None, last: str | None) -> str | None:
    """Build full name from first and last."""
    parts = [p for p in [first, last] if p]
    return " ".join(parts) if parts else None


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main(dry_run: bool = False, extract_dir: str = "./shared/pcms"):
    started_at = datetime.now().isoformat()
    tables = []
    errors = []

    try:
        base_dir = find_extract_dir(extract_dir)
        ingested_at = datetime.now().isoformat()

        # Load lookups for agencies and team code mapping
        with open(base_dir / "lookups.json") as f:
            lookups = json.load(f)

        # ─────────────────────────────────────────────────────────────────────
        # Build team code map (team_id -> team_code)
        # ─────────────────────────────────────────────────────────────────────
        teams_raw = lookups.get("lk_teams", {}).get("lk_team", [])
        team_code_map = {
            t["team_id"]: t.get("team_name_short") or t.get("team_code")
            for t in teams_raw
            if t.get("team_id") and (t.get("team_name_short") or t.get("team_code"))
        }

        # ─────────────────────────────────────────────────────────────────────
        # Agencies (from lookups.json) - use Polars for clean transform
        # ─────────────────────────────────────────────────────────────────────
        agencies_raw = lookups.get("lk_agencies", {}).get("lk_agency", [])
        agencies_df = pl.DataFrame(agencies_raw)

        agencies = (
            agencies_df
            .filter(pl.col("agency_id").is_not_null())
            .rename({"active_flg": "is_active"})
            .with_columns([
                pl.col("create_date").alias("created_at"),
                pl.col("last_change_date").alias("updated_at"),
                pl.col("record_change_date").alias("record_changed_at"),
                pl.struct(pl.all()).map_elements(
                    lambda x: json.dumps(dict(x), default=str), return_dtype=pl.Utf8
                ).alias("agency_json"),
                pl.lit(ingested_at).alias("ingested_at"),
            ])
            .select([
                "agency_id", "agency_name", "is_active",
                "created_at", "updated_at", "record_changed_at",
                "agency_json", "ingested_at",
            ])
            .unique(subset=["agency_id"])
            .to_dicts()
        )

        # Build agency name map for agents
        agency_name_map = {a["agency_id"]: a["agency_name"] for a in agencies if a.get("agency_name")}

        # ─────────────────────────────────────────────────────────────────────
        # Players (from players.json) - dict-based due to mixed types
        # ─────────────────────────────────────────────────────────────────────
        with open(base_dir / "players.json") as f:
            players_raw = json.load(f)

        # ─────────────────────────────────────────────────────────────────────
        # Agents (subset of players where person_type_lk = "AGENT")
        # ─────────────────────────────────────────────────────────────────────
        agents_seen = {}
        for p in players_raw:
            if p.get("person_type_lk") != "AGENT":
                continue
            agent_id = to_int(p.get("player_id"))
            if agent_id is None:
                continue
            agency_id = to_int(p.get("agency_id"))
            agents_seen[agent_id] = {
                "agent_id": agent_id,
                "agency_id": agency_id,
                "agency_name": agency_name_map.get(agency_id) if agency_id else None,
                "first_name": p.get("first_name"),
                "last_name": p.get("last_name"),
                "full_name": build_full_name(p.get("first_name"), p.get("last_name")),
                "is_active": p.get("record_status_lk") == "ACT" if p.get("record_status_lk") else None,
                "is_certified": True,
                "person_type_lk": p.get("person_type_lk"),
                "created_at": p.get("create_date"),
                "updated_at": p.get("last_change_date"),
                "record_changed_at": p.get("record_change_date"),
                "agent_json": json.dumps(p, default=str),
                "ingested_at": ingested_at,
            }
        agents = list(agents_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # People (all records in players.json)
        # ─────────────────────────────────────────────────────────────────────
        people_seen = {}
        for p in players_raw:
            person_id = to_int(p.get("player_id"))
            if person_id is None:
                continue

            team_id = to_int(p.get("team_id"))
            draft_team_id = to_int(p.get("draft_team_id"))
            dlg_returning_rights_team_id = to_int(p.get("dlg_returning_rights_team_id"))
            dlg_team_id = to_int(p.get("dlg_team_id"))

            people_seen[person_id] = {
                "person_id": person_id,
                "first_name": p.get("first_name"),
                "last_name": p.get("last_name"),
                "middle_name": p.get("middle_name") or None,
                "display_first_name": p.get("display_first_name"),
                "display_last_name": p.get("display_last_name"),
                "roster_first_name": p.get("roster_first_name"),
                "roster_last_name": p.get("roster_last_name"),
                "birth_date": p.get("birth_date") or None,
                "birth_country_lk": p.get("birth_country_lk"),
                "gender": p.get("gender"),
                "height": to_int(p.get("height")),
                "weight": to_int(p.get("weight")),
                "person_type_lk": p.get("person_type_lk"),
                "player_status_lk": p.get("player_status_lk"),
                "record_status_lk": p.get("record_status_lk"),
                "league_lk": p.get("league_lk"),
                "team_id": team_id,
                "team_code": team_code_map.get(team_id) if team_id else None,
                "draft_team_id": draft_team_id,
                "draft_team_code": team_code_map.get(draft_team_id) if draft_team_id else None,
                "dlg_returning_rights_team_id": dlg_returning_rights_team_id,
                "dlg_returning_rights_team_code": team_code_map.get(dlg_returning_rights_team_id) if dlg_returning_rights_team_id else None,
                "dlg_team_id": dlg_team_id,
                "dlg_team_code": team_code_map.get(dlg_team_id) if dlg_team_id else None,
                "agency_id": to_int(p.get("agency_id")),
                "agent_id": to_int(p.get("agent_id")),
                "school_id": to_int(p.get("school_id")),
                "draft_year": to_int(p.get("draft_year")),
                "draft_round": to_int(p.get("draft_round")),
                "draft_pick": to_int(first_element(p.get("draft_pick"))),
                "years_of_service": to_int(p.get("years_of_service")),
                "service_years_json": json.dumps(p.get("player_service_years"), default=str) if p.get("player_service_years") else None,
                "created_at": p.get("create_date") or None,
                "updated_at": p.get("last_change_date") or None,
                "record_changed_at": p.get("record_change_date") or None,
                "poison_pill_amt": to_int(p.get("poison_pill_amt")),
                "is_two_way": p.get("two_way_flg") or False,
                "is_flex": p.get("flex_flg") or False,
                "ingested_at": ingested_at,
            }
        people = list(people_seen.values())

        print(f"Found {len(agencies)} agencies")
        print(f"Found {len(agents)} agents")
        print(f"Found {len(people)} people")

        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                # Upsert in FK order: agencies → agents → people
                count = upsert(conn, "pcms.agencies", agencies, ["agency_id"])
                tables.append({"table": "pcms.agencies", "attempted": count, "success": True})

                count = upsert(conn, "pcms.agents", agents, ["agent_id"])
                tables.append({"table": "pcms.agents", "attempted": count, "success": True})

                count = upsert(conn, "pcms.people", people, ["person_id"])
                tables.append({"table": "pcms.people", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "pcms.agencies", "attempted": len(agencies), "success": True})
            tables.append({"table": "pcms.agents", "attempted": len(agents), "success": True})
            tables.append({"table": "pcms.people", "attempted": len(people), "success": True})

    except Exception as e:
        import traceback
        errors.append(f"{e}\n{traceback.format_exc()}")

    return {
        "dry_run": dry_run,
        "started_at": started_at,
        "finished_at": datetime.now().isoformat(),
        "tables": tables,
        "errors": errors,
    }

