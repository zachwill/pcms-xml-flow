module Entities
  class PlayersController < ApplicationController
    # GET /players
    def index
      conn = ActiveRecord::Base.connection

      q = params[:q].to_s.strip
      @query = q

      if q.present?
        if q.match?(/\A\d+\z/)
          id_sql = conn.quote(q.to_i)
          @players = conn.exec_query(<<~SQL).to_a
            SELECT
              sbw.player_id,
              sbw.player_name,
              sbw.team_code,
              t.team_id,
              t.team_name,
              sbw.agent_id,
              sbw.agent_name,
              sbw.cap_2025::numeric AS cap_2025
            FROM pcms.salary_book_warehouse sbw
            LEFT JOIN pcms.teams t
              ON t.team_code = sbw.team_code
             AND t.league_lk = 'NBA'
            WHERE sbw.player_id = #{id_sql}
            ORDER BY sbw.cap_2025 DESC NULLS LAST
            LIMIT 50
          SQL
        else
          q_sql = conn.quote("%#{q}%")
          @players = conn.exec_query(<<~SQL).to_a
            SELECT
              sbw.player_id,
              sbw.player_name,
              sbw.team_code,
              t.team_id,
              t.team_name,
              sbw.agent_id,
              sbw.agent_name,
              sbw.cap_2025::numeric AS cap_2025
            FROM pcms.salary_book_warehouse sbw
            LEFT JOIN pcms.teams t
              ON t.team_code = sbw.team_code
             AND t.league_lk = 'NBA'
            WHERE sbw.player_name ILIKE #{q_sql}
            ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
            LIMIT 200
          SQL
        end
      else
        @players = conn.exec_query(<<~SQL).to_a
          SELECT
            sbw.player_id,
            sbw.player_name,
            sbw.team_code,
            t.team_id,
            t.team_name,
            sbw.agent_id,
            sbw.agent_name,
            sbw.cap_2025::numeric AS cap_2025
          FROM pcms.salary_book_warehouse sbw
          LEFT JOIN pcms.teams t
            ON t.team_code = sbw.team_code
           AND t.league_lk = 'NBA'
          ORDER BY sbw.cap_2025 DESC NULLS LAST
          LIMIT 50
        SQL
      end

      render :index
    end

    # GET /players/:slug
    # Canonical route.
    def show
      slug = params[:slug].to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.empty?

      record = Slug.find_by!(entity_type: "player", slug: slug)

      canonical = Slug.find_by(entity_type: "player", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        redirect_to player_path(canonical.slug), status: :moved_permanently
        return
      end

      @player_id = record.entity_id
      @player_slug = record.slug

      # Minimal identity lookup (PCMS)
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@player_id)

      @player = conn.exec_query(<<~SQL).first
        SELECT
          person_id,
          COALESCE(display_first_name, first_name) AS first_name,
          COALESCE(display_last_name, last_name) AS last_name
        FROM pcms.people
        WHERE person_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @player

      # Salary-book context (team + agent) to enable link graph pivots.
      @salary_book_row = conn.exec_query(<<~SQL).first
        SELECT
          sbw.team_code,
          t.team_id,
          t.team_name,
          sbw.agent_id,
          sbw.agent_name,
          agency.agency_id,
          agency.agency_name,
          sbw.cap_2025::numeric AS cap_2025
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        LEFT JOIN pcms.agents agent
          ON agent.agent_id = sbw.agent_id
        LEFT JOIN pcms.agencies agency
          ON agency.agency_id = agent.agency_id
        WHERE sbw.player_id = #{id_sql}
        LIMIT 1
      SQL

      # Draft selection (historical) — player → draft → team link.
      @draft_selection = conn.exec_query(<<~SQL).first
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

      render :show
    end

    # GET /players/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "player", entity_id: id, canonical: true)
      if canonical
        redirect_to player_path(canonical.slug), status: :moved_permanently
        return
      end

      # Create a default canonical slug on-demand, using PCMS name.
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(
        "SELECT COALESCE(display_first_name, first_name) AS first_name, COALESCE(display_last_name, last_name) AS last_name FROM pcms.people WHERE person_id = #{id_sql} LIMIT 1"
      ).first

      raise ActiveRecord::RecordNotFound unless row

      base = [row["first_name"], row["last_name"]].compact.join(" ").parameterize
      base = "player-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.exists?(entity_type: "player", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "player", entity_id: id, slug: slug, canonical: true)

      redirect_to player_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end
  end
end
