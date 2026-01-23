-- 052_player_rights_warehouse_assertions.sql

-- Basic existence
SELECT 1 AS ok
FROM information_schema.tables
WHERE table_schema='pcms' AND table_name='player_rights_warehouse';

-- Rowcount sanity
SELECT
  COUNT(*) AS rights_rows
FROM pcms.player_rights_warehouse;

-- No blank rights_team_code for NBA draft rights (allow some nulls if we truly can't resolve)
SELECT
  COUNT(*) AS blank_rights_team_code
FROM pcms.player_rights_warehouse
WHERE rights_kind='NBA_DRAFT_RIGHTS'
  AND (rights_team_code IS NULL OR rights_team_code='');

-- Spot check: Daniel Diez should have NYK rights after the 2024-06-27 DRLST trade
SELECT
  player_id,
  player_name,
  rights_team_code,
  rights_source,
  source_trade_id,
  source_trade_date
FROM pcms.player_rights_warehouse
WHERE player_id=1626229;
