require "json"

module Tools
  class SalaryBookController < ApplicationController
    CURRENT_SALARY_YEAR = 2025
    # Canonical year horizon for the salary book (keep in sync with SalaryBookHelper::SALARY_YEARS).
    SALARY_YEARS = (2025..2030).to_a.freeze
    AVAILABLE_VIEWS = %w[injuries salary-book tankathon].freeze
    DEFAULT_VIEW = "salary-book"

    # GET /tools/salary-book
    def show
      @salary_year = salary_year_param
      @salary_years = SALARY_YEARS
      @initial_view = salary_book_view_param

      team_rows = SalaryBookQueries.fetch_team_index_rows(@salary_year)
      @team_codes = team_rows.map { |row| row["team_code"] }.compact
      @teams_by_conference, @team_meta_by_code = SalaryBookQueries.build_team_maps(team_rows)

      requested = params[:team]
      default_team_code = "POR"
      @initial_team = if requested.present? && valid_team_code?(requested)
        requested.to_s.strip.upcase
      elsif @team_codes.include?(default_team_code)
        default_team_code
      else
        @team_codes.first
      end

      @initial_team_meta = @initial_team ? (@team_meta_by_code[@initial_team] || {}) : {}

      @initial_players = []
      @initial_cap_holds = []
      @initial_exceptions = []
      @initial_dead_money = []
      @initial_picks = []
      @initial_team_summary = nil
      @initial_team_summaries_by_year = {}
      @initial_tankathon_rows = []
      @initial_tankathon_standing_date = nil
      @initial_tankathon_season_year = nil
      @initial_tankathon_season_label = nil

      if @initial_team.present?
        @initial_players = SalaryBookQueries.fetch_team_players(@initial_team)

        payload = SalaryBookQueries.fetch_team_support_payload(@initial_team, base_year: @salary_year)
        @initial_cap_holds = payload[:cap_holds]
        @initial_exceptions = payload[:exceptions]
        @initial_dead_money = payload[:dead_money]
        @initial_picks = payload[:picks]
        @initial_team_summaries_by_year = payload[:team_summaries]
        @initial_team_meta = payload[:team_meta].presence || @initial_team_meta
        @initial_team_summary = @initial_team_summaries_by_year[@salary_year] || @initial_team_summaries_by_year[SALARY_YEARS.first]
      end

      if @initial_view == "tankathon"
        tankathon_payload = SalaryBookQueries.fetch_tankathon_payload(@salary_year)
        @initial_tankathon_rows = tankathon_payload[:rows]
        @initial_tankathon_standing_date = tankathon_payload[:standing_date]
        @initial_tankathon_season_year = tankathon_payload[:season_year]
        @initial_tankathon_season_label = tankathon_payload[:season_label]
      end
    rescue ActiveRecord::StatementInvalid => e
      # Useful when a dev DB hasn't been hydrated with the pcms.* schema yet.
      @boot_error = e.message
      @salary_year = salary_year_param
      @salary_years = SALARY_YEARS
      @initial_view = salary_book_view_param
      @team_codes = []
      @teams_by_conference = { "Eastern" => [], "Western" => [] }
      @team_meta_by_code = {}
      @initial_team = nil
      @initial_team_summary = nil
      @initial_team_meta = {}
      @initial_team_summaries_by_year = {}
      @initial_tankathon_rows = []
      @initial_tankathon_standing_date = nil
      @initial_tankathon_season_year = nil
      @initial_tankathon_season_label = nil
      @initial_players = []
      @initial_cap_holds = []
      @initial_exceptions = []
      @initial_dead_money = []
      @initial_picks = []
    end

    # GET /tools/salary-book/frame?view=tankathon&team=BOS&year=2025
    # Patchable main frame used by view switches.
    def frame
      team_code = normalize_team_code(params[:team])
      year = salary_year_param
      view = salary_book_view_param

      if view == "tankathon"
        tankathon_payload = SalaryBookQueries.fetch_tankathon_payload(year)

        render partial: "tools/salary_book/maincanvas_tankathon_frame", locals: {
          team_code:,
          year:,
          standings_rows: tankathon_payload[:rows],
          standing_date: tankathon_payload[:standing_date],
          season_year: tankathon_payload[:season_year],
          season_label: tankathon_payload[:season_label],
          error_message: nil
        }, layout: false
        return
      end

      if view == "injuries"
        team_rows = SalaryBookQueries.fetch_team_index_rows(year)
        team_codes = team_rows.map { |row| row["team_code"] }.compact
        _, team_meta_by_code = SalaryBookQueries.build_team_maps(team_rows)

        render partial: "tools/salary_book/maincanvas_injuries_frame", locals: {
          team_code:,
          team_codes:,
          team_meta_by_code:,
          year:,
          error_message: nil
        }, layout: false
        return
      end

      players = SalaryBookQueries.fetch_team_players(team_code)
      payload = SalaryBookQueries.fetch_team_support_payload(team_code, base_year: year)

      render partial: "tools/salary_book/maincanvas_team_frame", locals: {
        boot_error: nil,
        team_code:,
        players:,
        cap_holds: payload[:cap_holds],
        exceptions: payload[:exceptions],
        dead_money: payload[:dead_money],
        picks: payload[:picks],
        team_summaries: payload[:team_summaries],
        team_meta: payload[:team_meta],
        year:,
        salary_years: SALARY_YEARS,
        empty_message: nil
      }, layout: false
    rescue ActiveRecord::StatementInvalid => e
      if view == "tankathon"
        render partial: "tools/salary_book/maincanvas_tankathon_frame", locals: {
          team_code:,
          year:,
          standings_rows: [],
          standing_date: nil,
          season_year: nil,
          season_label: nil,
          error_message: e.message
        }, layout: false
      elsif view == "injuries"
        render partial: "tools/salary_book/maincanvas_injuries_frame", locals: {
          team_code:,
          team_codes: [],
          team_meta_by_code: {},
          year:,
          error_message: e.message
        }, layout: false
      else
        render partial: "tools/salary_book/maincanvas_team_frame", locals: {
          boot_error: e.message,
          team_code: nil,
          players: [],
          cap_holds: [],
          exceptions: [],
          dead_money: [],
          picks: [],
          team_summaries: {},
          team_meta: {},
          year:,
          salary_years: SALARY_YEARS,
          empty_message: nil
        }, layout: false
      end
    end

    # GET /tools/salary-book/sidebar/team?team=BOS
    # Base team sidebar shell (header + tabs + cap/stats payload).
    # Draft/Rights tabs are lazy-loaded via dedicated endpoints.
    def sidebar_team
      team_code = normalize_team_code(params[:team])
      year = salary_year_param

      # Multi-year summaries for cap tab + stats tab
      summaries_by_year = SalaryBookQueries.fetch_all_team_summaries([team_code])[team_code] || {}

      # Current year summary (includes computed cap_space + apron aliases)
      summary = summaries_by_year[year] || {}

      # Team metadata (name, conference, logo)
      team_meta = SalaryBookQueries.fetch_team_meta(team_code)

      render partial: "tools/salary_book/sidebar_team", locals: {
        team_code:,
        summary:,
        team_meta:,
        summaries_by_year:,
        year:
      }, layout: false
    end

    # GET /tools/salary-book/sidebar/team/cap?team=BOS&year=2026
    # Lightweight hover/year patch: only updates the Cap tab content.
    def sidebar_team_cap
      team_code = normalize_team_code(params[:team])
      year = salary_year_param

      summaries_by_year = SalaryBookQueries.fetch_all_team_summaries([team_code])[team_code] || {}
      summary = summaries_by_year[year] || {}

      render partial: "tools/salary_book/sidebar_team_tab_cap", locals: {
        summary:,
        summaries_by_year:,
        year:
      }, layout: false
    end

    # GET /tools/salary-book/sidebar/team/draft?team=BOS&year=2025
    # Lazy-loaded Draft tab payload (future years only, starting after selected year).
    def sidebar_team_draft
      team_code = normalize_team_code(params[:team])
      year = salary_year_param
      draft_start_year = year + 1

      draft_assets = SalaryBookQueries.fetch_sidebar_draft_assets(team_code, start_year: draft_start_year)

      render partial: "tools/salary_book/sidebar_team_tab_draft", locals: {
        team_code:,
        year:,
        draft_start_year:,
        draft_assets:,
        draft_loaded: true
      }, layout: false
    end

    # GET /tools/salary-book/sidebar/team/rights?team=BOS
    # Lazy-loaded Rights tab payload.
    def sidebar_team_rights
      team_code = normalize_team_code(params[:team])
      rights_by_kind = SalaryBookQueries.fetch_sidebar_rights_by_kind(team_code)

      render partial: "tools/salary_book/sidebar_team_tab_rights", locals: {
        rights_by_kind:,
        rights_loaded: true
      }, layout: false
    end

    # GET /tools/salary-book/sidebar/player/:id
    def sidebar_player
      player_id = Integer(params[:id])
      player = SalaryBookQueries.fetch_player(player_id)
      raise ActiveRecord::RecordNotFound unless player

      render partial: "tools/salary_book/sidebar_player", locals: { player: }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /tools/salary-book/sidebar/clear
    def sidebar_clear
      render partial: "tools/salary_book/sidebar_clear", layout: false
    end

    # GET /tools/salary-book/combobox/players/search?team=BOS&q=jay&limit=12&seq=3
    # Returns server-rendered popup/list HTML for the Salary Book player combobox.
    def combobox_players_search
      query = params[:q].to_s.strip
      seq = begin
        Integer(params[:seq])
      rescue ArgumentError, TypeError
        0
      end

      limit = params[:limit].to_i
      limit = 12 if limit <= 0
      limit = [limit, 50].min

      team_param = params[:team].to_s.strip.upcase
      team_code = valid_team_code?(team_param) ? team_param : nil

      players = SalaryBookQueries.fetch_combobox_players(team_code:, query:, limit:)

      render partial: "tools/salary_book/combobox_players_popup", locals: {
        players:,
        query:,
        seq:,
        team_code:,
        error_message: nil
      }, layout: false
    rescue ActiveRecord::StatementInvalid => e
      render partial: "tools/salary_book/combobox_players_popup", locals: {
        players: [],
        query:,
        seq:,
        team_code:,
        error_message: e.message
      }, layout: false
    end

    # GET /tools/salary-book/sidebar/agent/:id
    def sidebar_agent
      agent_id = Integer(params[:id])
      agent = SalaryBookQueries.fetch_agent(agent_id)
      raise ActiveRecord::RecordNotFound unless agent

      clients = SalaryBookQueries.fetch_agent_clients(agent_id)
      rollup = SalaryBookQueries.fetch_agent_rollup(agent_id)

      render partial: "tools/salary_book/sidebar_agent", locals: { agent:, clients:, rollup: }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /tools/salary-book/sidebar/pick?team=BOS&year=2025&round=1
    def sidebar_pick
      team_code = normalize_team_code(params[:team])
      year = Integer(params[:year])
      round = Integer(params[:round])
      salary_year = begin
        Integer(params[:salary_year])
      rescue ArgumentError, TypeError
        CURRENT_SALARY_YEAR
      end

      picks = SalaryBookQueries.fetch_pick_assets(team_code, year, round)
      raise ActiveRecord::RecordNotFound if picks.empty?

      # Get team metadata for display
      team_meta = SalaryBookQueries.fetch_team_meta(team_code)

      related_team_codes = SalaryBookQueries.extract_pick_related_team_codes(picks)
      related_team_codes << team_code
      team_meta_by_code = SalaryBookQueries.fetch_team_meta_by_codes(related_team_codes)

      render partial: "tools/salary_book/sidebar_pick", locals: {
        team_code:,
        year:,
        round:,
        salary_year:,
        picks:,
        team_meta:,
        team_meta_by_code:
      }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def salary_year_param
      raw = params[:year].presence
      return CURRENT_SALARY_YEAR unless raw

      year = Integer(raw)
      SALARY_YEARS.include?(year) ? year : CURRENT_SALARY_YEAR
    rescue ArgumentError, TypeError
      CURRENT_SALARY_YEAR
    end

    def salary_book_view_param
      raw = params[:view].to_s.strip.downcase
      AVAILABLE_VIEWS.include?(raw) ? raw : DEFAULT_VIEW
    end

    def valid_team_code?(raw)
      raw.to_s.strip.upcase.match?(/\A[A-Z]{3}\z/)
    end

    def normalize_team_code(raw)
      team = raw.to_s.strip.upcase
      raise ActiveRecord::RecordNotFound unless team.match?(/\A[A-Z]{3}\z/)

      team
    end

  end
end
