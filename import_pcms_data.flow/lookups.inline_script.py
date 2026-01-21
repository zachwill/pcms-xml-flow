# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]"]
# ///
"""
Lookups Import

Normalizes 43 lookup sub-tables from lookups.json into pcms.lookups.

Each lookup type (e.g., lk_agencies, lk_contract_types) is transformed into
a row with lookup_type, lookup_code, description, and properties_json.

Upserts into:
- pcms.lookups
"""
import os
import json
from pathlib import Path
from datetime import datetime

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


# ─────────────────────────────────────────────────────────────────────────────
# Lookup Transformation
# ─────────────────────────────────────────────────────────────────────────────

# Fields that identify the lookup code (in priority order)
CODE_PATTERNS = ["_lk", "_id", "_code", "_cd"]

# Fields to exclude from code inference
EXCLUDE_CODE_FIELDS = {"record_status_lk", "league_lk", "apron_level_lk", "criteria_type_lk", "country_lk", "state_lk"}

# Fields to exclude from properties_json
EXCLUDE_PROPERTY_FIELDS = {
    "description", "short_description", "abbreviation", "name",
    "agency_name", "team_name", "school_name",  # used for description
    "team_code", "team_name_short",  # used for short_description
    "active_flg", "seqno",
    "create_date", "last_change_date", "record_change_date",
}

# Field mappings for description inference
DESCRIPTION_FIELDS = ["description", "name", "agency_name", "team_name", "school_name"]
SHORT_DESC_FIELDS = ["short_description", "abbreviation", "team_code", "team_name_short"]


def infer_code(record: dict, lookup_type: str) -> tuple[str | None, str | None]:
    """Find the primary key field and value for a lookup record."""
    # Try derived field name from lookup type (e.g., lk_contract_types -> contract_type_lk)
    base = lookup_type.removeprefix("lk_").rstrip("s")
    expected_key = f"{base}_lk"
    if expected_key in record and record[expected_key] not in (None, ""):
        return expected_key, str(record[expected_key])

    # Also try plural form
    plural_key = f"{lookup_type.removeprefix('lk_')}_lk"
    if plural_key in record and record[plural_key] not in (None, ""):
        return plural_key, str(record[plural_key])

    # Fallback: find first *_lk, *_id, *_code, or *_cd field
    for pattern in CODE_PATTERNS:
        for key, val in record.items():
            if key.endswith(pattern) and key not in EXCLUDE_CODE_FIELDS:
                if val not in (None, ""):
                    return key, str(val)

    return None, None


def infer_description(record: dict) -> tuple[str | None, str | None]:
    """Extract description and short_description from record."""
    description = None
    for f in DESCRIPTION_FIELDS:
        if f in record and record[f] is not None:
            description = str(record[f])
            break

    short_description = None
    for f in SHORT_DESC_FIELDS:
        if f in record and record[f] is not None:
            short_description = str(record[f])
            break

    return description, short_description


def transform_lookup(lookup_type: str, record: dict, ingested_at: str) -> dict | None:
    """Transform a single lookup record into normalized form."""
    if not isinstance(record, dict):
        return None

    code_key, lookup_code = infer_code(record, lookup_type)
    if not lookup_code:
        return None

    description, short_description = infer_description(record)

    # Build properties_json with remaining fields
    exclude = EXCLUDE_PROPERTY_FIELDS | {code_key} if code_key else EXCLUDE_PROPERTY_FIELDS
    properties = {k: v for k, v in record.items() if k not in exclude}

    return {
        "lookup_type": lookup_type,
        "lookup_code": lookup_code,
        "description": description,
        "short_description": short_description,
        "is_active": record.get("active_flg"),
        "seqno": record.get("seqno"),
        "properties_json": json.dumps(properties) if properties else None,
        "created_at": record.get("create_date"),
        "updated_at": record.get("last_change_date"),
        "record_changed_at": record.get("record_change_date"),
        "ingested_at": ingested_at,
    }


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

        # Read lookups.json (grouped by lookup type)
        with open(base_dir / "lookups.json") as f:
            lookup_groups = json.load(f)

        print(f"Found {len(lookup_groups)} lookup groups")

        all_rows = []
        for lookup_type, container in lookup_groups.items():
            # Each container is like { "lk_agency": [...] }
            if not isinstance(container, dict):
                continue

            for records in container.values():
                if not isinstance(records, list):
                    records = [records]

                for record in records:
                    row = transform_lookup(lookup_type, record, ingested_at)
                    if row:
                        all_rows.append(row)

        print(f"Transformed {len(all_rows)} lookup records")

        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                count = upsert(conn, "pcms.lookups", all_rows, ["lookup_type", "lookup_code"])
                tables.append({"table": "pcms.lookups", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "pcms.lookups", "attempted": len(all_rows), "success": True})

    except Exception as e:
        errors.append(str(e))

    return {
        "dry_run": dry_run,
        "started_at": started_at,
        "finished_at": datetime.now().isoformat(),
        "tables": tables,
        "errors": errors,
    }

