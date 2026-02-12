module Entities
  class AgentsController < ApplicationController
    BOOK_YEARS = [2025, 2026, 2027].freeze
    AGENT_SORT_KEYS = %w[book clients teams max expirings options name].freeze
    AGENCY_SORT_KEYS = %w[book clients agents teams max expirings options name].freeze
    OVERLAY_TYPES = %w[agent agency].freeze

    # GET /agents
    def index
      setup_directory_filters!
      load_directory_rows!
      build_sidebar_summary!

      render :index
    end

    # GET /agents/pane
    # Datastar patch target for main canvas only.
    def pane
      setup_directory_filters!
      load_directory_rows!
      build_sidebar_summary!

      render partial: "entities/agents/workspace_main"
    end

    # GET /agents/sidebar/base
    def sidebar_base
      setup_directory_filters!
      load_directory_rows!
      build_sidebar_summary!

      render partial: "entities/agents/rightpanel_base"
    end

    # GET /agents/sidebar/agent/:id
    def sidebar_agent
      agent_id = Integer(params[:id])
      render partial: "entities/agents/rightpanel_overlay_agent", locals: load_sidebar_agent_payload(agent_id)
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /agents/sidebar/agency/:id
    def sidebar_agency
      agency_id = Integer(params[:id])
      render partial: "entities/agents/rightpanel_overlay_agency", locals: load_sidebar_agency_payload(agency_id)
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /agents/sidebar/clear
    def sidebar_clear
      render partial: "entities/agents/rightpanel_clear"
    end

    # GET /agents/:slug
    # Canonical route.
    def show
      slug = params[:slug].to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.blank?

      record = Slug.find_by!(entity_type: "agent", slug: slug)

      canonical = Slug.find_by(entity_type: "agent", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        redirect_to agent_path(canonical.slug), status: :moved_permanently
        return
      end

      @agent_id = record.entity_id
      @agent_slug = record.slug

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@agent_id)

      @agent = conn.exec_query(<<~SQL).first
        SELECT agent_id, full_name, agency_id, agency_name, is_active, is_certified
        FROM pcms.agents
        WHERE agent_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @agent

      if @agent["agency_id"].present?
        agency_sql = conn.quote(@agent["agency_id"])
        @agency = conn.exec_query(<<~SQL).first
          SELECT agency_id, agency_name, is_active
          FROM pcms.agencies
          WHERE agency_id = #{agency_sql}
          LIMIT 1
        SQL
      end

      # Current clients (salary book horizon)
      @clients = conn.exec_query(<<~SQL).to_a
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

      @client_rollup = conn.exec_query(<<~SQL).first || {}
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

      @team_distribution = conn.exec_query(<<~SQL).to_a
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

      @book_by_year = conn.exec_query(<<~SQL).to_a
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

      @historical_footprint_rollup = conn.exec_query(<<~SQL).first || {}
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

      @historical_signing_trend = conn.exec_query(<<~SQL).to_a
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

      render :show
    end

    # GET /agents/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "agent", entity_id: id, canonical: true)
      if canonical
        redirect_to agent_path(canonical.slug), status: :moved_permanently
        return
      end

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(<<~SQL).first
        SELECT full_name
        FROM pcms.agents
        WHERE agent_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless row

      base = row["full_name"].to_s.parameterize
      base = "agent-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: "agent", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "agent", entity_id: id, slug: slug, canonical: true)

      redirect_to agent_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def setup_directory_filters!
      @directory_kind = params[:kind].to_s == "agencies" ? "agencies" : "agents"

      @active_only = cast_bool(params[:active_only])
      @certified_only = cast_bool(params[:certified_only])
      @with_clients = cast_bool(params[:with_clients])
      @with_book = cast_bool(params[:with_book])
      @with_restrictions = cast_bool(params[:with_restrictions])
      @with_expiring = cast_bool(params[:with_expiring])

      year = begin
        Integer(params[:year])
      rescue ArgumentError, TypeError
        nil
      end
      @book_year = BOOK_YEARS.include?(year) ? year : BOOK_YEARS.first

      @sort_dir = params[:dir].to_s == "asc" ? "asc" : "desc"

      allowed_sort_keys = @directory_kind == "agencies" ? AGENCY_SORT_KEYS : AGENT_SORT_KEYS
      @sort_key = params[:sort].to_s
      @sort_key = "book" unless allowed_sort_keys.include?(@sort_key)
    end

    def load_directory_rows!
      conn = ActiveRecord::Base.connection
      book_total_sql = sql_book_total("w")
      book_percentile_sql = sql_book_percentile("w")
      expiring_sql = sql_expiring_in_window("w")

      if @directory_kind == "agencies"
        sort_sql = sql_sort_for_agencies(book_total_sql:, expiring_sql:)
        where_clauses = ["1 = 1"]
        where_clauses << "COALESCE(w.is_active, true) = true" if @active_only
        where_clauses << "COALESCE(w.client_count, 0) > 0" if @with_clients
        where_clauses << "COALESCE(#{book_total_sql}, 0) > 0" if @with_book
        where_clauses << "COALESCE(#{expiring_sql}, 0) > 0" if @with_expiring
        where_clauses << "(COALESCE(w.no_trade_count, 0) > 0 OR COALESCE(w.trade_kicker_count, 0) > 0 OR COALESCE(w.trade_restricted_count, 0) > 0)" if @with_restrictions

        @agencies = conn.exec_query(<<~SQL).to_a
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
          WHERE #{where_clauses.join(" AND ")}
          ORDER BY #{sort_sql} #{sql_sort_direction_for_key} NULLS LAST,
                   w.agency_name ASC
        SQL

        @agents = []
      else
        sort_sql = sql_sort_for_agents(book_total_sql:, expiring_sql:)
        where_clauses = ["1 = 1"]
        where_clauses << "COALESCE(w.is_active, true) = true" if @active_only
        where_clauses << "COALESCE(w.is_certified, false) = true" if @certified_only
        where_clauses << "COALESCE(w.client_count, 0) > 0" if @with_clients
        where_clauses << "COALESCE(#{book_total_sql}, 0) > 0" if @with_book
        where_clauses << "COALESCE(#{expiring_sql}, 0) > 0" if @with_expiring
        where_clauses << "(COALESCE(w.no_trade_count, 0) > 0 OR COALESCE(w.trade_kicker_count, 0) > 0 OR COALESCE(w.trade_restricted_count, 0) > 0)" if @with_restrictions

        @agents = conn.exec_query(<<~SQL).to_a
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
          WHERE #{where_clauses.join(" AND ")}
          ORDER BY #{sort_sql} #{sql_sort_direction_for_key} NULLS LAST,
                   w.full_name ASC
        SQL

        @agencies = []
      end
    end

    def build_sidebar_summary!
      rows = @directory_kind == "agencies" ? @agencies : @agents

      @sidebar_summary = {
        kind: @directory_kind,
        year: @book_year,
        sort_key: @sort_key,
        sort_dir: @sort_dir,
        row_count: rows.size,
        active_count: rows.count { |row| row["is_active"] != false },
        client_total: rows.sum { |row| row["client_count"].to_i },
        standard_total: rows.sum { |row| row["standard_count"].to_i },
        two_way_total: rows.sum { |row| row["two_way_count"].to_i },
        team_total: rows.sum { |row| row["team_count"].to_i },
        max_total: rows.sum { |row| row["max_contract_count"].to_i },
        expiring_total: rows.sum { |row| row["expiring_in_window"].to_i },
        restricted_total: rows.sum { |row| row["trade_restricted_count"].to_i },
        option_total: rows.sum { |row| row["player_option_count"].to_i + row["team_option_count"].to_i },
        book_total: rows.sum { |row| row["book_total"].to_i },
        filters: sidebar_filter_labels,
        top_rows: sidebar_top_rows(rows)
      }
    end

    def sidebar_top_rows(rows)
      rows.first(14).map do |row|
        if @directory_kind == "agencies"
          {
            type: "agency",
            id: row["agency_id"],
            title: row["agency_name"],
            subtitle: "#{row['agent_count'].to_i} agents · #{row['client_count'].to_i} clients",
            book_total: row["book_total"].to_i,
            percentile: row["book_total_percentile"]
          }
        else
          {
            type: "agent",
            id: row["agent_id"],
            title: row["full_name"],
            subtitle: "#{row['client_count'].to_i} clients · #{row['team_count'].to_i} teams",
            book_total: row["book_total"].to_i,
            percentile: row["book_total_percentile"]
          }
        end
      end
    end

    def sidebar_filter_labels
      labels = []
      labels << "Active only" if @active_only
      labels << "Certified only" if @certified_only && @directory_kind == "agents"
      labels << "With clients" if @with_clients
      labels << "With book" if @with_book
      labels << "With restrictions" if @with_restrictions
      labels << "With expirings" if @with_expiring
      labels
    end

    def selected_overlay_visible?(overlay_type:, overlay_id:)
      normalized_type = overlay_type.to_s
      return false unless OVERLAY_TYPES.include?(normalized_type)

      normalized_id = overlay_id.to_i
      return false if normalized_id <= 0

      case normalized_type
      when "agent"
        @directory_kind == "agents" && @agents.any? { |row| row["agent_id"].to_i == normalized_id }
      when "agency"
        @directory_kind == "agencies" && @agencies.any? { |row| row["agency_id"].to_i == normalized_id }
      else
        false
      end
    end

    def load_sidebar_agent_payload(agent_id)
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(agent_id)

      agent = conn.exec_query(<<~SQL).first
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
      raise ActiveRecord::RecordNotFound unless agent

      clients = conn.exec_query(<<~SQL).to_a
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

      {
        agent:,
        clients:
      }
    end

    def load_sidebar_agency_payload(agency_id)
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(agency_id)

      agency = conn.exec_query(<<~SQL).first
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
      raise ActiveRecord::RecordNotFound unless agency

      top_agents = conn.exec_query(<<~SQL).to_a
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

      top_clients = conn.exec_query(<<~SQL).to_a
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

      {
        agency:,
        top_agents:,
        top_clients:
      }
    end

    def cast_bool(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def sql_book_total(table_alias)
      case @book_year
      when 2026 then "#{table_alias}.cap_2026_total"
      when 2027 then "#{table_alias}.cap_2027_total"
      else "#{table_alias}.cap_2025_total"
      end
    end

    def sql_book_percentile(table_alias)
      case @book_year
      when 2026 then "#{table_alias}.cap_2026_total_percentile"
      when 2027 then "#{table_alias}.cap_2027_total_percentile"
      else "#{table_alias}.cap_2025_total_percentile"
      end
    end

    def sql_expiring_in_window(table_alias)
      case @book_year
      when 2026 then "#{table_alias}.expiring_2026"
      when 2027 then "#{table_alias}.expiring_2027"
      else "#{table_alias}.expiring_2025"
      end
    end

    def sql_sort_for_agents(book_total_sql:, expiring_sql:)
      case @sort_key
      when "clients" then "w.client_count"
      when "teams" then "w.team_count"
      when "max" then "w.max_contract_count"
      when "expirings" then expiring_sql
      when "options" then "(COALESCE(w.player_option_count, 0) + COALESCE(w.team_option_count, 0))"
      when "name" then "w.full_name"
      else book_total_sql
      end
    end

    def sql_sort_for_agencies(book_total_sql:, expiring_sql:)
      case @sort_key
      when "clients" then "w.client_count"
      when "agents" then "w.agent_count"
      when "teams" then "w.team_count"
      when "max" then "w.max_contract_count"
      when "expirings" then expiring_sql
      when "options" then "(COALESCE(w.player_option_count, 0) + COALESCE(w.team_option_count, 0))"
      when "name" then "w.agency_name"
      else book_total_sql
      end
    end

    def sql_sort_direction_for_key
      if @sort_key == "name"
        @sort_dir == "desc" ? "DESC" : "ASC"
      else
        @sort_dir == "asc" ? "ASC" : "DESC"
      end
    end
  end
end
