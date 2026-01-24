#!/usr/bin/env python3
"""Munge/normalize pcms.endnotes into something tool-usable.

This is intentionally a script (not a migration):
- it does data-dependent matching (heuristics + evidence scoring)
- it writes audit-friendly output

Planned steps (initial version):
1) Normalize original_note prefixes like "31) ...".
2) Attempt to match endnote_id -> trade_id using evidence from draft_assets_warehouse
   and draft_pick_trades.
3) Backfill trade_date from pcms.trades when trade_id is matched.
4) Write per-endnote match metadata to metadata_json.

Usage:
  uv run scripts/munge-endnotes.py --dry-run
  uv run scripts/munge-endnotes.py --write

Note: This script is conservative. It only auto-writes high-confidence matches
and leaves the rest for manual review.
"""

import argparse
import json
import os
import re
from dataclasses import dataclass
from typing import Any, Optional

import psycopg2
from psycopg2.extras import RealDictCursor


PREFIX_RE = re.compile(r"^\s*(\d{1,4})\)\s+")


@dataclass
class EndnoteMatch:
    endnote_id: int
    trade_id: Optional[int]
    confidence: float
    hits: int
    candidate_count: int
    chosen_trade_date: Optional[str]


def db_conn():
    url = os.environ.get("POSTGRES_URL")
    if not url:
        raise SystemExit("POSTGRES_URL is not set")
    return psycopg2.connect(url)


def normalize_original_note(original_note: Optional[str]) -> tuple[Optional[str], Optional[int]]:
    if not original_note:
        return original_note, None
    m = PREFIX_RE.match(original_note)
    if not m:
        return original_note, None
    endnote_id_in_text = int(m.group(1))
    cleaned = original_note[m.end() :]
    return cleaned, endnote_id_in_text


def fetch_trade_candidates(cur) -> list[dict[str, Any]]:
    """Return candidate trades per endnote_id (ranked), for audit + selection.

    Evidence source:
      pcms.draft_assets_warehouse provides (endnote_id, draft_year, draft_round, team_code)
      pcms.draft_pick_trades provides (trade_id, trade_date, from/to team_code, year/round)

    Output: one row per (endnote_id, trade_id) with a "hits" score.
    """

    cur.execute(
        """
        with evidence as (
          select
            da.primary_endnote_id as endnote_id,
            da.draft_year,
            da.draft_round,
            da.team_code
          from pcms.draft_assets_warehouse da
          where da.primary_endnote_id is not null
            and da.has_endnote_match
        ), candidates as (
          select
            e.endnote_id,
            dpt.trade_id,
            dpt.trade_date,
            count(*) as hits
          from evidence e
          join pcms.draft_pick_trades dpt
            on dpt.draft_year = e.draft_year
           and dpt.draft_round = e.draft_round
           and (dpt.from_team_code = e.team_code or dpt.to_team_code = e.team_code)
          group by 1,2,3
        ), ranked as (
          select
            c.*,
            count(*) over (partition by endnote_id) as candidate_count,
            row_number() over (
              partition by endnote_id
              order by hits desc, trade_date desc, trade_id desc
            ) as rnk
          from candidates c
        )
        select
          endnote_id,
          trade_id,
          trade_date,
          hits,
          candidate_count,
          rnk
        from ranked
        order by endnote_id, rnk;
        """
    )
    return list(cur.fetchall())


