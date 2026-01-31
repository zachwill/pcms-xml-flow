\set ON_ERROR_STOP on
\timing on

-- Basic presence + invariants
\ir 000_smoke.sql

-- Warehouse invariants
\ir 010_salary_book_warehouse_multi_contract_assertions.sql
\ir 020_exceptions_warehouse_assertions.sql
\ir 054_exceptions_warehouse_proration_assertions.sql

-- Trade primitives invariants
\ir 030_trade_primitives_assertions.sql
\ir 056_can_bring_back_assertions.sql

-- Minimum salary primitives
\ir 057_minimum_salary_assertions.sql

-- Buyout / waiver primitives
\ir 058_buyout_primitives_assertions.sql

-- Trade planner MVP (TPE-only)
\ir 040_trade_planner_tpe_assertions.sql
\ir 041_trade_planner_tpe_multi_absorb_assertions.sql

-- Endnotes (curated pick/trade annotations)
\ir 050_endnotes_assertions.sql

-- Draft assets (picks + rights)
\ir 051_draft_picks_warehouses_assertions.sql
\ir 052_player_rights_warehouse_assertions.sql
\ir 053_draft_assets_warehouse_assertions.sql

-- Luxury tax primitives
\ir 055_luxury_tax_assertions.sql
