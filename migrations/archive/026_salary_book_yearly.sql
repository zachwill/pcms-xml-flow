-- 026_salary_book_yearly.sql
--
-- Helper view + functions for trade tooling.
--
-- Purpose:
-- - `pcms.salary_book_warehouse` is wide (cap_2025, cap_2026, ...).
-- - For trade/apron math we want a one-row-per-(player_id, salary_year) shape.
--
-- This is *not* a tool-facing cache table, so we intentionally do NOT use a
-- `_warehouse` suffix.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Unpivot salary_book_warehouse to yearly rows
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW pcms.salary_book_yearly AS
SELECT
  sbw.player_id,
  sbw.player_name,
  sbw.league_lk,

  sbw.team_code,
  sbw.contract_team_code,
  sbw.person_team_code,

  sbw.contract_id,
  sbw.version_number,

  2025 AS salary_year,

  sbw.cap_2025  AS cap_amount,
  sbw.tax_2025  AS tax_amount,
  sbw.apron_2025 AS apron_amount,

  -- Trade-context amounts (when available)
  COALESCE(sbw.outgoing_buildup_2025, sbw.apron_2025) AS outgoing_apron_amount,
  COALESCE(sbw.incoming_apron_2025, sbw.apron_2025)  AS incoming_apron_amount,

  -- Trade-context cap/tax amounts (only present for 2025 today; fall back to cap/tax)
  COALESCE(sbw.incoming_salary_2025, sbw.cap_2025) AS incoming_cap_amount,
  COALESCE(sbw.incoming_tax_2025, sbw.tax_2025)    AS incoming_tax_amount,

  sbw.is_two_way,
  sbw.is_poison_pill,
  sbw.poison_pill_amount,

  sbw.is_trade_bonus,
  sbw.trade_bonus_percent,
  sbw.trade_kicker_amount_2025 AS trade_kicker_amount,

  sbw.refreshed_at
FROM pcms.salary_book_warehouse sbw

UNION ALL

SELECT
  sbw.player_id,
  sbw.player_name,
  sbw.league_lk,

  sbw.team_code,
  sbw.contract_team_code,
  sbw.person_team_code,

  sbw.contract_id,
  sbw.version_number,

  2026 AS salary_year,

  sbw.cap_2026  AS cap_amount,
  sbw.tax_2026  AS tax_amount,
  sbw.apron_2026 AS apron_amount,

  sbw.apron_2026 AS outgoing_apron_amount,
  sbw.apron_2026 AS incoming_apron_amount,

  sbw.cap_2026 AS incoming_cap_amount,
  sbw.tax_2026 AS incoming_tax_amount,

  sbw.is_two_way,
  sbw.is_poison_pill,
  sbw.poison_pill_amount,

  sbw.is_trade_bonus,
  sbw.trade_bonus_percent,
  NULL::bigint AS trade_kicker_amount,

  sbw.refreshed_at
FROM pcms.salary_book_warehouse sbw

UNION ALL

SELECT
  sbw.player_id,
  sbw.player_name,
  sbw.league_lk,

  sbw.team_code,
  sbw.contract_team_code,
  sbw.person_team_code,

  sbw.contract_id,
  sbw.version_number,

  2027 AS salary_year,

  sbw.cap_2027  AS cap_amount,
  sbw.tax_2027  AS tax_amount,
  sbw.apron_2027 AS apron_amount,

  sbw.apron_2027 AS outgoing_apron_amount,
  sbw.apron_2027 AS incoming_apron_amount,

  sbw.cap_2027 AS incoming_cap_amount,
  sbw.tax_2027 AS incoming_tax_amount,

  sbw.is_two_way,
  sbw.is_poison_pill,
  sbw.poison_pill_amount,

  sbw.is_trade_bonus,
  sbw.trade_bonus_percent,
  NULL::bigint AS trade_kicker_amount,

  sbw.refreshed_at
FROM pcms.salary_book_warehouse sbw

UNION ALL

SELECT
  sbw.player_id,
  sbw.player_name,
  sbw.league_lk,

  sbw.team_code,
  sbw.contract_team_code,
  sbw.person_team_code,

  sbw.contract_id,
  sbw.version_number,

  2028 AS salary_year,

  sbw.cap_2028  AS cap_amount,
  sbw.tax_2028  AS tax_amount,
  sbw.apron_2028 AS apron_amount,

  sbw.apron_2028 AS outgoing_apron_amount,
  sbw.apron_2028 AS incoming_apron_amount,

  sbw.cap_2028 AS incoming_cap_amount,
  sbw.tax_2028 AS incoming_tax_amount,

  sbw.is_two_way,
  sbw.is_poison_pill,
  sbw.poison_pill_amount,

  sbw.is_trade_bonus,
  sbw.trade_bonus_percent,
  NULL::bigint AS trade_kicker_amount,

  sbw.refreshed_at
