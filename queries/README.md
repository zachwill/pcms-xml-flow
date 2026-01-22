# queries/

This directory is for **replica query plans** that aim to reproduce Sean’s spreadsheet “warehouses” and tools (X, Y, Playground/Salary Book, Trade Machine, Give/Get, Team Master, Depth Chart) using our **pcms** Postgres schema.

We’re **not** committing to a single “one true SQL export” yet—these docs describe **multiple methods** (views, materialized views, ad-hoc exports) so we can iterate while ingestion is incomplete.

## Ground rules

- Assume ingestion may be partial (some tables empty). Each replica spec notes **fallbacks**.
- Prefer **building-block CTEs/views** that can be reused across tools.
- Prefer **one row per player** (warehouse style) for analyst-facing exports.
- “Active contract” is usually `pcms.contracts.record_status_lk IN ('APPR', 'FUTR')` and **latest version_number** per contract.

## Recommended build order

1. `components/active_contracts.md`
2. `components/salary_pivot.md`
3. `replicas/y_warehouse.md` (drives Salary Book)
4. `replicas/playground_salary_book.md`
5. `replicas/x_warehouse.md` (drives trade tools)
6. `replicas/trade_machine.md` and `replicas/give_get.md`

## Output philosophy

- Replica exports should be stable and spreadsheet-friendly.
- If a field is not available (e.g., some trade-math nuances), output `NULL` plus a comment in the plan.
