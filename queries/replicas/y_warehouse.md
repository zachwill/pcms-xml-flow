# replicas/y_warehouse ("Y.txt")

Goal: produce a **forward-looking** warehouse used by Salary Book (Playground), Team Master, and long-term planning.

Sean’s Y sheet is anchored on **2025** salaries (2025–2030 grid).

## Output shape (minimum viable)

One row per player (NBA players only):

- Identity: `player_name (Last, First)`, `team_code` (prefer active contract team_code; `people.team_code` can be blank), `birth_date`, `age`, `agent_name`
- Salaries: `cap_2025..cap_2030`
- Cap %: `pct_cap_2025..pct_cap_2030`
- Options: `option_2025..option_2030` (+ decision fields)
- Trade flags: `trade_bonus_percent`, `is_no_trade`, `is_poison_pill`, `trade_kicker_amount_2025` (best-effort)
- Tax/apron: `tax_2025..tax_2030`, `apron_2025..apron_2030`

## Method A (recommended): assemble from components

Building blocks:
- `components/active_contracts.md`
- `components/salary_pivot.md`

```sql
WITH ac AS (
  /* paste active contract/version selector here */
),
sp AS (
  /* paste salary pivot here */
)
SELECT
  p.person_id AS player_id,
  p.last_name || ', ' || p.first_name AS player_name,
  COALESCE(ac.team_code, p.team_code) AS team_code,
  p.birth_date,
  DATE_PART('year', AGE(p.birth_date))::int AS age,
  ag.full_name AS agent_name,

  -- cap salaries (the Y grid)
  sp.cap_2025, sp.cap_2026, sp.cap_2027, sp.cap_2028, sp.cap_2029, sp.cap_2030,

  -- % of cap
  (sp.cap_2025::numeric / NULLIF(lsv_2025.salary_cap_amount, 0)) AS pct_cap_2025,
  (sp.cap_2026::numeric / NULLIF(lsv_2026.salary_cap_amount, 0)) AS pct_cap_2026,
  (sp.cap_2027::numeric / NULLIF(lsv_2027.salary_cap_amount, 0)) AS pct_cap_2027,
  (sp.cap_2028::numeric / NULLIF(lsv_2028.salary_cap_amount, 0)) AS pct_cap_2028,
  (sp.cap_2029::numeric / NULLIF(lsv_2029.salary_cap_amount, 0)) AS pct_cap_2029,
  (sp.cap_2030::numeric / NULLIF(lsv_2030.salary_cap_amount, 0)) AS pct_cap_2030,

  -- options
  sp.option_2025, sp.option_2026, sp.option_2027, sp.option_2028, sp.option_2029, sp.option_2030,
  sp.option_decision_2025, sp.option_decision_2026, sp.option_decision_2027,
  sp.option_decision_2028, sp.option_decision_2029, sp.option_decision_2030,

  -- trade flags (best effort)
  ac.trade_bonus_percent,
  ac.is_no_trade,
  ac.is_poison_pill,
  sp.trade_bonus_amount_2025 AS trade_kicker_amount_2025,

  -- tax/apron
  sp.tax_2025, sp.tax_2026, sp.tax_2027, sp.tax_2028, sp.tax_2029, sp.tax_2030,
  sp.apron_2025, sp.apron_2026, sp.apron_2027, sp.apron_2028, sp.apron_2029, sp.apron_2030

FROM pcms.people p
LEFT JOIN ac ON ac.player_id = p.person_id
LEFT JOIN sp ON sp.contract_id = ac.contract_id AND sp.version_number = ac.version_number
LEFT JOIN pcms.agents ag ON ag.agent_id = p.agent_id

-- cap constants per year for % calcs
LEFT JOIN pcms.league_system_values lsv_2025 ON lsv_2025.league_lk = 'NBA' AND lsv_2025.salary_year = 2025
LEFT JOIN pcms.league_system_values lsv_2026 ON lsv_2026.league_lk = 'NBA' AND lsv_2026.salary_year = 2026
LEFT JOIN pcms.league_system_values lsv_2027 ON lsv_2027.league_lk = 'NBA' AND lsv_2027.salary_year = 2027
LEFT JOIN pcms.league_system_values lsv_2028 ON lsv_2028.league_lk = 'NBA' AND lsv_2028.salary_year = 2028
LEFT JOIN pcms.league_system_values lsv_2029 ON lsv_2029.league_lk = 'NBA' AND lsv_2029.salary_year = 2029
LEFT JOIN pcms.league_system_values lsv_2030 ON lsv_2030.league_lk = 'NBA' AND lsv_2030.salary_year = 2030

WHERE p.person_type_lk = 'PLYR'
  AND p.league_lk = 'NBA';
```

### Best-effort trade-math columns (Z–AG area)

We can approximate outgoing/incoming “buildup” for 2025 as:

- `outgoing_buildup_2025 = cap_2025`
- `incoming_buildup_2025 = cap_2025 + trade_kicker_amount_2025`

…but note this is not CBA-perfect (poison pill/base-year can matter).

## Fallbacks when data is missing

- If `pcms.salaries` is empty: output identity + null salary columns.
- If `pcms.agents` is empty: agent_name null.
- If `pcms.league_system_values` is empty: pct_cap columns null.
