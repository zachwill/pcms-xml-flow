# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "wmill", "typing-extensions"]
# ///
"""
League Config Import

Consolidates:
- System values, rookie scale & NCA
- League salary scales & cap projections
- Tax rates & apron constraints
- Draft pick summaries

Upserts into:
- pcms.league_system_values
- pcms.rookie_scale_amounts
- pcms.non_contract_amounts
- pcms.league_salary_scales
- pcms.league_salary_cap_projections
- pcms.league_tax_rates
- pcms.apron_constraints
- pcms.draft_pick_summaries

Note: draft_picks table removed - NBA draft data now comes from
transactions (draft_selections) and trades (draft_pick_trades).
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


def first_scalar(val):
    """Extract first element if array, else return as-is."""
    if val is None:
        return None
    if isinstance(val, list):
        return val[0] if val else None
    return val


def as_list(val) -> list:
    """Ensure value is a list."""
    if val is None:
        return []
    if isinstance(val, list):
        return val
    return [val]


def normalize_pick(val) -> tuple[str | None, int | None]:
    """Return (pick_number as str, pick_number_int)."""
    if val is None or val == "":
        return (None, None)
    if isinstance(val, (int, float)):
        int_val = int(val) if val == val else None  # NaN check
        return (str(val), int_val)
    s = str(val).strip()
    if not s:
        return (None, None)
    try:
        int_val = int(s)
        return (s, int_val)
    except ValueError:
        return (s, None)


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

        # Load all JSON files
        def load_json(filename: str) -> list:
            path = base_dir / filename
            if path.exists():
                with open(path) as f:
                    return json.load(f)
            return []

        ysv_raw = load_json("yearly_system_values.json")
        rookie_raw = load_json("rookie_scale_amounts.json")
        nca_raw = load_json("non_contract_amounts.json")
        scales_raw = load_json("yearly_salary_scales.json")
        projections_raw = load_json("cap_projections.json")
        tax_rates_raw = load_json("tax_rates.json")
        summaries_raw = load_json("draft_pick_summaries.json")

        print(f"Found: ysv={len(ysv_raw)}, rookie={len(rookie_raw)}, nca={len(nca_raw)}")
        print(f"Found: scales={len(scales_raw)}, projections={len(projections_raw)}, tax_rates={len(tax_rates_raw)}")
        print(f"Found: draft_pick_summaries={len(summaries_raw)}")

        # ─────────────────────────────────────────────────────────────────────
        # League System Values
        # ─────────────────────────────────────────────────────────────────────
        system_values = {}
        for sv in ysv_raw:
            league = sv.get("league_lk")
            year = to_int(sv.get("system_year"))
            if not league or year is None:
                continue

            system_values[(league, year)] = {
                "league_lk": league,
                "salary_year": year,
                "salary_cap_amount": to_int(sv.get("cap_amount")),
                "tax_level_amount": to_int(sv.get("tax_level")),
                "tax_apron_amount": to_int(sv.get("tax_apron")),
                "tax_apron2_amount": to_int(sv.get("tax_apron2")),
                "tax_bracket_amount": to_int(sv.get("tax_bracket_amount")),
                "minimum_team_salary_amount": to_int(sv.get("minimum_team_salary")),
                "maximum_salary_25_pct": to_int(sv.get("maximum_salary25")),
                "maximum_salary_30_pct": to_int(sv.get("maximum_salary30")),
                "maximum_salary_35_pct": to_int(sv.get("maximum_salary35")),
                "average_salary_amount": to_int(sv.get("average_salary")),
                "estimated_average_salary_amount": to_int(sv.get("estimated_average_salary")),
                "non_taxpayer_mid_level_amount": to_int(sv.get("non_taxpayer_mid_level_amount")),
                "taxpayer_mid_level_amount": to_int(sv.get("taxpayer_mid_level_amount")),
                "room_mid_level_amount": to_int(sv.get("room_mid_level_amount")),
                "bi_annual_amount": to_int(sv.get("bi_annual_amount")),
                "two_way_salary_amount": to_int(sv.get("two_way_salary_amount")),
                "two_way_dlg_salary_amount": to_int(sv.get("two_way_dlg_salary_amount")),
                "tpe_dollar_allowance": to_int(sv.get("tpe_dollar_allowance")),
                "max_trade_cash_amount": to_int(sv.get("max_trade_cash_amount")),
                "international_player_payment_limit": to_int(sv.get("international_player_payment")),
                "scale_raise_rate": sv.get("scale_raise_rate"),
                "days_in_season": to_int(sv.get("days_in_season")),
                "season_start_at": sv.get("first_day_of_season"),
                "season_end_at": sv.get("last_day_of_season"),
                "playing_start_at": sv.get("playing_start_date"),
                "playing_end_at": sv.get("playing_end_date"),
                "finals_end_at": sv.get("last_day_of_finals"),
                "training_camp_start_at": sv.get("training_camp_start_date"),
                "training_camp_end_at": sv.get("training_camp_end_date"),
                "rookie_camp_start_at": sv.get("rookie_camp_start_date"),
                "rookie_camp_end_at": sv.get("rookie_camp_end_date"),
                "draft_at": sv.get("draft_date"),
                "moratorium_end_at": sv.get("moratorium_end_date"),
                "trade_deadline_at": sv.get("trade_deadline_date"),
                "cut_down_at": sv.get("cut_down_date"),
                "two_way_cut_down_at": sv.get("two_way_cut_down_date"),
                "notification_start_at": sv.get("notification_start_date"),
                "notification_end_at": sv.get("notification_end_date"),
                "exception_start_at": sv.get("exception_start_date"),
                "exception_prorate_at": sv.get("exception_prorate_start_date"),
                "exceptions_added_at": sv.get("exceptions_added_date"),
                "rnd2_pick_exc_zero_cap_end_at": sv.get("rnd2_pick_exc_zero_cap_end_date"),
                "bonuses_finalized_at": sv.get("bonuses_finalized_date"),
                "is_bonuses_finalized": sv.get("bonuses_finalized_flg"),
                "is_cap_projection_generated": sv.get("cap_projection_generated_flg"),
                "is_exceptions_added": sv.get("exceptions_added_flg"),
                "free_agent_status_finalized_at": sv.get("free_agent_amounts_finalized_date"),
                "is_free_agent_amounts_finalized": sv.get("free_agent_amounts_finalized_flg"),
                "wnba_offseason_end_at": sv.get("wnba_offseason_end"),
                "wnba_season_finalized_at": sv.get("wnba_season_finalized_date"),
                "is_wnba_season_finalized": sv.get("wnba_season_finalized_flg"),
                "dlg_countable_roster_moves": to_int(sv.get("dlg_countable_roster_moves")),
                "dlg_max_level_a_salary_players": to_int(sv.get("dlg_max_level_a_salary_players")),
                "dlg_salary_level_a": to_int(sv.get("dlg_salary_level_a")),
                "dlg_salary_level_b": to_int(sv.get("dlg_salary_level_b")),
                "dlg_salary_level_c": to_int(sv.get("dlg_salary_level_c")),
                "dlg_team_salary_budget": to_int(sv.get("dlg_team_salary_budget")),
                "created_at": sv.get("create_date"),
                "updated_at": sv.get("last_change_date"),
                "record_changed_at": sv.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        # ─────────────────────────────────────────────────────────────────────
        # Rookie Scale Amounts
        # ─────────────────────────────────────────────────────────────────────
        rookie_scale = {}
        for rs in rookie_raw:
            year = to_int(rs.get("season"))
            pick = to_int(rs.get("pick"))
            league = rs.get("league_lk") or "NBA"
            if year is None or pick is None:
                continue

            rookie_scale[(year, pick, league)] = {
                "salary_year": year,
                "pick_number": pick,
                "league_lk": league,
                "salary_year_1": to_int(rs.get("salary_year1")),
                "salary_year_2": to_int(rs.get("salary_year2")),
                "salary_year_3": to_int(rs.get("salary_year3")),
                "salary_year_4": to_int(rs.get("salary_year4")),
                "option_amount_year_3": to_int(rs.get("option_year3")),
                "option_amount_year_4": to_int(rs.get("option_year4")),
                "option_pct_year_3": rs.get("percent_year3"),
                "option_pct_year_4": rs.get("percent_year4"),
                "is_baseline_scale": rs.get("baseline_scale_flg"),
                "is_active": rs.get("active_flg"),
                "created_at": rs.get("create_date"),
                "updated_at": rs.get("last_change_date"),
                "record_changed_at": rs.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        # ─────────────────────────────────────────────────────────────────────
        # Non-Contract Amounts (cap holds, etc.)
        # ─────────────────────────────────────────────────────────────────────
        non_contract = {}
        for nca in nca_raw:
            nca_id = to_int(nca.get("non_contract_amount_id"))
            if nca_id is None:
                continue

            team_id = to_int(nca.get("team_id"))
            non_contract[nca_id] = {
                "non_contract_amount_id": nca_id,
                "player_id": to_int(nca.get("player_id")),
                "team_id": team_id,
                "team_code": team_code_map.get(team_id) if team_id else None,
                "salary_year": to_int(nca.get("non_contract_year")),
                "amount_type_lk": nca.get("non_contract_amount_type_lk") or nca.get("amount_type_lk"),
                "cap_amount": to_int(nca.get("cap_amount")),
                "tax_amount": to_int(nca.get("tax_amount")),
                "apron_amount": to_int(nca.get("apron_amount")),
                "fa_amount": to_int(nca.get("fa_amount")),
                "fa_amount_calc": to_int(nca.get("fa_amount_calc")),
                "salary_fa_amount": to_int(nca.get("salary_fa_amount")),
                "qo_amount": to_int(nca.get("qo_amount")),
                "rofr_amount": to_int(nca.get("rofr_amount")),
                "rookie_scale_amount": to_int(first_scalar(nca.get("rookie_scale_amount"))),
                "carry_over_fa_flg": nca.get("carry_over_fa_flg"),
                "fa_amount_type_lk": nca.get("free_agent_amount_type_lk"),
                "fa_amount_type_lk_calc": nca.get("free_agent_amount_type_lk_calc"),
                "free_agent_designation_lk": nca.get("free_agent_designation_lk"),
                "free_agent_status_lk": nca.get("free_agent_status_lk"),
                "min_contract_lk": nca.get("min_contract_lk"),
                "contract_id": to_int(nca.get("contract_id")),
                "contract_type_lk": nca.get("contract_type_lk"),
                "transaction_id": to_int(nca.get("transaction_id")),
                "version_number": str(nca.get("version_number")) if nca.get("version_number") is not None else None,
                "years_of_service": to_int(nca.get("years_of_service")),
                "created_at": nca.get("create_date"),
                "updated_at": nca.get("last_change_date"),
                "record_changed_at": nca.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        # ─────────────────────────────────────────────────────────────────────
        # Salary Scales (minimum salary by YOS)
        # ─────────────────────────────────────────────────────────────────────
        salary_scales = {}
        for s in scales_raw:
            year = to_int(s.get("salary_year"))
            league = s.get("league_lk")
            yos = to_int(s.get("years_of_service"))
            if year is None or league is None or yos is None:
                continue

            salary_scales[(year, league, yos)] = {
                "salary_year": year,
                "league_lk": league,
                "years_of_service": yos,
                "minimum_salary_amount": to_int(s.get("minimum_salary_year1")),
                "created_at": s.get("create_date"),
                "updated_at": s.get("last_change_date"),
                "record_changed_at": s.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        # ─────────────────────────────────────────────────────────────────────
        # Cap Projections
        # ─────────────────────────────────────────────────────────────────────
        cap_projections = {}
        for p in projections_raw:
            proj_id = to_int(p.get("salary_cap_projection_id"))
            if proj_id is None:
                continue

            cap_projections[proj_id] = {
                "projection_id": proj_id,
                "salary_year": to_int(p.get("season_year")),
                "cap_amount": to_int(p.get("cap_amount")),
                "tax_level_amount": to_int(p.get("tax_level")),
                "estimated_average_player_salary": to_int(p.get("estimated_average_player_salary")),
                "growth_rate": p.get("growth_rate"),
                "effective_date": p.get("effective_date"),
                "is_generated": p.get("generated_flg"),
                "created_at": p.get("create_date"),
                "updated_at": p.get("last_change_date"),
                "record_changed_at": p.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        # ─────────────────────────────────────────────────────────────────────
        # Tax Rates
        # ─────────────────────────────────────────────────────────────────────
        tax_rates = {}
        for tr in tax_rates_raw:
            league = tr.get("league_lk") or "NBA"
            year = to_int(tr.get("salary_year"))
            lower = to_int(tr.get("lower_limit"))
            if year is None or lower is None:
                continue

            tax_rates[(league, year, lower)] = {
                "league_lk": league,
                "salary_year": year,
                "lower_limit": lower,
                "upper_limit": to_int(tr.get("upper_limit")),
                "tax_rate_non_repeater": tr.get("tax_rate_non_repeater"),
                "tax_rate_repeater": tr.get("tax_rate_repeater"),
                "base_charge_non_repeater": to_int(tr.get("base_charge_non_repeater")),
                "base_charge_repeater": to_int(tr.get("base_charge_repeater")),
                "created_at": tr.get("create_date"),
                "updated_at": tr.get("last_change_date"),
                "record_changed_at": tr.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        # ─────────────────────────────────────────────────────────────────────
        # Draft Pick Summaries
        # ─────────────────────────────────────────────────────────────────────
        draft_summaries = {}
        for s in summaries_raw:
            year = to_int(s.get("draft_year"))
            team_id = to_int(s.get("team_id"))
            if year is None or team_id is None:
                continue

            draft_summaries[(year, team_id)] = {
                "draft_year": year,
                "team_id": team_id,
                "team_code": team_code_map.get(team_id),
                "first_round": s.get("first_round"),
                "second_round": s.get("second_round"),
                "is_active": s.get("active_flg"),
                "created_at": s.get("create_date"),
                "updated_at": s.get("last_change_date"),
                "record_changed_at": s.get("record_change_date"),
                "ingested_at": ingested_at,
            }

        # Convert to lists
        system_values_rows = list(system_values.values())
        rookie_scale_rows = list(rookie_scale.values())
        non_contract_rows = list(non_contract.values())
        salary_scales_rows = list(salary_scales.values())
        cap_projections_rows = list(cap_projections.values())
        tax_rates_rows = list(tax_rates.values())
        draft_summaries_rows = list(draft_summaries.values())

        print(f"Prepared: system_values={len(system_values_rows)}, rookie_scale={len(rookie_scale_rows)}, "
              f"nca={len(non_contract_rows)}")
        print(f"Prepared: scales={len(salary_scales_rows)}, projections={len(cap_projections_rows)}, "
              f"tax_rates={len(tax_rates_rows)}")
        print(f"Prepared: draft_pick_summaries={len(draft_summaries_rows)}")

        if not dry_run:
            conn = psycopg.connect(os.environ["POSTGRES_URL"])
            try:
                # League system values
                count = upsert(conn, "pcms.league_system_values", system_values_rows,
                               ["league_lk", "salary_year"])
                tables.append({"table": "pcms.league_system_values", "attempted": count, "success": True})

                # Rookie scale amounts
                count = upsert(conn, "pcms.rookie_scale_amounts", rookie_scale_rows,
                               ["salary_year", "pick_number", "league_lk"])
                tables.append({"table": "pcms.rookie_scale_amounts", "attempted": count, "success": True})

                # Non-contract amounts
                count = upsert(conn, "pcms.non_contract_amounts", non_contract_rows,
                               ["non_contract_amount_id"])
                tables.append({"table": "pcms.non_contract_amounts", "attempted": count, "success": True})

                # Salary scales
                count = upsert(conn, "pcms.league_salary_scales", salary_scales_rows,
                               ["salary_year", "league_lk", "years_of_service"])
                tables.append({"table": "pcms.league_salary_scales", "attempted": count, "success": True})

                # Cap projections
                count = upsert(conn, "pcms.league_salary_cap_projections", cap_projections_rows,
                               ["projection_id"])
                tables.append({"table": "pcms.league_salary_cap_projections", "attempted": count, "success": True})

                # Tax rates
                count = upsert(conn, "pcms.league_tax_rates", tax_rates_rows,
                               ["league_lk", "salary_year", "lower_limit"])
                tables.append({"table": "pcms.league_tax_rates", "attempted": count, "success": True})

                # Draft pick summaries
                count = upsert(conn, "pcms.draft_pick_summaries", draft_summaries_rows,
                               ["draft_year", "team_id"])
                tables.append({"table": "pcms.draft_pick_summaries", "attempted": count, "success": True})

                # Apron constraints (derived from lookups × system_values)
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO pcms.apron_constraints (
                            apron_level_lk, constraint_code, effective_salary_year,
                            description, created_at, updated_at, ingested_at
                        )
                        SELECT
                            lk.properties_json->>'apron_level_lk' as apron_level_lk,
                            lk.lookup_code as constraint_code,
                            ysv.salary_year as effective_salary_year,
                            lk.description,
                            lk.created_at,
                            lk.updated_at,
                            NOW() as ingested_at
                        FROM pcms.lookups lk
                        CROSS JOIN pcms.league_system_values ysv
                        WHERE lk.lookup_type = 'lk_subject_to_apron_reasons'
                          AND lk.is_active = true
                          AND ysv.tax_apron_amount > 0
                          AND lk.properties_json->>'apron_level_lk' IS NOT NULL
                        ON CONFLICT (apron_level_lk, constraint_code, effective_salary_year) DO NOTHING
                    """)
                    apron_count = cur.rowcount
                conn.commit()
                tables.append({"table": "pcms.apron_constraints", "attempted": apron_count, "success": True})

            finally:
                conn.close()
        else:
            tables.append({"table": "pcms.league_system_values", "attempted": len(system_values_rows), "success": True})
            tables.append({"table": "pcms.rookie_scale_amounts", "attempted": len(rookie_scale_rows), "success": True})
            tables.append({"table": "pcms.non_contract_amounts", "attempted": len(non_contract_rows), "success": True})
            tables.append({"table": "pcms.league_salary_scales", "attempted": len(salary_scales_rows), "success": True})
            tables.append({"table": "pcms.league_salary_cap_projections", "attempted": len(cap_projections_rows), "success": True})
            tables.append({"table": "pcms.league_tax_rates", "attempted": len(tax_rates_rows), "success": True})
            tables.append({"table": "pcms.draft_pick_summaries", "attempted": len(draft_summaries_rows), "success": True})
            tables.append({"table": "pcms.apron_constraints", "attempted": "(derived)", "success": True})

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

