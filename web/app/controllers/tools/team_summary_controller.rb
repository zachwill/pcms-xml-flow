module Tools
  class TeamSummaryController < ApplicationController
    include Datastar

    CURRENT_SALARY_YEAR = 2025

    SORT_SQL = {
      "cap_space_desc" => "(COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0)) DESC NULLS LAST, tsw.team_code",
      "cap_space_asc" => "(COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0)) ASC NULLS LAST, tsw.team_code",
      "tax_overage_desc" => "(COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0)) DESC NULLS LAST, tsw.team_code",
      "tax_overage_asc" => "(COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0)) ASC NULLS LAST, tsw.team_code",
      "team_asc" => "tsw.team_code ASC"
    }.freeze

    # GET /tools/team-summary
    def show
      load_workspace_state!
    rescue ActiveRecord::StatementInvalid => e
      @boot_error = e.message
      @available_years = []
      @selected_year = CURRENT_SALARY_YEAR
      @conference = "all"
      @pressure = "all"
      @sort = "cap_space_desc"
      @rows = []
      @rows_by_code = {}
      @compare_a_code = nil
      @compare_b_code = nil
      @compare_a_row = nil
      @compare_b_row = nil
      @selected_team_code = nil
      @selected_row = nil
      @team_finder_query = ""
      @state_params = {
        year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort
      }
    end

    # GET /tools/team-summary/sidebar/:team_code
    def sidebar
      load_workspace_state!
      @selected_team_code = resolve_team_code(params[:team_code])
      hydrate_sidebar_payload!
      @state_params = build_state_params

      if @selected_row.present?
        render partial: "tools/team_summary/rightpanel_overlay_team", layout: false
      else
        render partial: "tools/team_summary/rightpanel_clear", layout: false
      end
    rescue ActiveRecord::StatementInvalid => e
      render html: <<~HTML.html_safe, layout: false
        <div id="rightpanel-overlay" class="h-full p-4">
          <div class="rounded border border-border bg-muted/20 p-3">
            <div class="text-sm font-medium text-destructive">Team Summary sidebar failed</div>
            <pre class="mt-2 text-xs text-muted-foreground overflow-x-auto">#{ERB::Util.h(e.message)}</pre>
          </div>
        </div>
      HTML
    end

    # GET /tools/team-summary/sidebar/clear
    def sidebar_clear
      render partial: "tools/team_summary/rightpanel_clear", layout: false
    end

    # GET /tools/team-summary/sse/compare
    def compare
      load_workspace_state!
      apply_compare_action!
      hydrate_sidebar_payload!
      @state_params = build_state_params

      with_sse_stream do |sse|
        patch_elements_by_id(sse, render_to_string(partial: "tools/team_summary/compare_strip", layout: false))
        patch_elements_by_id(sse, render_to_string(partial: "tools/team_summary/rightpanel_base", layout: false))

        overlay_html = if @selected_row.present?
          render_to_string(partial: "tools/team_summary/rightpanel_overlay_team", layout: false)
        else
          render_to_string(partial: "tools/team_summary/rightpanel_clear", layout: false)
        end

        patch_elements_by_id(sse, overlay_html)
        patch_signals(
          sse,
          selectedteam: @selected_team_code.to_s,
          comparea: @compare_a_code.to_s,
          compareb: @compare_b_code.to_s
        )
      end
    rescue ActiveRecord::StatementInvalid => e
      with_sse_stream do |sse|
        patch_flash(sse, "Team Summary compare update failed: #{e.message.to_s.truncate(160)}")
      end
    end

    # GET /tools/team-summary/sse/step
    # Overlay stepping for adjacent teams in the current filtered row order.
    # Patches:
    # - #rightpanel-overlay
    # - selectedteam/compare signals
    def step
      load_workspace_state!
      step_selected_team!(resolve_step_direction(params[:direction]))
      hydrate_sidebar_payload!
      @state_params = build_state_params

      with_sse_stream do |sse|
        overlay_html = if @selected_row.present?
          render_to_string(partial: "tools/team_summary/rightpanel_overlay_team", layout: false)
        else
          render_to_string(partial: "tools/team_summary/rightpanel_clear", layout: false)
        end

        patch_elements_by_id(sse, overlay_html)
        patch_signals(
          sse,
          selectedteam: @selected_team_code.to_s,
          comparea: @compare_a_code.to_s,
          compareb: @compare_b_code.to_s
        )
      end
    rescue ActiveRecord::StatementInvalid => e
      with_sse_stream do |sse|
        patch_flash(sse, "Team Summary step update failed: #{e.message.to_s.truncate(160)}")
      end
    end

    # GET /tools/team-summary/sse/refresh
    # One-request multi-region refresh for commandbar knob changes.
    # Patches:
    # - #maincanvas
    # - #team-summary-compare-strip
    # - #rightpanel-base
    # - #rightpanel-overlay
    def refresh
      load_workspace_state!
      @state_params = build_state_params

      with_sse_stream do |sse|
        main_html = render_to_string(partial: "tools/team_summary/workspace_main", layout: false)
        compare_html = render_to_string(partial: "tools/team_summary/compare_strip", layout: false)
        sidebar_html = render_to_string(partial: "tools/team_summary/rightpanel_base", layout: false)

        overlay_html = if @selected_row.present?
          render_to_string(partial: "tools/team_summary/rightpanel_overlay_team", layout: false)
        else
          render_to_string(partial: "tools/team_summary/rightpanel_clear", layout: false)
        end

        patch_elements(sse, selector: "#maincanvas", mode: "inner", html: main_html)
        patch_elements_by_id(sse, compare_html)
        patch_elements_by_id(sse, sidebar_html)
        patch_elements_by_id(sse, overlay_html)
        patch_signals(
          sse,
          tsyear: @selected_year.to_s,
          tspressure: @pressure.to_s,
          tssortmetric: sort_metric_for(@sort),
          tssortasc: sort_ascending_for(@sort),
          tsconferenceeast: @conference != "Western",
          tsconferencewest: @conference != "Eastern",
          tsteamfinderquery: @team_finder_query.to_s,
          selectedteam: @selected_team_code.to_s,
          comparea: @compare_a_code.to_s,
          compareb: @compare_b_code.to_s
        )
      end
    rescue ActiveRecord::StatementInvalid => e
      with_sse_stream do |sse|
        patch_flash(sse, "Team Summary refresh failed: #{e.message.to_s.truncate(160)}")
      end
    end

    private

    def conn
      ActiveRecord::Base.connection
    end

    def parse_year_param(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def fetch_available_years
      conn.exec_query(<<~SQL).rows.flatten.map(&:to_i)
        SELECT DISTINCT salary_year
        FROM pcms.team_salary_warehouse
        ORDER BY salary_year
      SQL
    end

    def resolve_selected_year(available_years)
      return CURRENT_SALARY_YEAR if available_years.empty?

      requested = parse_year_param(params[:year])
      return requested if requested && available_years.include?(requested)

      return CURRENT_SALARY_YEAR if available_years.include?(CURRENT_SALARY_YEAR)

      available_years.max
    end

    def checkbox_on?(value)
      %w[1 true on yes].include?(value.to_s.strip.downcase)
    end

    def resolve_conference_from_params
      east_raw = params[:conference_east]
      west_raw = params[:conference_west]

      if !east_raw.nil? || !west_raw.nil?
        east = checkbox_on?(east_raw)
        west = checkbox_on?(west_raw)

        return "Eastern" if east && !west
        return "Western" if west && !east

        return "all"
      end

      resolve_conference(params[:conference])
    end

    def resolve_conference(value)
      normalized = value.to_s.strip
      return normalized if ["all", "Eastern", "Western"].include?(normalized)

      "all"
    end

    def resolve_pressure(value)
      normalized = value.to_s.strip
      normalized = "over_apron1" if normalized == "over_apron"
      return normalized if ["all", "over_tax", "over_apron1", "over_apron2"].include?(normalized)

      "all"
    end

    def resolve_sort_from_params
      metric = params[:sort_metric].to_s.strip

      if metric.present?
        ascending = checkbox_on?(params[:sort_asc])

        derived_sort = case metric
        when "cap_space"
          ascending ? "cap_space_asc" : "cap_space_desc"
        when "tax_overage"
          ascending ? "tax_overage_asc" : "tax_overage_desc"
        when "team"
          "team_asc"
        end

        return resolve_sort(derived_sort) if derived_sort.present?
      end

      resolve_sort(params[:sort])
    end

    def resolve_sort(value)
      normalized = value.to_s.strip
      SORT_SQL.key?(normalized) ? normalized : "cap_space_desc"
    end

    def sort_metric_for(sort)
      sort_value = sort.to_s
      return "tax_overage" if sort_value.start_with?("tax_overage")
      return "team" if sort_value == "team_asc"

      "cap_space"
    end

    def sort_ascending_for(sort)
      sort_value = sort.to_s
      sort_value.end_with?("_asc") && sort_value != "team_asc"
    end

    def resolve_team_code(value)
      code = value.to_s.strip.upcase
      code.match?(/\A[A-Z]{3}\z/) ? code : nil
    end

    def resolve_team_finder_query(value)
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

    def resolve_step_direction(value)
      normalized = value.to_s.strip.downcase
      return normalized if %w[next prev].include?(normalized)

      nil
    end

    def step_selected_team!(direction)
      return if direction.blank?

      ordered_codes = @rows.map { |row| resolve_team_code(row["team_code"]) }.compact
      return if ordered_codes.empty?

      current_code = resolve_team_code(@selected_team_code)
      current_index = current_code.present? ? ordered_codes.index(current_code) : nil

      if current_index.nil?
        @selected_team_code = direction == "prev" ? ordered_codes.last : ordered_codes.first
        return
      end

      target_index = direction == "prev" ? current_index - 1 : current_index + 1
      return if target_index.negative? || target_index >= ordered_codes.length

      @selected_team_code = ordered_codes[target_index]
    end

    def normalize_compare_slots!
      if @compare_a_code.present? && @compare_a_code == @compare_b_code
        @compare_b_code = nil
      end
    end

    def load_workspace_state!
      @available_years = fetch_available_years
      @selected_year = resolve_selected_year(@available_years)
      @conference = resolve_conference_from_params
      @pressure = resolve_pressure(params[:pressure])
      @sort = resolve_sort_from_params
      @team_finder_query = resolve_team_finder_query(params[:team_finder_query])

      @rows = fetch_team_summary_rows(
        year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort
      )
      @rows_by_code = @rows.index_by { |row| row["team_code"] }

      @compare_a_code = resolve_team_code(params[:compare_a])
      @compare_b_code = resolve_team_code(params[:compare_b])
      normalize_compare_slots!

      @selected_team_code = resolve_team_code(params[:selected])

      hydrate_sidebar_payload!
      @state_params = build_state_params
    end

    def hydrate_sidebar_payload!
      lookup_codes = [@selected_team_code, @compare_a_code, @compare_b_code].compact.uniq
      lookup_rows_by_code = fetch_rows_by_team_codes(year: @selected_year, team_codes: lookup_codes)

      @compare_a_row = @compare_a_code.present? ? lookup_rows_by_code[@compare_a_code] : nil
      @compare_b_row = @compare_b_code.present? ? lookup_rows_by_code[@compare_b_code] : nil

      @compare_a_code = nil if @compare_a_code.present? && @compare_a_row.blank?
      @compare_b_code = nil if @compare_b_code.present? && @compare_b_row.blank?
      normalize_compare_slots!

      @selected_row = if @selected_team_code.present?
        @rows_by_code[@selected_team_code] || lookup_rows_by_code[@selected_team_code]
      end
      @selected_team_code = nil unless @selected_row.present?
    end

    def build_state_params
      {
        year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort,
        team_finder_query: @team_finder_query.presence,
        selected: @selected_team_code.presence,
        compare_a: @compare_a_code.presence,
        compare_b: @compare_b_code.presence
      }.compact
    end

    def apply_compare_action!
      compare_action_param = params[:compare_action].presence || request.query_parameters["action"]
      compare_slot_param = params[:compare_slot].presence || request.query_parameters["slot"]

      action = resolve_compare_action(compare_action_param)
      slot = resolve_compare_slot(compare_slot_param)
      team_code = resolve_team_code(params[:team_code])

      case action
      when "pin"
        return if slot.blank? || team_code.blank?

        if slot == "a"
          @compare_a_code = team_code
          @compare_b_code = nil if @compare_b_code == team_code
        else
          @compare_b_code = team_code
          @compare_a_code = nil if @compare_a_code == team_code
        end

      when "clear_slot"
        return if slot.blank?

        if slot == "a"
          @compare_a_code = nil
        else
          @compare_b_code = nil
        end
      when "clear_all"
        @compare_a_code = nil
        @compare_b_code = nil
      end

      normalize_compare_slots!
    end

    def fetch_rows_by_team_codes(year:, team_codes:)
      codes = Array(team_codes).filter_map { |code| resolve_team_code(code) }.uniq
      return {} if codes.empty?

      rows = fetch_team_summary_rows(
        year: year,
        conference: "all",
        pressure: "all",
        sort: "team_asc",
        team_codes: codes,
        apply_filters: false
      )

      rows_by_code = rows.index_by { |row| row["team_code"] }
      codes.each_with_object({}) do |code, acc|
        acc[code] = rows_by_code[code] if rows_by_code.key?(code)
      end
    end

    def fetch_team_summary_rows(year:, conference:, pressure:, sort:, team_codes: nil, apply_filters: true)
      where_clauses = [
        "tsw.salary_year = #{conn.quote(year)}",
        "t.league_lk = 'NBA'",
        "t.team_name NOT LIKE 'Non-NBA%'"
      ]

      if apply_filters && conference != "all"
        where_clauses << "t.conference_name = #{conn.quote(conference)}"
      end

      if apply_filters
        case pressure
        when "over_tax"
          where_clauses << "COALESCE(tsw.room_under_tax, 0) < 0"
        when "over_apron1"
          where_clauses << "COALESCE(tsw.room_under_apron1, 0) < 0"
        when "over_apron2"
          where_clauses << "COALESCE(tsw.room_under_apron2, 0) < 0"
        end
      end

      codes = Array(team_codes).filter_map { |code| resolve_team_code(code) }.uniq
      if codes.any?
        quoted_codes = codes.map { |code| conn.quote(code) }.join(", ")
        where_clauses << "tsw.team_code IN (#{quoted_codes})"
      end

      order_sql = if codes.any?
        "tsw.team_code ASC"
      else
        SORT_SQL.fetch(sort)
      end

      conn.exec_query(<<~SQL).to_a
        SELECT
          tsw.team_code,
          t.team_name,
          t.team_id,
          t.conference_name,
          tsw.salary_year,
          tsw.cap_total,
          tsw.cap_total_hold,
          tsw.tax_total,
          tsw.apron_total,
          tsw.salary_cap_amount,
          tsw.tax_level_amount,
          tsw.tax_apron_amount,
          tsw.tax_apron2_amount,
          (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0))::bigint AS cap_space,
          (COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0))::bigint AS tax_overage,
          tsw.room_under_tax,
          tsw.room_under_apron1,
          tsw.room_under_apron2,
          tsw.is_taxpayer,
          tsw.is_repeater_taxpayer,
          tsw.is_subject_to_apron,
          tsw.apron_level_lk,
          tsw.roster_row_count,
          tsw.two_way_row_count,
          tax_calc.luxury_tax_owed,
          tsw.refreshed_at
        FROM pcms.team_salary_warehouse tsw
        JOIN pcms.teams t
          ON t.team_code = tsw.team_code
        LEFT JOIN LATERAL pcms.fn_team_luxury_tax(tsw.team_code, tsw.salary_year) tax_calc
          ON true
        WHERE #{where_clauses.join(" AND ")}
        ORDER BY #{order_sql}
      SQL
    end
  end
end