def decide_confidence(hits: int, candidate_count: int) -> float:
    # Very simple heuristic for v1.
    if candidate_count == 0:
        return 0.0
    if candidate_count == 1:
        return 1.0
    # If there are many candidates, require strong evidence.
    if hits >= 8:
        return 0.9
    if hits >= 5:
        return 0.75
    return 0.5


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="Apply updates")
    ap.add_argument("--dry-run", action="store_true", help="No DB writes")
    ap.add_argument("--min-confidence", type=float, default=0.9)
    args = ap.parse_args()

    dry_run = args.dry_run or not args.write

    with db_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # 1) Normalize original_note prefix
            cur.execute("select endnote_id, original_note, metadata_json from pcms.endnotes order by endnote_id")
            rows = list(cur.fetchall())

            norm_updates = []
            for r in rows:
                cleaned, id_in_text = normalize_original_note(r.get("original_note"))
                if cleaned != r.get("original_note"):
                    meta = r.get("metadata_json") or {}
                    if isinstance(meta, str):
                        try:
                            meta = json.loads(meta)
                        except Exception:
                            meta = {"_metadata_parse_error": True, "raw": meta}
                    meta.setdefault("munge", {})
                    meta["munge"]["original_note_prefix_stripped"] = True
                    if id_in_text is not None:
                        meta["munge"]["original_note_prefix_id"] = id_in_text
                    norm_updates.append((cleaned, json.dumps(meta), r["endnote_id"]))

            # 2) Trade matching candidates (full candidate set)
            cand_rows = fetch_trade_candidates(cur)

            # group by endnote
            by_endnote: dict[int, list[dict[str, Any]]] = {}
            for r in cand_rows:
                by_endnote.setdefault(int(r["endnote_id"]), []).append(r)

            # decide: trade_ids[] always gets candidates (ranked), trade_id only if unambiguous/dominant
            auto_scalar: list[EndnoteMatch] = []
            trade_ids_updates: list[tuple[list[int], str, int]] = []  # (trade_ids, metadata_json, endnote_id)

            for endnote_id, cands in by_endnote.items():
                # cands are already ordered by rnk
                top = cands[0]
                candidate_count = int(top["candidate_count"])
                top_hits = int(top["hits"])
                second_hits = int(cands[1]["hits"]) if len(cands) > 1 else 0

                # build candidate list for metadata
                cand_for_meta = [
                    {
                        "trade_id": int(c["trade_id"]),
                        "trade_date": c["trade_date"].isoformat() if c.get("trade_date") else None,
                        "hits": int(c["hits"]),
                        "rank": int(c["rnk"]),
                    }
                    for c in cands[:10]
                ]

                # choose trade_ids: include top-k where hits are non-trivial
                # (v1: include all candidates with hits >= 2, plus always include the top candidate)
                tids: list[int] = []
                for c in cands:
                    tid = int(c["trade_id"])
                    hits = int(c["hits"])
                    if c["rnk"] == 1 or hits >= 2:
                        if tid not in tids:
                            tids.append(tid)

                # determine scalar trade_id confidence
                conf = decide_confidence(top_hits, candidate_count)
                dominant = candidate_count == 1 or (top_hits >= 2 * max(second_hits, 1) and top_hits >= 4)

                # load existing metadata
                cur.execute(
                    "select metadata_json, trade_id, trade_ids from pcms.endnotes where endnote_id = %s",
                    (endnote_id,),
                )
                existing = cur.fetchone()
                meta = existing["metadata_json"] or {}
                if isinstance(meta, str):
                    try:
                        meta = json.loads(meta)
                    except Exception:
                        meta = {"_metadata_parse_error": True, "raw": meta}

                meta.setdefault("munge", {})
                meta["munge"]["trade_candidates"] = cand_for_meta
                meta["munge"]["trade_ids_rule"] = "top candidate + any candidates with hits>=2 (max 10 in metadata)"

                # scalar match decision
                chosen_trade_id: Optional[int] = None
                if dominant and conf >= args.min_confidence:
                    chosen_trade_id = int(top["trade_id"])
                    meta["munge"]["matched_trade_id"] = chosen_trade_id
                    meta["munge"]["matched_trade_confidence"] = conf
                    meta["munge"]["matched_trade_hits"] = top_hits
                    meta["munge"]["matched_trade_candidate_count"] = candidate_count
                    meta["munge"]["matched_trade_method"] = "draft_assets_warehouse + draft_pick_trades evidence (dominant)"

                    auto_scalar.append(
                        EndnoteMatch(
                            endnote_id=endnote_id,
                            trade_id=chosen_trade_id,
                            confidence=conf,
                            hits=top_hits,
                            candidate_count=candidate_count,
                            chosen_trade_date=top["trade_date"].isoformat() if top.get("trade_date") else None,
                        )
                    )
                else:
                    meta["munge"]["matched_trade_method"] = "no scalar match (ambiguous)"

                trade_ids_updates.append((tids, json.dumps(meta), endnote_id))

            print(f"Normalize original_note: {len(norm_updates)} rows would change")
            print(f"Endnotes with any trade candidates: {len(by_endnote)}")
            print(f"Scalar trade_id auto-matches (confidence >= {args.min_confidence} + dominant): {len(auto_scalar)}")
            print(f"trade_ids[] updates (candidate lists): {len(trade_ids_updates)}")

            for m in auto_scalar[:10]:
                print(
                    f"  endnote_id={m.endnote_id} -> trade_id={m.trade_id} "
                    f"(conf={m.confidence}, hits={m.hits}, candidates={m.candidate_count}, trade_date={m.chosen_trade_date})"
                )

            if dry_run:
                print("[DRY RUN] No updates applied")
                return

            # Apply normalization updates
            if norm_updates:
                cur.executemany(
                    """
                    update pcms.endnotes
                    set original_note = %s,
                        metadata_json = %s::jsonb,
                        updated_at = now()
                    where endnote_id = %s
                    """,
                    norm_updates,
                )

            # Apply trade_ids updates + metadata
            if trade_ids_updates:
                cur.executemany(
                    """
                    update pcms.endnotes
                    set trade_ids = %s::int[],
                        metadata_json = %s::jsonb,
                        updated_at = now()
                    where endnote_id = %s
                    """,
                    trade_ids_updates,
                )

            # Apply scalar trade_id updates (only fill if null)
            scalar_updates = []
            for m in auto_scalar:
                scalar_updates.append((m.trade_id, m.endnote_id))

            if scalar_updates:
                cur.executemany(
                    """
                    update pcms.endnotes
                    set trade_id = %s,
                        updated_at = now()
                    where endnote_id = %s
                      and trade_id is null
                    """,
                    scalar_updates,
                )

            conn.commit()
            print(
                f"Applied: normalized_original_note={len(norm_updates)}, "
                f"trade_ids_updates={len(trade_ids_updates)}, scalar_trade_id_updates={len(scalar_updates)}"
            )


if __name__ == "__main__":
    main()
