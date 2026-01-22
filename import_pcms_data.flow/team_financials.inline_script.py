# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "typing-extensions"]
# ///
"""
Team Financials Import

Consolidates:
- Team budgets, tax summaries, tax team status
- Waiver priority & ranks
- Team transactions
- Two-way daily statuses, contract utility, game utility, team capacity

Upserts into:
- pcms.team_budget_snapshots (TRUNCATE + INSERT due to nullable composite key)
- pcms.team_tax_summary_snapshots
- pcms.tax_team_status
- pcms.waiver_priority
- pcms.waiver_priority_ranks
- pcms.team_transactions
- pcms.two_way_daily_statuses
- pcms.two_way_contract_utility
- pcms.two_way_game_utility
- pcms.team_two_way_capacity
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

    if update_cols:
        updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])
        sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO UPDATE SET {updates}"
    else:
        sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO NOTHING"

    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(r[c] for c in cols) for r in rows])
    conn.commit()
    return len(rows)


def truncate_insert(conn, table: str, rows: list[dict]) -> int:
    """Truncate table and insert rows (for tables with nullable composite keys)."""
    if not rows:
        with conn.cursor() as cur:
            cur.execute(f"TRUNCATE TABLE {table}")
        conn.commit()
        return 0

    cols = list(rows[0].keys())
    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)

    with conn.cursor() as cur:
        cur.execute(f"TRUNCATE TABLE {table}")
        sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders})"
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
        n = float(val)
        return int(n) if n == n else None  # NaN check
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
    s = str(val).lower()
    if s in ("true", "t", "1", "y", "yes"):
        return True
    if s in ("false", "f", "0", "n", "no"):
        return False
    return None


def to_date(val) -> str | None:
    """Extract date only (YYYY-MM-DD) from datetime string."""
    if val is None or val == "":
        return None
    s = str(val)
    return s[:10] if len(s) >= 10 else None


def as_list(val) -> list:
    """Ensure value is a list."""
    if val is None or val == "":
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
        if n != n:  # NaN check
            return None
        if n == int(n):
            return int(n)
        return round(n * 100)
    except (ValueError, TypeError):
        return None


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
            t["team_id"]: t.get("team_name_short") or t.get("team_code")
            for t in teams_raw
            if t.get("team_id") and (t.get("team_name_short") or t.get("team_code"))
        }

        def load_json(filename: str):
            path = base_dir / filename
            if path.exists():
                with open(path) as f:
                    return json.load(f)
            return None

        # Load all JSON files
        team_budgets = load_json("team_budgets.json") or {}
        waiver_priority = load_json("waiver_priority.json") or []
        tax_teams = load_json("tax_teams.json") or []
        team_transactions = load_json("team_transactions.json") or []
        two_way = load_json("two_way.json") or {}
        two_way_utility = load_json("two_way_utility.json") or {}

        # ─────────────────────────────────────────────────────────────────────
        # team_budget_snapshots (from team_budgets.json -> budget_teams)
        # ─────────────────────────────────────────────────────────────────────
        budget_teams = as_list(team_budgets.get("budget_teams", {}).get("budget_team"))
        budget_snapshot_seen = {}

        for bt in budget_teams:
            team_id = to_int(bt.get("team_id"))
            if team_id is None:
                continue

            budget_entries = as_list(bt.get("budget-entries", {}).get("budget-entry"))
            for entry in budget_entries:
                amounts = as_list(entry.get("budget_amounts_per_year", {}).get("budget_amount"))
                for amount in amounts:
                    salary_year = amount.get("year")
                    transaction_id = entry.get("transaction_id")
                    budget_group_lk = entry.get("budget_group_lk")
                    player_id = entry.get("player_id")
                    contract_id = entry.get("contract_id")
                    version_number = normalize_version_number(entry.get("version_number"))

                    # Dedupe key (nullable composite)
                    key = (team_id, salary_year, transaction_id or "∅", budget_group_lk or "∅",
                           player_id or "∅", contract_id or "∅", version_number or "∅")

                    budget_snapshot_seen[key] = {
                        "team_id": team_id,
                        "team_code": team_code_map.get(team_id),
                        "salary_year": salary_year,
                        "player_id": player_id,
                        "contract_id": contract_id,
                        "transaction_id": transaction_id,
                        "transaction_type_lk": entry.get("transaction_type_lk"),
                        "transaction_description_lk": entry.get("transaction_description_lk"),
                        "budget_group_lk": budget_group_lk,
                        "contract_type_lk": entry.get("contract_type_lk"),
                        "free_agent_designation_lk": entry.get("free_agent_designation_lk"),
                        "free_agent_status_lk": entry.get("free_agent_status_lk"),
                        "signing_method_lk": entry.get("signed_method_lk"),
                        "overall_contract_bonus_type_lk": entry.get("overall_contract_bonus_type_lk"),
                        "overall_protection_coverage_lk": entry.get("overall_protection_coverage_lk"),
                        "max_contract_lk": entry.get("max_contract_lk"),
                        "years_of_service": entry.get("year_of_service"),
                        "ledger_date": entry.get("ledger_date"),
                        "signing_date": entry.get("signing_date"),
                        "version_number": version_number,
                        "cap_amount": amount.get("cap_amount"),
                        "tax_amount": amount.get("tax_amount"),
                        "mts_amount": amount.get("mts_amount"),
                        "apron_amount": amount.get("apron_amount"),
                        "is_fa_amount": to_bool(amount.get("fa_amount_flg")),
                        "option_lk": amount.get("option_lk"),
                        "option_decision_lk": amount.get("option_decision_lk"),
                        "ingested_at": ingested_at,
                    }

        budget_snapshots = list(budget_snapshot_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # team_tax_summary_snapshots (from team_budgets.json -> tax_teams)
        # ─────────────────────────────────────────────────────────────────────
        tax_summary_teams = as_list(team_budgets.get("tax_teams", {}).get("tax_team"))
        tax_summary_seen = {}

        for t in tax_summary_teams:
            team_id = to_int(t.get("team_id"))
            salary_year = to_int(t.get("salary_year"))
            if team_id is None or salary_year is None:
                continue

            key = (team_id, salary_year)
            tax_summary_seen[key] = {
                "team_id": team_id,
                "team_code": team_code_map.get(team_id),
                "salary_year": salary_year,
                "is_taxpayer": to_bool(t.get("taxpayer_flg")),
                "is_repeater_taxpayer": to_bool(t.get("taxpayer_repeater_rate_flg")),
                "is_subject_to_apron": to_bool(t.get("subject_to_apron_flg")),
                "subject_to_apron_reason_lk": t.get("subject_to_apron_reason_lk"),
                "apron_level_lk": t.get("apron_level_lk"),
                "apron1_transaction_id": t.get("apron1_transaction_id"),
                "apron2_transaction_id": t.get("apron2_transaction_id"),
                "record_changed_at": t.get("record_change_date"),
                "created_at": t.get("create_date"),
                "updated_at": t.get("last_change_date"),
                "ingested_at": ingested_at,
            }

        tax_summaries = list(tax_summary_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # waiver_priority & waiver_priority_ranks (from waiver_priority.json)
        # ─────────────────────────────────────────────────────────────────────
        # Handle both array and object with nested waiver_priority key
        waiver_list = waiver_priority if isinstance(waiver_priority, list) else as_list(waiver_priority.get("waiver_priority"))

        waiver_priority_seen = {}
        waiver_rank_seen = {}

        for wp in waiver_list:
            waiver_priority_id = to_int(wp.get("waiver_priority_id"))
            if waiver_priority_id is None:
                continue

            waiver_priority_seen[waiver_priority_id] = {
                "waiver_priority_id": waiver_priority_id,
                "priority_date": wp.get("priority_date"),
                "seqno": to_int(wp.get("seqno")),
                "status_lk": wp.get("record_status_lk") or wp.get("status_lk"),
                "comments": wp.get("comments"),
                "created_at": wp.get("create_date"),
                "updated_at": wp.get("last_change_date"),
                "record_changed_at": wp.get("record_change_date"),
                "ingested_at": ingested_at,
            }

            ranks = as_list(wp.get("waiver_priority_ranks", {}).get("waiver_priority_rank"))
            for r in ranks:
                rank_id = to_int(r.get("waiver_priority_detail_id") or r.get("waiver_priority_rank_id"))
                if rank_id is None:
                    continue

                team_id = to_int(r.get("team_id"))
                waiver_rank_seen[rank_id] = {
                    "waiver_priority_rank_id": rank_id,
                    "waiver_priority_id": waiver_priority_id,
                    "team_id": team_id,
                    "team_code": team_code_map.get(team_id) if team_id else None,
                    "priority_order": to_int(r.get("priority_order")),
                    "is_order_priority": to_bool(r.get("order_priority_flg")),
                    "exclusivity_status_lk": r.get("exclusivity_status_lk"),
                    "exclusivity_expiration_date": r.get("exclusivity_expiration_date"),
                    "status_lk": r.get("record_status_lk") or r.get("status_lk"),
                    "seqno": to_int(r.get("seqno")),
                    "comments": r.get("comments"),
                    "created_at": r.get("create_date"),
                    "updated_at": r.get("last_change_date"),
                    "record_changed_at": r.get("record_change_date"),
                    "ingested_at": ingested_at,
                }

        waiver_priorities = list(waiver_priority_seen.values())
        waiver_ranks = list(waiver_rank_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # tax_team_status (from tax_teams.json)
        # ─────────────────────────────────────────────────────────────────────
        tax_team_status_seen = {}

        for tt in tax_teams:
            team_id = to_int(tt.get("team_id"))
            salary_year = to_int(tt.get("salary_year"))
            if team_id is None or salary_year is None:
                continue

            key = (team_id, salary_year)
            tax_team_status_seen[key] = {
                "team_id": team_id,
                "team_code": team_code_map.get(team_id),
                "salary_year": salary_year,
                "is_taxpayer": to_bool(tt.get("taxpayer_flg")) or False,
                "is_repeater_taxpayer": to_bool(tt.get("taxpayer_repeater_rate_flg")) or False,
                "is_subject_to_apron": to_bool(tt.get("subject_to_apron_flg")) or False,
                "apron_level_lk": tt.get("apron_level_lk"),
                "subject_to_apron_reason_lk": tt.get("subject_to_apron_reason_lk"),
                "apron1_transaction_id": to_int(tt.get("apron1_transaction_id")),
                "apron2_transaction_id": to_int(tt.get("apron2_transaction_id")),
                "created_at": tt.get("create_date"),
                "updated_at": tt.get("last_change_date"),
                "record_changed_at": tt.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        tax_team_statuses = list(tax_team_status_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # team_transactions (from team_transactions.json)
        # ─────────────────────────────────────────────────────────────────────
        team_tx_seen = {}

        for t in team_transactions:
            tx_id = to_int(t.get("team_transaction_id"))
            if tx_id is None:
                continue

            team_id = to_int(t.get("team_id"))
            team_tx_seen[tx_id] = {
                "team_transaction_id": tx_id,
                "team_id": team_id,
                "team_code": team_code_map.get(team_id) if team_id else None,
                "team_transaction_type_lk": t.get("team_transaction_type_lk"),
                "team_ledger_seqno": to_int(t.get("team_ledger_seqno")),
                "transaction_date": t.get("transaction_date"),
                "cap_adjustment": to_int(t.get("cap_adjustment")),
                "cap_hold_adjustment": to_int(t.get("cap_hold_adjustment")),
                "tax_adjustment": to_int(t.get("tax_adjustment")),
                "tax_apron_adjustment": to_int(t.get("tax_apron_adjustment")),
                "mts_adjustment": to_int(t.get("mts_adjustment")),
                "protection_count_flg": to_bool(t.get("protection_count_flg")),
                "comments": t.get("comments"),
                "record_status_lk": t.get("record_status_lk"),
                "created_at": t.get("create_date"),
                "updated_at": t.get("last_change_date"),
                "record_changed_at": t.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        team_txs = list(team_tx_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # two_way_daily_statuses (from two_way.json -> daily_statuses)
        # ─────────────────────────────────────────────────────────────────────
        # Handle different JSON structures (hyphenated vs underscored keys)
        daily_statuses_container = two_way.get("daily_statuses") or {}
        statuses = as_list(
            daily_statuses_container.get("daily-status") or
            daily_statuses_container.get("daily_status") or
            (daily_statuses_container if isinstance(daily_statuses_container, list) else [])
        )

        daily_status_seen = {}

        for s in statuses:
            player_id = to_int(s.get("player_id"))
            status_date = to_date(s.get("status_date"))
            salary_year = to_int(s.get("season_year")) or (to_int(status_date[:4]) if status_date else None)
            status_lk = s.get("two_way_daily_status_lk")

            if player_id is None or not status_date or salary_year is None or not status_lk:
                continue

            status_team_id = to_int(s.get("team_id") or s.get("status_team_id"))
            contract_team_id = to_int(s.get("contract_team_id"))
            signing_team_id = to_int(s.get("signing_team_id"))

            key = (player_id, status_date)
            daily_status_seen[key] = {
                "player_id": player_id,
                "status_date": status_date,
                "salary_year": salary_year,
                "day_of_season": to_int(s.get("day_of_season")),
                "status_lk": status_lk,
                "status_team_id": status_team_id,
                "status_team_code": team_code_map.get(status_team_id) if status_team_id else None,
                "contract_id": to_int(s.get("contract_id")),
                "contract_team_id": contract_team_id,
                "contract_team_code": team_code_map.get(contract_team_id) if contract_team_id else None,
                "signing_team_id": signing_team_id,
                "signing_team_code": team_code_map.get(signing_team_id) if signing_team_id else None,
                "nba_service_days": to_int(s.get("nba_service_days")),
                "nba_service_limit": to_int(s.get("nba_service_limit")),
                "nba_days_remaining": to_int(s.get("nba_days_remaining")),
                "nba_earned_salary": s.get("nba_earned_salary"),
                "glg_earned_salary": s.get("glg_earned_salary"),
                "nba_salary_days": to_int(s.get("nba_salary_days")),
                "glg_salary_days": to_int(s.get("glg_salary_days")),
                "unreported_days": to_int(s.get("unreported_days")),
                "season_active_nba_game_days": to_int(s.get("season_active_nba_game_days")),
                "season_with_nba_days": to_int(s.get("season_with_nba_days")),
                "season_travel_with_nba_days": to_int(s.get("season_travel_with_nba_days")),
                "season_non_nba_days": to_int(s.get("season_non_nba_days")),
                "season_non_nba_glg_days": to_int(s.get("season_non_nba_glg_days")),
                "season_total_days": to_int(s.get("season_total_days")),
                "created_at": s.get("create_date"),
                "updated_at": s.get("last_change_date"),
                "record_changed_at": s.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        daily_statuses = list(daily_status_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # two_way_contract_utility (from two_way.json -> two_way_seasons)
        # ─────────────────────────────────────────────────────────────────────
        seasons_container = two_way.get("two_way_seasons") or {}
        seasons = as_list(
            seasons_container.get("two-way-season") or
            seasons_container.get("two_way_season") or
            (seasons_container if isinstance(seasons_container, list) else [])
        )

        contract_utility_seen = {}

        for season in seasons:
            players_container = season.get("two-way-players") or season.get("two_way_players") or {}
            players = as_list(
                players_container.get("two-way-player") or
                players_container.get("two_way_player") or
                (players_container if isinstance(players_container, list) else [])
            )
            for p in players:
                contracts_container = p.get("two-way-contracts") or p.get("two_way_contracts") or {}
                contracts = as_list(
                    contracts_container.get("two-way-contract") or
                    contracts_container.get("two_way_contract") or
                    (contracts_container if isinstance(contracts_container, list) else [])
                )
                for c in contracts:
                    contract_id = to_int(c.get("contract_id"))
                    player_id = to_int(c.get("player_id") or p.get("player_id"))
                    if contract_id is None or player_id is None:
                        continue

                    contract_team_id = to_int(c.get("contract_team_id"))
                    signing_team_id = to_int(c.get("signing_team_id"))

                    contract_utility_seen[contract_id] = {
                        "contract_id": contract_id,
                        "player_id": player_id,
                        "contract_team_id": contract_team_id,
                        "contract_team_code": team_code_map.get(contract_team_id) if contract_team_id else None,
                        "signing_team_id": signing_team_id,
                        "signing_team_code": team_code_map.get(signing_team_id) if signing_team_id else None,
                        "is_active_two_way_contract": to_bool(c.get("is_active_two_way_contract")),
                        "games_on_active_list": to_int(c.get("number_of_games_on_active_list")),
                        "active_list_games_limit": to_int(c.get("active_list_games_limit")),
                        "remaining_active_list_games": to_int(c.get("remaining_active_list_games")),
                        "ingested_at": ingested_at,
                    }

        contract_utilities = list(contract_utility_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # two_way_game_utility (from two_way_utility.json -> active_list_by_team)
        # ─────────────────────────────────────────────────────────────────────
        active_list_container = two_way_utility.get("active_list_by_team") or {}
        games = as_list(active_list_container.get("two_way_util_game") or [])
        game_utility_seen = {}

        for g in games:
            game_id = to_int(g.get("game_id"))
            team_id = to_int(g.get("team_id"))
            if game_id is None or team_id is None:
                continue

            game_date = to_date(g.get("date_est"))
            opposition_team_id = to_int(g.get("opposition_team_id"))
            standard_contracts = to_int(g.get("number_of_standard_nba_contracts"))

            players_container = g.get("two_way_util_players") or {}
            players = as_list(players_container.get("two_way_util_player") or [])
            for p in players:
                player_id = to_int(p.get("player_id"))
                if player_id is None:
                    continue

                key = (game_id, player_id)
                game_utility_seen[key] = {
                    "game_id": game_id,
                    "team_id": team_id,
                    "team_code": team_code_map.get(team_id),
                    "player_id": player_id,
                    "game_date_est": game_date,
                    "opposition_team_id": opposition_team_id,
                    "opposition_team_code": team_code_map.get(opposition_team_id) if opposition_team_id else None,
                    "roster_first_name": p.get("roster_first_name"),
                    "roster_last_name": p.get("roster_last_name"),
                    "display_first_name": p.get("display_first_name"),
                    "display_last_name": p.get("display_last_name"),
                    "games_on_active_list": to_int(p.get("number_of_games_on_active_list")),
                    "active_list_games_limit": to_int(p.get("active_list_games_limit")),
                    "standard_nba_contracts_on_team": standard_contracts,
                    "ingested_at": ingested_at,
                }

        game_utilities = list(game_utility_seen.values())

        # ─────────────────────────────────────────────────────────────────────
        # team_two_way_capacity (from two_way_utility.json -> under15_games)
        # ─────────────────────────────────────────────────────────────────────
        under15_container = two_way_utility.get("under15_games") or {}
        budgets = as_list(under15_container.get("under15_team_budget") or [])
        capacity_seen = {}

        for b in budgets:
            team_id = to_int(b.get("team_id"))
            if team_id is None:
                continue

            capacity_seen[team_id] = {
                "team_id": team_id,
                "team_code": team_code_map.get(team_id),
                "current_contract_count": to_int(b.get("current_contract_count")),
                "games_remaining": to_int(b.get("games_remaining")),
                "under_15_games_count": to_int(b.get("under15_games_count")),
                "under_15_games_remaining": to_int(b.get("under15_games_remaining")),
                "ingested_at": ingested_at,
            }

        capacities = list(capacity_seen.values())

        # Print summary
        print(f"Prepared: budget_snapshots={len(budget_snapshots)}, tax_summaries={len(tax_summaries)}")
        print(f"Prepared: waiver_priority={len(waiver_priorities)}, waiver_ranks={len(waiver_ranks)}")
        print(f"Prepared: tax_team_status={len(tax_team_statuses)}, team_transactions={len(team_txs)}")
        print(f"Prepared: daily_statuses={len(daily_statuses)}, contract_utilities={len(contract_utilities)}")
        print(f"Prepared: game_utilities={len(game_utilities)}, capacities={len(capacities)}")

        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                # team_budget_snapshots: TRUNCATE + INSERT (nullable composite key)
                count = truncate_insert(conn, "pcms.team_budget_snapshots", budget_snapshots)
                tables.append({"table": "pcms.team_budget_snapshots", "attempted": count, "success": True})

                # team_tax_summary_snapshots
                count = upsert(conn, "pcms.team_tax_summary_snapshots", tax_summaries, ["team_id", "salary_year"])
                tables.append({"table": "pcms.team_tax_summary_snapshots", "attempted": count, "success": True})

                # tax_team_status
                count = upsert(conn, "pcms.tax_team_status", tax_team_statuses, ["team_id", "salary_year"])
                tables.append({"table": "pcms.tax_team_status", "attempted": count, "success": True})

                # waiver_priority
                count = upsert(conn, "pcms.waiver_priority", waiver_priorities, ["waiver_priority_id"])
                tables.append({"table": "pcms.waiver_priority", "attempted": count, "success": True})

                # waiver_priority_ranks
                count = upsert(conn, "pcms.waiver_priority_ranks", waiver_ranks, ["waiver_priority_rank_id"])
                tables.append({"table": "pcms.waiver_priority_ranks", "attempted": count, "success": True})

                # team_transactions
                count = upsert(conn, "pcms.team_transactions", team_txs, ["team_transaction_id"])
                tables.append({"table": "pcms.team_transactions", "attempted": count, "success": True})

                # two_way_daily_statuses
                count = upsert(conn, "pcms.two_way_daily_statuses", daily_statuses, ["player_id", "status_date"])
                tables.append({"table": "pcms.two_way_daily_statuses", "attempted": count, "success": True})

                # two_way_contract_utility
                count = upsert(conn, "pcms.two_way_contract_utility", contract_utilities, ["contract_id"])
                tables.append({"table": "pcms.two_way_contract_utility", "attempted": count, "success": True})

                # two_way_game_utility
                count = upsert(conn, "pcms.two_way_game_utility", game_utilities, ["game_id", "player_id"])
                tables.append({"table": "pcms.two_way_game_utility", "attempted": count, "success": True})

                # team_two_way_capacity
                count = upsert(conn, "pcms.team_two_way_capacity", capacities, ["team_id"])
                tables.append({"table": "pcms.team_two_way_capacity", "attempted": count, "success": True})

            finally:
                conn.close()
        else:
            tables = [
                {"table": "pcms.team_budget_snapshots", "attempted": len(budget_snapshots), "success": True},
                {"table": "pcms.team_tax_summary_snapshots", "attempted": len(tax_summaries), "success": True},
                {"table": "pcms.tax_team_status", "attempted": len(tax_team_statuses), "success": True},
                {"table": "pcms.waiver_priority", "attempted": len(waiver_priorities), "success": True},
                {"table": "pcms.waiver_priority_ranks", "attempted": len(waiver_ranks), "success": True},
                {"table": "pcms.team_transactions", "attempted": len(team_txs), "success": True},
                {"table": "pcms.two_way_daily_statuses", "attempted": len(daily_statuses), "success": True},
                {"table": "pcms.two_way_contract_utility", "attempted": len(contract_utilities), "success": True},
                {"table": "pcms.two_way_game_utility", "attempted": len(game_utilities), "success": True},
                {"table": "pcms.team_two_way_capacity", "attempted": len(capacities), "success": True},
            ]

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

