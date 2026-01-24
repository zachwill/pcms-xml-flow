#!/usr/bin/env python3
"""Backfill newly-added v2 columns on pcms.endnotes.

This script is intentionally iterative / pre-prod friendly.
It promotes useful fields out of metadata_json/conditions_json and applies
light heuristics based on revised_note/original_note.

Usage:
  uv run scripts/backfill-endnotes-v2.py --dry-run
  uv run scripts/backfill-endnotes-v2.py --write

What it does (v1 of this backfill):
- status_lk: from metadata_json.status if present
- note_type/is_frozen_pick: detect "Frozen Pick Notice" style
- teams_mentioned: from metadata_json.team_codes_mentioned
- depends_on_endnotes: from conditions_json.depends_on_endnotes
- trade_summary/conveyance_text/protections_text/contingency_text/exercise_text: from metadata_json
- draft_years/draft_rounds/has_rollover: heuristic from original_note text
  (safe, but not perfect; intended as a starting point)
- trade_ids: seeds with trade_id when present

It does NOT attempt to solve protections outcomes or conveyance resolution.
"""

import argparse
import json
import os
import re
from typing import Any, Optional

import psycopg2
from psycopg2.extras import RealDictCursor

YEAR_RE = re.compile(r"\b(20[0-3]\d)\b")


def db_conn():
    url = os.environ.get("POSTGRES_URL")
    if not url:
        raise SystemExit("POSTGRES_URL is not set")
    return psycopg2.connect(url)


def as_dict(v: Any) -> dict:
    if v is None:
        return {}
    if isinstance(v, dict):
        return v
    if isinstance(v, str):
        try:
            return json.loads(v)
        except Exception:
            return {}
    return {}


def as_list(v: Any) -> list:
    if v is None:
        return []
    if isinstance(v, list):
        return v
    return []


def uniq_ints(xs: list[Any]) -> list[int]:
    out: list[int] = []
    seen: set[int] = set()
    for x in xs:
        try:
            i = int(x)
        except Exception:
            continue
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out


def detect_rollover(text: str) -> bool:
    t = text.lower()
    return any(
        k in t
        for k in [
            "if ",
            "unless",
            "if not conveyed",
            "if it does not convey",
            "then",
            "shall instead receive",
            "converts to",
        ]
    )


def draft_rounds_from_text(text: str) -> list[int]:
    t = text.lower()
    rounds: list[int] = []
    if "first round" in t or "1st round" in t:
        rounds.append(1)
    if "second round" in t or "2nd round" in t:
        rounds.append(2)
    return rounds


def _strip_trailing_parens(text: str) -> str:
    """Most original_note values end with a parenthetical blob containing trade metadata + date.

    Example:
      "Phoenix conveys ... 2029 second round draft pick. (Saric ... 2/9/2023)"

    For draft year extraction, we want the pre-paren portion.
    """
    if not text:
        return text
    i = text.find("(")
    if i == -1:
        return text
    return text[:i].strip()


def draft_years_from_text(text: str) -> list[int]:
    base = _strip_trailing_parens(text)
    return sorted({int(y) for y in YEAR_RE.findall(base)})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    dry_run = args.dry_run or not args.write

    with db_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                select
                  endnote_id,
                  trade_id,
                  original_note,
                  revised_note,
                  metadata_json,
                  conditions_json
                from pcms.endnotes
                order by endnote_id
                """
            )
            rows = list(cur.fetchall())

            updates = []
            for r in rows:
                meta = as_dict(r.get("metadata_json"))
                cond = as_dict(r.get("conditions_json"))

                revised = r.get("revised_note") or ""
                original = r.get("original_note") or ""

                note_type = None
                is_frozen_pick = False
                if "frozen pick notice" in revised.lower() or "frozen pick" in revised.lower():
                    note_type = "FROZEN_PICK_NOTICE"
                    is_frozen_pick = True
                else:
                    note_type = "PICK_CONVEYANCE"

                status_lk = meta.get("status")

                teams_mentioned = meta.get("team_codes_mentioned") or []

                depends = cond.get("depends_on_endnotes") or meta.get("referenced_endnotes") or []

                trade_summary = meta.get("trade_summary")
                conveyance_text = meta.get("conveyance")
                protections_text = meta.get("protections")
                contingency_text = meta.get("contingency")
                exercise_text = meta.get("exercise")

                # draft_years: prefer parser output, but filter out trade-date years by re-deriving
                # from original_note without the trailing parenthetical trade/date blob.
                years = meta.get("draft_years_mentioned")
                if not years:
                    years = draft_years_from_text(original)
                else:
                    # still strip paren-derived noise if present
                    years = draft_years_from_text(original) or years
                rounds = draft_rounds_from_text(original)

                has_rollover = detect_rollover(original)

                trade_ids = []
                if r.get("trade_id") is not None:
                    trade_ids = [int(r["trade_id"])]

                updates.append(
                    (
                        note_type,
                        status_lk,
                        is_frozen_pick,
                        teams_mentioned,
                        trade_ids,
                        uniq_ints(depends),
                        trade_summary,
                        conveyance_text,
                        protections_text,
                        contingency_text,
                        exercise_text,
                        years,
                        rounds,
                        (min(years) if years else None),
                        (max(years) if years else None),
                        has_rollover,
                        r["endnote_id"],
                    )
                )

            if dry_run:
                # summary
                frozen = sum(1 for u in updates if u[2])
                with_years = sum(1 for u in updates if u[11])
                with_rounds = sum(1 for u in updates if u[12])
                with_depends = sum(1 for u in updates if u[5])
                print(f"Would update {len(updates)} rows")
                print(f"  frozen_pick_notice: {frozen}")
                print(f"  has draft_years: {with_years}")
                print(f"  has draft_rounds: {with_rounds}")
                print(f"  has depends_on_endnotes: {with_depends}")
                return

            cur.executemany(
                """
                update pcms.endnotes
                set
                  note_type = %s,
                  status_lk = %s,
                  is_frozen_pick = %s,
                  teams_mentioned = %s::text[],
                  trade_ids = %s::int[],
                  depends_on_endnotes = %s::int[],
                  trade_summary = %s,
                  conveyance_text = %s,
                  protections_text = %s,
                  contingency_text = %s,
                  exercise_text = %s,
                  draft_years = %s::int[],
                  draft_rounds = %s::int[],
                  draft_year_start = %s,
                  draft_year_end = %s,
                  has_rollover = %s,
                  updated_at = now()
                where endnote_id = %s
                """,
                updates,
            )
            conn.commit()
            print(f"Updated {len(updates)} pcms.endnotes rows")


if __name__ == "__main__":
    main()
