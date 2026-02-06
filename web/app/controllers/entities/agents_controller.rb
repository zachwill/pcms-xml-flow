module Entities
  class AgentsController < ApplicationController
    # GET /agents
    def index
      conn = ActiveRecord::Base.connection

      q = params[:q].to_s.strip
      if q.present?
        q_sql = conn.quote("%#{q}%")
        @agents = conn.exec_query(<<~SQL).to_a
          SELECT agent_id, full_name, agency_id, agency_name, is_active
          FROM pcms.agents
          WHERE full_name ILIKE #{q_sql}
             OR agency_name ILIKE #{q_sql}
          ORDER BY full_name
          LIMIT 200
        SQL
      else
        @agents = conn.exec_query(<<~SQL).to_a
          SELECT agent_id, full_name, agency_id, agency_name, is_active
          FROM pcms.agents
          ORDER BY full_name
          LIMIT 50
        SQL
      end

      @query = q

      render :index
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
          sbw.cap_2025::numeric AS cap_2025,
          sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
          sbw.is_two_way,
          sbw.is_min_contract,
          sbw.is_trade_restricted_now
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        WHERE sbw.agent_id = #{id_sql}
        ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
      SQL

      @client_rollup = conn.exec_query(<<~SQL).first || {}
        SELECT
          COUNT(*)::integer AS client_count,
          COUNT(DISTINCT sbw.team_code)::integer AS team_count,
          COALESCE(SUM(sbw.cap_2025), 0)::bigint AS cap_2025_total,
          COALESCE(SUM(sbw.total_salary_from_2025), 0)::bigint AS total_salary_from_2025,
          COUNT(*) FILTER (WHERE sbw.is_two_way)::integer AS two_way_count,
          COUNT(*) FILTER (WHERE sbw.is_min_contract)::integer AS min_contract_count,
          COUNT(*) FILTER (WHERE sbw.is_trade_restricted_now)::integer AS restricted_now_count
        FROM pcms.salary_book_warehouse sbw
        WHERE sbw.agent_id = #{id_sql}
      SQL

      @team_distribution = conn.exec_query(<<~SQL).to_a
        SELECT
          sbw.team_code,
          t.team_id,
          t.team_name,
          COUNT(*)::integer AS client_count,
          COALESCE(SUM(sbw.cap_2025), 0)::bigint AS cap_2025_total
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        WHERE sbw.agent_id = #{id_sql}
        GROUP BY sbw.team_code, t.team_id, t.team_name
        ORDER BY cap_2025_total DESC NULLS LAST, sbw.team_code
        LIMIT 12
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
      while Slug.exists?(entity_type: "agent", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "agent", entity_id: id, slug: slug, canonical: true)

      redirect_to agent_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end
  end
end
