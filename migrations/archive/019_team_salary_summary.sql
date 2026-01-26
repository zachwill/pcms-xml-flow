-- 019_team_salary_summary.sql
--
-- Team-level cap/tax/apron totals cache.
--
-- Source of truth: pcms.team_budget_snapshots
-- Enrich:
-- - pcms.league_system_values (cap/tax/apron constants)
-- - pcms.tax_team_status (taxpayer / repeater / apron flags)

BEGIN;

CREATE TABLE IF NOT EXISTS pcms.team_salary_summary (
  team_code text NOT NULL,
  salary_year integer NOT NULL,

  -- totals (all budget groups)
  cap_total bigint,
  tax_total bigint,
  apron_total bigint,
  mts_total bigint,

  -- subtotals (budget group buckets)
  cap_rost bigint,
  cap_fa bigint,
  cap_term bigint,
  cap_2way bigint,

  tax_rost bigint,
  tax_fa bigint,
  tax_term bigint,
  tax_2way bigint,

  apron_rost bigint,
  apron_fa bigint,
  apron_term bigint,
  apron_2way bigint,

  -- counts (rows per bucket)
  roster_row_count integer,
  fa_row_count integer,
  term_row_count integer,
  two_way_row_count integer,

  -- year constants
  salary_cap_amount bigint,
  tax_level_amount bigint,
  tax_apron_amount bigint,
  tax_apron2_amount bigint,
  minimum_team_salary_amount bigint,

  -- convenience deltas
  over_cap bigint,
  room_under_tax bigint,
  room_under_apron1 bigint,
  room_under_apron2 bigint,

  -- tax status
  is_taxpayer boolean,
  is_repeater_taxpayer boolean,
  is_subject_to_apron boolean,
  apron_level_lk text,

  refreshed_at timestamp with time zone NOT NULL DEFAULT now(),

  CONSTRAINT team_salary_summary_pkey PRIMARY KEY (team_code, salary_year)
);

-- Common access patterns
CREATE INDEX IF NOT EXISTS idx_team_salary_summary_year_cap_total_desc
  ON pcms.team_salary_summary (salary_year, cap_total DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_team_salary_summary_year_apron_total_desc
  ON pcms.team_salary_summary (salary_year, apron_total DESC NULLS LAST);


CREATE OR REPLACE FUNCTION pcms.refresh_team_salary_summary()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.team_salary_summary;

  INSERT INTO pcms.team_salary_summary (
    team_code,
    salary_year,

    cap_total,
    tax_total,
    apron_total,
    mts_total,

    cap_rost,
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

    salary_cap_amount,
    tax_level_amount,
    tax_apron_amount,
    tax_apron2_amount,
    minimum_team_salary_amount,

    over_cap,
    room_under_tax,
    room_under_apron1,
    room_under_apron2,

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

      SUM(COALESCE(tbs.cap_amount, 0))::bigint AS cap_total,
      SUM(COALESCE(tbs.tax_amount, 0))::bigint AS tax_total,
      SUM(COALESCE(tbs.apron_amount, 0))::bigint AS apron_total,
      SUM(COALESCE(tbs.mts_amount, 0))::bigint AS mts_total,

      -- Buckets:
      -- - roster: ROST
      -- - FA/holds: FA + QO + DRFPK + PR10D
      -- - terminated/dead: TERM
      -- - two-way: 2WAY
      COALESCE(SUM(COALESCE(tbs.cap_amount, 0)) FILTER (WHERE tbs.budget_group_lk = 'ROST'), 0)::bigint AS cap_rost,
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

      COUNT(*) FILTER (WHERE tbs.budget_group_lk = 'ROST')::int AS roster_row_count,
      COUNT(*) FILTER (WHERE tbs.budget_group_lk IN ('FA', 'QO', 'DRFPK', 'PR10D'))::int AS fa_row_count,
      COUNT(*) FILTER (WHERE tbs.budget_group_lk = 'TERM')::int AS term_row_count,
      COUNT(*) FILTER (WHERE tbs.budget_group_lk = '2WAY')::int AS two_way_row_count

    FROM pcms.team_budget_snapshots tbs
    WHERE tbs.team_code IS NOT NULL
      AND tbs.salary_year IS NOT NULL
    GROUP BY 1,2
  )
  SELECT
    a.team_code,
    a.salary_year,

    a.cap_total,
    a.tax_total,
    a.apron_total,
    a.mts_total,

    a.cap_rost,
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

    a.roster_row_count,
    a.fa_row_count,
    a.term_row_count,
    a.two_way_row_count,

    lsv.salary_cap_amount,
    lsv.tax_level_amount,
    lsv.tax_apron_amount,
    lsv.tax_apron2_amount,
    lsv.minimum_team_salary_amount,

    (a.cap_total - lsv.salary_cap_amount)::bigint AS over_cap,
    (lsv.tax_level_amount - a.tax_total)::bigint AS room_under_tax,
    (lsv.tax_apron_amount - a.apron_total)::bigint AS room_under_apron1,
    (lsv.tax_apron2_amount - a.apron_total)::bigint AS room_under_apron2,

    COALESCE(tts.is_taxpayer, false) AS is_taxpayer,
    COALESCE(tts.is_repeater_taxpayer, false) AS is_repeater_taxpayer,
    COALESCE(tts.is_subject_to_apron, false) AS is_subject_to_apron,
    tts.apron_level_lk,

    now() AS refreshed_at

  FROM agg a
  LEFT JOIN pcms.league_system_values lsv
    ON lsv.league_lk = 'NBA'
   AND lsv.salary_year = a.salary_year
  LEFT JOIN pcms.tax_team_status tts
    ON tts.team_code = a.team_code
   AND tts.salary_year = a.salary_year;
END;
$$;

COMMIT;
