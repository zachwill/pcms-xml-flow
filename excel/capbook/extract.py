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
            bracket_number,
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


# TODO: Implement remaining extract functions per data contract:
# - extract_salary_book_warehouse (wide, with relative-year columns)
# - extract_cap_holds_warehouse
# - extract_dead_money_warehouse
# - extract_exceptions_warehouse
# - extract_draft_picks_warehouse
