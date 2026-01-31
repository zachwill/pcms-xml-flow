-- 060_fn_buyout_primitives.sql
--
-- Buyout / waiver / stretch primitives used for scenario modeling.

BEGIN;

-- Days remaining in the regular season after a player clears waivers.
--
-- Matches Sean's spreadsheet convention:
--   clears_waivers = waive_date + 2
--   day_of_season  = clears_waivers - season_start
--   days_remaining = 174 - day_of_season
CREATE OR REPLACE FUNCTION pcms.fn_days_remaining(
  p_waive_date date,
  p_season_start date DEFAULT '2025-10-20'::date
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT GREATEST(
    0,
    174 - (((p_waive_date + 2) - p_season_start)::integer)
  );
$$;

-- Stretch provision: spread dead money over (2 * remaining_years + 1).
CREATE OR REPLACE FUNCTION pcms.fn_stretch_waiver(
  p_total_dead_money bigint,
  p_remaining_years integer
)
RETURNS TABLE (
  stretch_years integer,
  annual_amount bigint
)
LANGUAGE sql
IMMUTABLE
AS $$
SELECT
  CASE WHEN p_remaining_years IS NULL OR p_remaining_years < 1 THEN NULL
       ELSE (2 * p_remaining_years + 1) END AS stretch_years,
  CASE WHEN p_remaining_years IS NULL OR p_remaining_years < 1 THEN NULL
       ELSE (p_total_dead_money / (2 * p_remaining_years + 1)) END AS annual_amount;
$$;

-- Set-off amount (when a waived player signs elsewhere):
--   setoff = (new_salary - minimum_salary) / 2
CREATE OR REPLACE FUNCTION pcms.fn_setoff_amount(
  p_new_salary bigint,
  p_years_of_service integer DEFAULT 1,
  p_salary_year integer DEFAULT 2025,
  p_league_lk text DEFAULT 'NBA'
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
SELECT
  CASE
    WHEN p_new_salary IS NULL THEN NULL
    ELSE GREATEST(
      0::bigint,
      (
        p_new_salary
        - pcms.fn_minimum_salary(p_salary_year, p_years_of_service, 1, p_league_lk)
      ) / 2
    )
  END;
$$;

-- Buyout scenario helper.
--
-- Produces a year-by-year breakdown with give-back allocation based on
-- prorated current-year remaining salary.
CREATE OR REPLACE FUNCTION pcms.fn_buyout_scenario(
  p_player_id integer,
  p_waive_date date,
  p_give_back_amount bigint DEFAULT 0,
  p_season_start date DEFAULT '2025-10-20'::date,
  p_league_lk text DEFAULT 'NBA'
)
RETURNS TABLE (
  salary_year integer,
  cap_salary bigint,
  days_remaining integer,
  proration_factor numeric,
  guaranteed_remaining bigint,
  give_back_pct numeric,
  give_back_amount bigint,
  dead_money bigint
)
LANGUAGE sql
STABLE
AS $$
WITH season AS (
  SELECT
    EXTRACT(YEAR FROM p_season_start)::int AS current_salary_year,
    pcms.fn_days_remaining(p_waive_date, p_season_start) AS days_remaining,
    174::numeric AS season_days,
    COALESCE(p_give_back_amount, 0)::bigint AS give_back_amount
),
player_salaries AS (
  SELECT
    sby.salary_year,
    sby.cap_amount::bigint AS cap_salary
  FROM pcms.salary_book_yearly sby
  JOIN season s ON TRUE
  WHERE sby.league_lk = p_league_lk
    AND sby.player_id = p_player_id
    AND sby.salary_year >= s.current_salary_year
    AND sby.cap_amount IS NOT NULL
    AND sby.cap_amount > 0
),
calc AS (
  SELECT
    ps.salary_year,
    ps.cap_salary,

    CASE
      WHEN ps.salary_year = s.current_salary_year THEN s.days_remaining
      ELSE NULL
    END AS days_remaining,

    CASE
      WHEN ps.salary_year = s.current_salary_year THEN (s.days_remaining::numeric / s.season_days)
      ELSE 1::numeric
    END AS proration_factor,

    CASE
      WHEN ps.salary_year = s.current_salary_year THEN
        ROUND(ps.cap_salary::numeric * (s.days_remaining::numeric / s.season_days), 0)::bigint
      ELSE
        ps.cap_salary
    END AS guaranteed_remaining

  FROM player_salaries ps
  JOIN season s ON TRUE
),
with_totals AS (
  SELECT
    c.*, 
    (SUM(c.guaranteed_remaining) OVER ())::numeric AS guaranteed_total
  FROM calc c
),
alloc_raw AS (
  SELECT
    wt.*,
    CASE
      WHEN wt.guaranteed_total IS NULL OR wt.guaranteed_total = 0 THEN NULL
      ELSE (wt.guaranteed_remaining::numeric / wt.guaranteed_total)
    END AS give_back_pct,

    CASE
      WHEN wt.guaranteed_total IS NULL OR wt.guaranteed_total = 0 THEN 0::bigint
      ELSE ROUND((wt.guaranteed_remaining::numeric / wt.guaranteed_total) * s.give_back_amount, 0)::bigint
    END AS give_back_amount_rounded,

    s.give_back_amount AS give_back_amount_total

  FROM with_totals wt
  JOIN season s ON TRUE
),
alloc_fixed AS (
  SELECT
    ar.*,
    SUM(ar.give_back_amount_rounded) OVER (
      ORDER BY ar.salary_year
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS give_back_prev_sum,
    ROW_NUMBER() OVER (ORDER BY ar.salary_year DESC) AS rn_desc
  FROM alloc_raw ar
)
SELECT
  af.salary_year,
  af.cap_salary,
  af.days_remaining,
  af.proration_factor,
  af.guaranteed_remaining,
  af.give_back_pct,

  CASE
    WHEN af.rn_desc = 1 THEN (af.give_back_amount_total - COALESCE(af.give_back_prev_sum, 0))::bigint
    ELSE af.give_back_amount_rounded
  END AS give_back_amount,

  GREATEST(
    0::bigint,
    af.cap_salary - (
      CASE
        WHEN af.rn_desc = 1 THEN (af.give_back_amount_total - COALESCE(af.give_back_prev_sum, 0))::bigint
        ELSE af.give_back_amount_rounded
      END
    )
  ) AS dead_money

FROM alloc_fixed af
ORDER BY af.salary_year;
$$;

COMMIT;
