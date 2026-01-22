# replicas/rookie_scale

Goal: reproduce the rookie-scale blocks used in Y warehouse.

Source table: `pcms.rookie_scale_amounts`.

## Query sketch

```sql
SELECT
  salary_year,
  pick_number,
  salary_year_1,
  salary_year_2,
  salary_year_3,
  salary_year_4,
  option_amount_year_3,
  option_amount_year_4,
  option_pct_year_3,
  option_pct_year_4,
  is_baseline_scale
FROM pcms.rookie_scale_amounts
WHERE league_lk = 'NBA'
  AND salary_year BETWEEN 2024 AND 2030
ORDER BY salary_year, pick_number;
```
