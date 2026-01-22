-- 027_tpe_trade_math.sql
--
-- Traded Player Exception (TPE) math helpers.
--
-- This is meant to support tool/validator logic.
--
-- Design choice (important):
-- - For the *TPE salary math* ("Salary" / "post-assignment Salaries"), we use the
--   cap-side amounts from `pcms.salary_book_yearly` (cap_amount / incoming_cap_amount).
-- - For the *apron padding gate* (CBA 6(j)(3)), we compute post-trade Apron Team Salary
--   using apron amounts via `pcms.fn_post_trade_apron(...)` and compare it to
--   `pcms.league_system_values.tax_apron_amount` (First Apron).
--
-- Rationale:
-- - The CBA formulas in 6(j)(1) are expressed in terms of "Salary" and the apron is
--   a *separate* restriction system.
-- - PCMS gives us distinct cap/tax/apron numbers; mixing them would blur meaning.

BEGIN;

CREATE OR REPLACE FUNCTION pcms.fn_tpe_trade_math(
  p_team_code text,
  p_salary_year int,
  p_traded_player_ids int[] DEFAULT '{}'::int[],
  p_replacement_player_ids int[] DEFAULT '{}'::int[],
  p_tpe_type text DEFAULT 'standard',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS TABLE (
  team_code text,
  salary_year int,
  tpe_type text,

  -- Inputs aggregated
  traded_pre_trade_salary_total bigint,
  replacement_post_salary_total bigint,

  -- Apron gate + constants
  baseline_apron_total bigint,
  post_trade_apron_total bigint,
  first_apron_amount bigint,
  is_padding_removed boolean,
  tpe_padding_amount bigint,

  -- Expanded-TPE specific constant
  tpe_dollar_allowance bigint,

  -- Outputs
  max_replacement_salary bigint,
  created_exception_amount bigint,

  -- Diagnostics
  has_league_system_values boolean,
  has_team_salary boolean,
  traded_rows_found int,
  replacement_rows_found int
)
LANGUAGE sql
STABLE
AS $$
WITH lsv AS (
  SELECT
    l.salary_cap_amount,
    l.tax_apron_amount,
    l.tpe_dollar_allowance
  FROM pcms.league_system_values l
  WHERE l.league_lk = p_league_lk
    AND l.salary_year = p_salary_year
),
traded AS (
  SELECT
    COALESCE(SUM(sby.cap_amount), 0)::bigint AS traded_pre_trade_salary_total,
    COUNT(*)::int AS traded_rows_found
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = ANY(p_traded_player_ids)
    AND sby.team_code = p_team_code
),
repl AS (
  SELECT
    COALESCE(SUM(sby.incoming_cap_amount), 0)::bigint AS replacement_post_salary_total,
    COUNT(*)::int AS replacement_rows_found
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = ANY(p_replacement_player_ids)
),
post_apron AS (
  SELECT *
  FROM pcms.fn_post_trade_apron(
    p_team_code,
    p_salary_year,
    p_traded_player_ids,
    p_replacement_player_ids,
    p_league_lk
  )
),
constants AS (
  SELECT
    pa.baseline_apron_total,
    pa.post_trade_apron_total,
    (lsv.tax_apron_amount)::bigint AS first_apron_amount,
    (lsv.tpe_dollar_allowance)::bigint AS tpe_dollar_allowance,
    (lsv.tax_apron_amount IS NOT NULL) AS has_league_system_values,
    pa.has_team_salary
  FROM post_apron pa
  LEFT JOIN lsv ON TRUE
),
calc AS (
  SELECT
    p_team_code::text AS team_code,
    p_salary_year::int AS salary_year,
    LOWER(p_tpe_type)::text AS tpe_type,

    t.traded_pre_trade_salary_total,
    r.replacement_post_salary_total,

    c.baseline_apron_total,
    c.post_trade_apron_total,
    c.first_apron_amount,

    CASE
      WHEN c.first_apron_amount IS NULL OR c.post_trade_apron_total IS NULL THEN NULL
      WHEN c.post_trade_apron_total > c.first_apron_amount THEN TRUE
      ELSE FALSE
    END AS is_padding_removed,

    CASE
      WHEN c.first_apron_amount IS NULL OR c.post_trade_apron_total IS NULL THEN NULL
      WHEN c.post_trade_apron_total > c.first_apron_amount THEN 0::bigint
      ELSE 250000::bigint
    END AS tpe_padding_amount,

    c.tpe_dollar_allowance,

    c.has_league_system_values,
    c.has_team_salary,
    t.traded_rows_found,
    r.replacement_rows_found

  FROM traded t
  CROSS JOIN repl r
  CROSS JOIN constants c
)
SELECT
  c.team_code,
  c.salary_year,
  c.tpe_type,

  c.traded_pre_trade_salary_total,
  c.replacement_post_salary_total,

  c.baseline_apron_total,
  c.post_trade_apron_total,
  c.first_apron_amount,
  c.is_padding_removed,
  c.tpe_padding_amount,

  c.tpe_dollar_allowance,

  -- max_replacement_salary
  CASE c.tpe_type
    WHEN 'standard' THEN
      (c.traded_pre_trade_salary_total + c.tpe_padding_amount)

    WHEN 'aggregated_standard' THEN
      (c.traded_pre_trade_salary_total + c.tpe_padding_amount)

    WHEN 'transition' THEN
      CASE
        -- Transition TPE only exists for 2023-24 (salary_year=2023)
        WHEN c.salary_year = 2023 THEN
          (CEIL(c.traded_pre_trade_salary_total::numeric * 1.10)::bigint + c.tpe_padding_amount)
        ELSE NULL
      END

    WHEN 'expanded' THEN
      GREATEST(
        LEAST(
          -- (A) 200% of aggregated pre-trade salaries + $250k allowance
          (c.traded_pre_trade_salary_total * 2 + c.tpe_padding_amount),
          -- (B) 100% + ($7.5M × cap_ratio). Note: CBA text does NOT include $250k here.
          (c.traded_pre_trade_salary_total + c.tpe_dollar_allowance)
        ),
        -- (z) 125% + $250k allowance
        (CEIL(c.traded_pre_trade_salary_total::numeric * 1.25)::bigint + c.tpe_padding_amount)
      )

    ELSE NULL
  END AS max_replacement_salary,

  -- created_exception_amount (remaining exception after simultaneously acquiring replacement players)
  CASE
    WHEN (
      CASE c.tpe_type
        WHEN 'standard' THEN (c.traded_pre_trade_salary_total + c.tpe_padding_amount)
        WHEN 'aggregated_standard' THEN (c.traded_pre_trade_salary_total + c.tpe_padding_amount)
        WHEN 'transition' THEN CASE WHEN c.salary_year = 2023 THEN (CEIL(c.traded_pre_trade_salary_total::numeric * 1.10)::bigint + c.tpe_padding_amount) ELSE NULL END
        WHEN 'expanded' THEN GREATEST(
          LEAST(
            (c.traded_pre_trade_salary_total * 2 + c.tpe_padding_amount),
            (c.traded_pre_trade_salary_total + c.tpe_dollar_allowance)
          ),
          (CEIL(c.traded_pre_trade_salary_total::numeric * 1.25)::bigint + c.tpe_padding_amount)
        )
        ELSE NULL
      END
    ) IS NULL THEN NULL

    ELSE GREATEST(
      0::bigint,
      (
        CASE c.tpe_type
          WHEN 'standard' THEN (c.traded_pre_trade_salary_total + c.tpe_padding_amount)
          WHEN 'aggregated_standard' THEN (c.traded_pre_trade_salary_total + c.tpe_padding_amount)
          WHEN 'transition' THEN CASE WHEN c.salary_year = 2023 THEN (CEIL(c.traded_pre_trade_salary_total::numeric * 1.10)::bigint + c.tpe_padding_amount) ELSE NULL END
          WHEN 'expanded' THEN GREATEST(
            LEAST(
              (c.traded_pre_trade_salary_total * 2 + c.tpe_padding_amount),
              (c.traded_pre_trade_salary_total + c.tpe_dollar_allowance)
            ),
            (CEIL(c.traded_pre_trade_salary_total::numeric * 1.25)::bigint + c.tpe_padding_amount)
          )
          ELSE NULL
        END
      ) - c.replacement_post_salary_total
    )
  END AS created_exception_amount,

  c.has_league_system_values,
  c.has_team_salary,
  c.traded_rows_found,
  c.replacement_rows_found

FROM calc c;
$$;

COMMIT;
