# Next steps checklist

1) Decide if we want to formalize analyst-facing views:
   - `pcms.vw_y_warehouse`
   - `pcms.vw_x_warehouse`
   - `pcms.vw_exceptions_warehouse`

2) Decide where to compute trade matching bands:
   - SQL table `pcms.trade_rules` (recommended)
   - or app-layer constants

3) Confirm roster source of truth:
   - `people.team_code` vs `team_budget_snapshots`

4) Confirm dead money source/sign convention:
   - `transaction_waiver_amounts.cap_change_value`

5) After ingestion, validate:
   - row counts
   - sanity checks on known salaries
   - team totals vs third-party references
