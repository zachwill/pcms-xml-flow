module Entities
  class TeamsController < ApplicationController
    # GET /teams
    def index
      conn = ActiveRecord::Base.connection

      q = params[:q].to_s.strip
      @query = q

      if q.present?
        q_sql = conn.quote("%#{q}%")
        @teams = conn.exec_query(<<~SQL).to_a
          SELECT team_id, team_code, team_name, conference_name
          FROM pcms.teams
          WHERE league_lk = 'NBA'
            AND team_name NOT LIKE 'Non-NBA%'
            AND (
              team_code ILIKE #{q_sql}
              OR team_name ILIKE #{q_sql}
              OR conference_name ILIKE #{q_sql}
            )
          ORDER BY team_code
        SQL
      else
        @teams = conn.exec_query(<<~SQL).to_a
          SELECT team_id, team_code, team_name, conference_name
          FROM pcms.teams
          WHERE league_lk = 'NBA'
            AND team_name NOT LIKE 'Non-NBA%'
          ORDER BY team_code
        SQL
      end

      render :index
    end

    # GET /teams/:slug
    # Canonical route.
    def show
      slug = params[:slug].to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.blank?

      # Teams are special: team_code is stable + guessable.
      # If we don't have a slug record yet, try to bootstrap it from pcms.teams.
      record = Slug.find_by(entity_type: "team", slug: slug)
      record ||= bootstrap_team_slug_from_code!(slug)

      canonical = Slug.find_by(entity_type: "team", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        redirect_to team_path(canonical.slug), status: :moved_permanently
        return
      end

      @team_id = record.entity_id
      @team_slug = record.slug

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@team_id)

      @team = conn.exec_query(<<~SQL).first
        SELECT team_id, team_code, team_name, conference_name
        FROM pcms.teams
        WHERE team_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @team

      code_sql = conn.quote(@team["team_code"])

      # Salary book (current horizon) roster view.
      @roster = conn.exec_query(<<~SQL).to_a
        SELECT
          sbw.player_id,
          sbw.player_name,
          sbw.team_code,
          sbw.agent_id,
          sbw.agent_name,
          sbw.cap_2025::numeric AS cap_2025,
          sbw.total_salary_from_2025::numeric AS total_salary_from_2025
        FROM pcms.salary_book_warehouse sbw
        WHERE sbw.team_code = #{code_sql}
        ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.total_salary_from_2025 DESC NULLS LAST, sbw.player_name
      SQL

      # Draft pick assets (future picks) — same source as Salary Book draft pills.
      @draft_assets = conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          draft_year,
          draft_round,
          asset_slot,
          sub_asset_slot,
          asset_type,
          is_swap,
          is_conditional,
          counterparty_team_code,
          raw_part,
          endnote_explanation,
          refreshed_at
        FROM pcms.draft_pick_summary_assets
        WHERE team_code = #{code_sql}
          AND draft_year BETWEEN 2025 AND 2030
        ORDER BY draft_year, draft_round, asset_slot, sub_asset_slot
      SQL

      render :show
    end

    # GET /teams/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "team", entity_id: id, canonical: true)
      if canonical
        redirect_to team_path(canonical.slug), status: :moved_permanently
        return
      end

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(<<~SQL).first
        SELECT team_code, team_name
        FROM pcms.teams
        WHERE team_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless row

      base = row["team_code"].to_s.strip.downcase
      base = row["team_name"].to_s.parameterize if base.blank?
      base = "team-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.exists?(entity_type: "team", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "team", entity_id: id, slug: slug, canonical: true)

      redirect_to team_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def bootstrap_team_slug_from_code!(slug)
      code = slug.to_s.strip.upcase
      raise ActiveRecord::RecordNotFound unless code.match?(/\A[A-Z]{3}\z/)

      conn = ActiveRecord::Base.connection
      code_sql = conn.quote(code)

      row = conn.exec_query(<<~SQL).first
        SELECT team_id
        FROM pcms.teams
        WHERE team_code = #{code_sql}
          AND league_lk = 'NBA'
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless row

      team_id = row["team_id"]

      # If another team already owns this slug, don't overwrite.
      existing = Slug.find_by(entity_type: "team", slug: slug)
      return existing if existing

      canonical = Slug.find_by(entity_type: "team", entity_id: team_id, canonical: true)
      return canonical if canonical

      Slug.create!(entity_type: "team", entity_id: team_id, slug: slug, canonical: true)
    end
  end
end
