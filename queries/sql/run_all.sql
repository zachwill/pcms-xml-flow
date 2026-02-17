\set ON_ERROR_STOP on
\timing on

-- Basic presence + invariants
\ir 000_smoke.sql

-- Warehouse invariants
\ir 064_people_team_from_transactions_assertions.sql
\ir 010_salary_book_warehouse_multi_contract_assertions.sql
\ir 061_salary_book_min_contract_assertions.sql
\ir 065_cap_holds_and_salary_book_hold_columns_assertions.sql
\ir 066_agents_and_agencies_warehouse_assertions.sql
\ir 071_representation_nonzero_percentiles_assertions.sql
\ir 067_team_salary_percentiles_assertions.sql
\ir 072_dead_money_warehouse_assertions.sql
\ir 073_salary_book_two_way_overlay_assertions.sql
\ir 074_salary_book_team_assignment_assertions.sql
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
\ir 060_draft_pick_summary_assets_assertions.sql
\ir 052_player_rights_warehouse_assertions.sql
\ir 075_player_rights_trade_direction_assertions.sql
\ir 059_draft_pick_shorthand_assets_assertions.sql
\ir 062_draft_pick_assets_views_assertions.sql
\ir 063_draft_pick_assets_display_text_direction_assertions.sql

-- Luxury tax primitives
\ir 055_luxury_tax_assertions.sql

-- NBA shot chart
\ir 070_nba_shot_chart_assertions.sql
