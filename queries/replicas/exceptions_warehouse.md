# replicas/exceptions_warehouse

Goal: reproduce the “Exceptions Warehouse” block used in Trade tools.

## Output shape

- team_code
- salary_year
- exception_type_lk (+ description)
- original_amount
- remaining_amount
- effective_date
- expiration_date
- trade_exception_player_name (if present)

## Query sketch

```sql
SELECT
  te.team_code,
  te.salary_year,
  te.exception_type_lk,
  l.description AS exception_type_name,
  te.original_amount,
  te.remaining_amount,
  te.effective_date,
  te.expiration_date,
  te.trade_exception_player_id,
  p.last_name || ', ' || p.first_name AS trade_exception_player_name
FROM pcms.team_exceptions te
LEFT JOIN pcms.lookups l
  ON l.lookup_type = 'EXCEPTION_TYPE' AND l.lookup_code = te.exception_type_lk
LEFT JOIN pcms.people p
  ON p.person_id = te.trade_exception_player_id
WHERE te.record_status_lk = 'ACT'
ORDER BY te.team_code, te.salary_year, te.remaining_amount DESC;
```
