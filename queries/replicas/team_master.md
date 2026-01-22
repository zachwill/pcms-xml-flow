# replicas/team_master

Goal: replicate Team Master’s “big picture” blocks:

- roster salary grid (same as Playground)
- single-year KPIs vs cap/tax/aprons
- repeater status for multiple years
- draft-pick inventory (from our draft tables)

## Approach

Compose:

1) `playground_salary_book` (roster grid)
2) `league_system_values` (thresholds)
3) `tax_team_status` (repeater flags)
4) “dead money” export (waiver amounts)
5) draft picks (see `DRAFT_PICKS.md` + `pcms.draft_*` tables)

## KPI query sketch

```sql
SELECT
  yw.team_code,
  2025 AS salary_year,
  SUM(yw.cap_2025) AS total_cap,
  SUM(yw.tax_2025) AS total_tax,
  SUM(yw.apron_2025) AS total_apron,
  lsv.salary_cap_amount,
  lsv.tax_level_amount,
  lsv.tax_apron_amount,
  lsv.tax_apron2_amount
FROM pcms.vw_y_warehouse yw
JOIN pcms.league_system_values lsv
  ON lsv.league_lk = 'NBA' AND lsv.salary_year = 2025
WHERE yw.team_code = ${TEAM_CODE}
GROUP BY 1,2, lsv.salary_cap_amount, lsv.tax_level_amount, lsv.tax_apron_amount, lsv.tax_apron2_amount;
```

## Notes

- Sean’s sheets add “vet mins” to reach roster size 14 — implement in app logic.
