-- 050_salary_book_guarantees_and_bonuses.sql
--
-- Add per-year guarantee detail + likely/unlikely bonus detail to
-- pcms.salary_book_warehouse, and update pcms.refresh_salary_book_warehouse()
-- to populate them.
--
-- IMPORTANT: We store guarantees in the warehouse using numeric amounts + booleans
-- (consistent with existing warehouse style), NOT string enums.
--
-- Guarantee columns per year (2025..2030):
-- - guaranteed_amount_YYYY: bigint (amount protected/guaranteed for that season)
-- - is_fully_guaranteed_YYYY: boolean
-- - is_partially_guaranteed_YYYY: boolean
-- - is_non_guaranteed_YYYY: boolean
--
-- Bonus columns per year (2025..2030):
-- - likely_bonus_YYYY: bigint
-- - unlikely_bonus_YYYY: bigint
--
-- Guarantee derivation:
-- - Join the *chosen* (player_id, salary_year) salary row to pcms.contract_protections
--   for that same (contract_id, version_number, salary_year).
-- - Prefer effective_protection_amount, fall back to protection_amount.
-- - If amounts are missing but coverage clearly implies FULL/NONE, fall back to cap/0.
-- - Clamp guaranteed_amount to [0, contract_cap_salary] when possible.

BEGIN;

-- Previous draft of 050 introduced guarantee_YYYY text columns. Drop them.
ALTER TABLE pcms.salary_book_warehouse
  DROP COLUMN IF EXISTS guarantee_2025,
  DROP COLUMN IF EXISTS guarantee_2026,
  DROP COLUMN IF EXISTS guarantee_2027,
  DROP COLUMN IF EXISTS guarantee_2028,
  DROP COLUMN IF EXISTS guarantee_2029,
  DROP COLUMN IF EXISTS guarantee_2030;

