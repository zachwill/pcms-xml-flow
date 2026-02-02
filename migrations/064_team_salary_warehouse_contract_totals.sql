-- 064_team_salary_warehouse_contract_totals.sql
--
-- Redefine cap_total to exclude cap holds, while preserving the snapshot
-- total (holds included) as cap_total_hold.
--
-- cap_total = contract-only roster (salary_book_yearly, no two-ways) + term + two-way
-- cap_total_hold = old snapshot total (team_budget_snapshots cap_amount)

BEGIN;

ALTER TABLE pcms.team_salary_warehouse
  ADD COLUMN IF NOT EXISTS cap_total_hold bigint;

CREATE OR REPLACE FUNCTION pcms.refresh_team_salary_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_current_year integer;
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  -- Get current year (min year in team_budget_snapshots)
  SELECT MIN(salary_year) INTO v_current_year FROM pcms.team_budget_snapshots;

  TRUNCATE TABLE pcms.team_salary_warehouse;

  INSERT INTO pcms.team_salary_warehouse (
    team_code,
    salary_year,

    cap_total,
    cap_total_hold,
    tax_total,
    apron_total,
    mts_total,

    cap_rost,
    cap_rost_hold,
    cap_fa,
    cap_term,
    cap_2way,

    tax_rost,
    tax_fa,
    tax_term,
    tax_2way,

    apron_rost,
    apron_fa,
    apron_term,
    apron_2way,

    roster_row_count,
    fa_row_count,
    term_row_count,
    two_way_row_count,

    -- Columns from team_two_way_capacity
    games_remaining,
    under_15_games_count,
    under_15_games_remaining,

    salary_cap_amount,
    tax_level_amount,
    tax_apron_amount,
    tax_apron2_amount,
    minimum_team_salary_amount,

    over_cap,
    room_under_tax,
    room_under_apron1,
    room_under_apron2,

    tax_team_status_id,
    team_tax_summary_id,
    has_tax_team_status,
    has_team_tax_summary_snapshot,
    has_any_tax_status,
    tax_status_source,
    has_league_system_values,

    is_taxpayer,
    is_repeater_taxpayer,
    is_subject_to_apron,
    apron_level_lk,

    refreshed_at
  )
  WITH agg AS (
    SELECT
      tbs.team_code,
      tbs.salary_year,

      SUM(COALESCE(tbs.cap_amount, 0))::bigint AS cap_total_hold,
      SUM(COALESCE(tbs.tax_amount, 0))::bigint AS tax_total,
      SUM(COALESCE(tbs.apron_amount, 0))::bigint AS apron_total,
      SUM(COALESCE(tbs.mts_amount, 0))::bigint AS mts_total,

      COALESCE(SUM(COALESCE(tbs.cap_amount, 0)) FILTER (WHERE tbs.budget_group_lk = 'ROST'), 0)::bigint AS cap_rost_hold,
      COALESCE(SUM(COALESCE(tbs.cap_amount, 0)) FILTER (WHERE tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D')), 0)::bigint AS cap_fa,
      COALESCE(SUM(COALESCE(tbs.cap_amount, 0)) FILTER (WHERE tbs.budget_group_lk = 'TERM'), 0)::bigint AS cap_term,
      COALESCE(SUM(COALESCE(tbs.cap_amount, 0)) FILTER (WHERE tbs.budget_group_lk = '2WAY'), 0)::bigint AS cap_2way,

      COALESCE(SUM(COALESCE(tbs.tax_amount, 0)) FILTER (WHERE tbs.budget_group_lk = 'ROST'), 0)::bigint AS tax_rost,
      COALESCE(SUM(COALESCE(tbs.tax_amount, 0)) FILTER (WHERE tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D')), 0)::bigint AS tax_fa,
      COALESCE(SUM(COALESCE(tbs.tax_amount, 0)) FILTER (WHERE tbs.budget_group_lk = 'TERM'), 0)::bigint AS tax_term,
      COALESCE(SUM(COALESCE(tbs.tax_amount, 0)) FILTER (WHERE tbs.budget_group_lk = '2WAY'), 0)::bigint AS tax_2way,

      COALESCE(SUM(COALESCE(tbs.apron_amount, 0)) FILTER (WHERE tbs.budget_group_lk = 'ROST'), 0)::bigint AS apron_rost,
      COALESCE(SUM(COALESCE(tbs.apron_amount, 0)) FILTER (WHERE tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D')), 0)::bigint AS apron_fa,
      COALESCE(SUM(COALESCE(tbs.apron_amount, 0)) FILTER (WHERE tbs.budget_group_lk = 'TERM'), 0)::bigint AS apron_term,
      COALESCE(SUM(COALESCE(tbs.apron_amount, 0)) FILTER (WHERE tbs.budget_group_lk = '2WAY'), 0)::bigint AS apron_2way,

      -- Fallback roster count: distinct players in ROST with cap > 0 (used for future years)
      COUNT(DISTINCT tbs.player_id) FILTER (WHERE tbs.budget_group_lk = 'ROST' AND tbs.cap_amount > 0)::int AS calc_roster_row_count,
      COUNT(*) FILTER (WHERE tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D'))::int AS fa_row_count,
      COUNT(*) FILTER (WHERE tbs.budget_group_lk = 'TERM')::int AS term_row_count,
      COUNT(*) FILTER (WHERE tbs.budget_group_lk = '2WAY')::int AS two_way_row_count

    FROM pcms.team_budget_snapshots tbs
    WHERE tbs.team_code IS NOT NULL
      AND tbs.salary_year IS NOT NULL
    GROUP BY 1,2
  ),
  contract_rost AS (
    SELECT
      sby.team_code,
      sby.salary_year,
      COALESCE(
        SUM(COALESCE(sby.cap_amount, 0)) FILTER (WHERE COALESCE(sby.is_two_way, false) = false),
        0
      )::bigint AS cap_rost
    FROM pcms.salary_book_yearly sby
    WHERE sby.team_code IS NOT NULL
      AND sby.salary_year IS NOT NULL
    GROUP BY 1,2
  )
  SELECT
    a.team_code,
    a.salary_year,

    (COALESCE(cr.cap_rost, 0) + a.cap_term + a.cap_2way)::bigint AS cap_total,
    a.cap_total_hold,
    a.tax_total,
    a.apron_total,
    a.mts_total,

    COALESCE(cr.cap_rost, 0)::bigint AS cap_rost,
    a.cap_rost_hold,
    a.cap_fa,
    a.cap_term,
    a.cap_2way,

    a.tax_rost,
    a.tax_fa,
    a.tax_term,
    a.tax_2way,

    a.apron_rost,
    a.apron_fa,
    a.apron_term,
    a.apron_2way,

    -- Use authoritative current_contract_count for current year, fallback for future years
    COALESCE(ttwc.current_contract_count, a.calc_roster_row_count)::int AS roster_row_count,
    a.fa_row_count,
    a.term_row_count,
    a.two_way_row_count,

    -- Columns from team_two_way_capacity (only populated for current year)
    ttwc.games_remaining,
    ttwc.under_15_games_count,
    ttwc.under_15_games_remaining,

    lsv.salary_cap_amount,
    lsv.tax_level_amount,
    lsv.tax_apron_amount,
    lsv.tax_apron2_amount,
    lsv.minimum_team_salary_amount,

    ((COALESCE(cr.cap_rost, 0) + a.cap_term + a.cap_2way) - lsv.salary_cap_amount)::bigint AS over_cap,
    (lsv.tax_level_amount - a.tax_total)::bigint AS room_under_tax,
    (lsv.tax_apron_amount - a.apron_total)::bigint AS room_under_apron1,
    (lsv.tax_apron2_amount - a.apron_total)::bigint AS room_under_apron2,

    tts.tax_team_status_id,
    ttsn.team_tax_summary_id,

    (tts.tax_team_status_id IS NOT NULL) AS has_tax_team_status,
    (ttsn.team_tax_summary_id IS NOT NULL) AS has_team_tax_summary_snapshot,
    ((tts.tax_team_status_id IS NOT NULL) OR (ttsn.team_tax_summary_id IS NOT NULL)) AS has_any_tax_status,

    CASE
      WHEN tts.tax_team_status_id IS NOT NULL THEN 'tax_team_status'
      WHEN ttsn.team_tax_summary_id IS NOT NULL THEN 'team_tax_summary_snapshots'
      ELSE NULL
    END AS tax_status_source,

    (lsv.salary_year IS NOT NULL) AS has_league_system_values,

    COALESCE(tts.is_taxpayer, ttsn.is_taxpayer, false) AS is_taxpayer,
    COALESCE(tts.is_repeater_taxpayer, ttsn.is_repeater_taxpayer, false) AS is_repeater_taxpayer,
    COALESCE(tts.is_subject_to_apron, ttsn.is_subject_to_apron, false) AS is_subject_to_apron,
    COALESCE(tts.apron_level_lk, ttsn.apron_level_lk) AS apron_level_lk,

    now() AS refreshed_at

  FROM agg a
  LEFT JOIN contract_rost cr
    ON cr.team_code = a.team_code
   AND cr.salary_year = a.salary_year

  LEFT JOIN pcms.league_system_values lsv
    ON lsv.league_lk = 'NBA'
   AND lsv.salary_year = a.salary_year

  LEFT JOIN pcms.tax_team_status tts
    ON tts.team_code = a.team_code
   AND tts.salary_year = a.salary_year

  LEFT JOIN pcms.team_tax_summary_snapshots ttsn
    ON ttsn.team_code = a.team_code
   AND ttsn.salary_year = a.salary_year

  -- Join team_two_way_capacity only for current year
  LEFT JOIN pcms.team_two_way_capacity ttwc
    ON ttwc.team_code = a.team_code
   AND a.salary_year = v_current_year;
END;
$$;

COMMIT;
