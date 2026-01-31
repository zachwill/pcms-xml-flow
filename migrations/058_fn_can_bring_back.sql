-- 058_fn_can_bring_back.sql
--
-- Inverse trade matching primitive (“Can Bring Back”).
--
-- Given an incoming salary (what the other team would receive), compute the
-- minimum outgoing salary required to legally match it under the selected
-- matching mode.
--
-- This is the inverse of the forward matching helper embedded in
-- pcms.fn_tpe_trade_math().

BEGIN;

-- Core primitive: minimum outgoing required for an incoming target.
CREATE OR REPLACE FUNCTION pcms.fn_min_outgoing_for_incoming(
  p_incoming_salary bigint,
  p_salary_year int,
  p_mode text DEFAULT 'expanded',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
SELECT
  CASE
    WHEN p_incoming_salary IS NULL THEN NULL

    WHEN LOWER(COALESCE(p_mode, '')) = 'standard' THEN
      (p_incoming_salary - lsv.tpe_dollar_allowance)

    WHEN LOWER(COALESCE(p_mode, '')) = 'expanded' THEN
      CASE
        WHEN lsv.tpe_dollar_allowance IS NULL THEN NULL

        -- Low tier: invert 200% + 250K
        --
        -- Breakpoint derivation (matches forward function):
        -- 2x + 250K <= x + TPE  <=>  x <= TPE - 250K
        WHEN (p_incoming_salary - lsv.tpe_dollar_allowance)
          <= (lsv.tpe_dollar_allowance - 250000) THEN
          CEIL((p_incoming_salary - 250000)::numeric / 2)::bigint

        -- High tier: invert 125% + 250K
        --
        -- Breakpoint derivation (matches forward function):
        -- x + TPE > 1.25x + 250K  <=>  x > 4*(TPE - 250K)
        WHEN (p_incoming_salary - lsv.tpe_dollar_allowance)
          > (4 * (lsv.tpe_dollar_allowance - 250000)) THEN
          CEIL((p_incoming_salary - 250000)::numeric / 1.25)::bigint

        -- Mid tier: invert 100% + TPE
        ELSE
          (p_incoming_salary - lsv.tpe_dollar_allowance)
      END

    -- Apron teams / catch-all: 1:1
    ELSE
      p_incoming_salary
  END
FROM pcms.league_system_values lsv
WHERE lsv.league_lk = p_league_lk
  AND lsv.salary_year = p_salary_year;
$$;

-- Convenience wrapper matching naming in TODO.md.
CREATE OR REPLACE FUNCTION pcms.fn_can_bring_back(
  p_salary_year int,
  p_outgoing_salary bigint,
  p_mode text DEFAULT 'expanded',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT pcms.fn_min_outgoing_for_incoming(p_outgoing_salary, p_salary_year, p_mode, p_league_lk);
$$;

-- Player convenience wrapper: looks up the player’s incoming cap amount for a
-- year (includes trade kicker for 2025 where present) and runs the inverse math.
CREATE OR REPLACE FUNCTION pcms.fn_player_can_bring_back(
  p_player_id int,
  p_salary_year int,
  p_mode text DEFAULT 'expanded',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT pcms.fn_min_outgoing_for_incoming(sby.incoming_cap_amount, p_salary_year, p_mode, p_league_lk)
  FROM pcms.salary_book_yearly sby
  WHERE sby.league_lk = p_league_lk
    AND sby.salary_year = p_salary_year
    AND sby.player_id = p_player_id;
$$;

-- Optional helper: return the full matching window for an outgoing salary.
--
-- Note: this does NOT apply apron padding gate logic; it is a pure formula
-- helper meant for tool UI tables.
CREATE OR REPLACE FUNCTION pcms.fn_trade_salary_range(
  p_outgoing_salary bigint,
  p_salary_year int,
  p_mode text DEFAULT 'expanded',
  p_league_lk text DEFAULT 'NBA'
)
RETURNS TABLE (
  min_incoming bigint,
  max_incoming bigint
)
LANGUAGE sql
STABLE
AS $$
SELECT
  pcms.fn_min_outgoing_for_incoming(p_outgoing_salary, p_salary_year, p_mode, p_league_lk) AS min_incoming,

  CASE LOWER(COALESCE(p_mode, ''))
    WHEN 'expanded' THEN
      GREATEST(
        LEAST(
          (p_outgoing_salary * 2 + 250000),
          (p_outgoing_salary + lsv.tpe_dollar_allowance)
        ),
        (CEIL(p_outgoing_salary::numeric * 1.25)::bigint + 250000)
      )

    WHEN 'standard' THEN
      (p_outgoing_salary + lsv.tpe_dollar_allowance)

    ELSE
      p_outgoing_salary
  END AS max_incoming

FROM pcms.league_system_values lsv
WHERE lsv.league_lk = p_league_lk
  AND lsv.salary_year = p_salary_year;
$$;

COMMIT;
