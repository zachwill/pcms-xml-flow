\set ON_ERROR_STOP on
\timing on

-- Basic presence + invariants
\ir 000_smoke.sql

-- Warehouse invariants
\ir 010_salary_book_warehouse_multi_contract_assertions.sql
\ir 020_exceptions_warehouse_assertions.sql

-- Trade primitives invariants
\ir 030_trade_primitives_assertions.sql

-- Trade planner MVP (TPE-only)
\ir 040_trade_planner_tpe_assertions.sql
\ir 041_trade_planner_tpe_multi_absorb_assertions.sql

-- Draft assets (picks + rights)
\ir 051_draft_picks_warehouses_assertions.sql
\ir 052_player_rights_warehouse_assertions.sql
