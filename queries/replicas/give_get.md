# replicas/give_get

Goal: reproduce data requirements for `Give Get.txt` (multi-team trade sandbox):

- team roster cap/tax/apron values for selected year
- team-level before/after totals
- team exceptions list
- dead money per team/year

## Method A (recommended): treat as an application workflow

Give/Get is interactive; split into:

1) SQL exports (static reference)
   - X warehouse (2024)
   - Y warehouse (2025+)
   - exceptions warehouse
   - team tax status
   - league system values

2) App logic
   - user enters give/get lists
   - compute totals + trade validity

## Exceptions warehouse query sketch

```sql
SELECT
  te.team_code,
  te.salary_year,
  te.exception_type_lk,
  te.original_amount,
  te.remaining_amount,
  te.expiration_date
FROM pcms.team_exceptions te
WHERE te.record_status_lk = 'ACT'
  AND te.remaining_amount > 0;
```

## Dead money (best effort)

```sql
SELECT
  team_code,
  salary_year,
  SUM(cap_change_value) AS dead_money_cap
FROM pcms.transaction_waiver_amounts
GROUP BY 1,2;
```

(We need to confirm sign conventions.)
