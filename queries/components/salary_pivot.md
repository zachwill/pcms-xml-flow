# components/salary_pivot

Pivot `pcms.salaries` into a wide (warehouse-friendly) format.

## Method A (recommended): fixed-year pivot (2024–2030)

```sql
WITH salary_pivot AS (
  SELECT
    s.contract_id,
    s.version_number,

    -- cap (Sean’s primary “salary”)
    MAX(CASE WHEN s.salary_year = 2024 THEN s.contract_cap_salary END) AS cap_2024,
    MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_cap_salary END) AS cap_2025,
    MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_cap_salary END) AS cap_2026,
    MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_cap_salary END) AS cap_2027,
    MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_cap_salary END) AS cap_2028,
    MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_cap_salary END) AS cap_2029,
    MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_cap_salary END) AS cap_2030,

    -- tax / apron
    MAX(CASE WHEN s.salary_year = 2024 THEN s.contract_tax_salary END) AS tax_2024,
    MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_tax_salary END) AS tax_2025,
    MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_tax_salary END) AS tax_2026,
    MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_tax_salary END) AS tax_2027,
    MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_tax_salary END) AS tax_2028,
    MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_tax_salary END) AS tax_2029,
    MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_tax_salary END) AS tax_2030,

    MAX(CASE WHEN s.salary_year = 2024 THEN s.contract_tax_apron_salary END) AS apron_2024,
    MAX(CASE WHEN s.salary_year = 2025 THEN s.contract_tax_apron_salary END) AS apron_2025,
    MAX(CASE WHEN s.salary_year = 2026 THEN s.contract_tax_apron_salary END) AS apron_2026,
    MAX(CASE WHEN s.salary_year = 2027 THEN s.contract_tax_apron_salary END) AS apron_2027,
    MAX(CASE WHEN s.salary_year = 2028 THEN s.contract_tax_apron_salary END) AS apron_2028,
    MAX(CASE WHEN s.salary_year = 2029 THEN s.contract_tax_apron_salary END) AS apron_2029,
    MAX(CASE WHEN s.salary_year = 2030 THEN s.contract_tax_apron_salary END) AS apron_2030,

    -- options
    MAX(CASE WHEN s.salary_year = 2024 THEN s.option_lk END) AS option_2024,
    MAX(CASE WHEN s.salary_year = 2025 THEN s.option_lk END) AS option_2025,
    MAX(CASE WHEN s.salary_year = 2026 THEN s.option_lk END) AS option_2026,
    MAX(CASE WHEN s.salary_year = 2027 THEN s.option_lk END) AS option_2027,
    MAX(CASE WHEN s.salary_year = 2028 THEN s.option_lk END) AS option_2028,
    MAX(CASE WHEN s.salary_year = 2029 THEN s.option_lk END) AS option_2029,
    MAX(CASE WHEN s.salary_year = 2030 THEN s.option_lk END) AS option_2030,

    MAX(CASE WHEN s.salary_year = 2024 THEN s.option_decision_lk END) AS option_decision_2024,
    MAX(CASE WHEN s.salary_year = 2025 THEN s.option_decision_lk END) AS option_decision_2025,
    MAX(CASE WHEN s.salary_year = 2026 THEN s.option_decision_lk END) AS option_decision_2026,
    MAX(CASE WHEN s.salary_year = 2027 THEN s.option_decision_lk END) AS option_decision_2027,
    MAX(CASE WHEN s.salary_year = 2028 THEN s.option_decision_lk END) AS option_decision_2028,
    MAX(CASE WHEN s.salary_year = 2029 THEN s.option_decision_lk END) AS option_decision_2029,
    MAX(CASE WHEN s.salary_year = 2030 THEN s.option_decision_lk END) AS option_decision_2030,

    -- trade bonus amount (best-effort)
    MAX(CASE WHEN s.salary_year = 2024 THEN s.trade_bonus_amount_calc END) AS trade_bonus_amount_2024,
    MAX(CASE WHEN s.salary_year = 2025 THEN s.trade_bonus_amount_calc END) AS trade_bonus_amount_2025,
    MAX(CASE WHEN s.salary_year = 2026 THEN s.trade_bonus_amount_calc END) AS trade_bonus_amount_2026,

    -- totals
    SUM(s.total_salary) AS total_salary_all_years
  FROM pcms.salaries s
  GROUP BY 1, 2
)
SELECT * FROM salary_pivot;
```

## Method B: “tall” output (preferred for BI)

Instead of pivoting, return one row per `(contract_id, version_number, salary_year)` and let BI/pandas pivot.

## Known gaps

- Sean’s “Total remaining value” is anchored (X vs Y) and may exclude past years.
  - We can compute both: `total_from_2024`, `total_from_2025`, etc.
