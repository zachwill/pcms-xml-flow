"""
Dataset extraction functions per the data contract.

Each function returns rows suitable for writing to a DATA_* sheet.

See: reference/blueprints/data-contract.md
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .db import fetch_all


@dataclass
class DatasetExtractError(Exception):
    """Raised when a dataset fails to extract, but we still know its schema.

    build_capbook() uses this to:
      - mark META.validation_status = FAILED
      - still emit a workbook artifact
      - still create the Excel Table with the correct headers (empty rows)

    Attributes:
        dataset_name: Stable dataset identifier (e.g., "tax_rates")
        columns: Column headers that would have been exported
        original: The original exception
    """

    dataset_name: str
    columns: list[str]
    original: Exception

    def __str__(self) -> str:  # pragma: no cover
        return f"{self.dataset_name}: {self.original}"


def extract_system_values(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_system_values dataset (DATA_system_values).

    Includes CBA thresholds and key exception amounts (MLE, BAE, TPE, etc.)
    per the data contract.
    """

    columns = [
        "league_lk",
        "salary_year",
        # Thresholds
        "salary_cap_amount",
        "tax_level_amount",
        "tax_apron_amount",
        "tax_apron2_amount",
        "minimum_team_salary_amount",
        # Exception amounts
        "non_taxpayer_mid_level_amount",
        "taxpayer_mid_level_amount",
        "room_mid_level_amount",
        "bi_annual_amount",
        "tpe_dollar_allowance",
        # Two-way amounts
        "two_way_salary_amount",
        "two_way_dlg_salary_amount",
        # Salary limits
        "maximum_salary_25_pct",
        "maximum_salary_30_pct",
        "maximum_salary_35_pct",
        "average_salary_amount",
        "max_trade_cash_amount",
        # Season calendar (league year + regular season)
        "days_in_season",
        "season_start_at",
        "season_end_at",
        "playing_start_at",
        "playing_end_at",
    ]

    sql = """
        SELECT
            league_lk,
            salary_year,
            -- Thresholds
            salary_cap_amount,
            tax_level_amount,
            tax_apron_amount,
            tax_apron2_amount,
            minimum_team_salary_amount,
            -- Exception amounts
            non_taxpayer_mid_level_amount,
            taxpayer_mid_level_amount,
            room_mid_level_amount,
            bi_annual_amount,
            tpe_dollar_allowance,
            -- Two-way amounts
            two_way_salary_amount,
            two_way_dlg_salary_amount,
            -- Salary limits
            maximum_salary_25_pct,
            maximum_salary_30_pct,
            maximum_salary_35_pct,
            average_salary_amount,
            max_trade_cash_amount,
            -- Season calendar
            days_in_season,
            season_start_at,
            season_end_at,
            playing_start_at,
            playing_end_at
        FROM pcms.league_system_values
        WHERE league_lk = %(league)s
          AND salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY salary_year
    """

    try:
        rows = fetch_all(sql, {"league": league, "base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("system_values", columns, e) from e

    return columns, rows


def extract_tax_rates(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_tax_rates dataset (DATA_tax_rates)."""

    columns = [
        "league_lk",
        "salary_year",
        # Derived for UI convenience (stable ordering of brackets)
        "ui_bracket_number",
        "lower_limit",
        "upper_limit",
        "tax_rate_non_repeater",
        "tax_rate_repeater",
        "base_charge_non_repeater",
        "base_charge_repeater",
    ]

    sql = """
        SELECT
            league_lk,
            salary_year,
            ROW_NUMBER() OVER (
                PARTITION BY league_lk, salary_year
                ORDER BY lower_limit
            ) AS ui_bracket_number,
            lower_limit,
            upper_limit,
            tax_rate_non_repeater,
            tax_rate_repeater,
            base_charge_non_repeater,
            base_charge_repeater
        FROM pcms.league_tax_rates
        WHERE league_lk = %(league)s
          AND salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY salary_year, ui_bracket_number
    """

    try:
        rows = fetch_all(sql, {"league": league, "base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("tax_rates", columns, e) from e

    return columns, rows


def extract_team_salary_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_team_salary_warehouse dataset (DATA_team_salary_warehouse)."""

    columns = [
        "team_code",
        "salary_year",
        "cap_total",
        "cap_total_hold",
        "tax_total",
        "apron_total",
        "cap_rost",
        "cap_rost_hold",
        "cap_fa",
        "cap_term",
        "cap_2way",
        "tax_rost",
        "tax_fa",
        "tax_term",
        "tax_2way",
        "apron_rost",
        "apron_fa",
        "apron_term",
        "apron_2way",
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

    sql = """
        SELECT
            team_code,
            salary_year,
            cap_total,
            cap_total_hold,
            tax_total,
            apron_total,
            cap_rost,
            cap_rost_hold,
            cap_fa,
            cap_term,
            cap_2way,
            tax_rost,
            tax_fa,
            tax_term,
            tax_2way,
            apron_rost,
            apron_fa,
            apron_term,
            apron_2way,
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

    try:
        rows = fetch_all(sql, {"base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("team_salary_warehouse", columns, e) from e

    return columns, rows


def extract_salary_book_yearly(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_salary_book_yearly dataset (DATA_salary_book_yearly).

    Note: We intentionally do NOT filter by league_lk here. The salary_book
    tables contain NBA players, but some may be temporarily assigned to
    G League (league_lk='DLG'). Filtering by league would exclude them.
    """

    columns = [
        "player_id",
        "player_name",
        "team_code",
        "salary_year",
        "cap_amount",
        "tax_amount",
        "apron_amount",
        "is_two_way",
        # Trade-context amounts (includes trade bonus/kicker where applicable)
        "incoming_cap_amount",
        "incoming_tax_amount",
        "outgoing_apron_amount",
        "incoming_apron_amount",
    ]

    sql = """
        SELECT
            player_id,
            player_name,
            team_code,
            salary_year,
            cap_amount,
            tax_amount,
            apron_amount,
            is_two_way,
            incoming_cap_amount,
            incoming_tax_amount,
            outgoing_apron_amount,
            incoming_apron_amount
        FROM pcms.salary_book_yearly
        WHERE salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY team_code, player_name, salary_year
    """

    try:
        rows = fetch_all(sql, {"base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("salary_book_yearly", columns, e) from e

    return columns, rows


def extract_salary_book_warehouse(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_salary_book_warehouse dataset (DATA_salary_book_warehouse).

    This is intended to be a near 1:1 mirror of `pcms.salary_book_warehouse`.

    Key rule:
      - **No renamed columns.** We do not alias years into cap_y0/cap_y1/etc.
        Excel column headers should match Postgres column names.

    Note:
      - `base_year` is currently unused for this dataset. The underlying
        warehouse is a wide table with explicit year columns (e.g. cap_2025).
        The workbook's year-aware UI should generally use
        `tbl_salary_book_yearly` instead.
      - We intentionally do NOT filter by league_lk. The salary_book tables
        contain NBA players, but some may be temporarily assigned to G League
        (league_lk='DLG'). Filtering by league would exclude them.
    """

    # Discover columns directly from Postgres so Excel mirrors the warehouse.
    columns_sql = """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'pcms'
          AND table_name = 'salary_book_warehouse'
        ORDER BY ordinal_position
    """

    try:
        col_rows = fetch_all(columns_sql)
        columns = [r["column_name"] for r in col_rows]
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("salary_book_warehouse", [], e) from e

    if not columns:
        raise DatasetExtractError(
            "salary_book_warehouse",
            [],
            RuntimeError("No columns found for pcms.salary_book_warehouse"),
        )

    select_cols = ", ".join(f'"{c}"' for c in columns)
    sql = f"""
        SELECT {select_cols}
        FROM pcms.salary_book_warehouse
        ORDER BY team_code, player_name
    """

    try:
        rows = fetch_all(sql)
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("salary_book_warehouse", columns, e) from e

    return columns, rows


def extract_cap_holds_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_cap_holds_warehouse dataset (DATA_cap_holds_warehouse)."""

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

    try:
        rows = fetch_all(sql, {"base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("cap_holds_warehouse", columns, e) from e

    return columns, rows


def extract_dead_money_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_dead_money_warehouse dataset (DATA_dead_money_warehouse)."""

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

    try:
        rows = fetch_all(sql, {"base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("dead_money_warehouse", columns, e) from e

    return columns, rows


def extract_exceptions_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_exceptions_warehouse dataset (DATA_exceptions_warehouse)."""

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

    try:
        rows = fetch_all(sql, {"base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("exceptions_warehouse", columns, e) from e

    return columns, rows


def extract_draft_picks_warehouse(
    base_year: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_draft_picks_warehouse dataset (DATA_draft_picks_warehouse)."""

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

    try:
        rows = fetch_all(sql, {"base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("draft_picks_warehouse", columns, e) from e

    return columns, rows


def extract_rookie_scale(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_rookie_scale dataset (DATA_rookie_scale).

    Rookie scale amounts by pick number and contract year (1-4).
    The DB stores salary_year_1..salary_year_4 and option amounts.
    We export one row per pick with all 4 contract year amounts.
    """

    columns = [
        "salary_year",
        "league_lk",
        "pick_number",
        "salary_year_1",
        "salary_year_2",
        "salary_year_3",
        "salary_year_4",
        "option_amount_year_3",
        "option_amount_year_4",
        "is_baseline_scale",
    ]

    sql = """
        SELECT
            salary_year,
            league_lk,
            pick_number,
            salary_year_1,
            salary_year_2,
            salary_year_3,
            salary_year_4,
            option_amount_year_3,
            option_amount_year_4,
            is_baseline_scale
        FROM pcms.rookie_scale_amounts
        WHERE league_lk = %(league)s
          AND salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
          AND is_active = TRUE
        ORDER BY salary_year, pick_number
    """

    try:
        rows = fetch_all(sql, {"league": league, "base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("rookie_scale", columns, e) from e

    return columns, rows


def extract_minimum_scale(
    base_year: int, league: str = "NBA"
) -> tuple[list[str], list[dict[str, Any]]]:
    """Extract tbl_minimum_scale dataset (DATA_minimum_scale).

    Minimum salary by years of service.
    """

    columns = [
        "salary_year",
        "league_lk",
        "years_of_service",
        "minimum_salary_amount",
    ]

    sql = """
        SELECT
            salary_year,
            league_lk,
            years_of_service,
            minimum_salary_amount
        FROM pcms.league_salary_scales
        WHERE league_lk = %(league)s
          AND salary_year BETWEEN %(base_year)s AND %(base_year)s + 5
        ORDER BY salary_year, years_of_service
    """

    try:
        rows = fetch_all(sql, {"league": league, "base_year": base_year})
    except Exception as e:  # noqa: BLE001
        raise DatasetExtractError("minimum_scale", columns, e) from e

    return columns, rows