-- Add per-year guarantee + bonus columns.
ALTER TABLE pcms.salary_book_warehouse
  ADD COLUMN IF NOT EXISTS guaranteed_amount_2025 bigint,
  ADD COLUMN IF NOT EXISTS guaranteed_amount_2026 bigint,
  ADD COLUMN IF NOT EXISTS guaranteed_amount_2027 bigint,
  ADD COLUMN IF NOT EXISTS guaranteed_amount_2028 bigint,
  ADD COLUMN IF NOT EXISTS guaranteed_amount_2029 bigint,
  ADD COLUMN IF NOT EXISTS guaranteed_amount_2030 bigint,

  ADD COLUMN IF NOT EXISTS is_fully_guaranteed_2025 boolean,
  ADD COLUMN IF NOT EXISTS is_fully_guaranteed_2026 boolean,
  ADD COLUMN IF NOT EXISTS is_fully_guaranteed_2027 boolean,
  ADD COLUMN IF NOT EXISTS is_fully_guaranteed_2028 boolean,
  ADD COLUMN IF NOT EXISTS is_fully_guaranteed_2029 boolean,
  ADD COLUMN IF NOT EXISTS is_fully_guaranteed_2030 boolean,

  ADD COLUMN IF NOT EXISTS is_partially_guaranteed_2025 boolean,
  ADD COLUMN IF NOT EXISTS is_partially_guaranteed_2026 boolean,
  ADD COLUMN IF NOT EXISTS is_partially_guaranteed_2027 boolean,
  ADD COLUMN IF NOT EXISTS is_partially_guaranteed_2028 boolean,
  ADD COLUMN IF NOT EXISTS is_partially_guaranteed_2029 boolean,
  ADD COLUMN IF NOT EXISTS is_partially_guaranteed_2030 boolean,

  ADD COLUMN IF NOT EXISTS is_non_guaranteed_2025 boolean,
  ADD COLUMN IF NOT EXISTS is_non_guaranteed_2026 boolean,
  ADD COLUMN IF NOT EXISTS is_non_guaranteed_2027 boolean,
  ADD COLUMN IF NOT EXISTS is_non_guaranteed_2028 boolean,
  ADD COLUMN IF NOT EXISTS is_non_guaranteed_2029 boolean,
  ADD COLUMN IF NOT EXISTS is_non_guaranteed_2030 boolean,

  ADD COLUMN IF NOT EXISTS likely_bonus_2025 bigint,
  ADD COLUMN IF NOT EXISTS likely_bonus_2026 bigint,
  ADD COLUMN IF NOT EXISTS likely_bonus_2027 bigint,
  ADD COLUMN IF NOT EXISTS likely_bonus_2028 bigint,
  ADD COLUMN IF NOT EXISTS likely_bonus_2029 bigint,
  ADD COLUMN IF NOT EXISTS likely_bonus_2030 bigint,

  ADD COLUMN IF NOT EXISTS unlikely_bonus_2025 bigint,
  ADD COLUMN IF NOT EXISTS unlikely_bonus_2026 bigint,
  ADD COLUMN IF NOT EXISTS unlikely_bonus_2027 bigint,
  ADD COLUMN IF NOT EXISTS unlikely_bonus_2028 bigint,
  ADD COLUMN IF NOT EXISTS unlikely_bonus_2029 bigint,
  ADD COLUMN IF NOT EXISTS unlikely_bonus_2030 bigint;

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  PERFORM set_config('lock_timeout', '5s', true);

  TRUNCATE TABLE pcms.salary_book_warehouse;

  INSERT INTO pcms.salary_book_warehouse (
    player_id,
    player_name,
    league_lk,
    team_code,
    contract_team_code,
    person_team_code,
    signing_team_id,
    contract_id,
    version_number,
    birth_date,
    age,
    agent_name,
    agent_id,

    cap_2025, cap_2026, cap_2027, cap_2028, cap_2029, cap_2030,
    pct_cap_2025, pct_cap_2026, pct_cap_2027, pct_cap_2028, pct_cap_2029, pct_cap_2030,
    total_salary_from_2025,

    option_2025, option_2026, option_2027, option_2028, option_2029, option_2030,
    option_decision_2025, option_decision_2026, option_decision_2027,
    option_decision_2028, option_decision_2029, option_decision_2030,

    guaranteed_amount_2025, guaranteed_amount_2026, guaranteed_amount_2027,
    guaranteed_amount_2028, guaranteed_amount_2029, guaranteed_amount_2030,

    is_fully_guaranteed_2025, is_fully_guaranteed_2026, is_fully_guaranteed_2027,
    is_fully_guaranteed_2028, is_fully_guaranteed_2029, is_fully_guaranteed_2030,

    is_partially_guaranteed_2025, is_partially_guaranteed_2026, is_partially_guaranteed_2027,
    is_partially_guaranteed_2028, is_partially_guaranteed_2029, is_partially_guaranteed_2030,

    is_non_guaranteed_2025, is_non_guaranteed_2026, is_non_guaranteed_2027,
    is_non_guaranteed_2028, is_non_guaranteed_2029, is_non_guaranteed_2030,

    likely_bonus_2025, likely_bonus_2026, likely_bonus_2027,
    likely_bonus_2028, likely_bonus_2029, likely_bonus_2030,

    unlikely_bonus_2025, unlikely_bonus_2026, unlikely_bonus_2027,
    unlikely_bonus_2028, unlikely_bonus_2029, unlikely_bonus_2030,

    is_two_way,
    is_poison_pill,
    poison_pill_amount,
    is_no_trade,
    is_trade_bonus,
    trade_bonus_percent,
    trade_kicker_amount_2025,
    trade_kicker_display,

    tax_2025, tax_2026, tax_2027, tax_2028, tax_2029, tax_2030,
    apron_2025, apron_2026, apron_2027, apron_2028, apron_2029, apron_2030,

    outgoing_buildup_2025,
    incoming_buildup_2025,
    incoming_salary_2025,
    incoming_tax_2025,
    incoming_apron_2025,

    player_consent_lk,
    player_consent_end_date,
    is_trade_consent_required_now,
    is_trade_preconsented,

    refreshed_at
  )
  WITH active_contracts AS (
    SELECT
      c.*,
      ROW_NUMBER() OVER (
        PARTITION BY c.player_id
        ORDER BY
          (c.record_status_lk = 'APPR') DESC,
          (c.record_status_lk = 'FUTR') DESC,
          c.signing_date DESC NULLS LAST,
          c.contract_id DESC
      ) AS rn
    FROM pcms.contracts c
    WHERE c.record_status_lk IN ('APPR', 'FUTR')
  ),
  latest_versions AS (
    SELECT
      cv.*,
      ROW_NUMBER() OVER (
        PARTITION BY cv.contract_id
        ORDER BY cv.version_number DESC
      ) AS rn
    FROM pcms.contract_versions cv
  ),
  ac AS (
    -- Primary contract identity per player (used for flags/IDs)
    SELECT
      a.contract_id,
      a.player_id,
      a.signing_team_id,
      a.team_code,
      lv.version_number,

      -- Derive two-way from contract type (2WCT or converted two-way REGCV)
      (lv.contract_type_lk IN ('2WCT', 'REGCV')) AS is_two_way,

      lv.is_poison_pill,
      lv.poison_pill_amount,
      lv.is_trade_bonus,
      lv.trade_bonus_percent,
      lv.trade_bonus_amount,
      lv.is_no_trade,

      -- Player consent / trade-consent-ish flags live in version_json.
      NULLIF(lv.version_json->>'player_consent_lk', 'NONE') AS player_consent_lk,
      NULLIF(lv.version_json->>'player_consent_end_date', '')::timestamptz::date AS player_consent_end_date

    FROM active_contracts a
    JOIN latest_versions lv
      ON lv.contract_id = a.contract_id
     AND lv.rn = 1
    WHERE a.rn = 1
  ),
  declined_option_decisions AS (
    SELECT l.lookup_code
    FROM pcms.lookups l
    WHERE l.lookup_type = 'lk_option_decisions'
      AND l.description ILIKE '%Declined%'
  ),
  salary_candidates AS (
    -- Candidate salary rows across all APPR/FUTR contracts, on latest version.
    SELECT
      c.player_id,
      s.salary_year,
      s.contract_id,
      s.version_number,
      c.record_status_lk,
      c.signing_date,

      s.contract_cap_salary,
      s.contract_tax_salary,
      s.contract_tax_apron_salary,
      s.total_salary,

      s.option_lk,
      s.option_decision_lk,

      s.trade_bonus_amount_calc,

      -- Bonus detail
      s.likely_bonus,
      s.unlikely_bonus

    FROM pcms.contracts c
    JOIN latest_versions lv
      ON lv.contract_id = c.contract_id
     AND lv.rn = 1
    JOIN pcms.salaries s
      ON s.contract_id = c.contract_id
     AND s.version_number = lv.version_number
    WHERE c.record_status_lk IN ('APPR', 'FUTR')
      AND s.salary_year BETWEEN 2025 AND 2030
      AND NOT (
        s.option_decision_lk IS NOT NULL
        AND BTRIM(s.option_decision_lk) <> ''
        AND s.option_decision_lk IN (SELECT lookup_code FROM declined_option_decisions)
      )
  ),
  chosen_salary AS (
    -- Choose 1 salary row per (player_id, salary_year).
    SELECT *
    FROM (
      SELECT
        sc.*,
        ROW_NUMBER() OVER (
          PARTITION BY sc.player_id, sc.salary_year
          ORDER BY
            sc.signing_date DESC NULLS LAST,
            (sc.record_status_lk = 'APPR') DESC,
            (sc.record_status_lk = 'FUTR') DESC,
            sc.contract_id DESC
        ) AS rn
      FROM salary_candidates sc
    ) x
    WHERE x.rn = 1
  ),
  chosen_salary_enriched AS (
    -- Enrich chosen salary rows with per-year guarantee/protection info.
    SELECT
      cs.*,

      -- Raw protection amount selection.
      -- If amounts are absent but coverage implies FULL/NONE, fall back to cap/0.
      COALESCE(
        cp.effective_protection_amount,
        cp.protection_amount,
        CASE
          WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
          WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
          ELSE NULL
        END
      ) AS guaranteed_amount_raw,

      CASE
        WHEN (
          COALESCE(
            cp.effective_protection_amount,
            cp.protection_amount,
            CASE
              WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
              WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
              ELSE NULL
            END
          )
        ) IS NULL THEN NULL
        WHEN cs.contract_cap_salary IS NULL THEN
          GREATEST(
            COALESCE(
              cp.effective_protection_amount,
              cp.protection_amount,
              CASE
                WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                ELSE NULL
              END
            ),
            0
          )
        ELSE
          LEAST(
            GREATEST(
              COALESCE(
                cp.effective_protection_amount,
                cp.protection_amount,
                CASE
                  WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                  WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                  ELSE NULL
                END
              ),
              0
            ),
            cs.contract_cap_salary
          )
      END AS guaranteed_amount,

      CASE
        WHEN cs.contract_cap_salary IS NULL OR cs.contract_cap_salary = 0 THEN NULL
        WHEN (
          CASE
            WHEN (
              COALESCE(
                cp.effective_protection_amount,
                cp.protection_amount,
                CASE
                  WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                  WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                  ELSE NULL
                END
              )
            ) IS NULL THEN NULL
            ELSE
              LEAST(
                GREATEST(
                  COALESCE(
                    cp.effective_protection_amount,
                    cp.protection_amount,
                    CASE
                      WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                      WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                      ELSE NULL
                    END
                  ),
                  0
                ),
                cs.contract_cap_salary
              )
          END
        ) >= cs.contract_cap_salary THEN true
        ELSE false
      END AS is_fully_guaranteed,

      CASE
        WHEN cs.contract_cap_salary IS NULL OR cs.contract_cap_salary = 0 THEN NULL
        WHEN (
          CASE
            WHEN (
              COALESCE(
                cp.effective_protection_amount,
                cp.protection_amount,
                CASE
                  WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                  WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                  ELSE NULL
                END
              )
            ) IS NULL THEN NULL
            ELSE
              LEAST(
                GREATEST(
                  COALESCE(
                    cp.effective_protection_amount,
                    cp.protection_amount,
                    CASE
                      WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                      WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                      ELSE NULL
                    END
                  ),
                  0
                ),
                cs.contract_cap_salary
              )
          END
        ) = 0 THEN true
        ELSE false
      END AS is_non_guaranteed,

      CASE
        WHEN cs.contract_cap_salary IS NULL OR cs.contract_cap_salary = 0 THEN NULL
        ELSE
          (
            (
              CASE
                WHEN (
                  COALESCE(
                    cp.effective_protection_amount,
                    cp.protection_amount,
                    CASE
                      WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                      WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                      ELSE NULL
                    END
                  )
                ) IS NULL THEN NULL
                ELSE
                  LEAST(
                    GREATEST(
                      COALESCE(
                        cp.effective_protection_amount,
                        cp.protection_amount,
                        CASE
                          WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                          WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                          ELSE NULL
                        END
                      ),
                      0
                    ),
                    cs.contract_cap_salary
                  )
              END
            ) > 0
            AND (
              CASE
                WHEN (
                  COALESCE(
                    cp.effective_protection_amount,
                    cp.protection_amount,
                    CASE
                      WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                      WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                      ELSE NULL
                    END
                  )
                ) IS NULL THEN NULL
                ELSE
                  LEAST(
                    GREATEST(
                      COALESCE(
                        cp.effective_protection_amount,
                        cp.protection_amount,
                        CASE
                          WHEN cp.protection_coverage_lk = 'FULL' THEN cs.contract_cap_salary
                          WHEN cp.protection_coverage_lk IN ('NONE', 'NOCND') THEN 0
                          ELSE NULL
                        END
                      ),
                      0
                    ),
                    cs.contract_cap_salary
                  )
              END
            ) < cs.contract_cap_salary
          )
      END AS is_partially_guaranteed

    FROM chosen_salary cs
    LEFT JOIN pcms.contract_protections cp
      ON cp.contract_id = cs.contract_id
     AND cp.version_number = cs.version_number
     AND cp.salary_year = cs.salary_year
  ),
  sp AS (
    -- Pivot the chosen per-year salaries into a single row per player.
    SELECT
      cs.player_id,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.contract_cap_salary END) AS cap_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.contract_cap_salary END) AS cap_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.contract_cap_salary END) AS cap_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.contract_cap_salary END) AS cap_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.contract_cap_salary END) AS cap_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.contract_cap_salary END) AS cap_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.contract_tax_salary END) AS tax_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.contract_tax_salary END) AS tax_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.contract_tax_salary END) AS tax_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.contract_tax_salary END) AS tax_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.contract_tax_salary END) AS tax_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.contract_tax_salary END) AS tax_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.contract_tax_apron_salary END) AS apron_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.contract_tax_apron_salary END) AS apron_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.contract_tax_apron_salary END) AS apron_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.contract_tax_apron_salary END) AS apron_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.contract_tax_apron_salary END) AS apron_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.contract_tax_apron_salary END) AS apron_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.option_lk END) AS option_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.option_lk END) AS option_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.option_lk END) AS option_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.option_lk END) AS option_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.option_lk END) AS option_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.option_lk END) AS option_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.option_decision_lk END) AS option_decision_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.option_decision_lk END) AS option_decision_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.option_decision_lk END) AS option_decision_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.option_decision_lk END) AS option_decision_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.option_decision_lk END) AS option_decision_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.option_decision_lk END) AS option_decision_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.guaranteed_amount END) AS guaranteed_amount_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.guaranteed_amount END) AS guaranteed_amount_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.guaranteed_amount END) AS guaranteed_amount_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.guaranteed_amount END) AS guaranteed_amount_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.guaranteed_amount END) AS guaranteed_amount_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.guaranteed_amount END) AS guaranteed_amount_2030,

      BOOL_OR(cs.is_fully_guaranteed) FILTER (WHERE cs.salary_year = 2025) AS is_fully_guaranteed_2025,
      BOOL_OR(cs.is_fully_guaranteed) FILTER (WHERE cs.salary_year = 2026) AS is_fully_guaranteed_2026,
      BOOL_OR(cs.is_fully_guaranteed) FILTER (WHERE cs.salary_year = 2027) AS is_fully_guaranteed_2027,
      BOOL_OR(cs.is_fully_guaranteed) FILTER (WHERE cs.salary_year = 2028) AS is_fully_guaranteed_2028,
      BOOL_OR(cs.is_fully_guaranteed) FILTER (WHERE cs.salary_year = 2029) AS is_fully_guaranteed_2029,
      BOOL_OR(cs.is_fully_guaranteed) FILTER (WHERE cs.salary_year = 2030) AS is_fully_guaranteed_2030,

      BOOL_OR(cs.is_partially_guaranteed) FILTER (WHERE cs.salary_year = 2025) AS is_partially_guaranteed_2025,
      BOOL_OR(cs.is_partially_guaranteed) FILTER (WHERE cs.salary_year = 2026) AS is_partially_guaranteed_2026,
      BOOL_OR(cs.is_partially_guaranteed) FILTER (WHERE cs.salary_year = 2027) AS is_partially_guaranteed_2027,
      BOOL_OR(cs.is_partially_guaranteed) FILTER (WHERE cs.salary_year = 2028) AS is_partially_guaranteed_2028,
      BOOL_OR(cs.is_partially_guaranteed) FILTER (WHERE cs.salary_year = 2029) AS is_partially_guaranteed_2029,
      BOOL_OR(cs.is_partially_guaranteed) FILTER (WHERE cs.salary_year = 2030) AS is_partially_guaranteed_2030,

      BOOL_OR(cs.is_non_guaranteed) FILTER (WHERE cs.salary_year = 2025) AS is_non_guaranteed_2025,
      BOOL_OR(cs.is_non_guaranteed) FILTER (WHERE cs.salary_year = 2026) AS is_non_guaranteed_2026,
      BOOL_OR(cs.is_non_guaranteed) FILTER (WHERE cs.salary_year = 2027) AS is_non_guaranteed_2027,
      BOOL_OR(cs.is_non_guaranteed) FILTER (WHERE cs.salary_year = 2028) AS is_non_guaranteed_2028,
      BOOL_OR(cs.is_non_guaranteed) FILTER (WHERE cs.salary_year = 2029) AS is_non_guaranteed_2029,
      BOOL_OR(cs.is_non_guaranteed) FILTER (WHERE cs.salary_year = 2030) AS is_non_guaranteed_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.likely_bonus END) AS likely_bonus_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.likely_bonus END) AS likely_bonus_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.likely_bonus END) AS likely_bonus_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.likely_bonus END) AS likely_bonus_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.likely_bonus END) AS likely_bonus_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.likely_bonus END) AS likely_bonus_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.unlikely_bonus END) AS unlikely_bonus_2025,
      MAX(CASE WHEN cs.salary_year = 2026 THEN cs.unlikely_bonus END) AS unlikely_bonus_2026,
      MAX(CASE WHEN cs.salary_year = 2027 THEN cs.unlikely_bonus END) AS unlikely_bonus_2027,
      MAX(CASE WHEN cs.salary_year = 2028 THEN cs.unlikely_bonus END) AS unlikely_bonus_2028,
      MAX(CASE WHEN cs.salary_year = 2029 THEN cs.unlikely_bonus END) AS unlikely_bonus_2029,
      MAX(CASE WHEN cs.salary_year = 2030 THEN cs.unlikely_bonus END) AS unlikely_bonus_2030,

      MAX(CASE WHEN cs.salary_year = 2025 THEN cs.trade_bonus_amount_calc END) AS trade_bonus_amount_2025,

      SUM(cs.total_salary)::bigint AS total_salary_from_2025

    FROM chosen_salary_enriched cs
    GROUP BY 1
  )
  SELECT
    p.person_id AS player_id,
    p.display_last_name || ', ' || p.display_first_name AS player_name,
    p.league_lk,

    COALESCE(ac.team_code, p.team_code) AS team_code,
    ac.team_code AS contract_team_code,
    p.team_code AS person_team_code,
    ac.signing_team_id,

    ac.contract_id,
    ac.version_number,

    p.birth_date,

    CASE
      WHEN p.birth_date IS NULL THEN NULL
      ELSE ROUND((EXTRACT(EPOCH FROM age(current_date, p.birth_date)) / 31557600.0)::numeric, 1)
    END AS age,

    ag.full_name AS agent_name,
    p.agent_id,

    sp.cap_2025, sp.cap_2026, sp.cap_2027, sp.cap_2028, sp.cap_2029, sp.cap_2030,

    (sp.cap_2025::numeric / NULLIF(lsv_2025.salary_cap_amount, 0)) AS pct_cap_2025,
    (sp.cap_2026::numeric / NULLIF(lsv_2026.salary_cap_amount, 0)) AS pct_cap_2026,
    (sp.cap_2027::numeric / NULLIF(lsv_2027.salary_cap_amount, 0)) AS pct_cap_2027,
    (sp.cap_2028::numeric / NULLIF(lsv_2028.salary_cap_amount, 0)) AS pct_cap_2028,
    (sp.cap_2029::numeric / NULLIF(lsv_2029.salary_cap_amount, 0)) AS pct_cap_2029,
    (sp.cap_2030::numeric / NULLIF(lsv_2030.salary_cap_amount, 0)) AS pct_cap_2030,

    sp.total_salary_from_2025,

    NULLIF(sp.option_2025, 'NONE') AS option_2025,
    NULLIF(sp.option_2026, 'NONE') AS option_2026,
    NULLIF(sp.option_2027, 'NONE') AS option_2027,
    NULLIF(sp.option_2028, 'NONE') AS option_2028,
    NULLIF(sp.option_2029, 'NONE') AS option_2029,
    NULLIF(sp.option_2030, 'NONE') AS option_2030,

    sp.option_decision_2025,
    sp.option_decision_2026,
    sp.option_decision_2027,
    sp.option_decision_2028,
    sp.option_decision_2029,
    sp.option_decision_2030,

    sp.guaranteed_amount_2025,
    sp.guaranteed_amount_2026,
    sp.guaranteed_amount_2027,
    sp.guaranteed_amount_2028,
    sp.guaranteed_amount_2029,
    sp.guaranteed_amount_2030,

    sp.is_fully_guaranteed_2025,
    sp.is_fully_guaranteed_2026,
    sp.is_fully_guaranteed_2027,
    sp.is_fully_guaranteed_2028,
    sp.is_fully_guaranteed_2029,
    sp.is_fully_guaranteed_2030,

    sp.is_partially_guaranteed_2025,
    sp.is_partially_guaranteed_2026,
    sp.is_partially_guaranteed_2027,
    sp.is_partially_guaranteed_2028,
    sp.is_partially_guaranteed_2029,
    sp.is_partially_guaranteed_2030,

    sp.is_non_guaranteed_2025,
    sp.is_non_guaranteed_2026,
    sp.is_non_guaranteed_2027,
    sp.is_non_guaranteed_2028,
    sp.is_non_guaranteed_2029,
    sp.is_non_guaranteed_2030,

    sp.likely_bonus_2025,
    sp.likely_bonus_2026,
    sp.likely_bonus_2027,
    sp.likely_bonus_2028,
    sp.likely_bonus_2029,
    sp.likely_bonus_2030,

    sp.unlikely_bonus_2025,
    sp.unlikely_bonus_2026,
    sp.unlikely_bonus_2027,
    sp.unlikely_bonus_2028,
    sp.unlikely_bonus_2029,
    sp.unlikely_bonus_2030,

    ac.is_two_way,
    ac.is_poison_pill,
    ac.poison_pill_amount,
    ac.is_no_trade,
    ac.is_trade_bonus,
    ac.trade_bonus_percent,

    sp.trade_bonus_amount_2025 AS trade_kicker_amount_2025,
    CASE
      WHEN ac.is_trade_bonus AND ac.trade_bonus_percent IS NOT NULL THEN (ac.trade_bonus_percent::text || '%')
      WHEN ac.is_trade_bonus THEN 'TK'
      ELSE NULL
    END AS trade_kicker_display,

    sp.tax_2025, sp.tax_2026, sp.tax_2027, sp.tax_2028, sp.tax_2029, sp.tax_2030,
    sp.apron_2025, sp.apron_2026, sp.apron_2027, sp.apron_2028, sp.apron_2029, sp.apron_2030,

    sp.cap_2025 AS outgoing_buildup_2025,
    (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_buildup_2025,
    (sp.cap_2025 + COALESCE(sp.trade_bonus_amount_2025, 0)) AS incoming_salary_2025,
    sp.tax_2025 AS incoming_tax_2025,
    sp.apron_2025 AS incoming_apron_2025,

    ac.player_consent_lk AS player_consent_lk,
    ac.player_consent_end_date,

    COALESCE(
      (
        ac.player_consent_lk IN ('YEARK', 'ROFRE')
        AND (
          ac.player_consent_end_date IS NULL
          OR ac.player_consent_end_date >= current_date
        )
      ),
      false
    ) AS is_trade_consent_required_now,

    COALESCE((ac.player_consent_lk = 'YRKPC'), false) AS is_trade_preconsented,

    now() AS refreshed_at

  FROM pcms.people p
  JOIN ac
    ON ac.player_id = p.person_id
  LEFT JOIN sp
    ON sp.player_id = p.person_id
  LEFT JOIN pcms.agents ag
    ON ag.agent_id = p.agent_id

  LEFT JOIN pcms.league_system_values lsv_2025
    ON lsv_2025.league_lk = 'NBA' AND lsv_2025.salary_year = 2025
  LEFT JOIN pcms.league_system_values lsv_2026
    ON lsv_2026.league_lk = 'NBA' AND lsv_2026.salary_year = 2026
  LEFT JOIN pcms.league_system_values lsv_2027
    ON lsv_2027.league_lk = 'NBA' AND lsv_2027.salary_year = 2027
  LEFT JOIN pcms.league_system_values lsv_2028
    ON lsv_2028.league_lk = 'NBA' AND lsv_2028.salary_year = 2028
  LEFT JOIN pcms.league_system_values lsv_2029
    ON lsv_2029.league_lk = 'NBA' AND lsv_2029.salary_year = 2029
  LEFT JOIN pcms.league_system_values lsv_2030
    ON lsv_2030.league_lk = 'NBA' AND lsv_2030.salary_year = 2030

  WHERE p.person_type_lk = 'PLYR'
    AND p.league_lk IN ('NBA', 'DLG');
END;
$$;

COMMIT;
