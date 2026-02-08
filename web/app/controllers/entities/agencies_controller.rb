module Entities
  class AgenciesController < ApplicationController
    # GET /agencies
    # Agencies now live under /agents with a radio knob for directory scope.
    def index
      query = {
        kind: "agencies",
        active_only: params[:active_only],
        q: params[:q]
      }.compact_blank

      redirect_to "/agents#{query_string(query)}", status: :moved_permanently
    end

    # GET /agencies/:slug
    # Canonical route.
    def show
      slug = params[:slug].to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.blank?

      record = Slug.find_by!(entity_type: "agency", slug: slug)

      canonical = Slug.find_by(entity_type: "agency", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        redirect_to agency_path(canonical.slug), status: :moved_permanently
        return
      end

      @agency_id = record.entity_id
      @agency_slug = record.slug

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@agency_id)

      @agency = conn.exec_query(<<~SQL).first
        SELECT agency_id, agency_name, is_active
        FROM pcms.agencies
        WHERE agency_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @agency

      @agents = conn.exec_query(<<~SQL).to_a
        SELECT
          ag.agent_id,
          ag.full_name,
          ag.is_active,
          COUNT(sbw.player_id)::integer AS client_count,
          COALESCE(SUM(sbw.cap_2025), 0)::bigint AS cap_2025_total,
          COALESCE(SUM(sbw.total_salary_from_2025), 0)::bigint AS total_salary_from_2025
        FROM pcms.agents ag
        LEFT JOIN pcms.salary_book_warehouse sbw
          ON sbw.agent_id = ag.agent_id
        WHERE ag.agency_id = #{id_sql}
        GROUP BY ag.agent_id, ag.full_name, ag.is_active
        ORDER BY cap_2025_total DESC NULLS LAST, ag.full_name
      SQL

      @agency_rollup = conn.exec_query(<<~SQL).first || {}
        SELECT
          COUNT(DISTINCT ag.agent_id)::integer AS agent_count,
          COUNT(sbw.player_id)::integer AS client_count,
          COUNT(DISTINCT sbw.team_code)::integer AS team_count,
          COALESCE(SUM(sbw.cap_2025), 0)::bigint AS cap_2025_total,
          COALESCE(SUM(sbw.total_salary_from_2025), 0)::bigint AS total_salary_from_2025,
          COUNT(sbw.player_id) FILTER (WHERE sbw.is_two_way)::integer AS two_way_count,
          COUNT(sbw.player_id) FILTER (WHERE sbw.is_min_contract)::integer AS min_contract_count
        FROM pcms.agents ag
        LEFT JOIN pcms.salary_book_warehouse sbw
          ON sbw.agent_id = ag.agent_id
        WHERE ag.agency_id = #{id_sql}
      SQL

      @team_distribution = conn.exec_query(<<~SQL).to_a
        SELECT
          sbw.team_code,
          t.team_id,
          t.team_name,
          COUNT(sbw.player_id)::integer AS client_count,
          COALESCE(SUM(sbw.cap_2025), 0)::bigint AS cap_2025_total
        FROM pcms.agents ag
        JOIN pcms.salary_book_warehouse sbw
          ON sbw.agent_id = ag.agent_id
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        WHERE ag.agency_id = #{id_sql}
        GROUP BY sbw.team_code, t.team_id, t.team_name
        ORDER BY cap_2025_total DESC NULLS LAST, sbw.team_code
        LIMIT 12
      SQL

      @top_clients = conn.exec_query(<<~SQL).to_a
        SELECT
          sbw.player_id,
          sbw.player_name,
          sbw.team_code,
          t.team_id,
          t.team_name,
          sbw.agent_id,
          ag.full_name AS agent_name,
          sbw.cap_2025::numeric AS cap_2025,
          sbw.total_salary_from_2025::numeric AS total_salary_from_2025
        FROM pcms.agents ag
        JOIN pcms.salary_book_warehouse sbw
          ON sbw.agent_id = ag.agent_id
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        WHERE ag.agency_id = #{id_sql}
        ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
        LIMIT 20
      SQL

      @book_by_year = conn.exec_query(<<~SQL).to_a
        SELECT
          sby.salary_year,
          COUNT(*)::integer AS player_count,
          COALESCE(SUM(sby.cap_amount), 0)::bigint AS cap_total,
          COALESCE(SUM(sby.tax_amount), 0)::bigint AS tax_total,
          COALESCE(SUM(sby.apron_amount), 0)::bigint AS apron_total
        FROM pcms.agents ag
        JOIN pcms.salary_book_warehouse sbw
          ON sbw.agent_id = ag.agent_id
        JOIN pcms.salary_book_yearly sby
          ON sby.player_id = sbw.player_id
        WHERE ag.agency_id = #{id_sql}
          AND sby.salary_year BETWEEN 2025 AND 2030
        GROUP BY sby.salary_year
        ORDER BY sby.salary_year
      SQL

      render :show
    end

    # GET /agencies/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "agency", entity_id: id, canonical: true)
      if canonical
        redirect_to agency_path(canonical.slug), status: :moved_permanently
        return
      end

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(<<~SQL).first
        SELECT agency_name
        FROM pcms.agencies
        WHERE agency_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless row

      base = row["agency_name"].to_s.parameterize
      base = "agency-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: "agency", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "agency", entity_id: id, slug: slug, canonical: true)

      redirect_to agency_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def query_string(hash)
      return "" if hash.blank?

      "?#{hash.to_query}"
    end
  end
end
