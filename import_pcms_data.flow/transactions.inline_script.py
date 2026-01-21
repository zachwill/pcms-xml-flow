# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]"]
# ///
"""
Transactions Import

Imports trades, transactions, ledger entries, waiver amounts, and team exceptions.

Order (FK-safe): 
  trades → trade_teams → trade_team_details → trade_groups
  → transactions → ledger_entries → transaction_waiver_amounts
  → team_exceptions → team_exception_usage

Upserts into:
- pcms.trades
- pcms.trade_teams
- pcms.trade_team_details
- pcms.trade_groups
- pcms.transactions
- pcms.ledger_entries
- pcms.transaction_waiver_amounts
- pcms.team_exceptions
- pcms.team_exception_usage
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


def to_int(val) -> int | None:
    """Convert to int or None."""
    if val is None or val == "":
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


def as_list(val) -> list:
    """Ensure value is a list."""
    if val is None:
        return []
    if isinstance(val, list):
        return val
    return [val]


def normalize_version_number(val) -> int | None:
    """
    Convert version_number to int.
    PCMS sometimes represents version_number as a decimal like 1.01 -> 101
    """
    if val is None or val == "":
        return None
    try:
        n = float(val)
        if not n or n != n:  # NaN check
            return None
        # If it's already an integer, return as-is
        if n == int(n):
            return int(n)
        # Otherwise, multiply by 100 (1.01 -> 101)
        return round(n * 100)
    except (ValueError, TypeError):
        return None


def to_bool(val) -> bool | None:
    """Convert to bool or None."""
    if val is None or val == "":
        return None
    if isinstance(val, bool):
        return val
    if val in (0, "0", "false", "False"):
        return False
    if val in (1, "1", "true", "True"):
        return True
    return None


def unwrap_single_array(val):
    """If val is a single-element array, return that element; else return val."""
    if val is None:
        return None
    if isinstance(val, list):
        return val[0] if len(val) > 0 else None
    return val


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

        # Load lookups for team code mapping
        with open(base_dir / "lookups.json") as f:
            lookups = json.load(f)

        teams_raw = lookups.get("lk_teams", {}).get("lk_team", [])
        team_code_map = {
            t["team_id"]: t.get("team_code")
            for t in teams_raw
            if t.get("team_id") and t.get("team_code")
        }

        # Load data files
        with open(base_dir / "trades.json") as f:
            trades_raw = json.load(f)

        with open(base_dir / "transactions.json") as f:
            transactions_raw = json.load(f)

        with open(base_dir / "ledger.json") as f:
            ledger_raw = json.load(f)

        waiver_path = base_dir / "transaction_waiver_amounts.json"
        waiver_raw = []
        if waiver_path.exists():
            with open(waiver_path) as f:
                waiver_raw = json.load(f)

        with open(base_dir / "team_exceptions.json") as f:
            team_exceptions_data = json.load(f)

        print(f"Found trades={len(trades_raw)}, transactions={len(transactions_raw)}, "
              f"ledger={len(ledger_raw)}, waiver_amounts={len(waiver_raw)}")

        # ─────────────────────────────────────────────────────────────────────
        # Trades / Trade Teams / Trade Team Details / Trade Groups
        # ─────────────────────────────────────────────────────────────────────
        trades_seen = {}
        trade_teams_seen = {}
        trade_details_seen = {}
        trade_groups_seen = {}

        for t in trades_raw:
            trade_id = to_int(t.get("trade_id"))
            if trade_id is None:
                continue

            trades_seen[trade_id] = {
                "trade_id": trade_id,
                "trade_date": t.get("trade_date"),
                "trade_finalized_date": t.get("trade_finalized_date"),
                "league_lk": t.get("league_lk"),
                "record_status_lk": t.get("record_status_lk"),
                "trade_comments": t.get("trade_comments"),
                "created_at": t.get("create_date"),
                "updated_at": t.get("last_change_date"),
                "record_changed_at": t.get("record_change_date"),
                "ingested_at": ingested_at,
            }

            # Trade teams nested under trade
            trade_teams_data = t.get("trade_teams", {})
            trade_team_list = as_list(trade_teams_data.get("trade_team"))

            for tt in trade_team_list:
                team_id = to_int(tt.get("team_id"))
                if team_id is None:
                    continue

                trade_team_id = f"{trade_id}_{team_id}"

                trade_teams_seen[trade_team_id] = {
                    "trade_team_id": trade_team_id,
                    "trade_id": trade_id,
                    "team_id": team_id,
                    "team_code": team_code_map.get(team_id),
                    "team_salary_change": tt.get("team_salary_change"),
                    "total_cash_received": tt.get("total_cash_received"),
                    "total_cash_sent": tt.get("total_cash_sent"),
                    "seqno": tt.get("seqno"),
                    "ingested_at": ingested_at,
                }

                # Trade team details
                details_data = tt.get("trade_team_details", {})
                details_list = as_list(details_data.get("trade_team_detail"))

                for d in details_list:
                    seqno = d.get("seqno")
                    if seqno is None:
                        continue

                    detail_id = f"{trade_id}_{team_id}_{seqno}"

                    trade_details_seen[detail_id] = {
                        "trade_team_detail_id": detail_id,
                        "trade_id": trade_id,
                        "team_id": team_id,
                        "team_code": team_code_map.get(team_id),
                        "seqno": seqno,
                        "group_number": d.get("group_number"),
                        "player_id": to_int(d.get("player_id")),
                        "contract_id": to_int(d.get("contract_id")),
                        "version_number": normalize_version_number(d.get("version_number")),
                        "post_version_number": normalize_version_number(d.get("post_version_number")),
                        "is_sent": d.get("sent_flg"),
                        "is_sign_and_trade": d.get("sign_and_trade_flg"),
                        "mts_value_override": d.get("mts_value_override"),
                        "is_trade_bonus": d.get("trade_bonus_flg"),
                        "is_no_trade": d.get("no_trade_flg"),
                        "is_player_consent": d.get("player_consent_flg"),
                        "is_poison_pill": d.get("poison_pill_flg"),
                        "is_incentive_bonus": d.get("incentive_bonus_flg"),
                        "cash_amount": d.get("cash_amount"),
                        "trade_entry_lk": d.get("trade_entry_lk"),
                        "free_agent_designation_lk": d.get("free_agent_designation_lk"),
                        "base_year_amount": d.get("base_year_amount"),
                        "is_base_year": d.get("base_year_flg"),
                        "draft_pick_year": d.get("draft_pick_year"),
                        "draft_pick_round": d.get("draft_pick_round"),
                        "is_draft_pick_future": d.get("draft_pick_future_flg"),
                        "is_draft_pick_swap": d.get("draft_pick_swap_flg"),
                        "draft_pick_conditional_lk": d.get("draft_pick_conditional_lk"),
                        "is_draft_year_plus_two": d.get("draft_year_plus_two_flg"),
                        "ingested_at": ingested_at,
                    }

                # Trade groups (nested under trade_team, fall back to trade-level)
                groups_from_team = as_list(tt.get("trade_groups", {}).get("trade_group"))
                groups_from_trade = as_list(t.get("trade_groups", {}).get("trade_group"))
                groups_list = groups_from_team if groups_from_team else groups_from_trade

                for g in groups_list:
                    group_number = g.get("trade_group_number")
                    if group_number is None:
                        continue

                    group_team_id = to_int(g.get("team_id")) or team_id
                    group_id = f"{trade_id}_{group_team_id}_{group_number}"

                    trade_groups_seen[group_id] = {
                        "trade_group_id": group_id,
                        "trade_id": trade_id,
                        "team_id": group_team_id,
                        "team_code": team_code_map.get(group_team_id),
                        "trade_group_number": group_number,
                        "trade_group_comments": g.get("trade_group_comments"),
                        "acquired_team_exception_id": to_int(g.get("acquired_team_exception_id")),
                        "generated_team_exception_id": to_int(g.get("generated_team_exception_id")),
                        "signed_method_lk": g.get("signed_method_lk"),
                        "ingested_at": ingested_at,
                    }

        trades = list(trades_seen.values())
        trade_teams = list(trade_teams_seen.values())
        trade_details = list(trade_details_seen.values())
        trade_groups = list(trade_groups_seen.values())

        print(f"Prepared: trades={len(trades)}, trade_teams={len(trade_teams)}, "
              f"trade_details={len(trade_details)}, trade_groups={len(trade_groups)}")

        # ─────────────────────────────────────────────────────────────────────
        # Transactions
        # ─────────────────────────────────────────────────────────────────────
        transactions_seen = {}

        for txn in transactions_raw:
            txn_id = to_int(txn.get("transaction_id"))
            if txn_id is None:
                continue

            from_team_id = to_int(txn.get("from_team_id"))
            to_team_id = to_int(txn.get("to_team_id"))
            rights_team_id = to_int(txn.get("rights_team_id"))
            sat_team_id = to_int(txn.get("sign_and_trade_team_id"))

            transactions_seen[txn_id] = {
                "transaction_id": txn_id,
                "player_id": to_int(txn.get("player_id")),
                "from_team_id": from_team_id,
                "from_team_code": team_code_map.get(from_team_id) if from_team_id else None,
                "to_team_id": to_team_id,
                "to_team_code": team_code_map.get(to_team_id) if to_team_id else None,
                "transaction_date": txn.get("transaction_date"),
                "trade_finalized_date": txn.get("trade_finalized_date"),
                "trade_id": to_int(txn.get("trade_id")),
                "transaction_type_lk": txn.get("transaction_type_lk"),
                "transaction_description_lk": txn.get("transaction_description_lk"),
                "record_status_lk": txn.get("record_status_lk"),
                "league_lk": txn.get("league_lk"),
                "seqno": txn.get("seqno"),
                "is_in_season": txn.get("in_season_flg"),
                "contract_id": to_int(txn.get("contract_id")),
                "original_contract_id": to_int(txn.get("original_contract_id")),
                "version_number": normalize_version_number(txn.get("version_number")),
                "contract_type_lk": txn.get("contract_type_lk"),
                "min_contract_lk": txn.get("min_contract_lk"),
                "signed_method_lk": txn.get("signed_method_lk"),
                "team_exception_id": to_int(txn.get("team_exception_id")),
                "rights_team_id": rights_team_id,
                "rights_team_code": team_code_map.get(rights_team_id) if rights_team_id else None,
                "waiver_clear_date": txn.get("waiver_clear_date"),
                "is_clear_player_rights": txn.get("clear_player_rights_flg"),
                "free_agent_status_lk": txn.get("free_agent_status_lk"),
                "free_agent_designation_lk": txn.get("free_agent_designation_lk"),
                "from_player_status_lk": txn.get("from_player_status_lk"),
                "to_player_status_lk": txn.get("to_player_status_lk"),
                "option_year": to_int(txn.get("option_year")),
                "adjustment_amount": txn.get("adjustment_amount"),
                "bonus_true_up_amount": txn.get("bonus_true_up_amount"),
                "draft_amount": txn.get("draft_amount"),
                "draft_pick": to_int(unwrap_single_array(txn.get("draft_pick"))),
                "draft_round": txn.get("draft_round"),
                "draft_year": to_int(txn.get("draft_year")),
                "free_agent_amount": txn.get("free_agent_amount"),
                "qoe_amount": txn.get("qoe_amount"),
                "tender_amount": txn.get("tender_amount"),
                "is_divorce": txn.get("divorce_flg"),
                "effective_salary_year": to_int(txn.get("effective_salary_year")),
                "is_initially_convertible_exception": txn.get("initially_convertible_exception_flg"),
                "is_sign_and_trade": txn.get("sign_and_trade_flg"),
                "sign_and_trade_team_id": sat_team_id,
                "sign_and_trade_team_code": team_code_map.get(sat_team_id) if sat_team_id else None,
                "sign_and_trade_link_transaction_id": to_int(txn.get("sign_and_trade_link_transaction_id")),
                "dlg_contract_id": to_int(txn.get("dlg_contract_id")),
                "dlg_experience_level_lk": txn.get("dlg_experience_level_lk"),
                "dlg_salary_level_lk": txn.get("dlg_salary_level_lk"),
                "comments": txn.get("comments"),
                "created_at": txn.get("create_date"),
                "updated_at": txn.get("last_change_date"),
                "record_changed_at": txn.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        transactions = list(transactions_seen.values())
        print(f"Prepared: transactions={len(transactions)}")

        # ─────────────────────────────────────────────────────────────────────
        # Ledger Entries
        # ─────────────────────────────────────────────────────────────────────
        ledger_seen = {}

        for le in ledger_raw:
            entry_id = to_int(le.get("transaction_ledger_entry_id"))
            team_id = to_int(le.get("team_id"))
            if entry_id is None or team_id is None:
                continue

            ledger_seen[entry_id] = {
                "transaction_ledger_entry_id": entry_id,
                "transaction_id": to_int(le.get("transaction_id")),
                "team_id": team_id,
                "team_code": team_code_map.get(team_id),
                "player_id": to_int(le.get("player_id")),
                "contract_id": to_int(le.get("contract_id")),
                "dlg_contract_id": to_int(le.get("dlg_contract_id")),
                "salary_year": to_int(le.get("salary_year")),
                "ledger_date": le.get("ledger_date"),
                "league_lk": le.get("league_lk"),
                "transaction_type_lk": le.get("transaction_type_lk"),
                "transaction_description_lk": le.get("transaction_description_lk"),
                "version_number": normalize_version_number(le.get("version_number")),
                "seqno": le.get("seqno"),
                "sub_seqno": le.get("sub_seqno"),
                "team_ledger_seqno": le.get("team_ledger_seqno"),
                "is_leaving_team": le.get("leaving_team_flg"),
                "has_no_budget_impact": le.get("no_budget_impact_flg"),
                "mts_amount": le.get("mts_amount"),
                "mts_change": le.get("mts_change"),
                "mts_value": le.get("mts_value"),
                "cap_amount": le.get("cap_amount"),
                "cap_change": le.get("cap_change"),
                "cap_value": le.get("cap_value"),
                "tax_amount": le.get("tax_amount"),
                "tax_change": le.get("tax_change"),
                "tax_value": le.get("tax_value"),
                "apron_amount": le.get("apron_amount"),
                "apron_change": le.get("apron_change"),
                "apron_value": le.get("apron_value"),
                "trade_bonus_amount": le.get("trade_bonus_amount"),
                "ingested_at": ingested_at,
            }

        ledger = list(ledger_seen.values())
        print(f"Prepared: ledger_entries={len(ledger)}")

        # ─────────────────────────────────────────────────────────────────────
        # Transaction Waiver Amounts
        # ─────────────────────────────────────────────────────────────────────
        waiver_seen = {}

        for wa in waiver_raw:
            wa_id = to_int(wa.get("transaction_waiver_amount_id"))
            if wa_id is None:
                continue

            waiver_seen[wa_id] = {
                "transaction_waiver_amount_id": wa_id,
                "transaction_id": to_int(wa.get("transaction_id")),
                "player_id": to_int(wa.get("player_id")),
                "team_id": to_int(wa.get("team_id")),
                "contract_id": to_int(wa.get("contract_id")),
                "salary_year": to_int(wa.get("salary_year")),
                "version_number": normalize_version_number(wa.get("version_number")),
                "waive_date": wa.get("waive_date"),
                "cap_value": wa.get("cap_value"),
                "cap_change_value": wa.get("cap_change_value"),
                "is_cap_calculated": to_bool(wa.get("cap_calculated")),
                "tax_value": wa.get("tax_value"),
                "tax_change_value": wa.get("tax_change_value"),
                "is_tax_calculated": to_bool(wa.get("tax_calculated")),
                "apron_value": wa.get("apron_value"),
                "apron_change_value": wa.get("apron_change_value"),
                "is_apron_calculated": to_bool(wa.get("apron_calculated")),
                "mts_value": wa.get("mts_value"),
                "mts_change_value": wa.get("mts_change_value"),
                "two_way_salary": wa.get("two_way_salary"),
                "two_way_nba_salary": wa.get("two_way_nba_salary"),
                "two_way_dlg_salary": wa.get("two_way_dlg_salary"),
                "option_decision_lk": wa.get("option_decision_lk"),
                "wnba_contract_id": to_int(wa.get("wnba_contract_id")),
                "wnba_version_number": wa.get("wnba_version_number"),
                "ingested_at": ingested_at,
            }

        waiver = list(waiver_seen.values())
        print(f"Prepared: transaction_waiver_amounts={len(waiver)}")

        # ─────────────────────────────────────────────────────────────────────
        # Team Exceptions / Exception Usage
        # ─────────────────────────────────────────────────────────────────────
        exceptions_seen = {}
        usage_seen = {}

        exception_teams = as_list(team_exceptions_data.get("exception_team"))

        for et in exception_teams:
            team_id = to_int(et.get("team_id"))

            # NOTE: this extract uses hyphenated keys
            team_exceptions = as_list(et.get("team-exceptions", {}).get("team-exception"))

            for te in team_exceptions:
                exc_id = to_int(te.get("team_exception_id"))
                if exc_id is None:
                    continue

                exceptions_seen[exc_id] = {
                    "team_exception_id": exc_id,
                    "team_id": team_id,
                    "team_code": team_code_map.get(team_id) if team_id else None,
                    "salary_year": to_int(te.get("team_exception_year")),
                    "exception_type_lk": te.get("exception_type_lk"),
                    "effective_date": te.get("effective_date"),
                    "expiration_date": te.get("expiration_date"),
                    "original_amount": te.get("original_amount"),
                    "remaining_amount": te.get("remaining_amount"),
                    "proration_rate": te.get("proration_rate"),
                    "is_initially_convertible": te.get("initially_convertible_flg"),
                    "trade_exception_player_id": to_int(te.get("trade_exception_player_id")),
                    "trade_id": to_int(te.get("trade_id")),
                    "record_status_lk": te.get("record_status_lk"),
                    "created_at": te.get("create_date"),
                    "updated_at": te.get("last_change_date"),
                    "record_changed_at": te.get("record_change_date"),
                    "ingested_at": ingested_at,
                }

                # Exception usage/details
                details = as_list(te.get("exception_details", {}).get("exception_detail"))
                for ed in details:
                    detail_id = to_int(ed.get("team_exception_detail_id"))
                    if detail_id is None:
                        continue

                    usage_seen[detail_id] = {
                        "team_exception_detail_id": detail_id,
                        "team_exception_id": exc_id,
                        "seqno": ed.get("seqno"),
                        "effective_date": ed.get("effective_date"),
                        "exception_action_lk": ed.get("exception_action_lk"),
                        "transaction_type_lk": ed.get("transaction_type_lk"),
                        "transaction_id": to_int(ed.get("transaction_id")),
                        "player_id": to_int(ed.get("player_id")),
                        "contract_id": to_int(ed.get("contract_id")),
                        "change_amount": ed.get("change_amount"),
                        "remaining_exception_amount": ed.get("remaining_exception_amount"),
                        "proration_rate": ed.get("proration_rate"),
                        "prorate_days": ed.get("prorate_days"),
                        "is_convert_exception": ed.get("convert_exception_flg"),
                        "manual_action_text": ed.get("manual_action_text"),
                        "created_at": ed.get("create_date"),
                        "updated_at": ed.get("last_change_date"),
                        "record_changed_at": ed.get("record_change_date"),
                        "ingested_at": ingested_at,
                    }

        exceptions = list(exceptions_seen.values())
        usage = list(usage_seen.values())
        print(f"Prepared: team_exceptions={len(exceptions)}, team_exception_usage={len(usage)}")

        # ─────────────────────────────────────────────────────────────────────
        # Upsert
        # ─────────────────────────────────────────────────────────────────────
        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                # Trade data
                count = upsert(conn, "pcms.trades", trades, ["trade_id"])
                tables.append({"table": "pcms.trades", "attempted": count, "success": True})

                count = upsert(conn, "pcms.trade_teams", trade_teams, ["trade_team_id"])
                tables.append({"table": "pcms.trade_teams", "attempted": count, "success": True})

                count = upsert(conn, "pcms.trade_team_details", trade_details, ["trade_team_detail_id"])
                tables.append({"table": "pcms.trade_team_details", "attempted": count, "success": True})

                count = upsert(conn, "pcms.trade_groups", trade_groups, ["trade_group_id"])
                tables.append({"table": "pcms.trade_groups", "attempted": count, "success": True})

                # Transactions
                count = upsert(conn, "pcms.transactions", transactions, ["transaction_id"])
                tables.append({"table": "pcms.transactions", "attempted": count, "success": True})

                # Ledger
                count = upsert(conn, "pcms.ledger_entries", ledger, ["transaction_ledger_entry_id"])
                tables.append({"table": "pcms.ledger_entries", "attempted": count, "success": True})

                # Waiver amounts
                count = upsert(conn, "pcms.transaction_waiver_amounts", waiver, ["transaction_waiver_amount_id"])
                tables.append({"table": "pcms.transaction_waiver_amounts", "attempted": count, "success": True})

                # Team exceptions
                count = upsert(conn, "pcms.team_exceptions", exceptions, ["team_exception_id"])
                tables.append({"table": "pcms.team_exceptions", "attempted": count, "success": True})

                count = upsert(conn, "pcms.team_exception_usage", usage, ["team_exception_detail_id"])
                tables.append({"table": "pcms.team_exception_usage", "attempted": count, "success": True})
            finally:
                conn.close()
        else:
            tables.append({"table": "pcms.trades", "attempted": len(trades), "success": True})
            tables.append({"table": "pcms.trade_teams", "attempted": len(trade_teams), "success": True})
            tables.append({"table": "pcms.trade_team_details", "attempted": len(trade_details), "success": True})
            tables.append({"table": "pcms.trade_groups", "attempted": len(trade_groups), "success": True})
            tables.append({"table": "pcms.transactions", "attempted": len(transactions), "success": True})
            tables.append({"table": "pcms.ledger_entries", "attempted": len(ledger), "success": True})
            tables.append({"table": "pcms.transaction_waiver_amounts", "attempted": len(waiver), "success": True})
            tables.append({"table": "pcms.team_exceptions", "attempted": len(exceptions), "success": True})
            tables.append({"table": "pcms.team_exception_usage", "attempted": len(usage), "success": True})

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

