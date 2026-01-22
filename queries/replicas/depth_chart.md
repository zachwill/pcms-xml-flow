# replicas/depth_chart

Goal: provide the data backbone for a depth chart tool.

We have a dedicated table: `pcms.depth_charts`.

## Method A (recommended): query `pcms.depth_charts`

```sql
SELECT
  team_code,
  salary_year,
  chart_type_lk,
  position_lk,
  depth_rank,
  p.last_name || ', ' || p.first_name AS player_name,
  roster_status_lk,
  role_lk,
  is_starter,
  notes
FROM pcms.depth_charts dc
LEFT JOIN pcms.people p ON p.person_id = dc.person_id
WHERE dc.team_code = ${TEAM_CODE}
  AND dc.salary_year IN (2025, 2026)
ORDER BY dc.salary_year, dc.chart_type_lk, dc.position_lk, dc.depth_rank;
```

## Method B (fallback)

If `depth_charts` is empty, we can only provide roster salaries; user places players manually.
