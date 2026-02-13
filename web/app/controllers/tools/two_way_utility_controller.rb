module Tools
  class TwoWayUtilityController < ApplicationController
    include Datastar

    RISK_LENSES = %w[all warning critical estimate].freeze
    CONFERENCE_LENSES = ["all", "Eastern", "Western"].freeze
    INTENT_SHORTLIST_LIMIT = 5

    # GET /tools/two-way-utility
    def show
      load_workspace_state!
    rescue ActiveRecord::StatementInvalid => e
      apply_boot_error!(e)
    end

    # GET /tools/two-way-utility/sidebar/:id
    def sidebar
      load_workspace_state!

      player_id = Integer(params[:id])
      raise ActiveRecord::RecordNotFound if player_id <= 0

      @sidebar_player = @rows.find { |row| row["player_id"].to_i == player_id } || fetch_player_row(player_id)
      raise ActiveRecord::RecordNotFound unless @sidebar_player

      @sidebar_team_meta = @team_meta_by_code[@sidebar_player["team_code"].to_s] || {}

      render partial: "tools/two_way_utility/rightpanel_overlay_player", layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    rescue ActiveRecord::StatementInvalid => e
      render html: <<~HTML.html_safe, layout: false
        <div id="rightpanel-overlay" class="h-full p-4">
          <div class="rounded border border-border bg-muted/20 p-3">
            <div class="text-sm font-medium text-destructive">Two-Way sidebar failed</div>
            <pre class="mt-2 text-xs text-muted-foreground overflow-x-auto">#{ERB::Util.h(e.message)}</pre>
          </div>
        </div>
      HTML
    end

    # GET /tools/two-way-utility/sidebar/clear
    def sidebar_clear
      render partial: "tools/two_way_utility/rightpanel_clear", layout: false
    end

    # GET /tools/two-way-utility/sse/refresh
    # One-request multi-region update for commandbar + board + sidebars.
    # Patches:
    # - #commandbar
    # - #maincanvas
    # - #rightpanel-base
    # - #rightpanel-overlay (preserved when selected row remains visible)
    def refresh
      load_workspace_state!
      apply_compare_action!

      requested_overlay_id = requested_overlay_id_param
      overlay_html, resolved_overlay_type, resolved_overlay_id = refreshed_overlay_payload(
        requested_overlay_id: requested_overlay_id
      )

      with_sse_stream do |sse|
        commandbar_html = without_view_annotations do
          render_to_string(partial: "tools/two_way_utility/commandbar", layout: false)
        end

        main_html = without_view_annotations do
          render_to_string(partial: "tools/two_way_utility/workspace_main", layout: false)
        end

        sidebar_html = without_view_annotations do
          render_to_string(partial: "tools/two_way_utility/rightpanel_base", layout: false)
        end

        patch_elements_by_id(sse, commandbar_html)
        patch_elements_by_id(sse, main_html)
        patch_elements_by_id(sse, sidebar_html)
        patch_elements_by_id(sse, overlay_html)
        patch_signals(
          sse,
          twconference: @conference,
          twteam: @team.to_s,
          twrisk: @risk,
          twintent: @intent.to_s,
          twintentcursor: @intent_shortlist_default_id.to_s,
          twintentcursorindex: 0,
          comparea: @compare_a_id.to_s,
          compareb: @compare_b_id.to_s,
          overlaytype: resolved_overlay_type,
          overlayid: resolved_overlay_id
        )
      end
    rescue ActiveRecord::StatementInvalid => e
      with_sse_stream do |sse|
        patch_flash(sse, "Two-Way refresh failed: #{e.message.to_s.truncate(160)}")
      end
    end

    private

    def conn
      ActiveRecord::Base.connection
    end

    def load_workspace_state!
      @conference = resolve_conference(params[:conference])
      @team = resolve_team(params[:team])
      @risk = resolve_risk(params[:risk])
      @intent = resolve_intent(params[:intent])

      @rows = fetch_rows(conference: @conference, team: @team, risk: @risk, intent: @intent)
      @rows_by_team = @rows.group_by { |row| row["team_code"] }

      @teams_by_conference, @team_meta_by_code = fetch_teams
      @team_capacity_by_code = fetch_team_capacity_by_code
      @team_options = build_team_options(@teams_by_conference, @rows_by_team.keys)
      @team_codes = resolve_team_codes(@team_options, @rows_by_team.keys, @team)

      @state_query = build_state_query
      @compare_a_id = normalize_player_id_param(params[:compare_a])
      @compare_b_id = normalize_player_id_param(params[:compare_b])
      normalize_compare_slots!
      hydrate_compare_rows!
      @selected_player_id = normalize_selected_player_id_param(params[:selected_id])
      build_sidebar_summary!(selected_player_id: @selected_player_id)
      build_intent_shortlist!
    end

    def apply_boot_error!(error)
      @boot_error = error.message
      @conference = "all"
      @team = nil
      @risk = "all"
      @intent = ""
      @rows = []
      @rows_by_team = {}
      @teams_by_conference = { "Eastern" => [], "Western" => [] }
      @team_meta_by_code = {}
      @team_capacity_by_code = {}
      @team_options = []
      @team_codes = []
      @state_query = build_state_query
      @compare_a_id = nil
      @compare_b_id = nil
      @compare_a_row = nil
      @compare_b_row = nil
      @selected_player_id = nil
      build_sidebar_summary!(selected_player_id: @selected_player_id)
      @intent_shortlist = []
      @intent_shortlist_default_id = ""
    end

    def resolve_conference(value)
      normalized = value.to_s.strip
      CONFERENCE_LENSES.include?(normalized) ? normalized : "all"
    end

    def resolve_team(value)
      code = value.to_s.strip.upcase
      code.match?(/\A[A-Z]{3}\z/) ? code : nil
    end

    def resolve_risk(value)
      normalized = value.to_s.strip
      RISK_LENSES.include?(normalized) ? normalized : "all"
    end

    def resolve_intent(value)
      value.to_s.strip.tr("\u0000", "")[0, 80]
    end

    def resolve_compare_action(value)
      normalized = value.to_s.strip
      return normalized if %w[pin clear_slot clear_all].include?(normalized)

      nil
    end

    def resolve_compare_slot(value)
      normalized = value.to_s.strip.downcase
      return normalized if %w[a b].include?(normalized)

      nil
    end

    def normalize_player_id_param(raw)
      player_id = Integer(raw.to_s.strip, 10)
      player_id.positive? ? player_id : nil
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_compare_slots!
      if @compare_a_id.present? && @compare_a_id == @compare_b_id
        @compare_b_id = nil
      end
    end

    def hydrate_compare_rows!
      @compare_a_row = row_for_compare_slot(@compare_a_id)
      @compare_b_row = row_for_compare_slot(@compare_b_id)

      @compare_a_id = nil if @compare_a_id.present? && @compare_a_row.blank?
      @compare_b_id = nil if @compare_b_id.present? && @compare_b_row.blank?
      normalize_compare_slots!

      @compare_a_row = nil if @compare_a_id.blank?
      @compare_b_row = nil if @compare_b_id.blank?
    end

    def row_for_compare_slot(player_id)
      normalized_id = player_id.to_i
      return nil if normalized_id <= 0

      @rows.find { |row| row["player_id"].to_i == normalized_id } || fetch_player_row(normalized_id)
    end

    def apply_compare_action!
      compare_action_param = params[:compare_action].presence || request.query_parameters["action"]
      compare_slot_param = params[:compare_slot].presence || request.query_parameters["slot"]

      action = resolve_compare_action(compare_action_param)
      slot = resolve_compare_slot(compare_slot_param)
      player_id = normalize_player_id_param(params[:player_id])

      case action
      when "pin"
        return if slot.blank? || player_id.blank?

        if slot == "a"
          @compare_a_id = player_id
          @compare_b_id = nil if @compare_b_id == player_id
        else
          @compare_b_id = player_id
          @compare_a_id = nil if @compare_a_id == player_id
        end
      when "clear_slot"
        return if slot.blank?

        if slot == "a"
          @compare_a_id = nil
        else
          @compare_b_id = nil
        end
      when "clear_all"
        @compare_a_id = nil
        @compare_b_id = nil
      end

      normalize_compare_slots!
      hydrate_compare_rows!
    end

    def build_state_query
      Rack::Utils.build_query(
        conference: @conference.to_s,
        team: @team.to_s,
        risk: @risk.to_s,
        intent: @intent.to_s
      )
    end

    def resolve_team_codes(team_options, rows_team_codes, selected_team)
      options = Array(team_options).map { |row| row[:code] }
      row_codes = Array(rows_team_codes).compact.map(&:to_s)

      if selected_team.present?
        return [ selected_team ]
      end

      (options & row_codes) + (row_codes - options)
    end

    def fetch_rows(conference:, team:, risk:, intent:)
      where_clauses = []
      where_clauses << "tw.conference_name = #{conn.quote(conference)}" if conference != "all"
      where_clauses << "tw.team_code = #{conn.quote(team)}" if team.present?

      case risk
      when "critical"
        where_clauses << "COALESCE(tw.remaining_active_list_games, 999) <= 10"
      when "warning"
        where_clauses << "COALESCE(tw.remaining_active_list_games, 999) <= 20"
      when "estimate"
        where_clauses << "COALESCE(tw.active_list_games_limit_is_estimate, false) = true"
      end

      if intent.present?
        intent_like = conn.quote("%#{intent}%")
        where_clauses << "(tw.player_name ILIKE #{intent_like} OR tw.player_id::text ILIKE #{intent_like})"
      end

      where_sql = where_clauses.any? ? where_clauses.join(" AND ") : "TRUE"

      conn.exec_query(<<~SQL).to_a.map { |row| decorate_row(row) }
        SELECT
          tw.team_code,
          tw.team_name,
          tw.conference_name,
          tw.team_current_contract_count,
          tw.team_games_remaining_context,
          tw.team_is_under_15_contracts,
          tw.team_two_way_contract_count,
          tw.player_id,
          tw.player_name,
          tw.years_of_service,
          tw.games_on_active_list,
          tw.active_list_games_limit,
          tw.remaining_active_list_games,
          tw.active_list_games_limit_is_estimate,
          tw.signing_date,
          tw.last_game_date_est,
          sbw.age,
          sbw.cap_2025,
          sbw.cap_2026,
          sbw.agent_id,
          sbw.agent_name,
          ag.agency_name,
          COALESCE(sbw.is_two_way, true) AS is_two_way,
          COALESCE(sbw.is_trade_consent_required_now, false) AS is_trade_consent_required_now,
          COALESCE(sbw.is_trade_restricted_now, false) AS is_trade_restricted_now,
          COALESCE(sbw.is_poison_pill, false) AS is_poison_pill,
          COALESCE(sbw.is_no_trade, false) AS is_no_trade,
          COALESCE(sbw.is_trade_bonus, false) AS is_trade_bonus,
          sbw.trade_bonus_percent,
          sbw.option_2026,
          COALESCE(sbw.is_non_guaranteed_2026, false) AS is_non_guaranteed_2026,
          sbw.pct_cap_2025
        FROM pcms.two_way_utility_warehouse tw
        LEFT JOIN LATERAL (
          SELECT
            s.age,
            s.cap_2025,
            s.cap_2026,
            s.agent_id,
            s.agent_name,
            s.is_two_way,
            s.is_trade_consent_required_now,
            s.is_trade_restricted_now,
            s.is_poison_pill,
            s.is_no_trade,
            s.is_trade_bonus,
            s.trade_bonus_percent,
            s.option_2026,
            s.is_non_guaranteed_2026,
            s.pct_cap_2025
          FROM pcms.salary_book_warehouse s
          WHERE s.player_id = tw.player_id
            AND s.team_code = tw.team_code
          ORDER BY s.cap_2025 DESC NULLS LAST
          LIMIT 1
        ) sbw ON true
        LEFT JOIN pcms.agents ag
          ON ag.agent_id = sbw.agent_id
        WHERE #{where_sql}
        ORDER BY
          tw.team_code,
          CASE
            WHEN COALESCE(tw.remaining_active_list_games, 999) <= 10 THEN 0
            WHEN COALESCE(tw.remaining_active_list_games, 999) <= 20 THEN 1
            WHEN COALESCE(tw.active_list_games_limit_is_estimate, false) THEN 2
            ELSE 3
          END,
          COALESCE(tw.remaining_active_list_games, 999),
          tw.games_on_active_list DESC NULLS LAST,
          tw.player_name
      SQL
    end

    def fetch_player_row(player_id)
      id_sql = conn.quote(player_id)

      row = conn.exec_query(<<~SQL).first
        SELECT
          tw.team_code,
          tw.team_name,
          tw.conference_name,
          tw.team_current_contract_count,
          tw.team_games_remaining_context,
          tw.team_is_under_15_contracts,
          tw.team_two_way_contract_count,
          tw.player_id,
          tw.player_name,
          tw.years_of_service,
          tw.games_on_active_list,
          tw.active_list_games_limit,
          tw.remaining_active_list_games,
          tw.active_list_games_limit_is_estimate,
          tw.signing_date,
          tw.last_game_date_est,
          sbw.age,
          sbw.cap_2025,
          sbw.cap_2026,
          sbw.agent_id,
          sbw.agent_name,
          ag.agency_name,
          COALESCE(sbw.is_two_way, true) AS is_two_way,
          COALESCE(sbw.is_trade_consent_required_now, false) AS is_trade_consent_required_now,
          COALESCE(sbw.is_trade_restricted_now, false) AS is_trade_restricted_now,
          COALESCE(sbw.is_poison_pill, false) AS is_poison_pill,
          COALESCE(sbw.is_no_trade, false) AS is_no_trade,
          COALESCE(sbw.is_trade_bonus, false) AS is_trade_bonus,
          sbw.trade_bonus_percent,
          sbw.option_2026,
          COALESCE(sbw.is_non_guaranteed_2026, false) AS is_non_guaranteed_2026,
          sbw.pct_cap_2025
        FROM pcms.two_way_utility_warehouse tw
        LEFT JOIN LATERAL (
          SELECT
            s.age,
            s.cap_2025,
            s.cap_2026,
            s.agent_id,
            s.agent_name,
            s.is_two_way,
            s.is_trade_consent_required_now,
            s.is_trade_restricted_now,
            s.is_poison_pill,
            s.is_no_trade,
            s.is_trade_bonus,
            s.trade_bonus_percent,
            s.option_2026,
            s.is_non_guaranteed_2026,
            s.pct_cap_2025
          FROM pcms.salary_book_warehouse s
          WHERE s.player_id = tw.player_id
            AND s.team_code = tw.team_code
          ORDER BY s.cap_2025 DESC NULLS LAST
          LIMIT 1
        ) sbw ON true
        LEFT JOIN pcms.agents ag
          ON ag.agent_id = sbw.agent_id
        WHERE tw.player_id = #{id_sql}
        LIMIT 1
      SQL

      row.present? ? decorate_row(row) : nil
    end

    def decorate_row(row)
      used = row["games_on_active_list"]&.to_f
      limit = row["active_list_games_limit"]&.to_f
      remaining = row["remaining_active_list_games"]&.to_i
      estimate = truthy?(row["active_list_games_limit_is_estimate"])

      row["games_used_pct"] = if used && limit && limit.positive?
        used / limit
      end

      row["limit_status_chip"] = estimate ? "EST" : nil
      row["risk_tier"] = if remaining.present? && remaining <= 10
        "critical"
      elsif remaining.present? && remaining <= 20
        "warning"
      elsif estimate
        "estimate"
      else
        "stable"
      end

      row
    end

    def truthy?(value)
      case value
      when true, 1, "1", "t", "T", "true", "TRUE", "yes", "YES", "y", "Y"
        true
      else
        false
      end
    end

    def fetch_teams
      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_id,
          team_code,
          team_name,
          conference_name
        FROM pcms.teams
        WHERE league_lk = 'NBA'
          AND team_name NOT LIKE 'Non-NBA%'
          AND conference_name IS NOT NULL
        ORDER BY team_code
      SQL

      grouped = { "Eastern" => [], "Western" => [] }
      by_code = {}

      rows.each do |row|
        conf = row["conference_name"]
        next unless grouped.key?(conf)

        grouped[conf] << { code: row["team_code"], name: row["team_name"] }
        by_code[row["team_code"]] = row
      end

      [ grouped, by_code ]
    end

    def fetch_team_capacity_by_code
      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          current_contract_count AS team_current_contract_count,
          CASE
            WHEN COALESCE(current_contract_count, 0) < 15 THEN under_15_games_remaining
            ELSE games_remaining
          END AS team_games_remaining_context,
          (COALESCE(current_contract_count, 0) < 15) AS team_is_under_15_contracts
        FROM pcms.team_two_way_capacity
      SQL

      rows.each_with_object({}) { |row, by_code| by_code[row["team_code"]] = row }
    end

    def build_team_options(teams_by_conference, warehouse_team_codes)
      ordered_codes = %w[Eastern Western].flat_map do |conference|
        teams_by_conference.fetch(conference, []).map { |team| team[:code] }
      end

      extras = Array(warehouse_team_codes).compact.uniq - ordered_codes

      (ordered_codes + extras.sort).map do |code|
        meta = @team_meta_by_code[code] || {}
        {
          code:,
          name: meta["team_name"].presence || code,
          conference: meta["conference_name"].presence || "—"
        }
      end
    end

    def build_sidebar_summary!(selected_player_id: nil)
      rows = Array(@rows)
      critical_count = rows.count { |row| row["risk_tier"] == "critical" }
      warning_count = rows.count { |row| row["risk_tier"] == "warning" }
      low_remaining_count = rows.count { |row| row["remaining_active_list_games"].present? && row["remaining_active_list_games"].to_i <= 20 }
      estimate_count = rows.count { |row| truthy?(row["active_list_games_limit_is_estimate"]) }

      quick_rows = rows
        .select { |row| row["risk_tier"] != "stable" }
        .sort_by do |row|
          [
            risk_sort_priority(row["risk_tier"]),
            row["remaining_active_list_games"].presence || 999,
            -(row["games_used_pct"] || 0).to_f,
            row["team_code"].to_s,
            row["player_name"].to_s
          ]
        end
        .first(14)

      selected_id = selected_player_id.to_i
      if selected_id.positive?
        selected_row = rows.find { |row| row["player_id"].to_i == selected_id }
        if selected_row.present? && quick_rows.none? { |row| row["player_id"].to_i == selected_id }
          quick_rows = [selected_row] + quick_rows.first(13)
        end
      end

      active_filters = []
      active_filters << %(Intent: "#{@intent}") if @intent.present?
      active_filters << "Conference: #{@conference}" unless @conference == "all"
      active_filters << "Team: #{@team}" if @team.present?
      active_filters << "Risk: #{risk_filter_label(@risk)}" unless @risk == "all"

      @sidebar_summary = {
        row_count: rows.size,
        intent: @intent.to_s,
        intent_active: @intent.present?,
        team_count: @rows_by_team.keys.size,
        critical_count:,
        warning_count:,
        low_remaining_count:,
        estimate_count:,
        active_filters:,
        quick_rows:
      }
    end

    def build_intent_shortlist!
      query = @intent.to_s.strip.downcase
      if query.blank?
        @intent_shortlist = []
        @intent_shortlist_default_id = ""
        return
      end

      ranked_rows = Array(@rows)
        .map do |row|
          [
            intent_shortlist_score(row:, query:),
            risk_sort_priority(row["risk_tier"]),
            row["remaining_active_list_games"].presence || 999,
            -(row["games_used_pct"] || 0).to_f,
            row["team_code"].to_s,
            row["player_name"].to_s,
            row
          ]
        end
        .sort_by { |entry| entry[0..5] }
        .first(INTENT_SHORTLIST_LIMIT)

      @intent_shortlist = ranked_rows.map do |entry|
        row = entry.last
        {
          player_id: row["player_id"].to_i,
          player_name: row["player_name"].to_s,
          team_code: row["team_code"].to_s,
          risk_tier: row["risk_tier"].to_s,
          remaining_active_list_games: row["remaining_active_list_games"],
          games_used_pct: row["games_used_pct"]
        }
      end

      @intent_shortlist_default_id = @intent_shortlist.first&.dig(:player_id).to_s
    end

    def intent_shortlist_score(row:, query:)
      player_name = row["player_name"].to_s.downcase
      player_id = row["player_id"].to_s

      return 0 if player_id == query
      return 1 if player_name == query
      return 2 if player_name.start_with?(query)

      tokens = player_name.split(/[^a-z0-9]+/)
      return 3 if tokens.any? { |token| token.start_with?(query) }

      player_name.include?(query) ? 4 : 5
    end

    def normalize_selected_player_id_param(raw)
      normalize_player_id_param(raw)
    end

    def requested_overlay_id_param
      @selected_player_id || normalize_selected_player_id_param(params[:selected_id])
    end

    def selected_overlay_visible?(overlay_id:)
      normalized_id = overlay_id.to_i
      return false if normalized_id <= 0

      Array(@rows).any? { |row| row["player_id"].to_i == normalized_id }
    end

    def refreshed_overlay_payload(requested_overlay_id:)
      return [overlay_clear_html, "none", ""] unless selected_overlay_visible?(overlay_id: requested_overlay_id)

      @sidebar_player = @rows.find { |row| row["player_id"].to_i == requested_overlay_id.to_i }
      return [overlay_clear_html, "none", ""] unless @sidebar_player.present?

      @sidebar_team_meta = @team_meta_by_code[@sidebar_player["team_code"].to_s] || {}

      html = without_view_annotations do
        render_to_string(partial: "tools/two_way_utility/rightpanel_overlay_player", layout: false)
      end

      [html, "player", requested_overlay_id.to_s]
    rescue ActiveRecord::RecordNotFound
      [overlay_clear_html, "none", ""]
    end

    def overlay_clear_html
      '<div id="rightpanel-overlay"></div>'
    end

    def risk_sort_priority(tier)
      case tier.to_s
      when "critical" then 0
      when "warning" then 1
      when "estimate" then 2
      else 3
      end
    end

    def risk_filter_label(risk)
      case risk.to_s
      when "critical" then "≤10 games remaining"
      when "warning" then "≤20 games remaining"
      when "estimate" then "Estimated limits"
      else "All"
      end
    end

    def without_view_annotations
      original = ActionView::Base.annotate_rendered_view_with_filenames
      ActionView::Base.annotate_rendered_view_with_filenames = false
      yield
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = original
    end
  end
end
