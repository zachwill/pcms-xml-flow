# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]"]
# ///
"""
Contracts Import

Imports contracts and all nested structures from PCMS extract.

Order (FK-safe): contracts → versions → salaries → bonuses → bonus_criteria →
                 bonus_maximums → payment_schedules → protections → protection_conditions

Upserts into:
- pcms.contracts
- pcms.contract_versions
- pcms.salaries
- pcms.contract_bonuses
- pcms.contract_bonus_criteria
- pcms.contract_bonus_maximums
- pcms.payment_schedules
- pcms.contract_protections
- pcms.contract_protection_conditions
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

        # Load contracts
        with open(base_dir / "contracts.json") as f:
            contracts_raw = json.load(f)
        print(f"Found {len(contracts_raw)} contracts")

        # Load lookups for team code mapping
        with open(base_dir / "lookups.json") as f:
            lookups = json.load(f)

        teams_raw = lookups.get("lk_teams", {}).get("lk_team", [])
        team_code_map = {
            t["team_id"]: t.get("team_name_short") or t.get("team_code")
            for t in teams_raw
            if t.get("team_id") and (t.get("team_name_short") or t.get("team_code"))
        }

        # ─────────────────────────────────────────────────────────────────────
        # Contracts
        # ─────────────────────────────────────────────────────────────────────
        contracts_seen = {}
        versions_seen = {}
        salaries_seen = {}
        bonuses_seen = {}          # Key: (contract_id, version_number, bonus_id)
        bonus_criteria_seen = {}   # Key: (contract_id, version_number, bonus_id, bonus_criteria_id)
        bonus_maximums_seen = {}   # Key: (contract_id, version_number, bonus_max_id)
        payments_seen = {}
        protections_seen = {}      # Key: (contract_id, version_number, protection_id)
        protection_conditions_seen = {}  # Key: (contract_id, version_number, protection_id, condition_id)

        for c in contracts_raw:
            contract_id = to_int(c.get("contract_id"))
            if contract_id is None:
                continue

            signing_team_id = to_int(c.get("signing_team_id"))
            sat_team_id = to_int(c.get("sign_and_trade_to_team_id"))

            contracts_seen[contract_id] = {
                "contract_id": contract_id,
                "player_id": to_int(c.get("player_id")),
                "signing_team_id": signing_team_id,
                "team_code": team_code_map.get(signing_team_id) if signing_team_id else None,
                "signing_date": c.get("signing_date"),
                "contract_end_date": c.get("contract_end_date"),
                "record_status_lk": c.get("record_status_lk"),
                "signed_method_lk": c.get("signed_method_lk"),
                "team_exception_id": to_int(c.get("team_exception_id")),
                "is_sign_and_trade": c.get("sign_and_trade_flg") or False,
                "sign_and_trade_date": c.get("sign_and_trade_date"),
                "sign_and_trade_to_team_id": sat_team_id,
                "sign_and_trade_to_team_code": team_code_map.get(sat_team_id) if sat_team_id else None,
                "sign_and_trade_id": to_int(c.get("sign_and_trade_id")),
                "start_year": to_int(c.get("start_year")),
                "contract_length_wnba": c.get("contract_length_wnba") or c.get("contract_length"),
                "convert_date": c.get("convert_date"),
                "two_way_service_limit": to_int(c.get("two_way_service_limit")),
                "created_at": c.get("create_date"),
                "updated_at": c.get("last_change_date"),
                "record_changed_at": c.get("record_change_date"),
                "ingested_at": ingested_at,
            }

            # ─────────────────────────────────────────────────────────────────
            # Versions (nested under contract)
            # ─────────────────────────────────────────────────────────────────
            versions = as_list(c.get("versions", {}).get("version"))

            for v in versions:
                version_number = normalize_version_number(v.get("version_number"))
                if version_number is None:
                    continue

                version_key = (contract_id, version_number)

                # Extract protections to derive flags
                protections = as_list(v.get("protections", {}).get("protection") if v.get("protections") else None)
                has_protections = len(protections) > 0
                all_full = has_protections and all(
                    p.get("protection_coverage_lk") == "FULL" for p in protections
                )

                # Build version_json (leftover fields not mapped to columns)
                exclude_keys = {
                    "version_number", "transaction_id", "version_date", "start_year",
                    "contract_length", "contract_type_lk", "record_status_lk",
                    "agency_id", "agent_id", "full_protection_flg",
                    "exhibit10", "exhibit10_bonus_amount", "exhibit10_protection_amount",
                    "exhibit10_end_date", "dp_rookie_scale_extension_flg",
                    "dp_veteran_extension_flg", "poison_pill_flg", "poison_pill_amt",
                    "trade_bonus_percent", "trade_bonus_amount", "trade_bonus_flg",
                    "no_trade_flg", "create_date", "last_change_date", "record_change_date",
                    "salaries", "bonuses", "protections", "bonus_maximums",
                }
                version_json = {k: val for k, val in v.items() if k not in exclude_keys}

                versions_seen[version_key] = {
                    "contract_id": contract_id,
                    "version_number": version_number,
                    "transaction_id": to_int(v.get("transaction_id")),
                    "version_date": v.get("version_date"),
                    "start_salary_year": to_int(v.get("start_year")),
                    "contract_length": to_int(v.get("contract_length")),
                    "contract_type_lk": v.get("contract_type_lk"),
                    "record_status_lk": v.get("record_status_lk"),
                    "agency_id": to_int(v.get("agency_id")),
                    "agent_id": to_int(v.get("agent_id")),
                    "is_full_protection": all_full if has_protections else (v.get("full_protection_flg") or None),
                    "is_exhibit_10": v.get("exhibit10") or None,
                    "exhibit_10_bonus_amount": to_int(v.get("exhibit10_bonus_amount")),
                    "exhibit_10_protection_amount": to_int(v.get("exhibit10_protection_amount")),
                    "exhibit_10_end_date": v.get("exhibit10_end_date"),
                    "is_two_way": v.get("is_two_way") or None,
                    "is_rookie_scale_extension": v.get("dp_rookie_scale_extension_flg") or None,
                    "is_veteran_extension": v.get("dp_veteran_extension_flg") or None,
                    "is_poison_pill": v.get("poison_pill_flg") or None,
                    "poison_pill_amount": to_int(v.get("poison_pill_amt")),
                    "trade_bonus_percent": v.get("trade_bonus_percent"),
                    "trade_bonus_amount": to_int(v.get("trade_bonus_amount")),
                    "is_trade_bonus": v.get("trade_bonus_flg") or None,
                    "is_no_trade": v.get("no_trade_flg") or None,
                    "is_minimum_contract": v.get("is_minimum_contract") or None,
                    "is_protected_contract": True if has_protections else (v.get("is_protected_contract") or None),
                    "version_json": json.dumps(version_json, default=str) if version_json else None,
                    "created_at": v.get("create_date"),
                    "updated_at": v.get("last_change_date"),
                    "record_changed_at": v.get("record_change_date"),
                    "ingested_at": ingested_at,
                }

                # ─────────────────────────────────────────────────────────────
                # Protections (nested under version)
                # ─────────────────────────────────────────────────────────────
                for p in protections:
                    protection_id = to_int(p.get("contract_protection_id"))
                    if protection_id is None:
                        continue

                    protection_key = (contract_id, version_number, protection_id)

                    protection_types = as_list(
                        p.get("protection_types", {}).get("protection_type")
                        if p.get("protection_types") else None
                    )
                    has_conditions = p.get("protection_conditions") is not None

                    protections_seen[protection_key] = {
                        "protection_id": protection_id,
                        "contract_id": contract_id,
                        "version_number": version_number,
                        "salary_year": to_int(p.get("contract_year")),
                        "protection_amount": to_int(p.get("protection_amount")),
                        "effective_protection_amount": to_int(p.get("effective_protection_amount")),
                        "protection_coverage_lk": p.get("protection_coverage_lk"),
                        "is_conditional_protection": has_conditions,
                        "conditional_protection_comments": str(p.get("protection_conditions")) if has_conditions else None,
                        "protection_types_json": json.dumps(protection_types) if protection_types else None,
                        "ingested_at": ingested_at,
                    }

                    # ─────────────────────────────────────────────────────────
                    # Protection Conditions (nested under protection)
                    # ─────────────────────────────────────────────────────────
                    if has_conditions:
                        conditions = as_list(p["protection_conditions"].get("protection_condition"))
                        for cond in conditions:
                            condition_id = to_int(cond.get("contract_protection_condition_id"))
                            if condition_id is None:
                                continue

                            condition_key = (contract_id, version_number, protection_id, condition_id)

                            protection_conditions_seen[condition_key] = {
                                "condition_id": condition_id,
                                "protection_id": protection_id,
                                "contract_id": contract_id,
                                "version_number": version_number,
                                "amount": to_int(cond.get("amount")),
                                "clause_name": cond.get("clause_name"),
                                "earned_date": cond.get("earned_date"),
                                "earned_type_lk": cond.get("earned_type_lk"),
                                "is_full_condition": cond.get("full_flg") or None,
                                "criteria_description": cond.get("criteria_description"),
                                "criteria_json": json.dumps(cond.get("criteria"), default=str) if cond.get("criteria") else None,
                                "ingested_at": ingested_at,
                            }

                # ─────────────────────────────────────────────────────────────
                # Bonuses (nested under version)
                # ─────────────────────────────────────────────────────────────
                bonuses = as_list(v.get("bonuses", {}).get("bonus") if v.get("bonuses") else None)
                for b in bonuses:
                    bonus_id = to_int(b.get("bonus_id"))
                    if bonus_id is None:
                        continue

                    bonus_key = (contract_id, version_number, bonus_id)

                    bonuses_seen[bonus_key] = {
                        "bonus_id": bonus_id,
                        "contract_id": contract_id,
                        "version_number": version_number,
                        "salary_year": to_int(b.get("bonus_year")),
                        "bonus_amount": to_int(b.get("bonus_amount")),
                        "bonus_type_lk": b.get("contract_bonus_type_lk"),
                        "is_likely": b.get("bonus_likely_flg") or None,
                        "earned_lk": b.get("earned_lk"),
                        "paid_by_date": b.get("bonus_paid_by_date"),
                        "clause_name": b.get("clause_name"),
                        "criteria_description": b.get("criteria_description"),
                        "criteria_json": json.dumps(b.get("bonus_criteria"), default=str) if b.get("bonus_criteria") else None,
                        "ingested_at": ingested_at,
                    }

                    # ─────────────────────────────────────────────────────────
                    # Bonus Criteria (nested under bonus)
                    # ─────────────────────────────────────────────────────────
                    criteria_groups = as_list(b.get("bonus_criteria"))
                    for group in criteria_groups:
                        if group is None:
                            continue
                        criteria_items = as_list(group.get("bonus_criterium") if isinstance(group, dict) else None)
                        for cri in criteria_items:
                            criteria_id = to_int(cri.get("bonus_criteria_id"))
                            if criteria_id is None:
                                continue

                            criteria_key = (contract_id, version_number, bonus_id, criteria_id)

                            bonus_criteria_seen[criteria_key] = {
                                "bonus_criteria_id": criteria_id,
                                "bonus_id": bonus_id,
                                "contract_id": contract_id,
                                "version_number": version_number,
                                "criteria_lk": cri.get("criteria_lk"),
                                "criteria_operator_lk": cri.get("criteria_operator_lk"),
                                "modifier_lk": cri.get("modifier_lk"),
                                "season_type_lk": cri.get("season_type_lk"),
                                "is_player_criteria": cri.get("player_criteria_flg") or None,
                                "is_team_criteria": cri.get("team_criteria_flg") or None,
                                "value_1": cri.get("value1"),
                                "value_2": cri.get("value2"),
                                "date_1": cri.get("date1"),
                                "date_2": cri.get("date2"),
                                "ingested_at": ingested_at,
                            }

                # ─────────────────────────────────────────────────────────────
                # Bonus Maximums (nested under version)
                # ─────────────────────────────────────────────────────────────
                bonus_maxes = as_list(v.get("bonus_maximums", {}).get("bonus_maximum") if v.get("bonus_maximums") else None)
                for bm in bonus_maxes:
                    bonus_max_id = to_int(bm.get("bonus_max_id"))
                    if bonus_max_id is None:
                        continue

                    max_key = (contract_id, version_number, bonus_max_id)

                    bonus_maximums_seen[max_key] = {
                        "bonus_max_id": bonus_max_id,
                        "contract_id": contract_id,
                        "version_number": version_number,
                        "salary_year": to_int(bm.get("salary_year")),
                        "max_amount": to_int(bm.get("bonus_max_amount")),
                        "bonus_type_lk": None,  # Not in source data
                        "is_likely": bm.get("greater_of_max_flg") or None,
                        "ingested_at": ingested_at,
                    }

                # ─────────────────────────────────────────────────────────────
                # Salaries (nested under version)
                # ─────────────────────────────────────────────────────────────
                salaries = as_list(v.get("salaries", {}).get("salary") if v.get("salaries") else None)
                for s in salaries:
                    salary_year = to_int(s.get("salary_year"))
                    if salary_year is None:
                        continue

                    salary_key = (contract_id, version_number, salary_year)
                    salaries_seen[salary_key] = {
                        "contract_id": contract_id,
                        "version_number": version_number,
                        "salary_year": salary_year,
                        "total_salary": to_int(s.get("total_salary")),
                        "total_salary_adjustment": to_int(s.get("total_salary_adjustment")),
                        "total_base_comp": to_int(s.get("total_base_comp")),
                        "current_base_comp": to_int(s.get("current_base_comp")),
                        "deferred_base_comp": to_int(s.get("deferred_base_comp")),
                        "signing_bonus": to_int(s.get("signing_bonus")),
                        "likely_bonus": to_int(s.get("likely_bonus")),
                        "unlikely_bonus": to_int(s.get("unlikely_bonus")),
                        "contract_cap_salary": to_int(s.get("contract_cap_salary")),
                        "contract_cap_salary_adjustment": to_int(s.get("contract_cap_salary_adjustment")),
                        "contract_tax_salary": to_int(s.get("contract_tax_salary")),
                        "contract_tax_salary_adjustment": to_int(s.get("contract_tax_salary_adjustment")),
                        "contract_tax_apron_salary": to_int(s.get("contract_tax_apron_salary")),
                        "contract_tax_apron_salary_adjustment": to_int(s.get("contract_tax_apron_salary_adjustment")),
                        "contract_mts_salary": to_int(s.get("contract_mts_salary")),
                        "skill_protection_amount": to_int(s.get("skill_protection_amount")),
                        "trade_bonus_amount": to_int(s.get("trade_bonus_amount")),
                        "trade_bonus_amount_calc": to_int(s.get("trade_bonus_amount_calc")),
                        "cap_raise_percent": s.get("cap_raise_percent"),
                        "two_way_nba_salary": to_int(s.get("two_way_nba_salary")),
                        "two_way_dlg_salary": to_int(s.get("two_way_dlg_salary")),
                        "wnba_salary": to_int(s.get("wnba_salary")),
                        "wnba_time_off_bonus_amount": to_int(s.get("wnba_time_off_bonus_amount")),
                        "wnba_merit_bonus_amount": to_int(s.get("wnba_merit_bonus_amount")),
                        "wnba_time_off_bonus_days": to_int(s.get("wnba_time_off_bonus_days")),
                        "option_lk": s.get("option_lk"),
                        "option_decision_lk": s.get("option_decision_lk"),
                        "is_applicable_min_salary": s.get("applicable_min_salary_flg") or None,
                        "created_at": s.get("create_date"),
                        "updated_at": s.get("last_change_date"),
                        "record_changed_at": s.get("record_change_date"),
                        "ingested_at": ingested_at,
                    }

                    # ─────────────────────────────────────────────────────────
                    # Payment Schedules (nested under salary)
                    # ─────────────────────────────────────────────────────────
                    payment_schedules = as_list(
                        s.get("payment_schedules", {}).get("payment_schedule")
                        if s.get("payment_schedules") else None
                    )
                    for ps in payment_schedules:
                        payment_id = to_int(ps.get("contract_payment_schedule_id"))
                        if payment_id is None:
                            continue

                        payments_seen[payment_id] = {
                            "payment_schedule_id": payment_id,
                            "contract_id": contract_id,
                            "version_number": version_number,
                            "salary_year": to_int(ps.get("salary_year")) or salary_year,
                            "payment_amount": to_int(ps.get("payment_amount")),
                            "payment_start_date": ps.get("payment_start_date"),
                            "schedule_type_lk": ps.get("payment_schedule_type_lk"),
                            "payment_type_lk": ps.get("contract_payment_type_lk"),
                            "is_default_schedule": ps.get("default_payment_schedule_flg") or None,
                            "created_at": ps.get("create_date"),
                            "updated_at": ps.get("last_change_date"),
                            "record_changed_at": ps.get("record_change_date"),
                            "ingested_at": ingested_at,
                        }

        contracts = list(contracts_seen.values())
        versions = list(versions_seen.values())
        salaries = list(salaries_seen.values())
        bonuses = list(bonuses_seen.values())
        bonus_criteria = list(bonus_criteria_seen.values())
        bonus_maximums = list(bonus_maximums_seen.values())
        payments = list(payments_seen.values())
        protections = list(protections_seen.values())
        protection_conditions = list(protection_conditions_seen.values())

        print(f"Prepared: contracts={len(contracts)}, versions={len(versions)}, "
              f"salaries={len(salaries)}, bonuses={len(bonuses)}, "
              f"bonus_criteria={len(bonus_criteria)}, bonus_maximums={len(bonus_maximums)}, "
              f"payments={len(payments)}, protections={len(protections)}, "
              f"protection_conditions={len(protection_conditions)}")

        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                # Upsert in FK order
                count = upsert(conn, "pcms.contracts", contracts, ["contract_id"])
                tables.append({"table": "pcms.contracts", "attempted": count, "success": True})

                count = upsert(conn, "pcms.contract_versions", versions, ["contract_id", "version_number"])
                tables.append({"table": "pcms.contract_versions", "attempted": count, "success": True})

                count = upsert(conn, "pcms.salaries", salaries, ["contract_id", "version_number", "salary_year"])
                tables.append({"table": "pcms.salaries", "attempted": count, "success": True})

                # Bonuses - composite key: (contract_id, version_number, bonus_id)
                count = upsert(conn, "pcms.contract_bonuses", bonuses, ["contract_id", "version_number", "bonus_id"])
                tables.append({"table": "pcms.contract_bonuses", "attempted": count, "success": True})

                # Bonus Criteria - composite key: (contract_id, version_number, bonus_id, bonus_criteria_id)
                count = upsert(conn, "pcms.contract_bonus_criteria", bonus_criteria,
                               ["contract_id", "version_number", "bonus_id", "bonus_criteria_id"])
                tables.append({"table": "pcms.contract_bonus_criteria", "attempted": count, "success": True})

                # Bonus Maximums - composite key: (contract_id, version_number, bonus_max_id)
                count = upsert(conn, "pcms.contract_bonus_maximums", bonus_maximums,
                               ["contract_id", "version_number", "bonus_max_id"])
                tables.append({"table": "pcms.contract_bonus_maximums", "attempted": count, "success": True})

                count = upsert(conn, "pcms.payment_schedules", payments, ["payment_schedule_id"])
                tables.append({"table": "pcms.payment_schedules", "attempted": count, "success": True})

                # Protections - composite key: (contract_id, version_number, protection_id)
                count = upsert(conn, "pcms.contract_protections", protections,
                               ["contract_id", "version_number", "protection_id"])
                tables.append({"table": "pcms.contract_protections", "attempted": count, "success": True})

                # Protection Conditions - composite key: (contract_id, version_number, protection_id, condition_id)
                count = upsert(conn, "pcms.contract_protection_conditions", protection_conditions,
                               ["contract_id", "version_number", "protection_id", "condition_id"])
                tables.append({"table": "pcms.contract_protection_conditions", "attempted": count, "success": True})

            finally:
                conn.close()
        else:
            tables.append({"table": "pcms.contracts", "attempted": len(contracts), "success": True})
            tables.append({"table": "pcms.contract_versions", "attempted": len(versions), "success": True})
            tables.append({"table": "pcms.salaries", "attempted": len(salaries), "success": True})
            tables.append({"table": "pcms.contract_bonuses", "attempted": len(bonuses), "success": True})
            tables.append({"table": "pcms.contract_bonus_criteria", "attempted": len(bonus_criteria), "success": True})
            tables.append({"table": "pcms.contract_bonus_maximums", "attempted": len(bonus_maximums), "success": True})
            tables.append({"table": "pcms.payment_schedules", "attempted": len(payments), "success": True})
            tables.append({"table": "pcms.contract_protections", "attempted": len(protections), "success": True})
            tables.append({"table": "pcms.contract_protection_conditions", "attempted": len(protection_conditions), "success": True})

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

