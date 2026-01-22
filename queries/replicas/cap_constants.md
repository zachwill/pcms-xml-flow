# replicas/cap_constants

Goal: provide the cap/tax/apron constants block used in X/Y warehouses.

Source table: `pcms.league_system_values`.

## Query sketch

```sql
SELECT
  salary_year AS cap_year,
  average_salary_amount AS avg_salary,
  salary_cap_amount AS cap_level,
  tax_level_amount AS tax_level,
  tax_apron_amount AS apron_1,
  minimum_team_salary_amount AS minimum_level,
  bi_annual_amount AS bi_annual,
  non_taxpayer_mid_level_amount AS non_taxpayer_mle,
  taxpayer_mid_level_amount AS taxpayer_mle,
  room_mid_level_amount AS room_mle,
  maximum_salary_25_pct AS max_0_6,
  maximum_salary_30_pct AS max_7_9,
  maximum_salary_35_pct AS max_10_plus,
  tax_apron2_amount AS apron_2
FROM pcms.league_system_values
WHERE league_lk = 'NBA'
  AND salary_year BETWEEN 2019 AND 2031
ORDER BY salary_year;
```