FROM pcms.salary_book_warehouse sbw

UNION ALL

SELECT
  sbw.player_id,
  sbw.player_name,
  sbw.league_lk,

  sbw.team_code,
  sbw.contract_team_code,
  sbw.person_team_code,

  sbw.contract_id,
  sbw.version_number,

  2029 AS salary_year,

  sbw.cap_2029  AS cap_amount,
  sbw.tax_2029  AS tax_amount,
  sbw.apron_2029 AS apron_amount,

  sbw.apron_2029 AS outgoing_apron_amount,
  sbw.apron_2029 AS incoming_apron_amount,

  sbw.cap_2029 AS incoming_cap_amount,
  sbw.tax_2029 AS incoming_tax_amount,

  sbw.is_two_way,
  sbw.is_poison_pill,
  sbw.poison_pill_amount,

  sbw.is_trade_bonus,
  sbw.trade_bonus_percent,
  NULL::bigint AS trade_kicker_amount,

  sbw.refreshed_at
FROM pcms.salary_book_warehouse sbw

UNION ALL

SELECT
  sbw.player_id,
  sbw.player_name,
  sbw.league_lk,

  sbw.team_code,
  sbw.contract_team_code,
  sbw.person_team_code,

  sbw.contract_id,
  sbw.version_number,

  2030 AS salary_year,

  sbw.cap_2030  AS cap_amount,
  sbw.tax_2030  AS tax_amount,
  sbw.apron_2030 AS apron_amount,

  sbw.apron_2030 AS outgoing_apron_amount,
  sbw.apron_2030 AS incoming_apron_amount,

  sbw.cap_2030 AS incoming_cap_amount,
  sbw.tax_2030 AS incoming_tax_amount,

  sbw.is_two_way,
  sbw.is_poison_pill,
  sbw.poison_pill_amount,

  sbw.is_trade_bonus,
  sbw.trade_bonus_percent,
  NULL::bigint AS trade_kicker_amount,

  sbw.refreshed_at
FROM pcms.salary_book_warehouse sbw;


-- -----------------------------------------------------------------------------
-- 2) Compute post-trade apron total (delta method)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pcms.fn_post_trade_apron(
  p_team_code text,
  p_salary_year int,
  p_outgoing_player_ids int[] DEFAULT '{}'::int[],
  p_incoming_player_ids int[] DEFAULT '{}'::int[],
  p_league_lk text DEFAULT 'NBA'
)
RETURNS TABLE (
  team_code text,
  salary_year int,

  baseline_apron_total bigint,
  outgoing_apron_total bigint,
  incoming_apron_total bigint,
  post_trade_apron_total bigint,

  has_team_salary boolean,
  outgoing_rows_found int,
  incoming_rows_found int
)
LANGUAGE sql
STABLE
AS $$
WITH team AS (
  SELECT
    tsw.apron_total AS baseline_apron_total
  FROM pcms.team_salary_warehouse tsw
  WHERE tsw.team_code = p_team_code
    AND tsw.salary_year = p_salary_year
),
outgoing AS (
  SELECT
    COALESCE(SUM(sby.outgoing_apron_amount), 0)::bigint AS outgoing_apron_total,
    COUNT(*)::int AS outgoing_rows_found
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = ANY(p_outgoing_player_ids)
    AND sby.team_code = p_team_code
),
incoming AS (
  SELECT
    COALESCE(SUM(sby.incoming_apron_amount), 0)::bigint AS incoming_apron_total,
    COUNT(*)::int AS incoming_rows_found
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = ANY(p_incoming_player_ids)
)
SELECT
  p_team_code AS team_code,
  p_salary_year AS salary_year,

  t.baseline_apron_total,
  o.outgoing_apron_total,
  i.incoming_apron_total,

  CASE
    WHEN t.baseline_apron_total IS NULL THEN NULL
    ELSE (t.baseline_apron_total - o.outgoing_apron_total + i.incoming_apron_total)
  END AS post_trade_apron_total,

  (t.baseline_apron_total IS NOT NULL) AS has_team_salary,
  o.outgoing_rows_found,
  i.incoming_rows_found
FROM team t
CROSS JOIN outgoing o
CROSS JOIN incoming i;
$$;

COMMIT;
