"""
Dataset extraction functions per the data contract.

Each function returns rows suitable for writing to a DATA_* sheet.

See: reference/blueprints/excel-workbook-data-contract.md
"""

from __future__ import annotations

from typing import Any

from .db import fetch_all


def extract_system_values(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_system_values dataset.

    Returns (columns, rows) for DATA_system_values sheet.
    """
    sql = """
        SELECT
            league_lk,
            salary_year,
            salary_cap_amount,
            tax_level_amount,
            tax_apron_amount,
            tax_apron2_amount,
            minimum_team_salary_amount,
            days_in_season
        FROM pcms.league_system_values
        WHERE league_lk = %(league)s
          AND salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY salary_year
    """
    rows = fetch_all(sql, {"league": league, "base_year": base_year})
    columns = [
        "league_lk",
        "salary_year",
        "salary_cap_amount",
        "tax_level_amount",
        "tax_apron_amount",
        "tax_apron2_amount",
        "minimum_team_salary_amount",
        "days_in_season",
    ]
    return columns, rows


def extract_tax_rates(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_tax_rates dataset.

    Returns (columns, rows) for DATA_tax_rates sheet.
    """
    sql = """
        SELECT
            league_lk,
            salary_year,
            ROW_NUMBER() OVER (
                PARTITION BY league_lk, salary_year
                ORDER BY lower_limit
            ) AS bracket_number,
            lower_limit,
            upper_limit,
            tax_rate_non_repeater,
            tax_rate_repeater,
            base_charge_non_repeater,
            base_charge_repeater
        FROM pcms.league_tax_rates
        WHERE league_lk = %(league)s
          AND salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY salary_year, bracket_number
    """
    rows = fetch_all(sql, {"league": league, "base_year": base_year})
    columns = [
        "league_lk",
        "salary_year",
        "bracket_number",
        "lower_limit",
        "upper_limit",
        "tax_rate_non_repeater",
        "tax_rate_repeater",
        "base_charge_non_repeater",
        "base_charge_repeater",
    ]
    return columns, rows


def extract_team_salary_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_team_salary_warehouse dataset.

    Returns (columns, rows) for DATA_team_salary_warehouse sheet.
    """
    sql = """
        SELECT
            team_code,
            salary_year,
            cap_total,
            tax_total,
            apron_total,
            cap_rost,
            cap_fa,
            cap_term,
            cap_2way,
            tax_rost,
            tax_fa,
            tax_term,
            tax_2way,
            roster_row_count,
            two_way_row_count,
            salary_cap_amount,
            tax_level_amount,
            tax_apron_amount,
            tax_apron2_amount,
            over_cap,
            room_under_tax,
            room_under_apron1,
            room_under_apron2,
            is_taxpayer,
            is_repeater_taxpayer,
            apron_level_lk
        FROM pcms.team_salary_warehouse
        WHERE salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY team_code, salary_year
    """
    rows = fetch_all(sql, {"base_year": base_year})
    columns = [
        "team_code",
        "salary_year",
        "cap_total",
        "tax_total",
        "apron_total",
        "cap_rost",
        "cap_fa",
        "cap_term",
        "cap_2way",
        "tax_rost",
        "tax_fa",
        "tax_term",
        "tax_2way",
        "roster_row_count",
        "two_way_row_count",
        "salary_cap_amount",
        "tax_level_amount",
        "tax_apron_amount",
        "tax_apron2_amount",
        "over_cap",
        "room_under_tax",
        "room_under_apron1",
        "room_under_apron2",
        "is_taxpayer",
        "is_repeater_taxpayer",
        "apron_level_lk",
    ]
    return columns, rows


def extract_salary_book_yearly(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_salary_book_yearly dataset.

    Returns (columns, rows) for DATA_salary_book_yearly sheet.
    """
    sql = """
        SELECT
            player_id,
            player_name,
            team_code,
            salary_year,
            cap_amount,
            tax_amount,
            apron_amount,
            is_two_way
        FROM pcms.salary_book_yearly
        WHERE league_lk = %(league)s
          AND salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY team_code, player_name, salary_year
    """
    rows = fetch_all(sql, {"league": league, "base_year": base_year})
    columns = [
        "player_id",
        "player_name",
        "team_code",
        "salary_year",
        "cap_amount",
        "tax_amount",
        "apron_amount",
        "is_two_way",
    ]
    return columns, rows


def extract_salary_book_warehouse(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_salary_book_warehouse dataset with relative-year columns.

    Exports salary columns as relative-year (cap_y0..cap_y5, tax_y0..tax_y5, apron_y0..apron_y5)
    based on base_year, per the data contract.

    Returns (columns, rows) for DATA_salary_book_warehouse sheet.
    """
    # Build year mapping: y0 = base_year, y1 = base_year + 1, etc.
    years = [base_year + i for i in range(6)]

    # Build dynamic column aliases for relative-year columns
    # cap_YYYY -> cap_yN, tax_YYYY -> tax_yN, apron_YYYY -> apron_yN, etc.
    def year_cols(prefix: str) -> str:
        """Generate aliased column selects for a year-based prefix."""
        return ", ".join(
            f"{prefix}_{years[i]} AS {prefix}_y{i}" for i in range(6)
        )

    sql = f"""
        SELECT
            -- Identity
            player_id,
            player_name,
            team_code,
            league_lk,
            contract_id,
            version_number,

            -- Demographics
            birth_date,
            age,
            agent_name,

            -- Two-way status
            is_two_way,

            -- Salary columns (relative years: cap_y0..cap_y5)
            {year_cols("cap")},

            -- Tax columns (relative years: tax_y0..tax_y5)
            {year_cols("tax")},

            -- Apron columns (relative years: apron_y0..apron_y5)
            {year_cols("apron")},

            -- Option columns (relative years)
            {year_cols("option")},
            {year_cols("option_decision")},

            -- Guarantee columns (relative years)
            {year_cols("guaranteed_amount")},
            {year_cols("is_fully_guaranteed")},
            {year_cols("is_partially_guaranteed")},
            {year_cols("is_non_guaranteed")},

            -- Trade fields
            is_poison_pill,
            poison_pill_amount,
            is_no_trade,
            is_trade_bonus,
            trade_bonus_percent,
            trade_kicker_display,
            player_consent_lk,
            is_trade_consent_required_now,
            is_trade_preconsented,
            trade_restriction_lookup_value,
            trade_restriction_end_date,
            is_trade_restricted_now,

            -- Contract classification
            contract_type_lookup_value,
            signed_method_lookup_value,
            exception_type_lookup_value,
            min_contract_lookup_value,
            is_min_contract

        FROM pcms.salary_book_warehouse
        WHERE league_lk = %(league)s
        ORDER BY team_code, player_name
    """
    rows = fetch_all(sql, {"league": league})

    # Define columns in the same order as SELECT (for stable contract)
    columns = [
        # Identity
        "player_id",
        "player_name",
        "team_code",
        "league_lk",
        "contract_id",
        "version_number",
        # Demographics
        "birth_date",
        "age",
        "agent_name",
        # Two-way
        "is_two_way",
    ]

    # Add relative-year salary columns
    for prefix in ["cap", "tax", "apron"]:
        for i in range(6):
            columns.append(f"{prefix}_y{i}")

    # Add relative-year option columns
    for prefix in ["option", "option_decision"]:
        for i in range(6):
            columns.append(f"{prefix}_y{i}")

    # Add relative-year guarantee columns
    for prefix in [
        "guaranteed_amount",
        "is_fully_guaranteed",
        "is_partially_guaranteed",
        "is_non_guaranteed",
    ]:
        for i in range(6):
            columns.append(f"{prefix}_y{i}")

    # Add trade and contract classification columns
    columns.extend(
        [
            "is_poison_pill",
            "poison_pill_amount",
            "is_no_trade",
            "is_trade_bonus",
            "trade_bonus_percent",
            "trade_kicker_display",
            "player_consent_lk",
            "is_trade_consent_required_now",
            "is_trade_preconsented",
            "trade_restriction_lookup_value",
            "trade_restriction_end_date",
            "is_trade_restricted_now",
            "contract_type_lookup_value",
            "signed_method_lookup_value",
            "exception_type_lookup_value",
            "min_contract_lookup_value",
            "is_min_contract",
        ]
    )

    return columns, rows


def extract_cap_holds_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_cap_holds_warehouse dataset.

    Returns (columns, rows) for DATA_cap_holds_warehouse sheet.

    Per the data contract:
    - Primary key: non_contract_amount_id
    - Filters: salary_year BETWEEN base_year AND base_year + 5
    """
    sql = """
        SELECT
            non_contract_amount_id,
            team_code,
            salary_year,
            player_id,
            player_name,
            amount_type_lk,
            cap_amount,
            tax_amount,
            apron_amount,
            free_agent_designation_lk,
            free_agent_status_lk,
            fa_amount,
            qo_amount,
            rofr_amount,
            rookie_scale_amount,
            carry_over_fa_flg,
            fa_amount_type_lk,
            min_contract_lk,
            contract_id,
            contract_type_lk,
            years_of_service
        FROM pcms.cap_holds_warehouse
        WHERE salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY team_code, salary_year, player_name
    """
    rows = fetch_all(sql, {"base_year": base_year})
    columns = [
        "non_contract_amount_id",
        "team_code",
        "salary_year",
        "player_id",
        "player_name",
        "amount_type_lk",
        "cap_amount",
        "tax_amount",
        "apron_amount",
        "free_agent_designation_lk",
        "free_agent_status_lk",
        "fa_amount",
        "qo_amount",
        "rofr_amount",
        "rookie_scale_amount",
        "carry_over_fa_flg",
        "fa_amount_type_lk",
        "min_contract_lk",
        "contract_id",
        "contract_type_lk",
        "years_of_service",
    ]
    return columns, rows


def extract_dead_money_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_dead_money_warehouse dataset.

    Returns (columns, rows) for DATA_dead_money_warehouse sheet.

    Per the data contract:
    - Primary key: transaction_waiver_amount_id
    - Filters: salary_year BETWEEN base_year AND base_year + 5
    - Used by: roster/ledger drilldowns for termination rows, buyout/waive modeling
    """
    sql = """
        SELECT
            transaction_waiver_amount_id,
            team_code,
            salary_year,
            player_id,
            player_name,
            contract_id,
            version_number,
            transaction_id,
            waive_date,
            cap_value,
            cap_change_value,
            is_cap_calculated,
            tax_value,
            tax_change_value,
            is_tax_calculated,
            apron_value,
            apron_change_value,
            is_apron_calculated,
            mts_value,
            mts_change_value,
            two_way_salary,
            two_way_nba_salary,
            two_way_dlg_salary,
            option_decision_lk
        FROM pcms.dead_money_warehouse
        WHERE salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY team_code, salary_year, player_name
    """
    rows = fetch_all(sql, {"base_year": base_year})
    columns = [
        "transaction_waiver_amount_id",
        "team_code",
        "salary_year",
        "player_id",
        "player_name",
        "contract_id",
        "version_number",
        "transaction_id",
        "waive_date",
        "cap_value",
        "cap_change_value",
        "is_cap_calculated",
        "tax_value",
        "tax_change_value",
        "is_tax_calculated",
        "apron_value",
        "apron_change_value",
        "is_apron_calculated",
        "mts_value",
        "mts_change_value",
        "two_way_salary",
        "two_way_nba_salary",
        "two_way_dlg_salary",
        "option_decision_lk",
    ]
    return columns, rows


def extract_exceptions_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_exceptions_warehouse dataset.

    Returns (columns, rows) for DATA_exceptions_warehouse sheet.

    Per the data contract:
    - Primary key: team_exception_id
    - Filters: salary_year BETWEEN base_year AND base_year + 5
    - Used by: exception inventory UI, trade planner / TPE absorption
    """
    sql = """
        SELECT
            team_exception_id,
            team_code,
            team_id,
            salary_year,
            exception_type_lk,
            exception_type_name,
            effective_date,
            expiration_date,
            original_amount,
            remaining_amount,
            trade_exception_player_id,
            trade_exception_player_name,
            record_status_lk,
            is_expired,
            proration_applies,
            proration_days,
            proration_factor,
            prorated_remaining_amount
        FROM pcms.exceptions_warehouse
        WHERE salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY team_code, salary_year, exception_type_lk, remaining_amount DESC
    """
    rows = fetch_all(sql, {"base_year": base_year})
    columns = [
        "team_exception_id",
        "team_code",
        "team_id",
        "salary_year",
        "exception_type_lk",
        "exception_type_name",
        "effective_date",
        "expiration_date",
        "original_amount",
        "remaining_amount",
        "trade_exception_player_id",
        "trade_exception_player_name",
        "record_status_lk",
        "is_expired",
        "proration_applies",
        "proration_days",
        "proration_factor",
        "prorated_remaining_amount",
    ]
    return columns, rows


def extract_draft_picks_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Extract tbl_draft_picks_warehouse dataset.

    Returns (columns, rows) for DATA_draft_picks_warehouse sheet.

    Per the data contract:
    - Filters: draft_year >= base_year (future picks only)
    - Primary key: (team_code, draft_year, draft_round, asset_slot)
    - Used by: assets dashboard
    """
    sql = """
        SELECT
            team_id,
            team_code,
            draft_year,
            draft_round,
            asset_slot,
            asset_type,
            raw_round_text,
            raw_fragment,
            is_forfeited,
            is_conditional_text,
            is_swap_text,
            needs_review,
            refreshed_at
        FROM pcms.draft_picks_warehouse
        WHERE draft_year >= %(base_year)s
        ORDER BY team_code, draft_year, draft_round, asset_slot
    """
    rows = fetch_all(sql, {"base_year": base_year})
    columns = [
        "team_id",
        "team_code",
        "draft_year",
        "draft_round",
        "asset_slot",
        "asset_type",
        "raw_round_text",
        "raw_fragment",
        "is_forfeited",
        "is_conditional_text",
        "is_swap_text",
        "needs_review",
        "refreshed_at",
    ]
    return columns, rows
