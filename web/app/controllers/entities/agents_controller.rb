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
          sbw.cap_2025::numeric AS cap_2025
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        WHERE sbw.agent_id = #{id_sql}
        ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
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
