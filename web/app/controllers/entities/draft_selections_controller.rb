module Entities
  class DraftSelectionsController < ApplicationController
    # GET /draft-selections
    def index
      conn = ActiveRecord::Base.connection

      q = params[:q].to_s.strip
      @query = q

      @years = conn.exec_query(<<~SQL).to_a
        SELECT draft_year, COUNT(*)::int AS pick_count
        FROM pcms.draft_selections
        GROUP BY draft_year
        ORDER BY draft_year DESC
      SQL

      if q.present?
        q_sql = conn.quote("%#{q}%")
        @results = conn.exec_query(<<~SQL).to_a
          SELECT
            ds.transaction_id,
            ds.draft_year,
            ds.draft_round,
            ds.pick_number,
            ds.player_id,
            COALESCE(
              NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
              NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
              ds.player_id::text
            ) AS player_name,
            ds.drafting_team_code,
            ds.transaction_date
          FROM pcms.draft_selections ds
          LEFT JOIN pcms.people p ON p.person_id = ds.player_id
          WHERE (
            CONCAT_WS(' ', p.display_first_name, p.display_last_name, p.first_name, p.last_name) ILIKE #{q_sql}
          )
          ORDER BY ds.draft_year DESC, ds.draft_round ASC, ds.pick_number ASC
          LIMIT 200
        SQL
      else
        @results = []
      end

      render :index
    end

    # GET /draft-selections/:slug
    def show
      slug = params[:slug].to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.blank?

      record = Slug.find_by!(entity_type: "draft_selection", slug: slug)

      canonical = Slug.find_by(entity_type: "draft_selection", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        redirect_to draft_selection_path(canonical.slug), status: :moved_permanently
        return
      end

      @draft_selection_id = record.entity_id
      @draft_selection_slug = record.slug

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@draft_selection_id)

      @draft_selection = conn.exec_query(<<~SQL).first
        SELECT
          ds.transaction_id,
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          ds.drafting_team_id,
          ds.drafting_team_code,
          ds.draft_amount,
          ds.transaction_date,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ''
          ) AS player_name,
          t.team_name
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.people p ON p.person_id = ds.player_id
        LEFT JOIN pcms.teams t ON t.team_id = ds.drafting_team_id
        WHERE ds.transaction_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @draft_selection

      render :show
    end

    # GET /draft-selections/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "draft_selection", entity_id: id, canonical: true)
      if canonical
        redirect_to draft_selection_path(canonical.slug), status: :moved_permanently
        return
      end

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(<<~SQL).first
        SELECT
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ''
          ) AS player_name
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.people p ON p.person_id = ds.player_id
        WHERE ds.transaction_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless row

      parts = [
        "draft",
        row["draft_year"],
        "r#{row['draft_round']}",
        "p#{row['pick_number']}",
        row["player_name"].to_s.parameterize.presence,
      ].compact

      base = parts.join("-")
      base = "draft-selection-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.exists?(entity_type: "draft_selection", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "draft_selection", entity_id: id, slug: slug, canonical: true)

      redirect_to draft_selection_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end
  end
end
