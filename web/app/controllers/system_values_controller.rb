class SystemValuesController < ApplicationController
  include Datastar

  CURRENT_SALARY_YEAR = 2025
  DEFAULT_WINDOW_YEARS = 2
  DEFAULT_BASELINE_OFFSET_YEARS = 1

  SECTION_VISIBILITY_PARAM_DEFINITIONS = {
    showsystemvalues: "show_system_values",
    showtaxrates: "show_tax_rates",
    showsalaryscales: "show_salary_scales",
    showrookiescales: "show_rookie_scales"
  }.freeze

  # GET /system-values
  def show
    load_workspace_state!
    load_workspace_derived_state!
  rescue ActiveRecord::StatementInvalid => e
    assign_state!(workspace_state.fallback(error: e))
    load_workspace_derived_state!
  end

  # GET /system-values/sidebar/metric
  def sidebar_metric
    load_workspace_state!
    load_workspace_derived_state!

    render partial: overlay_partial_name, layout: false
  rescue ActiveRecord::StatementInvalid => e
    render html: <<~HTML.html_safe, layout: false
      <div id="rightpanel-overlay" class="h-full p-4">
        <div class="rounded border border-border bg-muted/20 p-3">
          <div class="text-sm font-medium text-destructive">System Values sidebar failed</div>
          <pre class="mt-2 text-xs text-muted-foreground overflow-x-auto">#{ERB::Util.h(e.message)}</pre>
        </div>
      </div>
    HTML
  end

  # GET /system-values/sidebar/clear
  def sidebar_clear
    render partial: "system_values/rightpanel_clear", layout: false
  end

  # GET /system-values/sse/refresh
  # One-request multi-region refresh for commandbar apply and baseline/range transitions.
  # Patches:
  # - #commandbar
  # - #maincanvas
  # - #rightpanel-base
  # - #rightpanel-overlay
  def refresh
    load_workspace_state!
    load_workspace_derived_state!

    with_sse_stream do |sse|
      commandbar_html = render_to_string(
        partial: "system_values/commandbar",
        layout: false,
        locals: {
          state_query_expr:,
          overlay_query_expr:
        }
      )
      main_html = render_to_string(
        partial: "system_values/workspace_main",
        layout: false,
        locals: {
          overlay_query_expr:
        }
      )
      rightpanel_base_html = render_to_string(
        partial: "system_values/rightpanel_base",
        layout: false,
        locals: {
          overlay_query_expr:
        }
      )
      rightpanel_overlay_html = render_to_string(partial: overlay_partial_name, layout: false)

      patch_elements(sse, selector: "#commandbar", mode: "inner", html: commandbar_html)
      patch_elements(sse, selector: "#maincanvas", mode: "inner", html: main_html)
      patch_elements_by_id(sse, rightpanel_base_html)
      patch_elements_by_id(sse, rightpanel_overlay_html)
      patch_signals(
        sse,
        showsystemvalues: @show_system_values,
        showtaxrates: @show_tax_rates,
        showsalaryscales: @show_salary_scales,
        showrookiescales: @show_rookie_scales,
        svyear: @selected_year.to_s,
        svbaseline: @baseline_year.to_s,
        svfrom: @from_year.to_s,
        svto: @to_year.to_s,
        svmetricfinder: @active_metric_finder_value.to_s,
        svmetricfinderquery: @metric_finder_query.to_s,
        svmetricfindercursor: @metric_finder_cursor_value.to_s,
        svmetricfindercursorindex: @metric_finder_cursor_index.to_i,
        svoverlaysection: @overlay_signals.fetch(:section),
        svoverlaymetric: @overlay_signals.fetch(:metric),
        svoverlayyear: @overlay_signals.fetch(:year),
        svoverlaylower: @overlay_signals.fetch(:lower),
        svoverlayupper: @overlay_signals.fetch(:upper)
      )
    end
  rescue ActiveRecord::StatementInvalid => e
    with_sse_stream do |sse|
      patch_flash(sse, "System Values refresh failed: #{e.message.to_s.truncate(160)}")
    end
  end

  private

  def assign_state!(state)
    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def state_query_expr
    "'year=' + encodeURIComponent($svyear) + " \
      "'&baseline_year=' + encodeURIComponent($svbaseline) + " \
      "'&from_year=' + encodeURIComponent($svfrom) + " \
      "'&to_year=' + encodeURIComponent($svto) + " \
      "'&show_system_values=' + encodeURIComponent($showsystemvalues ? '1' : '0') + " \
      "'&show_tax_rates=' + encodeURIComponent($showtaxrates ? '1' : '0') + " \
      "'&show_salary_scales=' + encodeURIComponent($showsalaryscales ? '1' : '0') + " \
      "'&show_rookie_scales=' + encodeURIComponent($showrookiescales ? '1' : '0') + " \
      "'&metric_finder_query=' + encodeURIComponent($svmetricfinderquery || '') + " \
      "'&metric_finder_cursor=' + encodeURIComponent($svmetricfindercursor || '')"
  end

  def overlay_query_expr
    "(#{state_query_expr}) + " \
      "'&overlay_section=' + encodeURIComponent($svoverlaysection || '') + " \
      "'&overlay_metric=' + encodeURIComponent($svoverlaymetric || '') + " \
      "'&overlay_year=' + encodeURIComponent($svoverlayyear || '') + " \
      "'&overlay_lower=' + encodeURIComponent($svoverlaylower || '') + " \
      "'&overlay_upper=' + encodeURIComponent($svoverlayupper || '')"
  end

  def overlay_partial_name
    @overlay_payload.present? ? "system_values/rightpanel_overlay_metric" : "system_values/rightpanel_clear"
  end

  def queries
    @queries ||= ::SystemValuesQueries.new(connection: ActiveRecord::Base.connection)
  end

  def workspace_state
    @workspace_state ||= ::SystemValues::WorkspaceState.new(
      queries: queries,
      params: params,
      current_salary_year: CURRENT_SALARY_YEAR,
      default_window_years: DEFAULT_WINDOW_YEARS,
      default_baseline_offset_years: DEFAULT_BASELINE_OFFSET_YEARS,
      section_visibility_param_definitions: SECTION_VISIBILITY_PARAM_DEFINITIONS
    )
  end

  def load_workspace_state!
    assign_state!(workspace_state.build)
  end

  def load_workspace_derived_state!
    assign_state!(
      ::SystemValues::WorkspaceDerivedState.new(
        helpers: helpers,
        routes: self,
        selected_year: @selected_year,
        baseline_year: @baseline_year,
        state_params: @state_params,
        league_system_values: @league_system_values,
        league_tax_rates: @league_tax_rates,
        league_salary_scales: @league_salary_scales,
        rookie_scale_amounts: @rookie_scale_amounts,
        selected_system_values_row: @selected_system_values_row,
        baseline_system_values_row: @baseline_system_values_row,
        selected_tax_rate_rows: @selected_tax_rate_rows,
        baseline_tax_rate_rows: @baseline_tax_rate_rows,
        selected_salary_scale_rows: @selected_salary_scale_rows,
        baseline_salary_scale_rows: @baseline_salary_scale_rows,
        selected_rookie_scale_rows: @selected_rookie_scale_rows,
        baseline_rookie_scale_rows: @baseline_rookie_scale_rows,
        metric_finder_query_param: params[:metric_finder_query],
        metric_finder_cursor_param: params[:metric_finder_cursor],
        overlay_params: {
          overlay_section: params[:overlay_section],
          overlay_metric: params[:overlay_metric],
          overlay_year: params[:overlay_year],
          overlay_lower: params[:overlay_lower],
          overlay_upper: params[:overlay_upper]
        }
      ).build
    )
  end
end
