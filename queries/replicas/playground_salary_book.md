# replicas/playground_salary_book (Salary Book / Playground)

Goal: reproduce the roster + multi-year salary grid that Sean’s `Playground.txt` shows.

This is primarily a **team-filtered view** over the **Y warehouse**.

## Key behaviors

- Filter to one `team_code` (selected team).
- Sort roster descending by anchor year cap salary (usually 2025).
- Display salaries for 2025–2030.
- Include trade-kicker / flags.
- Provide KPI inputs: cap/tax/aprons per year.

## Method A (recommended): query over a Y-warehouse view

Once we have `pcms.vw_y_warehouse` (or an inline query), then:

```sql
SELECT
  player_name,
  team_code,
  cap_2025, cap_2026, cap_2027, cap_2028, cap_2029, cap_2030,
  option_2025, option_2026, option_2027, option_2028, option_2029, option_2030,
  trade_bonus_percent,
  tax_2025, tax_2026, tax_2027, tax_2028, tax_2029, tax_2030,
  apron_2025, apron_2026, apron_2027, apron_2028, apron_2029, apron_2030
FROM pcms.vw_y_warehouse
WHERE team_code = ${TEAM_CODE}
ORDER BY cap_2025 DESC NULLS LAST, player_name;
```

## Method B: roster derived from `team_budget_snapshots`

If “current team” assignment is unreliable in `people.team_code`, treat the roster as:

- “players with latest `team_budget_snapshots` row for a given `salary_year` and team”

Sketch:

```sql
WITH latest_budget AS (
  SELECT
    tbs.*, 
    ROW_NUMBER() OVER (
      PARTITION BY team_id, salary_year, player_id
      ORDER BY ledger_date DESC NULLS LAST, team_budget_snapshot_id DESC
    ) AS rn
  FROM pcms.team_budget_snapshots tbs
  WHERE salary_year = 2025
)
SELECT *
FROM latest_budget
WHERE rn = 1 AND team_code = ${TEAM_CODE};
```

## Dead money (row 24)

Best-effort sources:

1) `pcms.transaction_waiver_amounts` aggregated by team + year
2) `pcms.team_budget_snapshots` where `budget_group_lk` implies dead money

## KPI constants (cap/tax/aprons)

From `pcms.league_system_values` by year:
- salary_cap_amount
- tax_level_amount
- tax_apron_amount
- tax_apron2_amount

Plus repeater status from `pcms.tax_team_status`.
