module PlayerQueries
  module_function

  def fetch_team_options
    conn.exec_query(<<~SQL).to_a
      SELECT team_code, team_name
      FROM pcms.teams
      WHERE league_lk = 'NBA'
        AND team_name NOT LIKE 'Non-NBA%'
      ORDER BY team_code
    SQL
  end

  def fetch_sidebar_player(player_id)
    normalized_id = Integer(player_id)
    raise ActiveRecord::RecordNotFound if normalized_id <= 0

    id_sql = conn.quote(normalized_id)

    player = conn.exec_query(<<~SQL).first
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.agent_id,
        sbw.agent_name,
        sbw.is_two_way,
        sbw.is_trade_restricted_now,
        sbw.is_no_trade,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.cap_2026::numeric AS cap_2026,
        sbw.cap_2027::numeric AS cap_2027,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        p.years_of_service,
        p.player_status_lk,
        status_lk.short_description AS player_status_name
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      LEFT JOIN pcms.people p
        ON p.person_id = sbw.player_id
      LEFT JOIN pcms.lookups status_lk
        ON status_lk.lookup_type = 'lk_player_statuses'
       AND status_lk.lookup_code = p.player_status_lk
      WHERE sbw.player_id = #{id_sql}
      LIMIT 1
    SQL
    raise ActiveRecord::RecordNotFound unless player

    player
  end

  def fetch_player_person(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).first
      SELECT
        p.person_id,
        COALESCE(p.display_first_name, p.first_name) AS first_name,
        COALESCE(p.display_last_name, p.last_name) AS last_name,
        p.birth_date,
        p.height,
        p.weight,
        p.uniform_number,
        p.years_of_service,
        p.draft_year,
        p.draft_round,
        p.draft_pick,
        p.draft_team_id,
        p.draft_team_code,
        p.player_status_lk,
        status_lk.short_description AS player_status_name,
        p.birth_country_lk,
        p.team_id AS person_team_id,
        p.team_code AS person_team_code,
        p.is_two_way AS person_is_two_way
      FROM pcms.people p
      LEFT JOIN pcms.lookups status_lk
        ON status_lk.lookup_type = 'lk_player_statuses'
       AND status_lk.lookup_code = p.player_status_lk
      WHERE p.person_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_player_salary_book_context(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).first
      SELECT
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.agent_id,
        sbw.agent_name,
        agency.agency_id,
        agency.agency_name,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        sbw.contract_id,
        sbw.version_number,
        sbw.contract_type_lookup_value,
        sbw.signed_method_lookup_value,
        sbw.exception_type_lookup_value,
        sbw.min_contract_lookup_value,
        sbw.player_consent_lk,
        consent_lk.short_description AS player_consent_label,
        sbw.player_consent_end_date,
        sbw.is_trade_consent_required_now,
        sbw.is_trade_preconsented,
        sbw.trade_restriction_code,
        sbw.trade_restriction_lookup_value,
        sbw.trade_restriction_end_date,
        sbw.is_trade_restricted_now,
        sbw.is_no_trade,
        sbw.is_trade_bonus,
        sbw.trade_bonus_percent,
        sbw.trade_kicker_display,
        sbw.is_poison_pill,
        sbw.is_two_way,
        sbw.is_min_contract,
        sbw.guaranteed_amount_2025,
        sbw.guaranteed_amount_2026,
        sbw.guaranteed_amount_2027,
        sbw.guaranteed_amount_2028,
        sbw.guaranteed_amount_2029,
        sbw.guaranteed_amount_2030,
        sbw.is_fully_guaranteed_2025,
        sbw.is_fully_guaranteed_2026,
        sbw.is_fully_guaranteed_2027,
        sbw.is_fully_guaranteed_2028,
        sbw.is_fully_guaranteed_2029,
        sbw.is_fully_guaranteed_2030,
        sbw.is_partially_guaranteed_2025,
        sbw.is_partially_guaranteed_2026,
        sbw.is_partially_guaranteed_2027,
        sbw.is_partially_guaranteed_2028,
        sbw.is_partially_guaranteed_2029,
        sbw.is_partially_guaranteed_2030,
        sbw.is_non_guaranteed_2025,
        sbw.is_non_guaranteed_2026,
        sbw.is_non_guaranteed_2027,
        sbw.is_non_guaranteed_2028,
        sbw.is_non_guaranteed_2029,
        sbw.is_non_guaranteed_2030
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      LEFT JOIN pcms.agents agent
        ON agent.agent_id = sbw.agent_id
      LEFT JOIN pcms.agencies agency
        ON agency.agency_id = agent.agency_id
      LEFT JOIN pcms.lookups consent_lk
        ON consent_lk.lookup_type = 'lk_player_consents'
       AND consent_lk.lookup_code = sbw.player_consent_lk
      WHERE sbw.player_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_player_draft_selection(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).first
      SELECT
        transaction_id,
        draft_year,
        draft_round,
        pick_number,
        drafting_team_id,
        drafting_team_code,
        transaction_date
      FROM pcms.draft_selections
      WHERE player_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_index_players(where_sql:, sort_sql:, limit:, horizon_cap_column:, next_horizon_year:, option_presence_sql:, non_guaranteed_presence_sql:, lock_now_sql:, expiring_sql:, next_option_sql:, next_non_guaranteed_sql:)
    next_cap_column = "sbw.cap_#{next_horizon_year}"

    conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.agent_id,
        sbw.agent_name,
        sbw.is_two_way,
        sbw.is_trade_restricted_now,
        sbw.is_trade_consent_required_now,
        sbw.is_no_trade,
        sbw.is_trade_bonus,
        (#{option_presence_sql}) AS has_future_option,
        (#{non_guaranteed_presence_sql}) AS has_non_guaranteed,
        (#{next_option_sql} IS NOT NULL) AS has_next_horizon_option,
        #{next_option_sql} AS next_horizon_option,
        (#{next_non_guaranteed_sql}) AS has_next_horizon_non_guaranteed,
        #{lock_now_sql} AS has_lock_now,
        (#{expiring_sql}) AS expires_after_horizon,
        #{horizon_cap_column}::numeric AS cap_lens_value,
        #{next_cap_column}::numeric AS cap_next_value,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.cap_2026::numeric AS cap_2026,
        sbw.cap_2027::numeric AS cap_2027,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        p.years_of_service,
        p.player_status_lk,
        status_lk.short_description AS player_status_name
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      LEFT JOIN pcms.people p
        ON p.person_id = sbw.player_id
      LEFT JOIN pcms.lookups status_lk
        ON status_lk.lookup_type = 'lk_player_statuses'
       AND status_lk.lookup_code = p.player_status_lk
      WHERE #{where_sql}
      ORDER BY #{sort_sql}
      LIMIT #{limit}
    SQL
  end

  def fetch_player_team_history(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).to_a
      WITH team_transactions AS (
        SELECT
          tx.transaction_id,
          tx.transaction_date,
          tx.transaction_type_lk,
          COALESCE(to_team.team_id, from_team.team_id) AS team_id,
          COALESCE(to_team.team_code, from_team.team_code) AS team_code,
          COALESCE(to_team.team_name, from_team.team_name) AS team_name,
          tx.trade_id
        FROM pcms.transactions tx
        LEFT JOIN pcms.teams from_team ON from_team.team_id = tx.from_team_id AND from_team.league_lk = 'NBA'
        LEFT JOIN pcms.teams to_team ON to_team.team_id = tx.to_team_id AND to_team.league_lk = 'NBA'
        WHERE tx.player_id = #{id_sql}
          AND tx.transaction_type_lk IN ('SIGN', 'TRADE', 'DRAFT', 'DDRFT', 'WSIGN', 'REAQC', 'REAQT', 'CLLUP', '2WCNV')
      )
      SELECT
        team_code,
        team_id,
        team_name,
        MIN(transaction_date) AS start_date,
        MAX(transaction_date) AS last_date,
        array_agg(DISTINCT transaction_type_lk ORDER BY transaction_type_lk) AS tx_types,
        COUNT(*)::integer AS tx_count
      FROM team_transactions
      WHERE team_code IS NOT NULL
      GROUP BY team_code, team_id, team_name
      ORDER BY start_date
    SQL
  end

  def fetch_player_salary_book_yearly(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        salary_year,
        cap_amount,
        tax_amount,
        apron_amount,
        incoming_cap_amount,
        incoming_tax_amount,
        incoming_apron_amount,
        trade_kicker_amount,
        is_two_way,
        refreshed_at
      FROM pcms.salary_book_yearly
      WHERE player_id = #{id_sql}
        AND salary_year BETWEEN 2025 AND 2030
      ORDER BY salary_year
    SQL
  end

  def fetch_player_contract_chronology(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        c.contract_id,
        c.signing_date,
        c.contract_end_date,
        c.start_year,
        c.record_status_lk,
        c.signed_method_lk,
        COALESCE(signed_lk.short_description, signed_lk.description) AS signed_method_label,
        c.team_exception_id,
        te.exception_type_lk,
        COALESCE(exc_lk.short_description, exc_lk.description) AS exception_type_label,
        c.is_sign_and_trade,
        c.sign_and_trade_date,
        c.sign_and_trade_id,
        c.two_way_service_limit,
        c.convert_date,
        c.team_code,
        c.signing_team_id,
        signing_team.team_code AS signing_team_code,
        signing_team.team_name AS signing_team_name,
        c.sign_and_trade_to_team_id,
        sat_team.team_code AS sign_and_trade_to_team_code,
        sat_team.team_name AS sign_and_trade_to_team_name,
        COUNT(cv.contract_version_id)::integer AS version_count,
        MIN(cv.start_salary_year) AS min_version_start_year,
        MAX(cv.version_number) AS latest_version_number
      FROM pcms.contracts c
      LEFT JOIN pcms.lookups signed_lk
        ON signed_lk.lookup_type = 'lk_signed_methods'
       AND signed_lk.lookup_code = c.signed_method_lk
      LEFT JOIN pcms.team_exceptions te
        ON te.team_exception_id = c.team_exception_id
      LEFT JOIN pcms.lookups exc_lk
        ON exc_lk.lookup_type = 'lk_exception_types'
       AND exc_lk.lookup_code = te.exception_type_lk
      LEFT JOIN pcms.teams signing_team
        ON signing_team.team_id = c.signing_team_id
      LEFT JOIN pcms.teams sat_team
        ON sat_team.team_id = c.sign_and_trade_to_team_id
      LEFT JOIN pcms.contract_versions cv
        ON cv.contract_id = c.contract_id
      WHERE c.player_id = #{id_sql}
      GROUP BY
        c.contract_id,
        c.signing_date,
        c.contract_end_date,
        c.start_year,
        c.record_status_lk,
        c.signed_method_lk,
        signed_lk.short_description,
        signed_lk.description,
        c.team_exception_id,
        te.exception_type_lk,
        exc_lk.short_description,
        exc_lk.description,
        c.is_sign_and_trade,
        c.sign_and_trade_date,
        c.sign_and_trade_id,
        c.two_way_service_limit,
        c.convert_date,
        c.team_code,
        c.signing_team_id,
        signing_team.team_code,
        signing_team.team_name,
        c.sign_and_trade_to_team_id,
        sat_team.team_code,
        sat_team.team_name
      ORDER BY c.signing_date DESC NULLS LAST, c.contract_id DESC
    SQL
  end

  def fetch_player_contract_versions(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        cv.contract_id,
        cv.version_number,
        cv.version_date,
        cv.start_salary_year,
        cv.contract_length,
        cv.contract_type_lk,
        COALESCE(contract_type_lk.short_description, contract_type_lk.description) AS contract_type_label,
        cv.record_status_lk,
        cv.is_rookie_scale_extension,
        cv.is_veteran_extension,
        cv.is_exhibit_10,
        cv.exhibit_10_bonus_amount,
        cv.is_poison_pill,
        cv.poison_pill_amount,
        cv.is_trade_bonus,
        cv.trade_bonus_percent,
        cv.trade_bonus_amount,
        cv.is_no_trade,
        cv.is_protected_contract,
        cv.is_full_protection
      FROM pcms.contract_versions cv
      JOIN pcms.contracts c
        ON c.contract_id = cv.contract_id
      LEFT JOIN pcms.lookups contract_type_lk
        ON contract_type_lk.lookup_type = 'lk_contract_types'
       AND contract_type_lk.lookup_code = cv.contract_type_lk
      WHERE c.player_id = #{id_sql}
      ORDER BY c.signing_date DESC NULLS LAST, cv.contract_id DESC, cv.version_number DESC
      LIMIT 400
    SQL
  end

  def fetch_player_salaries(contract_id, version_number)
    contract_sql = conn.quote(contract_id)
    version_sql = conn.quote(version_number)

    conn.exec_query(<<~SQL).to_a
      SELECT
        salary_year,
        total_salary,
        current_base_comp,
        contract_cap_salary,
        contract_tax_salary,
        contract_tax_apron_salary,
        signing_bonus,
        likely_bonus,
        unlikely_bonus,
        trade_bonus_amount,
        option_lk,
        option_decision_lk
      FROM pcms.salaries
      WHERE contract_id = #{contract_sql}
        AND version_number = #{version_sql}
        AND salary_year BETWEEN 2024 AND 2031
      ORDER BY salary_year
    SQL
  end

  def fetch_player_protections(contract_id, version_number)
    contract_sql = conn.quote(contract_id)
    version_sql = conn.quote(version_number)

    conn.exec_query(<<~SQL).to_a
      SELECT
        salary_year,
        SUM(protection_amount)::bigint AS protection_amount,
        SUM(effective_protection_amount)::bigint AS effective_protection_amount,
        BOOL_OR(COALESCE(is_conditional_protection, false)) AS has_conditional,
        STRING_AGG(DISTINCT protection_coverage_lk, ', ' ORDER BY protection_coverage_lk) AS coverage_codes,
        COUNT(*)::integer AS row_count
      FROM pcms.contract_protections
      WHERE contract_id = #{contract_sql}
        AND version_number = #{version_sql}
      GROUP BY salary_year
      ORDER BY salary_year
    SQL
  end

  def fetch_player_protection_conditions(contract_id, version_number)
    contract_sql = conn.quote(contract_id)
    version_sql = conn.quote(version_number)

    conn.exec_query(<<~SQL).to_a
      SELECT
        cpc.condition_id,
        cp.salary_year,
        cpc.amount,
        cpc.earned_type_lk,
        cpc.earned_date,
        cpc.is_full_condition,
        cpc.clause_name,
        cpc.criteria_description
      FROM pcms.contract_protection_conditions cpc
      LEFT JOIN pcms.contract_protections cp
        ON cp.protection_id = cpc.protection_id
       AND cp.contract_id = cpc.contract_id
       AND cp.version_number = cpc.version_number
      WHERE cpc.contract_id = #{contract_sql}
        AND cpc.version_number = #{version_sql}
      ORDER BY cp.salary_year, cpc.amount DESC NULLS LAST, cpc.condition_id
      LIMIT 120
    SQL
  end

  def fetch_player_bonuses(contract_id, version_number)
    contract_sql = conn.quote(contract_id)
    version_sql = conn.quote(version_number)

    conn.exec_query(<<~SQL).to_a
      SELECT
        bonus_id,
        salary_year,
        bonus_type_lk,
        is_likely,
        bonus_amount,
        earned_lk,
        paid_by_date,
        clause_name,
        criteria_description
      FROM pcms.contract_bonuses
      WHERE contract_id = #{contract_sql}
        AND version_number = #{version_sql}
      ORDER BY salary_year, is_likely DESC, bonus_amount DESC NULLS LAST, bonus_id
      LIMIT 200
    SQL
  end

  def fetch_player_bonus_maximums(contract_id, version_number)
    contract_sql = conn.quote(contract_id)
    version_sql = conn.quote(version_number)

    conn.exec_query(<<~SQL).to_a
      SELECT
        salary_year,
        bonus_type_lk,
        is_likely,
        max_amount
      FROM pcms.contract_bonus_maximums
      WHERE contract_id = #{contract_sql}
        AND version_number = #{version_sql}
      ORDER BY salary_year, max_amount DESC NULLS LAST
    SQL
  end

  def fetch_player_payment_schedules(contract_id, version_number)
    contract_sql = conn.quote(contract_id)
    version_sql = conn.quote(version_number)

    conn.exec_query(<<~SQL).to_a
      SELECT
        ps.payment_schedule_id,
        ps.salary_year,
        ps.payment_amount,
        ps.payment_start_date,
        ps.schedule_type_lk,
        ps.payment_type_lk,
        ps.is_default_schedule,
        COALESCE(detail_agg.detail_count, 0)::integer AS detail_count,
        detail_agg.first_payment_date,
        detail_agg.last_payment_date
      FROM pcms.payment_schedules ps
      LEFT JOIN (
        SELECT
          payment_schedule_id,
          COUNT(*)::integer AS detail_count,
          MIN(payment_date) AS first_payment_date,
          MAX(payment_date) AS last_payment_date
        FROM pcms.payment_schedule_details
        GROUP BY payment_schedule_id
      ) detail_agg
        ON detail_agg.payment_schedule_id = ps.payment_schedule_id
      WHERE ps.contract_id = #{contract_sql}
        AND ps.version_number = #{version_sql}
      ORDER BY ps.salary_year, ps.payment_start_date NULLS LAST, ps.payment_schedule_id
    SQL
  end

  def fetch_player_ledger_entries(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        le.ledger_date,
        le.salary_year,
        le.transaction_id,
        tx.trade_id,
        le.transaction_type_lk,
        le.transaction_description_lk,
        le.team_id,
        t.team_code,
        t.team_name,
        le.cap_amount,
        le.cap_change,
        le.tax_change,
        le.apron_change,
        le.mts_change
      FROM pcms.ledger_entries le
      LEFT JOIN pcms.transactions tx
        ON tx.transaction_id = le.transaction_id
      LEFT JOIN pcms.teams t
        ON t.team_id = le.team_id
       AND t.league_lk = 'NBA'
      WHERE le.player_id = #{id_sql}
        AND le.league_lk = 'NBA'
      ORDER BY le.ledger_date DESC, le.transaction_ledger_entry_id DESC
      LIMIT 80
    SQL
  end

  def conn
    ActiveRecord::Base.connection
  end
  private_class_method :conn
end
