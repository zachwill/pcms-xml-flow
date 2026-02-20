class AgentQueries
  def initialize(connection: ActiveRecord::Base.connection)
    @connection = connection
  end

  private attr_reader :connection

  def conn
    connection
  end

  def fetch_agent_for_show(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first
      SELECT agent_id, full_name, agency_id, agency_name, is_active, is_certified
      FROM pcms.agents
      WHERE agent_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_agency(agency_id)
    agency_sql = conn.quote(agency_id)

    conn.exec_query(<<~SQL).first
      SELECT agency_id, agency_name, is_active
      FROM pcms.agencies
      WHERE agency_id = #{agency_sql}
      LIMIT 1
    SQL
  end

  def fetch_agency_name(agency_id)
    agency_sql = conn.quote(agency_id)

    conn.exec_query(<<~SQL).first&.dig("agency_name")
      SELECT agency_name
      FROM pcms.agencies
      WHERE agency_id = #{agency_sql}
      LIMIT 1
    SQL
  end

  def fetch_agency_filter_options(limit: 400)
    limit_sql = limit.to_i.positive? ? limit.to_i : 400

    conn.exec_query(<<~SQL).to_a
      SELECT
        aw.agency_id,
        aw.agency_name,
        COALESCE(aw.agent_count, 0)::integer AS agent_count,
        COALESCE(aw.client_count, 0)::integer AS client_count
      FROM pcms.agencies_warehouse aw
      WHERE aw.agency_id IS NOT NULL
        AND NULLIF(TRIM(aw.agency_name), '') IS NOT NULL
      ORDER BY aw.client_count DESC NULLS LAST, aw.agency_name ASC
      LIMIT #{limit_sql}
    SQL
  end

  def fetch_show_clients(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.age,
        p.years_of_service,
        p.display_first_name,
        p.display_last_name,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.cap_2026::numeric AS cap_2026,
        sbw.cap_2027::numeric AS cap_2027,
        sbw.cap_2028::numeric AS cap_2028,
        sbw.cap_2029::numeric AS cap_2029,
        sbw.cap_2030::numeric AS cap_2030,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        sbw.pct_cap_2025,
        COALESCE(sbw.is_two_way, false)::boolean AS is_two_way,
        COALESCE(sbw.is_min_contract, false)::boolean AS is_min_contract,
        COALESCE(sbw.is_no_trade, false)::boolean AS is_no_trade,
        COALESCE(sbw.is_trade_bonus, false)::boolean AS is_trade_bonus,
        sbw.trade_bonus_percent,
        COALESCE(sbw.is_trade_restricted_now, false)::boolean AS is_trade_restricted_now,
        sbw.option_2025,
        sbw.option_2026,
        sbw.option_2027,
        sbw.option_2028,
        sbw.contract_type_code,
        sbw.contract_type_lookup_value,
        sbw.signed_method_lookup_value
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.people p ON sbw.player_id = p.person_id
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE sbw.agent_id = #{id_sql}
      ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
    SQL
  end

  def fetch_show_client_rollup(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first || {}
      SELECT
        client_count,
        team_count,
        cap_2025_total,
        total_salary_from_2025,
        two_way_count,
        min_contract_count,
        trade_restricted_count AS restricted_now_count,

        standard_count,
        rookie_scale_count,
        max_contract_count,
        no_trade_count,
        trade_kicker_count,

        expiring_2025,
        expiring_2026,
        expiring_2027,

        player_option_count,
        team_option_count,
        prior_year_nba_now_free_agent_count,

        cap_2025_total_percentile,
        cap_2026_total_percentile,
        cap_2027_total_percentile,
        client_count_percentile,
        max_contract_count_percentile
      FROM pcms.agents_warehouse
      WHERE agent_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_show_team_distribution(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.team_code,
        t.team_id,
        t.team_name,
        COUNT(*)::integer AS client_count,
        COALESCE(SUM(sbw.cap_2025), 0)::bigint AS cap_2025_total,
        COALESCE(SUM(sbw.cap_2026), 0)::bigint AS cap_2026_total
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE sbw.agent_id = #{id_sql}
      GROUP BY sbw.team_code, t.team_id, t.team_name
      ORDER BY cap_2025_total DESC NULLS LAST, sbw.team_code
      LIMIT 30
    SQL
  end

  def fetch_show_book_by_year(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        sby.salary_year,
        COUNT(*)::integer AS player_count,
        COALESCE(SUM(sby.cap_amount), 0)::bigint AS cap_total,
        COALESCE(SUM(sby.tax_amount), 0)::bigint AS tax_total,
        COALESCE(SUM(sby.apron_amount), 0)::bigint AS apron_total
      FROM pcms.salary_book_yearly sby
      JOIN pcms.salary_book_warehouse sbw
        ON sbw.player_id = sby.player_id
      WHERE sbw.agent_id = #{id_sql}
        AND sby.salary_year BETWEEN 2025 AND 2030
      GROUP BY sby.salary_year
      ORDER BY sby.salary_year
    SQL
  end

  def fetch_show_historical_footprint_rollup(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first || {}
      WITH historical AS (
        SELECT
          c.player_id,
          c.contract_id,
          cv.contract_version_id,
          c.signing_date
        FROM pcms.contract_versions cv
        JOIN pcms.contracts c
          ON c.contract_id = cv.contract_id
        WHERE cv.agent_id = #{id_sql}
      ),
      current_clients AS (
        SELECT DISTINCT sbw.player_id
        FROM pcms.salary_book_warehouse sbw
        WHERE sbw.agent_id = #{id_sql}
      )
      SELECT
        COUNT(DISTINCT h.player_id)::integer AS historical_client_count,
        MIN(h.signing_date) AS first_signing_date,
        MAX(h.signing_date) AS last_signing_date,
        COUNT(DISTINCT h.contract_id)::integer AS contract_count,
        COUNT(h.contract_version_id)::integer AS version_count,
        COUNT(DISTINCT h.player_id) FILTER (WHERE cc.player_id IS NULL)::integer AS historical_not_current_client_count
      FROM historical h
      LEFT JOIN current_clients cc
        ON cc.player_id = h.player_id
    SQL
  end

  def fetch_show_historical_signing_trend(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        EXTRACT(YEAR FROM c.signing_date)::integer AS signing_year,
        COUNT(DISTINCT c.player_id)::integer AS distinct_clients,
        COUNT(DISTINCT c.contract_id)::integer AS contract_count,
        COUNT(cv.contract_version_id)::integer AS version_count
      FROM pcms.contract_versions cv
      JOIN pcms.contracts c
        ON c.contract_id = cv.contract_id
      WHERE cv.agent_id = #{id_sql}
        AND c.signing_date IS NOT NULL
      GROUP BY EXTRACT(YEAR FROM c.signing_date)
      ORDER BY signing_year DESC
      LIMIT 20
    SQL
  end

  def fetch_agent_name_for_redirect(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first
      SELECT full_name
      FROM pcms.agents
      WHERE agent_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_directory_agencies(where_sql:, sort_sql:, sort_direction:, book_total_sql:, book_percentile_sql:, expiring_sql:)
    conn.exec_query(<<~SQL).to_a
      SELECT
        w.agency_id,
        w.agency_name,
        w.is_active,

        COALESCE(w.agent_count, 0)::integer AS agent_count,
        COALESCE(w.client_count, 0)::integer AS client_count,
        COALESCE(w.standard_count, 0)::integer AS standard_count,
        COALESCE(w.two_way_count, 0)::integer AS two_way_count,
        COALESCE(w.team_count, 0)::integer AS team_count,

        COALESCE(#{book_total_sql}, 0)::bigint AS book_total,
        #{book_percentile_sql} AS book_total_percentile,
        COALESCE(w.cap_2025_total, 0)::bigint AS cap_2025_total,
        COALESCE(w.cap_2026_total, 0)::bigint AS cap_2026_total,
        COALESCE(w.cap_2027_total, 0)::bigint AS cap_2027_total,
        COALESCE(w.total_salary_from_2025, 0)::bigint AS total_salary_from_2025,

        COALESCE(w.max_contract_count, 0)::integer AS max_contract_count,
        COALESCE(w.rookie_scale_count, 0)::integer AS rookie_scale_count,
        COALESCE(w.min_contract_count, 0)::integer AS min_contract_count,

        COALESCE(w.no_trade_count, 0)::integer AS no_trade_count,
        COALESCE(w.trade_kicker_count, 0)::integer AS trade_kicker_count,
        COALESCE(w.trade_restricted_count, 0)::integer AS trade_restricted_count,

        COALESCE(#{expiring_sql}, 0)::integer AS expiring_in_window,
        COALESCE(w.expiring_2025, 0)::integer AS expiring_2025,
        COALESCE(w.expiring_2026, 0)::integer AS expiring_2026,
        COALESCE(w.expiring_2027, 0)::integer AS expiring_2027,

        COALESCE(w.player_option_count, 0)::integer AS player_option_count,
        COALESCE(w.team_option_count, 0)::integer AS team_option_count,

        w.agent_count_percentile,
        w.client_count_percentile,
        w.max_contract_count_percentile
      FROM pcms.agencies_warehouse w
      WHERE #{where_sql}
      ORDER BY #{sort_sql} #{sort_direction} NULLS LAST,
               w.agency_name ASC
    SQL
  end

  def fetch_directory_agents(where_sql:, sort_sql:, sort_direction:, book_total_sql:, book_percentile_sql:, expiring_sql:)
    conn.exec_query(<<~SQL).to_a
      SELECT
        w.agent_id,
        w.full_name,
        w.agency_id,
        w.agency_name,
        w.is_active,
        w.is_certified,

        COALESCE(w.client_count, 0)::integer AS client_count,
        COALESCE(w.standard_count, 0)::integer AS standard_count,
        COALESCE(w.two_way_count, 0)::integer AS two_way_count,
        COALESCE(w.team_count, 0)::integer AS team_count,

        COALESCE(#{book_total_sql}, 0)::bigint AS book_total,
        #{book_percentile_sql} AS book_total_percentile,
        COALESCE(w.cap_2025_total, 0)::bigint AS cap_2025_total,
        COALESCE(w.cap_2026_total, 0)::bigint AS cap_2026_total,
        COALESCE(w.cap_2027_total, 0)::bigint AS cap_2027_total,
        COALESCE(w.total_salary_from_2025, 0)::bigint AS total_salary_from_2025,

        COALESCE(w.max_contract_count, 0)::integer AS max_contract_count,
        COALESCE(w.rookie_scale_count, 0)::integer AS rookie_scale_count,
        COALESCE(w.min_contract_count, 0)::integer AS min_contract_count,

        COALESCE(w.no_trade_count, 0)::integer AS no_trade_count,
        COALESCE(w.trade_kicker_count, 0)::integer AS trade_kicker_count,
        COALESCE(w.trade_restricted_count, 0)::integer AS trade_restricted_count,

        COALESCE(#{expiring_sql}, 0)::integer AS expiring_in_window,
        COALESCE(w.expiring_2025, 0)::integer AS expiring_2025,
        COALESCE(w.expiring_2026, 0)::integer AS expiring_2026,
        COALESCE(w.expiring_2027, 0)::integer AS expiring_2027,

        COALESCE(w.player_option_count, 0)::integer AS player_option_count,
        COALESCE(w.team_option_count, 0)::integer AS team_option_count,

        w.client_count_percentile,
        w.team_count_percentile,
        w.standard_count_percentile,
        w.two_way_count_percentile,
        w.max_contract_count_percentile
      FROM pcms.agents_warehouse w
      WHERE #{where_sql}
      ORDER BY #{sort_sql} #{sort_direction} NULLS LAST,
               w.full_name ASC
    SQL
  end

  def fetch_index_top_clients_for_agents(agent_ids, limit_per_agent: 3, book_total_sql: "sbw.cap_2025")
    ids = Array(agent_ids).map(&:to_i).select(&:positive?).uniq
    return [] if ids.empty?

    limit = limit_per_agent.to_i
    limit = 3 if limit <= 0

    conn.exec_query(<<~SQL).to_a
      WITH ranked AS (
        SELECT
          sbw.agent_id,
          sbw.player_id,
          sbw.player_name,
          sbw.team_code,
          COALESCE(sbw.is_two_way, false)::boolean AS is_two_way,
          COALESCE(#{book_total_sql}, 0)::bigint AS book_total,
          ROW_NUMBER() OVER (
            PARTITION BY sbw.agent_id
            ORDER BY #{book_total_sql} DESC NULLS LAST, sbw.player_name ASC
          ) AS row_num
        FROM pcms.salary_book_warehouse sbw
        WHERE sbw.agent_id IN (#{ids.join(',')})
      )
      SELECT
        ranked.agent_id,
        ranked.player_id,
        ranked.player_name,
        ranked.team_code,
        ranked.is_two_way,
        ranked.book_total
      FROM ranked
      WHERE ranked.row_num <= #{limit}
      ORDER BY ranked.agent_id ASC, ranked.row_num ASC
    SQL
  end

  def fetch_index_top_teams_for_agents(agent_ids, limit_per_agent: 3, book_total_sql: "sbw.cap_2025")
    ids = Array(agent_ids).map(&:to_i).select(&:positive?).uniq
    return [] if ids.empty?

    limit = limit_per_agent.to_i
    limit = 3 if limit <= 0

    conn.exec_query(<<~SQL).to_a
      WITH grouped AS (
        SELECT
          sbw.agent_id,
          sbw.team_code,
          t.team_id,
          COUNT(*)::integer AS player_count,
          COALESCE(SUM(#{book_total_sql}), 0)::bigint AS book_total
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        WHERE sbw.agent_id IN (#{ids.join(',')})
          AND sbw.team_code IS NOT NULL
        GROUP BY sbw.agent_id, sbw.team_code, t.team_id
      ), ranked AS (
        SELECT
          grouped.*,
          ROW_NUMBER() OVER (
            PARTITION BY grouped.agent_id
            ORDER BY grouped.player_count DESC, grouped.book_total DESC, grouped.team_code ASC
          ) AS row_num
        FROM grouped
      )
      SELECT
        ranked.agent_id,
        ranked.team_code,
        ranked.team_id,
        ranked.player_count,
        ranked.book_total
      FROM ranked
      WHERE ranked.row_num <= #{limit}
      ORDER BY ranked.agent_id ASC, ranked.row_num ASC
    SQL
  end

  def fetch_agency_id_for_agent(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first
      SELECT agency_id
      FROM pcms.agents_warehouse
      WHERE agent_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_sidebar_agent(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first
      SELECT
        w.agent_id,
        w.full_name,
        w.agency_id,
        w.agency_name,
        w.is_active,
        w.is_certified,
        w.client_count,
        w.standard_count,
        w.two_way_count,
        w.team_count,
        w.cap_2025_total,
        w.cap_2026_total,
        w.cap_2027_total,
        w.total_salary_from_2025,
        w.max_contract_count,
        w.rookie_scale_count,
        w.min_contract_count,
        w.no_trade_count,
        w.trade_kicker_count,
        w.trade_restricted_count,
        w.expiring_2025,
        w.expiring_2026,
        w.expiring_2027,
        w.player_option_count,
        w.team_option_count,
        w.prior_year_nba_now_free_agent_count,
        w.cap_2025_total_percentile,
        w.cap_2026_total_percentile,
        w.cap_2027_total_percentile,
        w.client_count_percentile,
        w.max_contract_count_percentile,
        w.team_count_percentile,
        w.standard_count_percentile,
        w.two_way_count_percentile
      FROM pcms.agents_warehouse w
      WHERE w.agent_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_sidebar_agent_clients(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.cap_2026::numeric AS cap_2026,
        sbw.cap_2027::numeric AS cap_2027,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        COALESCE(sbw.is_two_way, false)::boolean AS is_two_way,
        COALESCE(sbw.is_trade_restricted_now, false)::boolean AS is_trade_restricted_now,
        COALESCE(sbw.is_no_trade, false)::boolean AS is_no_trade,
        COALESCE(sbw.is_trade_bonus, false)::boolean AS is_trade_bonus,
        COALESCE(sbw.is_min_contract, false)::boolean AS is_min_contract,
        sbw.option_2026,
        sbw.option_2027,
        sbw.option_2028,
        p.years_of_service
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      LEFT JOIN pcms.people p
        ON p.person_id = sbw.player_id
      WHERE sbw.agent_id = #{id_sql}
      ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
      LIMIT 120
    SQL
  end

  def fetch_sidebar_agency(agency_id)
    id_sql = conn.quote(agency_id)

    conn.exec_query(<<~SQL).first
      SELECT
        w.agency_id,
        w.agency_name,
        w.is_active,
        w.agent_count,
        w.client_count,
        w.standard_count,
        w.two_way_count,
        w.team_count,
        w.cap_2025_total,
        w.cap_2026_total,
        w.cap_2027_total,
        w.total_salary_from_2025,
        w.max_contract_count,
        w.rookie_scale_count,
        w.min_contract_count,
        w.no_trade_count,
        w.trade_kicker_count,
        w.trade_restricted_count,
        w.expiring_2025,
        w.expiring_2026,
        w.expiring_2027,
        w.player_option_count,
        w.team_option_count,
        w.prior_year_nba_now_free_agent_count,
        w.cap_2025_total_percentile,
        w.cap_2026_total_percentile,
        w.cap_2027_total_percentile,
        w.client_count_percentile,
        w.max_contract_count_percentile,
        w.agent_count_percentile
      FROM pcms.agencies_warehouse w
      WHERE w.agency_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_sidebar_agency_top_agents(agency_id)
    id_sql = conn.quote(agency_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        w.agent_id,
        w.full_name,
        w.client_count,
        w.team_count,
        w.cap_2025_total,
        w.cap_2025_total_percentile,
        w.client_count_percentile,
        w.max_contract_count,
        w.expiring_2025
      FROM pcms.agents_warehouse w
      WHERE w.agency_id = #{id_sql}
      ORDER BY w.cap_2025_total DESC NULLS LAST, w.full_name
      LIMIT 60
    SQL
  end

  def fetch_sidebar_agency_top_clients(agency_id)
    id_sql = conn.quote(agency_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.agent_id,
        a.full_name AS agent_name,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        COALESCE(sbw.is_two_way, false)::boolean AS is_two_way
      FROM pcms.agents a
      JOIN pcms.salary_book_warehouse sbw
        ON sbw.agent_id = a.agent_id
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE a.agency_id = #{id_sql}
      ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
      LIMIT 80
    SQL
  end
end
