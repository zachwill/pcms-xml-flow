module Entities
  class DraftsController < ApplicationController
    # GET /drafts
    # Unified workspace for draft picks (future assets) and draft selections (historical)
    def index
      conn = ActiveRecord::Base.connection

      @view = params[:view].to_s.strip.presence || "picks"
      @view = "picks" unless %w[picks selections].include?(@view)

      @year = params[:year].to_s.strip.presence
      @round = params[:round].to_s.strip.presence
      @team = params[:team].to_s.strip.upcase.presence

      # Default year: current season for picks, most recent completed for selections
      current_year = Date.today.year
      default_picks_year = Date.today.month >= 7 ? current_year + 1 : current_year
      default_selections_year = Date.today.month >= 7 ? current_year : current_year - 1

      if @view == "picks"
        @year ||= default_picks_year.to_s
        load_picks(conn)
      else
        @year ||= default_selections_year.to_s
        load_selections(conn)
      end

      # Available years for the year selector
      @available_years = if @view == "picks"
        (current_year..(current_year + 7)).to_a
      else
        conn.exec_query(<<~SQL).rows.flatten
          SELECT DISTINCT draft_year FROM pcms.draft_selections ORDER BY draft_year DESC
        SQL
      end

      render :index
    end

    # GET /drafts/pane (Datastar partial refresh)
    def pane
      index
      render partial: "entities/drafts/results"
    end

    private

    def load_picks(conn)
      year_sql = conn.quote(@year.to_i)

      where_clauses = ["dp.draft_year = #{year_sql}"]
      where_clauses << "dp.draft_round = #{conn.quote(@round.to_i)}" if @round.present? && @round != "all"
      where_clauses << "dp.current_team_code = #{conn.quote(@team)}" if @team.present?

      @results = conn.exec_query(<<~SQL).to_a
        SELECT
          dp.draft_year,
          dp.draft_round,
          dp.original_team_code,
          dp.current_team_code,
          ot.team_name AS original_team_name,
          ct.team_name AS current_team_name,
          dp.is_swap,
          dp.protections_summary,
          dp.pick_status
        FROM pcms.draft_picks dp
        LEFT JOIN pcms.teams ot ON ot.team_code = dp.original_team_code AND ot.league_lk = 'NBA'
        LEFT JOIN pcms.teams ct ON ct.team_code = dp.current_team_code AND ct.league_lk = 'NBA'
        WHERE #{where_clauses.join(" AND ")}
        ORDER BY dp.draft_round, dp.original_team_code
      SQL
    end

    def load_selections(conn)
      year_sql = conn.quote(@year.to_i)

      where_clauses = ["ds.draft_year = #{year_sql}"]
      where_clauses << "ds.draft_round = #{conn.quote(@round.to_i)}" if @round.present? && @round != "all"
      where_clauses << "ds.drafting_team_code = #{conn.quote(@team)}" if @team.present?

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
          t.team_name AS drafting_team_name,
          ds.transaction_date
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.people p ON p.person_id = ds.player_id
        LEFT JOIN pcms.teams t ON t.team_code = ds.drafting_team_code AND t.league_lk = 'NBA'
        WHERE #{where_clauses.join(" AND ")}
        ORDER BY ds.draft_round ASC, ds.pick_number ASC
      SQL
    end
  end
end
