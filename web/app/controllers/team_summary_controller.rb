class TeamSummaryController < ApplicationController
  include Datastar

  helper_method :team_summary_state_query_expr

  CURRENT_SALARY_YEAR = 2025
  SALARY_YEAR_HORIZON = 7
  AVAILABLE_SALARY_YEARS = (CURRENT_SALARY_YEAR...(CURRENT_SALARY_YEAR + SALARY_YEAR_HORIZON)).to_a.freeze

  SORT_SQL = {
    "pressure_desc" => "pressure_rank DESC, COALESCE(tsw.room_under_apron2, 0) ASC NULLS LAST, COALESCE(tsw.room_under_apron1, 0) ASC NULLS LAST, COALESCE(tsw.room_under_tax, 0) ASC NULLS LAST, tsw.team_code ASC",
    "cap_space_desc" => "(COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0)) DESC NULLS LAST, tsw.team_code",
    "cap_space_asc" => "(COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0)) ASC NULLS LAST, tsw.team_code",
    "tax_overage_desc" => "(COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0)) DESC NULLS LAST, tsw.team_code",
    "tax_overage_asc" => "(COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0)) ASC NULLS LAST, tsw.team_code",
    "team_asc" => "tsw.team_code ASC"
  }.freeze

  # GET /team-summary
  def show
    load_workspace_state!
  rescue ActiveRecord::StatementInvalid => e
    assign_state!(workspace_state.fallback(error: e))
  end

  # GET /team-summary/sidebar/:team_code
  def sidebar
    load_workspace_state!(selected_override_team_code: params[:team_code])
    render partial: overlay_partial_name, layout: false
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

  # GET /team-summary/sidebar/clear
  def sidebar_clear
    render partial: "team_summary/rightpanel_clear", layout: false
  end

  # GET /team-summary/sse/step
  # Overlay stepping for adjacent teams in the current filtered row order.
  # Patches:
  # - #rightpanel-overlay
  # - selectedteam signal
  def step
    load_workspace_state!(step_direction: resolve_step_direction(params[:direction]))

    with_sse_stream do |sse|
      patch_elements_by_id(sse, render_to_string(partial: overlay_partial_name, layout: false))
      patch_signals(
        sse,
        tsyear: @selected_year.to_s,
        tspressure: @pressure.to_s,
        tssortmetric: sort_metric_for(@sort),
        tssortasc: sort_ascending_for(@sort),
        tsconferenceeast: @conference != "Western",
        tsconferencewest: @conference != "Eastern",
        selectedteam: @selected_team_code.to_s
      )
    end
  rescue ActiveRecord::StatementInvalid => e
    with_sse_stream do |sse|
      patch_flash(sse, "Team Summary step update failed: #{e.message.to_s.truncate(160)}")
    end
  end

  # GET /team-summary/sse/refresh
  # One-request multi-region refresh for commandbar knob changes.
  # Patches:
  # - #maincanvas
  # - #rightpanel-base
  # - #rightpanel-overlay
  def refresh
    load_workspace_state!

    with_sse_stream do |sse|
      main_html = render_to_string(partial: "team_summary/workspace_main", layout: false)
      sidebar_html = render_to_string(partial: "team_summary/rightpanel_base", layout: false)
      overlay_html = render_to_string(partial: overlay_partial_name, layout: false)

      patch_elements(sse, selector: "#maincanvas", mode: "inner", html: main_html)
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
        selectedteam: @selected_team_code.to_s
      )
    end
  rescue ActiveRecord::StatementInvalid => e
    with_sse_stream do |sse|
      patch_flash(sse, "Team Summary refresh failed: #{e.message.to_s.truncate(160)}")
    end
  end

  def team_summary_state_query_expr(selected_expression: "$selectedteam || ''")
    <<~JS.squish
      'year=' + encodeURIComponent($tsyear) +
      '&conference=' + encodeURIComponent(($tsconferenceeast && $tsconferencewest) ? 'all' : ($tsconferenceeast ? 'Eastern' : ($tsconferencewest ? 'Western' : 'all'))) +
      '&pressure=' + encodeURIComponent($tspressure) +
      '&sort=' + encodeURIComponent(($tssortmetric === 'pressure' ? 'pressure_desc' : ($tssortmetric === 'team' ? 'team_asc' : ($tssortmetric === 'tax_overage' ? ($tssortasc ? 'tax_overage_asc' : 'tax_overage_desc') : ($tssortasc ? 'cap_space_asc' : 'cap_space_desc'))))) +
      '&selected=' + encodeURIComponent(#{selected_expression})
    JS
  end

  private

  def assign_state!(state)
    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def queries
    @queries ||= ::TeamSummaryQueries.new(connection: ActiveRecord::Base.connection)
  end

  def workspace_state
    @workspace_state ||= ::TeamSummary::WorkspaceState.new(
      params: params,
      request_query_parameters: request.query_parameters,
      queries: queries,
      current_salary_year: CURRENT_SALARY_YEAR,
      available_salary_years: AVAILABLE_SALARY_YEARS,
      sort_sql: SORT_SQL
    )
  end

  def overlay_partial_name
    @selected_row.present? ? "team_summary/rightpanel_overlay_team" : "team_summary/rightpanel_clear"
  end

  def resolve_step_direction(value)
    normalized = value.to_s.strip.downcase
    return normalized if %w[next prev].include?(normalized)

    nil
  end

  def load_workspace_state!(step_direction: nil, selected_override_team_code: nil)
    assign_state!(
      workspace_state.build(
        step_direction: step_direction,
        selected_override_team_code: selected_override_team_code
      )
    )
  end

  def sort_metric_for(sort)
    sort_value = sort.to_s
    return "pressure" if sort_value == "pressure_desc"
    return "tax_overage" if sort_value.start_with?("tax_overage")
    return "team" if sort_value == "team_asc"

    "cap_space"
  end

  def sort_ascending_for(sort)
    sort_value = sort.to_s
    return false if sort_value == "team_asc" || sort_value == "pressure_desc"

    sort_value.end_with?("_asc")
  end
end
