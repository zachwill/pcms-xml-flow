module Tools
  class SalaryBookController < ApplicationController
    CURRENT_SALARY_YEAR = 2025
    # Canonical year horizon for the salary book (keep in sync with SalaryBookHelper::SALARY_YEARS).
    SALARY_YEARS = (2025..2030).to_a.freeze

    # GET /tools/salary-book
    def show
      @salary_year = salary_year_param
      @salary_years = SALARY_YEARS
      # Default path: ship shell quickly, then patch full #maincanvas HTML in a follow-up GET.
      @defer_heavy_load = params[:full].to_s != "1"

      team_rows = fetch_team_index_rows(@salary_year)
      @team_codes = team_rows.map { |row| row["team_code"] }.compact
      @teams_by_conference, @team_meta_by_code = build_team_maps(team_rows)

      requested = params[:team]
      @initial_team = if requested.present? && valid_team_code?(requested)
        requested.to_s.strip.upcase
      else
        @team_codes.first
      end

      @initial_team_meta = @initial_team ? (@team_meta_by_code[@initial_team] || {}) : {}

      if @defer_heavy_load
        @players_by_team = {}
        @cap_holds_by_team = {}
        @exceptions_by_team = {}
        @dead_money_by_team = {}
        @picks_by_team = {}
        @team_summaries = {}
        @initial_team_summary = nil
        @initial_team_summaries_by_year = {}
      else
        @players_by_team = fetch_players_by_team(@team_codes)

        # Bulk fetch sub-section data (avoids N+1)
        @cap_holds_by_team = fetch_cap_holds_by_team(@team_codes)
        @exceptions_by_team = fetch_exceptions_by_team(@team_codes)
        @dead_money_by_team = fetch_dead_money_by_team(@team_codes)
        @picks_by_team = fetch_picks_by_team(@team_codes)

        # Bulk fetch team salary summaries for all teams × years (for header KPIs + totals footer)
        @team_summaries = fetch_all_team_summaries(@team_codes)

        @initial_team_summaries_by_year = @initial_team ? (@team_summaries[@initial_team] || {}) : {}
        @initial_team_summary = if @initial_team
          @initial_team_summaries_by_year[@salary_year] || @initial_team_summaries_by_year[SALARY_YEARS.first]
        end
      end

      if maincanvas_fragment_request?
        render_maincanvas_fragment
        return
      end
    rescue ActiveRecord::StatementInvalid => e
      # Useful when a dev DB hasn't been hydrated with the pcms.* schema yet.
      @boot_error = e.message
      @salary_year = salary_year_param
      @salary_years = SALARY_YEARS
      @defer_heavy_load = false
      @team_codes = []
      @teams_by_conference = { "Eastern" => [], "Western" => [] }
      @players_by_team = {}
      @cap_holds_by_team = {}
      @exceptions_by_team = {}
      @dead_money_by_team = {}
      @picks_by_team = {}
      @team_summaries = {}
      @team_meta_by_code = {}
      @initial_team = nil
      @initial_team_summary = nil
      @initial_team_meta = {}
      @initial_team_summaries_by_year = {}

      if maincanvas_fragment_request?
        render_maincanvas_fragment
        return
      end
    end

    # GET /tools/salary-book/teams/:teamcode/section
    def team_section
      team_code = normalize_team_code(params[:teamcode])
      year = salary_year_param
      players = fetch_team_players(team_code)

      # Fetch sub-sections for this team
      cap_holds = fetch_cap_holds_by_team([team_code])[team_code] || []
      exceptions = fetch_exceptions_by_team([team_code])[team_code] || []
      dead_money = fetch_dead_money_by_team([team_code])[team_code] || []
      picks = fetch_picks_by_team([team_code])[team_code] || []

      # Fetch team summaries (all years) for header + footer
      team_summaries = fetch_all_team_summaries([team_code])[team_code] || {}

      # Get team metadata from conference lookup
      team_meta = fetch_team_meta(team_code)

      render partial: "tools/salary_book/team_section", locals: {
        team_code:,
        players:,
        cap_holds:,
        exceptions:,
        dead_money:,
        picks:,
        team_summaries:,
        team_meta:,
        year:,
        salary_years: SALARY_YEARS
      }, layout: false
    end

    # GET /tools/salary-book/sidebar/team?team=BOS
    def sidebar_team
      team_code = normalize_team_code(params[:team])
      year = salary_year_param

      # Multi-year summaries for projections bar chart + stats tab
      summaries_by_year = fetch_all_team_summaries([team_code])[team_code] || {}

      # Current year summary (includes computed cap_space + apron aliases)
      summary = summaries_by_year[year] || {}

      # Team metadata (name, conference, logo)
      team_meta = fetch_team_meta(team_code)

      # Sidebar tab payloads
      draft_assets = fetch_sidebar_draft_assets(team_code, start_year: year, year_count: 3)
      rights_by_kind = fetch_sidebar_rights_by_kind(team_code)

      render partial: "tools/salary_book/sidebar_team", locals: {
        team_code:,
        summary:,
        team_meta:,
        summaries_by_year:,
        draft_assets:,
        rights_by_kind:,
        year:
      }, layout: false
    end

    # GET /tools/salary-book/sidebar/player/:id
    def sidebar_player
      player_id = Integer(params[:id])
      player = fetch_player(player_id)
      raise ActiveRecord::RecordNotFound unless player

      render partial: "tools/salary_book/sidebar_player", locals: { player: }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /tools/salary-book/sidebar/clear
    def sidebar_clear
      render partial: "tools/salary_book/sidebar_clear", layout: false
    end

    # GET /tools/salary-book/sidebar/agent/:id
    def sidebar_agent
      agent_id = Integer(params[:id])
      agent = fetch_agent(agent_id)
      raise ActiveRecord::RecordNotFound unless agent

      clients = fetch_agent_clients(agent_id)

      render partial: "tools/salary_book/sidebar_agent", locals: { agent:, clients: }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /tools/salary-book/sidebar/pick?team=BOS&year=2025&round=1
    def sidebar_pick
      team_code = normalize_team_code(params[:team])
      year = Integer(params[:year])
      round = Integer(params[:round])

      picks = fetch_pick_assets(team_code, year, round)
      raise ActiveRecord::RecordNotFound if picks.empty?

      # Get team metadata for display
      team_meta = fetch_team_meta(team_code)

      render partial: "tools/salary_book/sidebar_pick", locals: {
        team_code:,
        year:,
        round:,
        picks:,
        team_meta:
      }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def conn
      ActiveRecord::Base.connection
    end

    def salary_year_param
      raw = params[:year].presence
      return CURRENT_SALARY_YEAR unless raw

      year = Integer(raw)
      SALARY_YEARS.include?(year) ? year : CURRENT_SALARY_YEAR
    rescue ArgumentError, TypeError
      CURRENT_SALARY_YEAR
    end

    def valid_team_code?(raw)
      raw.to_s.strip.upcase.match?(/\A[A-Z]{3}\z/)
    end

    def normalize_team_code(raw)
      team = raw.to_s.strip.upcase
      raise ActiveRecord::RecordNotFound unless team.match?(/\A[A-Z]{3}\z/)

      team
    end

    def maincanvas_fragment_request?
      params[:fragment].to_s == "maincanvas"
    end

    def render_maincanvas_fragment
      original = ActionView::Base.annotate_rendered_view_with_filenames
      ActionView::Base.annotate_rendered_view_with_filenames = false

      render partial: "tools/salary_book/maincanvas", locals: {
        defer_heavy_load: @defer_heavy_load,
        boot_error: @boot_error,
        team_codes: @team_codes,
        salary_year: @salary_year,
        salary_years: @salary_years,
        players_by_team: @players_by_team,
        cap_holds_by_team: @cap_holds_by_team,
        exceptions_by_team: @exceptions_by_team,
        dead_money_by_team: @dead_money_by_team,
        picks_by_team: @picks_by_team,
        team_summaries: @team_summaries,
        team_meta_by_code: @team_meta_by_code
      }, layout: false
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = original
    end

    # Team index rows for the selected salary year (single query).
    # Includes all metadata needed by the shell command bar + logos map.
    def fetch_team_index_rows(year)
      year_sql = conn.quote(year)

      conn.exec_query(<<~SQL).to_a
        SELECT
          tsw.team_code,
          t.team_name,
          t.conference_name,
          t.team_id
        FROM pcms.team_salary_warehouse tsw
        LEFT JOIN pcms.teams t
          ON t.team_code = tsw.team_code
         AND t.league_lk = 'NBA'
        WHERE tsw.salary_year = #{year_sql}
        ORDER BY tsw.team_code
      SQL
    end

    def build_team_maps(rows)
      teams_by_conference = { "Eastern" => [], "Western" => [] }
      team_meta_by_code = {}

      rows.each do |row|
        code = row["team_code"]
        next if code.blank?

        team_meta_by_code[code] = row

        conf = row["conference_name"]
        next unless teams_by_conference.key?(conf)

        teams_by_conference[conf] << {
          code:,
          name: (row["team_name"].presence || code)
        }
      end

      [teams_by_conference, team_meta_by_code]
    end

    def fetch_players_by_team(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(player_columns_sql("sbw.team_code IN (#{in_list})")).to_a

      rows.group_by { |r| r["team_code"] }
    end

    def fetch_team_players(team_code)
      team_sql = conn.quote(team_code)

      conn.exec_query(player_columns_sql("sbw.team_code = #{team_sql}")).to_a
    end

    def player_columns_sql(where_clause)
      <<~SQL
        SELECT
          sbw.player_id,
          sbw.player_name,
          sbw.team_code,
          sbw.age,
          p.years_of_service,
          sbw.agent_name,
          sbw.agent_id,
          a.agency_name,
          epm_latest.season AS epm_season,
          epm_latest.epm AS epm_value,
          epm_latest.epm_pctl AS epm_percentile,
          sbw.cap_2025, sbw.cap_2026, sbw.cap_2027, sbw.cap_2028, sbw.cap_2029, sbw.cap_2030,
          sbw.pct_cap_2025, sbw.pct_cap_2026, sbw.pct_cap_2027, sbw.pct_cap_2028, sbw.pct_cap_2029, sbw.pct_cap_2030,
          sbw.total_salary_from_2025,
          sbw.option_2025, sbw.option_2026, sbw.option_2027, sbw.option_2028, sbw.option_2029, sbw.option_2030,
          sbw.is_two_way,
          sbw.is_no_trade,
          sbw.is_trade_bonus,
          sbw.trade_bonus_percent,
          sbw.trade_kicker_display,
          sbw.is_trade_consent_required_now,
          sbw.is_trade_restricted_now,
          sbw.is_poison_pill,
          sbw.is_min_contract,
          sbw.is_fully_guaranteed_2025, sbw.is_fully_guaranteed_2026, sbw.is_fully_guaranteed_2027,
          sbw.is_fully_guaranteed_2028, sbw.is_fully_guaranteed_2029, sbw.is_fully_guaranteed_2030,
          sbw.is_partially_guaranteed_2025, sbw.is_partially_guaranteed_2026, sbw.is_partially_guaranteed_2027,
          sbw.is_partially_guaranteed_2028, sbw.is_partially_guaranteed_2029, sbw.is_partially_guaranteed_2030,
          sbw.is_non_guaranteed_2025, sbw.is_non_guaranteed_2026, sbw.is_non_guaranteed_2027,
          sbw.is_non_guaranteed_2028, sbw.is_non_guaranteed_2029, sbw.is_non_guaranteed_2030,
          sbw.pct_cap_percentile_2025, sbw.pct_cap_percentile_2026, sbw.pct_cap_percentile_2027,
          sbw.pct_cap_percentile_2028, sbw.pct_cap_percentile_2029, sbw.pct_cap_percentile_2030,
          sbw.contract_type_code,
          sbw.contract_type_lookup_value
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.people p
          ON p.person_id = sbw.player_id
        LEFT JOIN pcms.agents a
          ON a.agent_id = sbw.agent_id
        LEFT JOIN (
          SELECT DISTINCT ON (nba_id)
            nba_id,
            season,
            epm,
            epm_pctl
          FROM dunks.epm
          WHERE season_type = 2
          ORDER BY nba_id, (epm IS NULL), season DESC
        ) epm_latest
          ON epm_latest.nba_id = sbw.player_id
        WHERE #{where_clause}
        ORDER BY sbw.team_code, sbw.cap_2025 DESC NULLS LAST, sbw.total_salary_from_2025 DESC NULLS LAST, sbw.player_name
      SQL
    end

    def fetch_team_summary(team_code, year)
      team_sql = conn.quote(team_code)
      year_sql = conn.quote(year)

      conn.exec_query(
        <<~SQL
          SELECT *
          FROM pcms.team_salary_warehouse
          WHERE team_code = #{team_sql}
            AND salary_year = #{year_sql}
          LIMIT 1
        SQL
      ).first
    end

    def fetch_player(player_id)
      id_sql = conn.quote(player_id)

      conn.exec_query(
        <<~SQL
          SELECT
            sbw.player_id,
            sbw.player_name,
            sbw.team_code,
            sbw.agent_name,
            sbw.agent_id,
            sbw.age,
            p.years_of_service,
            epm_latest.season AS epm_season,
            epm_latest.epm AS epm_value,
            epm_latest.epm_pctl AS epm_percentile,
            sbw.cap_2025,
            sbw.cap_2026,
            sbw.cap_2027,
            sbw.cap_2028,
            sbw.cap_2029,
            sbw.cap_2030,
            sbw.total_salary_from_2025,
            sbw.option_2025,
            sbw.option_2026,
            sbw.option_2027,
            sbw.option_2028,
            sbw.option_2029,
            sbw.option_2030,
            sbw.is_two_way,
            sbw.is_no_trade,
            sbw.is_trade_bonus,
            sbw.trade_bonus_percent,
            sbw.trade_kicker_display,
            sbw.is_poison_pill,
            sbw.is_trade_consent_required_now,
            sbw.is_trade_preconsented,
            sbw.is_trade_restricted_now,
            sbw.trade_restriction_lookup_value,
            sbw.is_min_contract,
            sbw.min_contract_lookup_value,
            sbw.contract_type_code,
            sbw.contract_type_lookup_value,
            sbw.signed_method_code,
            sbw.signed_method_lookup_value,
            sbw.exception_type_lookup_value,
            sbw.guaranteed_amount_2025,
            sbw.guaranteed_amount_2026,
            sbw.guaranteed_amount_2027,
            sbw.guaranteed_amount_2028,
            sbw.guaranteed_amount_2029,
            sbw.guaranteed_amount_2030,
            sbw.is_fully_guaranteed_2025,
            sbw.is_fully_guaranteed_2026,
            sbw.is_fully_guaranteed_2027,
            sbw.is_fully_guaranteed_2028,
            sbw.is_fully_guaranteed_2029,
            sbw.is_fully_guaranteed_2030,
            sbw.is_partially_guaranteed_2025,
            sbw.is_partially_guaranteed_2026,
            sbw.is_partially_guaranteed_2027,
            sbw.is_partially_guaranteed_2028,
            sbw.is_partially_guaranteed_2029,
            sbw.is_partially_guaranteed_2030,
            sbw.is_non_guaranteed_2025,
            sbw.is_non_guaranteed_2026,
            sbw.is_non_guaranteed_2027,
            sbw.is_non_guaranteed_2028,
            sbw.is_non_guaranteed_2029,
            sbw.is_non_guaranteed_2030,
            sbw.likely_bonus_2025,
            sbw.likely_bonus_2026,
            sbw.likely_bonus_2027,
            sbw.likely_bonus_2028,
            sbw.likely_bonus_2029,
            sbw.likely_bonus_2030,
            sbw.unlikely_bonus_2025,
            sbw.unlikely_bonus_2026,
            sbw.unlikely_bonus_2027,
            sbw.unlikely_bonus_2028,
            sbw.unlikely_bonus_2029,
            sbw.unlikely_bonus_2030,
            sbw.refreshed_at
          FROM pcms.salary_book_warehouse sbw
          LEFT JOIN pcms.people p
            ON p.person_id = sbw.player_id
          LEFT JOIN (
            SELECT DISTINCT ON (nba_id)
              nba_id,
              season,
              epm,
              epm_pctl
            FROM dunks.epm
            WHERE season_type = 2
            ORDER BY nba_id, (epm IS NULL), season DESC
          ) epm_latest
            ON epm_latest.nba_id = sbw.player_id
          WHERE sbw.player_id = #{id_sql}
          LIMIT 1
        SQL
      ).first
    end

    # -------------------------------------------------------------------------
    # Bulk fetch sub-section data (avoids N+1 per team)
    # -------------------------------------------------------------------------

    def fetch_cap_holds_by_team(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          non_contract_amount_id AS id,
          team_code,
          player_id,
          player_name,
          amount_type_lk,
          MAX(cap_amount) FILTER (WHERE salary_year = 2025)::numeric AS cap_2025,
          MAX(cap_amount) FILTER (WHERE salary_year = 2026)::numeric AS cap_2026,
          MAX(cap_amount) FILTER (WHERE salary_year = 2027)::numeric AS cap_2027,
          MAX(cap_amount) FILTER (WHERE salary_year = 2028)::numeric AS cap_2028,
          MAX(cap_amount) FILTER (WHERE salary_year = 2029)::numeric AS cap_2029,
          MAX(cap_amount) FILTER (WHERE salary_year = 2030)::numeric AS cap_2030
        FROM pcms.cap_holds_warehouse
        WHERE team_code IN (#{in_list})
          AND salary_year BETWEEN 2025 AND 2030
        GROUP BY non_contract_amount_id, team_code, player_id, player_name, amount_type_lk
        ORDER BY team_code, cap_2025 DESC NULLS LAST, player_name ASC NULLS LAST
      SQL

      rows.group_by { |r| r["team_code"] }
    end

    def fetch_exceptions_by_team(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_exception_id AS id,
          team_code,
          exception_type_lk,
          exception_type_name,
          trade_exception_player_id,
          trade_exception_player_name,
          expiration_date,
          is_expired,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2025)::numeric AS remaining_2025,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2026)::numeric AS remaining_2026,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2027)::numeric AS remaining_2027,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2028)::numeric AS remaining_2028,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2029)::numeric AS remaining_2029,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2030)::numeric AS remaining_2030
        FROM pcms.exceptions_warehouse
        WHERE team_code IN (#{in_list})
          AND salary_year BETWEEN 2025 AND 2030
          AND COALESCE(is_expired, false) = false
        GROUP BY
          team_exception_id,
          team_code,
          exception_type_lk,
          exception_type_name,
          trade_exception_player_id,
          trade_exception_player_name,
          expiration_date,
          is_expired
        ORDER BY team_code, remaining_2025 DESC NULLS LAST, exception_type_name ASC NULLS LAST
      SQL

      rows.group_by { |r| r["team_code"] }
    end

    def fetch_dead_money_by_team(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          transaction_waiver_amount_id AS id,
          team_code,
          player_id,
          player_name,
          waive_date,
          MAX(cap_value) FILTER (WHERE salary_year = 2025)::numeric AS cap_2025,
          MAX(cap_value) FILTER (WHERE salary_year = 2026)::numeric AS cap_2026,
          MAX(cap_value) FILTER (WHERE salary_year = 2027)::numeric AS cap_2027,
          MAX(cap_value) FILTER (WHERE salary_year = 2028)::numeric AS cap_2028,
          MAX(cap_value) FILTER (WHERE salary_year = 2029)::numeric AS cap_2029,
          MAX(cap_value) FILTER (WHERE salary_year = 2030)::numeric AS cap_2030
        FROM pcms.dead_money_warehouse
        WHERE team_code IN (#{in_list})
          AND salary_year BETWEEN 2025 AND 2030
        GROUP BY transaction_waiver_amount_id, team_code, player_id, player_name, waive_date
        ORDER BY team_code, cap_2025 DESC NULLS LAST, player_name ASC NULLS LAST
      SQL

      rows.group_by { |r| r["team_code"] }
    end

    def fetch_picks_by_team(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          draft_year AS year,
          draft_round AS round,
          asset_slot,
          sub_asset_slot,
          asset_type,
          is_conditional,
          is_swap,
          counterparty_team_code AS origin_team_code,
          raw_part AS description
        FROM pcms.draft_pick_summary_assets
        WHERE team_code IN (#{in_list})
          AND draft_year BETWEEN 2025 AND 2030
        ORDER BY team_code, draft_year, draft_round, asset_slot, sub_asset_slot
      SQL

      # Generate unique ID for each pick
      rows.each_with_index do |row, idx|
        row["id"] = "#{row['team_code']}-#{row['year']}-#{row['round']}-#{row['asset_slot']}-#{row['sub_asset_slot']}"
      end

      rows.group_by { |r| r["team_code"] }
    end

    # -------------------------------------------------------------------------
    # Sidebar tab data (team context)
    # -------------------------------------------------------------------------

    def fetch_sidebar_draft_assets(team_code, start_year:, year_count: 3)
      team_sql = conn.quote(team_code)
      from_year = start_year.to_i
      to_year = from_year + year_count.to_i - 1

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          draft_year AS year,
          draft_round AS round,
          asset_slot,
          sub_asset_slot,
          asset_type,
          is_conditional,
          is_swap,
          counterparty_team_code AS origin_team_code,
          raw_part AS description
        FROM pcms.draft_pick_summary_assets
        WHERE team_code = #{team_sql}
          AND draft_year BETWEEN #{conn.quote(from_year)} AND #{conn.quote(to_year)}
        ORDER BY draft_year, draft_round, asset_slot, sub_asset_slot
      SQL

      rows.each do |row|
        row["id"] = "#{row['team_code']}-#{row['year']}-#{row['round']}-#{row['asset_slot']}-#{row['sub_asset_slot']}"
      end

      rows
    end

    def fetch_sidebar_rights_by_kind(team_code)
      team_sql = conn.quote(team_code)

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          player_id,
          player_name,
          rights_kind,
          rights_source,
          source_trade_id,
          source_trade_date,
          draft_year,
          draft_round,
          draft_pick,
          draft_team_code,
          needs_review,
          refreshed_at
        FROM pcms.player_rights_warehouse
        WHERE rights_team_code = #{team_sql}
        ORDER BY rights_kind, draft_year DESC NULLS LAST, draft_round ASC NULLS LAST, draft_pick ASC NULLS LAST, player_name
      SQL

      rows.group_by { |row| row["rights_kind"] }
    end

    # -------------------------------------------------------------------------
    # Team summary data (for header KPIs + totals footer)
    # -------------------------------------------------------------------------

    # Fetch all team salary summaries for all years, grouped by team_code.
    # Returns: { "BOS" => { 2025 => {...}, 2026 => {...}, ... }, "LAL" => {...} }
    def fetch_all_team_summaries(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          salary_year,
          cap_total,
          cap_total_hold,
          tax_total,
          apron_total,
          roster_row_count,
          two_way_row_count,
          salary_cap_amount,
          tax_level_amount,
          tax_apron_amount,
          tax_apron2_amount,
          (COALESCE(salary_cap_amount, 0) - COALESCE(cap_total_hold, 0))::bigint AS cap_space,
          room_under_tax,
          room_under_apron1 AS room_under_first_apron,
          room_under_apron2 AS room_under_second_apron,
          is_taxpayer AS is_over_tax,
          is_subject_to_apron AS is_over_first_apron,
          apron_level_lk,
          refreshed_at
        FROM pcms.team_salary_warehouse
        WHERE team_code IN (#{in_list})
          AND salary_year BETWEEN 2025 AND 2030
        ORDER BY team_code, salary_year
      SQL

      result = {}
      rows.each do |row|
        team_code = row["team_code"]
        year = row["salary_year"]
        result[team_code] ||= {}
        result[team_code][year] = row
      end
      result
    end

    # Fetch team metadata (name, conference, team_id) for a single team
    def fetch_team_meta(team_code)
      team_sql = conn.quote(team_code)

      conn.exec_query(<<~SQL).first || {}
        SELECT
          team_code,
          team_name,
          conference_name,
          team_id
        FROM pcms.teams
        WHERE team_code = #{team_sql}
          AND league_lk = 'NBA'
        LIMIT 1
      SQL
    end

    # Bulk fetch team metadata for multiple teams
    def fetch_team_meta_by_code(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          team_name,
          conference_name,
          team_id
        FROM pcms.teams
        WHERE team_code IN (#{in_list})
          AND league_lk = 'NBA'
      SQL

      rows.each_with_object({}) { |row, h| h[row["team_code"]] = row }
    end

    # -------------------------------------------------------------------------
    # Agent data (for sidebar overlay)
    # -------------------------------------------------------------------------

    def fetch_agent(agent_id)
      id_sql = conn.quote(agent_id)

      conn.exec_query(<<~SQL).first
        SELECT
          agent_id,
          full_name AS name,
          agency_id,
          agency_name
        FROM pcms.agents
        WHERE agent_id = #{id_sql}
        LIMIT 1
      SQL
    end

    def fetch_agent_clients(agent_id)
      id_sql = conn.quote(agent_id)

      conn.exec_query(<<~SQL).to_a
        SELECT
          s.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            s.player_name
          ) AS player_name,
          p.display_first_name,
          p.display_last_name,
          COALESCE(NULLIF(s.person_team_code, ''), s.team_code) AS team_code,
          s.age,
          p.years_of_service,
          s.cap_2025::numeric,
          s.cap_2026::numeric,
          s.cap_2027::numeric,
          s.cap_2028::numeric,
          s.cap_2029::numeric,
          s.cap_2030::numeric,
          COALESCE(s.is_two_way, false)::boolean AS is_two_way,
          t.team_id,
          t.team_name
        FROM pcms.salary_book_warehouse s
        LEFT JOIN pcms.people p ON s.player_id = p.person_id
        LEFT JOIN pcms.teams t ON s.team_code = t.team_code AND t.league_lk = 'NBA'
        WHERE s.agent_id = #{id_sql}
        ORDER BY s.cap_2025 DESC NULLS LAST, player_name
      SQL
    end

    # -------------------------------------------------------------------------
    # Pick data (for sidebar overlay)
    # -------------------------------------------------------------------------

    def fetch_pick_assets(team_code, year, round)
      team_sql = conn.quote(team_code)
      year_sql = conn.quote(year)
      round_sql = conn.quote(round)

      conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          draft_year AS year,
          draft_round AS round,
          asset_slot,
          sub_asset_slot,
          asset_type,
          is_conditional,
          is_swap,
          counterparty_team_code AS origin_team_code,
          counterparty_team_codes,
          via_team_codes,
          raw_part AS description,
          raw_round_text,
          raw_fragment,
          endnote_explanation,
          endnote_trade_date,
          endnote_is_swap,
          endnote_is_conditional,
          refreshed_at
        FROM pcms.draft_pick_summary_assets
        WHERE team_code = #{team_sql}
          AND draft_year = #{year_sql}
          AND draft_round = #{round_sql}
        ORDER BY asset_slot, sub_asset_slot
      SQL
    end
  end
end
