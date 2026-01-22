-- 015_update_salary_book_refresh.sql
--
-- Make refresh fast by sourcing everything from vw_y_warehouse directly.
-- (Avoid joining vw_active_contract_versions again, which inlines heavy window logic twice.)

BEGIN;

CREATE OR REPLACE FUNCTION pcms.refresh_salary_book_warehouse()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
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
    refreshed_at
  )
  SELECT
    y.player_id,
    y.player_name,
    y.league_lk,
    y.team_code,
    y.contract_team_code,
    y.person_team_code,
    y.signing_team_id,
    y.contract_id,
    y.version_number,
    y.birth_date,
    y.age,
    y.agent_name,
    y.agent_id,
    y.cap_2025, y.cap_2026, y.cap_2027, y.cap_2028, y.cap_2029, y.cap_2030,
    y.pct_cap_2025, y.pct_cap_2026, y.pct_cap_2027, y.pct_cap_2028, y.pct_cap_2029, y.pct_cap_2030,
    y.total_salary_from_2025::bigint,
    y.option_2025, y.option_2026, y.option_2027, y.option_2028, y.option_2029, y.option_2030,
    y.option_decision_2025, y.option_decision_2026, y.option_decision_2027,
    y.option_decision_2028, y.option_decision_2029, y.option_decision_2030,
    y.is_two_way,
    y.is_poison_pill,
    y.poison_pill_amount,
    y.is_no_trade,
    y.is_trade_bonus,
    y.trade_bonus_percent,
    y.trade_kicker_amount_2025,
    y.trade_kicker_display,
    y.tax_2025, y.tax_2026, y.tax_2027, y.tax_2028, y.tax_2029, y.tax_2030,
    y.apron_2025, y.apron_2026, y.apron_2027, y.apron_2028, y.apron_2029, y.apron_2030,
    y.outgoing_buildup_2025,
    y.incoming_buildup_2025,
    y.incoming_salary_2025,
    y.incoming_tax_2025,
    y.incoming_apron_2025,
    now()
  FROM pcms.vw_y_warehouse y;
END;
$$;

COMMIT;
