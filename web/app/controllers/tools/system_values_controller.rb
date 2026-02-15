module Tools
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

    SYSTEM_METRIC_DEFINITIONS = {
      "salary_cap_amount" => { label: "Salary Cap", kind: :currency },
      "tax_level_amount" => { label: "Tax Level", kind: :currency },
      "tax_apron_amount" => { label: "Apron 1", kind: :currency },
      "tax_apron2_amount" => { label: "Apron 2", kind: :currency },
      "maximum_salary_25_pct" => { label: "Max Salary 25%", kind: :currency },
      "maximum_salary_30_pct" => { label: "Max Salary 30%", kind: :currency },
      "maximum_salary_35_pct" => { label: "Max Salary 35%", kind: :currency },
      "non_taxpayer_mid_level_amount" => { label: "Non-Taxpayer MLE", kind: :currency },
      "taxpayer_mid_level_amount" => { label: "Taxpayer MLE", kind: :currency },
      "room_mid_level_amount" => { label: "Room MLE", kind: :currency },
      "bi_annual_amount" => { label: "Bi-Annual Exception", kind: :currency },
      "tpe_dollar_allowance" => { label: "Trade Exception Allowance", kind: :currency },
      "max_trade_cash_amount" => { label: "Max Trade Cash", kind: :currency }
    }.freeze

    TAX_METRIC_DEFINITIONS = {
      "tax_rate_non_repeater" => { label: "Tax Rate (Non-Repeater)", kind: :rate },
      "tax_rate_repeater" => { label: "Tax Rate (Repeater)", kind: :rate },
      "base_charge_non_repeater" => { label: "Base Charge (Non-Repeater)", kind: :currency },
      "base_charge_repeater" => { label: "Base Charge (Repeater)", kind: :currency }
    }.freeze

    MINIMUM_METRIC_DEFINITIONS = {
      "minimum_salary_amount" => { label: "Minimum Salary", kind: :currency }
    }.freeze

    ROOKIE_METRIC_DEFINITIONS = {
      "salary_year_1" => { label: "Year 1 Salary", kind: :currency },
      "salary_year_2" => { label: "Year 2 Salary", kind: :currency },
      "option_amount_year_3" => { label: "Option Year 3 Amount", kind: :currency },
      "option_amount_year_4" => { label: "Option Year 4 Amount", kind: :currency },
      "option_pct_year_3" => { label: "Option Year 3 %", kind: :percentage },
      "option_pct_year_4" => { label: "Option Year 4 %", kind: :percentage }
    }.freeze

    METRIC_FINDER_SECTION_LABELS = {
      "system" => "System",
      "tax" => "Tax",
      "minimum" => "Minimum",
      "rookie" => "Rookie"
    }.freeze
    METRIC_FINDER_SECTION_RANK = {
      "system" => 0,
      "tax" => 1,
      "minimum" => 2,
      "rookie" => 3
    }.freeze
    METRIC_SHORTLIST_LIMIT = 6

    # GET /tools/system-values
    def show
      load_workspace_state!
      resolve_overlay_payload!
    rescue ActiveRecord::StatementInvalid => e
      apply_boot_error!(e)
    end

    # GET /tools/system-values/sidebar/metric
    def sidebar_metric
      load_workspace_state!
      resolve_overlay_payload!

      if @overlay_payload.present?
        render partial: "tools/system_values/rightpanel_overlay_metric", layout: false
      else
        render partial: "tools/system_values/rightpanel_clear", layout: false
      end
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

    # GET /tools/system-values/sidebar/clear
    def sidebar_clear
      render partial: "tools/system_values/rightpanel_clear", layout: false
    end

    # GET /tools/system-values/sse/refresh
    # One-request multi-region refresh for commandbar apply and baseline/range transitions.
    # Patches:
    # - #commandbar
    # - #maincanvas
    # - #rightpanel-base
    # - #rightpanel-overlay
    def refresh
      load_workspace_state!
      resolve_overlay_payload!

      with_sse_stream do |sse|
        commandbar_html = render_to_string(
          partial: "tools/system_values/commandbar",
          layout: false,
          locals: {
            state_query_expr:,
            overlay_query_expr:
          }
        )
        main_html = render_to_string(
          partial: "tools/system_values/workspace_main",
          layout: false,
          locals: {
            overlay_query_expr:
          }
        )
        rightpanel_base_html = render_to_string(
          partial: "tools/system_values/rightpanel_base",
          layout: false,
          locals: {
            overlay_query_expr:
          }
        )
        rightpanel_overlay_html = if @overlay_payload.present?
          render_to_string(partial: "tools/system_values/rightpanel_overlay_metric", layout: false)
        else
          render_to_string(partial: "tools/system_values/rightpanel_clear", layout: false)
        end

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

    def parse_year_param(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_decimal_param(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      Float(raw)
    rescue ArgumentError, TypeError
      nil
    end

    def resolve_selected_year(available_years)
      return CURRENT_SALARY_YEAR if available_years.empty?

      requested = parse_year_param(params[:year])
      return requested if requested && available_years.include?(requested)

      return CURRENT_SALARY_YEAR if available_years.include?(CURRENT_SALARY_YEAR)

      available_years.max
    end

    def resolve_baseline_year(available_years, selected_year)
      return selected_year if available_years.empty?

      requested = parse_year_param(params[:baseline_year])
      return requested if requested && available_years.include?(requested)

      preferred = selected_year - DEFAULT_BASELINE_OFFSET_YEARS
      return preferred if available_years.include?(preferred)

      return selected_year if available_years.include?(selected_year)

      available_years.min
    end

    def resolve_year_range(available_years, selected_year)
      return [ selected_year, selected_year ] if available_years.empty?

      min_year = available_years.min
      max_year = available_years.max

      default_from = [ selected_year - DEFAULT_WINDOW_YEARS, min_year ].max
      default_to = [ selected_year + DEFAULT_WINDOW_YEARS, max_year ].min

      from_year = parse_year_param(params[:from_year]) || default_from
      to_year = parse_year_param(params[:to_year]) || default_to

      from_year = from_year.clamp(min_year, max_year)
      to_year = to_year.clamp(min_year, max_year)

      if from_year > to_year
        from_year, to_year = to_year, from_year
      end

      [ from_year, to_year ]
    end

    def resolve_section_visibility!
      @show_system_values = parse_visibility_param(params[SECTION_VISIBILITY_PARAM_DEFINITIONS.fetch(:showsystemvalues)])
      @show_tax_rates = parse_visibility_param(params[SECTION_VISIBILITY_PARAM_DEFINITIONS.fetch(:showtaxrates)])
      @show_salary_scales = parse_visibility_param(params[SECTION_VISIBILITY_PARAM_DEFINITIONS.fetch(:showsalaryscales)])
      @show_rookie_scales = parse_visibility_param(params[SECTION_VISIBILITY_PARAM_DEFINITIONS.fetch(:showrookiescales)])
    end

    def parse_visibility_param(value)
      normalized = value.to_s.strip.downcase
      return true if normalized.blank?
      return true if %w[1 true yes on].include?(normalized)
      return false if %w[0 false no off].include?(normalized)

      true
    end

    def visibility_state_params
      {
        show_system_values: @show_system_values ? "1" : "0",
        show_tax_rates: @show_tax_rates ? "1" : "0",
        show_salary_scales: @show_salary_scales ? "1" : "0",
        show_rookie_scales: @show_rookie_scales ? "1" : "0"
      }
    end

    def load_workspace_state!
      @available_years = SystemValuesQueries.fetch_available_years
      @selected_year = resolve_selected_year(@available_years)
      @baseline_year = resolve_baseline_year(@available_years, @selected_year)
      @from_year, @to_year = resolve_year_range(@available_years, @selected_year)

      @league_system_values = SystemValuesQueries.fetch_league_system_values(@from_year, @to_year)
      @league_tax_rates = SystemValuesQueries.fetch_league_tax_rates(@from_year, @to_year)
      @league_salary_scales = SystemValuesQueries.fetch_league_salary_scales(@from_year, @to_year)
      @rookie_scale_amounts = SystemValuesQueries.fetch_rookie_scale_amounts(@from_year, @to_year)

      @selected_system_values_row = @league_system_values.find { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_system_values_row = @league_system_values.find { |row| row["salary_year"].to_i == @baseline_year.to_i }

      @selected_tax_rate_rows = @league_tax_rates.select { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_tax_rate_rows = @league_tax_rates.select { |row| row["salary_year"].to_i == @baseline_year.to_i }

      @selected_salary_scale_rows = @league_salary_scales.select { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_salary_scale_rows = @league_salary_scales.select { |row| row["salary_year"].to_i == @baseline_year.to_i }

      @selected_rookie_scale_rows = @rookie_scale_amounts.select { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_rookie_scale_rows = @rookie_scale_amounts.select { |row| row["salary_year"].to_i == @baseline_year.to_i }

      # Fallback queries only when selected/baseline years were intentionally excluded by range.
      @selected_system_values_row ||= SystemValuesQueries.fetch_league_system_values(@selected_year, @selected_year).first
      @baseline_system_values_row ||= SystemValuesQueries.fetch_league_system_values(@baseline_year, @baseline_year).first
      @selected_tax_rate_rows = SystemValuesQueries.fetch_league_tax_rates(@selected_year, @selected_year) if @selected_tax_rate_rows.empty?
      @baseline_tax_rate_rows = SystemValuesQueries.fetch_league_tax_rates(@baseline_year, @baseline_year) if @baseline_tax_rate_rows.empty?
      @selected_salary_scale_rows = SystemValuesQueries.fetch_league_salary_scales(@selected_year, @selected_year) if @selected_salary_scale_rows.empty?
      @baseline_salary_scale_rows = SystemValuesQueries.fetch_league_salary_scales(@baseline_year, @baseline_year) if @baseline_salary_scale_rows.empty?
      @selected_rookie_scale_rows = SystemValuesQueries.fetch_rookie_scale_amounts(@selected_year, @selected_year) if @selected_rookie_scale_rows.empty?
      @baseline_rookie_scale_rows = SystemValuesQueries.fetch_rookie_scale_amounts(@baseline_year, @baseline_year) if @baseline_rookie_scale_rows.empty?

      resolve_section_visibility!

      @metric_finder_query = resolve_metric_finder_query(params[:metric_finder_query])
      @requested_metric_finder_cursor = resolve_metric_finder_cursor(params[:metric_finder_cursor])

      @section_shift_cards = build_section_shift_cards
      @comparison_label = "Comparing #{helpers.format_year_label(@selected_year)} against #{helpers.format_year_label(@baseline_year)} baseline"
      @quick_metric_cards = build_quick_metric_cards
      @metric_finder_options = build_metric_finder_options
      @active_metric_finder_value = ""
      @active_metric_finder_option = nil
      @metric_finder_shortlist = []
      @metric_finder_cursor_value = ""
      @metric_finder_cursor_index = 0
      @state_params = {
        year: @selected_year,
        baseline_year: @baseline_year,
        from_year: @from_year,
        to_year: @to_year
      }.merge(visibility_state_params)
    end

    def apply_boot_error!(error)
      @boot_error = error.message
      @available_years = []
      @selected_year = CURRENT_SALARY_YEAR
      @baseline_year = CURRENT_SALARY_YEAR
      @from_year = CURRENT_SALARY_YEAR
      @to_year = CURRENT_SALARY_YEAR
      @league_system_values = []
      @league_tax_rates = []
      @league_salary_scales = []
      @rookie_scale_amounts = []
      @selected_system_values_row = nil
      @baseline_system_values_row = nil
      @selected_tax_rate_rows = []
      @baseline_tax_rate_rows = []
      @selected_salary_scale_rows = []
      @baseline_salary_scale_rows = []
      @selected_rookie_scale_rows = []
      @baseline_rookie_scale_rows = []
      resolve_section_visibility!

      @section_shift_cards = []
      @quick_metric_cards = []
      @metric_finder_options = []
      @active_metric_finder_value = ""
      @active_metric_finder_option = nil
      @metric_finder_query = ""
      @requested_metric_finder_cursor = ""
      @metric_finder_shortlist = []
      @metric_finder_cursor_value = ""
      @metric_finder_cursor_index = 0
      @comparison_label = "Comparing #{helpers.format_year_label(@selected_year)} against #{helpers.format_year_label(@baseline_year)} baseline"
      @overlay_payload = nil
      @overlay_signals = empty_overlay_signals
      @state_params = {
        year: @selected_year,
        baseline_year: @baseline_year,
        from_year: @from_year,
        to_year: @to_year
      }.merge(visibility_state_params)
    end

    def resolve_overlay_payload!
      section = resolve_overlay_section(params[:overlay_section])
      metric = resolve_overlay_metric(section, params[:overlay_metric])
      year = parse_year_param(params[:overlay_year]) || @selected_year

      context = case section
      when "system"
        build_system_overlay_context(metric:, year:)
      when "tax"
        lower = parse_decimal_param(params[:overlay_lower])
        upper = parse_decimal_param(params[:overlay_upper])
        upper = nil if params[:overlay_upper].to_s.strip.blank?
        build_tax_overlay_context(metric:, year:, lower:, upper:)
      when "minimum"
        yos = parse_year_param(params[:overlay_lower])
        build_minimum_overlay_context(metric:, year:, yos:)
      when "rookie"
        pick = parse_year_param(params[:overlay_lower])
        build_rookie_overlay_context(metric:, year:, pick:)
      end

      @overlay_payload = context.present? ? build_overlay_payload(context) : nil
      @overlay_signals = if @overlay_payload.present?
        {
          section: @overlay_payload.fetch(:section),
          metric: @overlay_payload.fetch(:metric),
          year: @overlay_payload.fetch(:focus_year).to_s,
          lower: @overlay_payload.fetch(:overlay_lower),
          upper: @overlay_payload.fetch(:overlay_upper)
        }
      else
        empty_overlay_signals
      end

      @active_metric_finder_value = metric_finder_value_for_overlay(@overlay_signals)
      @active_metric_finder_option = @metric_finder_options.find { |option| option[:value] == @active_metric_finder_value }
      resolve_metric_finder_shortlist!
    end

    def resolve_overlay_section(value)
      normalized = value.to_s.strip
      return normalized if %w[system tax minimum rookie].include?(normalized)

      nil
    end

    def resolve_overlay_metric(section, value)
      metric = value.to_s.strip
      return nil if metric.blank?

      definitions = overlay_metric_definitions(section)
      definitions.key?(metric) ? metric : nil
    end

    def overlay_metric_definitions(section)
      case section
      when "tax"
        TAX_METRIC_DEFINITIONS
      when "minimum"
        MINIMUM_METRIC_DEFINITIONS
      when "rookie"
        ROOKIE_METRIC_DEFINITIONS
      else
        SYSTEM_METRIC_DEFINITIONS
      end
    end

    def build_system_overlay_context(metric:, year:)
      return nil if metric.blank? || year.blank?

      focus_row = @league_system_values.find { |row| row["salary_year"].to_i == year.to_i }
      return nil unless focus_row

      {
        section: "system",
        metric:,
        metric_definition: SYSTEM_METRIC_DEFINITIONS.fetch(metric),
        focus_year: year.to_i,
        focus_row:
      }
    end

    def build_tax_overlay_context(metric:, year:, lower:, upper:)
      return nil if metric.blank? || year.blank? || lower.nil?

      focus_row = @league_tax_rates.find do |row|
        row["salary_year"].to_i == year.to_i && tax_bracket_match?(row, lower:, upper:)
      end
      return nil unless focus_row

      {
        section: "tax",
        metric:,
        metric_definition: TAX_METRIC_DEFINITIONS.fetch(metric),
        focus_year: year.to_i,
        focus_row:
      }
    end

    def build_minimum_overlay_context(metric:, year:, yos:)
      return nil if metric.blank? || year.blank? || yos.nil?

      focus_row = @league_salary_scales.find do |row|
        row["salary_year"].to_i == year.to_i && row["years_of_service"].to_i == yos.to_i
      end
      return nil unless focus_row

      {
        section: "minimum",
        metric:,
        metric_definition: MINIMUM_METRIC_DEFINITIONS.fetch(metric),
        focus_year: year.to_i,
        focus_row:,
        yos: yos.to_i
      }
    end

    def build_rookie_overlay_context(metric:, year:, pick:)
      return nil if metric.blank? || year.blank? || pick.nil?

      focus_row = @rookie_scale_amounts.find do |row|
        row["salary_year"].to_i == year.to_i && row["pick_number"].to_i == pick.to_i
      end
      return nil unless focus_row

      {
        section: "rookie",
        metric:,
        metric_definition: ROOKIE_METRIC_DEFINITIONS.fetch(metric),
        focus_year: year.to_i,
        focus_row:,
        pick: pick.to_i
      }
    end

    def build_overlay_payload(context)
      section = context.fetch(:section)
      metric = context.fetch(:metric)
      metric_definition = context.fetch(:metric_definition)
      focus_row = context.fetch(:focus_row)
      focus_year = context.fetch(:focus_year)
      kind = metric_definition.fetch(:kind)

      rookie_detail_rows = nil

      selected_value, baseline_value, focus_baseline_value, context_label, overlay_lower, overlay_upper =
        case section
        when "tax"
          lower = focus_row["lower_limit"]&.to_f
          upper = focus_row["upper_limit"]&.to_f

          selected_row = tax_row_for_bracket(@selected_tax_rate_rows, lower:, upper:)
          baseline_row = tax_row_for_bracket(@baseline_tax_rate_rows, lower:, upper:)

          lower_raw = focus_row["lower_limit"]
          upper_raw = focus_row["upper_limit"]
          lower_label = helpers.format_compact_currency(lower_raw)
          upper_label = upper_raw.present? ? helpers.format_compact_currency(upper_raw) : "∞"

          [
            selected_row&.[](metric),
            baseline_row&.[](metric),
            baseline_row&.[](metric),
            "Bracket #{lower_label} – #{upper_label}",
            lower_raw.present? ? format("%.0f", lower_raw.to_f) : "",
            upper_raw.present? ? format("%.0f", upper_raw.to_f) : ""
          ]
        when "minimum"
          yos = context.fetch(:yos)
          selected_row = minimum_row_for_yos(@selected_salary_scale_rows, yos:)
          baseline_row = minimum_row_for_yos(@baseline_salary_scale_rows, yos:)

          [
            selected_row&.[](metric),
            baseline_row&.[](metric),
            baseline_row&.[](metric),
            "YOS #{yos}",
            yos.to_s,
            ""
          ]
        when "rookie"
          pick = context.fetch(:pick)
          selected_row = rookie_row_for_pick(@selected_rookie_scale_rows, pick:)
          baseline_row = rookie_row_for_pick(@baseline_rookie_scale_rows, pick:)

          rookie_detail_rows = build_rookie_overlay_detail_rows(selected_row:, baseline_row:)

          [
            selected_row&.[](metric),
            baseline_row&.[](metric),
            baseline_row&.[](metric),
            "Pick #{pick}",
            pick.to_s,
            ""
          ]
        else
          [
            @selected_system_values_row&.[](metric),
            @baseline_system_values_row&.[](metric),
            @baseline_system_values_row&.[](metric),
            nil,
            "",
            ""
          ]
        end

      focus_value = focus_row[metric]
      selected_delta = numeric_delta(selected_value, baseline_value)
      focus_delta = numeric_delta(focus_value, focus_baseline_value)

      selected_year_label = helpers.format_year_label(@selected_year)
      baseline_year_label = helpers.format_year_label(@baseline_year)
      focus_year_label = helpers.format_year_label(focus_year)

      context_suffix = context_label.present? ? " (#{context_label})" : ""

      summary_line = "#{selected_year_label} #{metric_definition.fetch(:label)}#{context_suffix} is #{format_metric_value(selected_value, kind)} (#{format_metric_delta(selected_delta, kind)} vs #{baseline_year_label})."

      focus_line = if focus_year.to_i == @selected_year.to_i
        "Current focus matches selected season baseline comparison."
      else
        "#{focus_year_label} value#{context_suffix}: #{format_metric_value(focus_value, kind)} (#{format_metric_delta(focus_delta, kind)} vs #{baseline_year_label})."
      end

      section_title = case section
      when "tax"
        "League Tax Rates"
      when "minimum"
        "League Salary Scales"
      when "rookie"
        "Rookie Scale Amounts"
      else
        "League System Values"
      end
      pivot_pressure = section == "tax" ? "over_tax" : "all"

      {
        section:,
        section_title:,
        metric:,
        metric_label: metric_definition.fetch(:label),
        metric_kind: kind,
        focus_year:,
        focus_year_label:,
        selected_year_label:,
        baseline_year_label:,
        selected_value_label: format_metric_value(selected_value, kind),
        baseline_value_label: format_metric_value(baseline_value, kind),
        focus_value_label: format_metric_value(focus_value, kind),
        selected_delta_label: format_metric_delta(selected_delta, kind),
        selected_delta_variant: delta_variant(selected_delta),
        focus_delta_label: format_metric_delta(focus_delta, kind),
        focus_delta_variant: delta_variant(focus_delta),
        summary_line:,
        focus_line:,
        context_label:,
        bracket_label: context_label,
        rookie_detail_rows:,
        source_table: case section
        when "tax"
          "pcms.league_tax_rates"
        when "minimum"
          "pcms.league_salary_scales"
        when "rookie"
          "pcms.rookie_scale_amounts"
        else
          "pcms.league_system_values"
        end,
        pivot_links: [
          {
            label: "Open Team Summary (#{selected_year_label})",
            href: tools_team_summary_path(year: @selected_year, conference: "all", pressure: pivot_pressure, sort: "cap_space_desc")
          },
          {
            label: "Open canonical System Values view",
            href: tools_system_values_path(@state_params)
          }
        ],
        overlay_lower:,
        overlay_upper:
      }
    end

    def tax_row_for_bracket(rows, lower:, upper:)
      Array(rows).find { |row| tax_bracket_match?(row, lower:, upper:) }
    end

    def minimum_row_for_yos(rows, yos:)
      Array(rows).find { |row| row["years_of_service"].to_i == yos.to_i }
    end

    def rookie_row_for_pick(rows, pick:)
      Array(rows).find { |row| row["pick_number"].to_i == pick.to_i }
    end

    def build_rookie_overlay_detail_rows(selected_row:, baseline_row:)
      ROOKIE_METRIC_DEFINITIONS.map do |metric_key, definition|
        selected_value = selected_row&.[](metric_key)
        baseline_value = baseline_row&.[](metric_key)
        delta = numeric_delta(selected_value, baseline_value)

        {
          metric: metric_key,
          label: definition.fetch(:label),
          selected_value_label: format_metric_value(selected_value, definition.fetch(:kind)),
          baseline_value_label: format_metric_value(baseline_value, definition.fetch(:kind)),
          delta_label: format_metric_delta(delta, definition.fetch(:kind)),
          delta_variant: delta_variant(delta)
        }
      end
    end

    def tax_bracket_match?(row, lower:, upper:)
      row_lower = row["lower_limit"]
      row_upper = row["upper_limit"]

      return false if row_lower.nil?
      return false unless row_lower.to_f == lower.to_f

      if upper.nil?
        row_upper.nil?
      else
        row_upper.present? && row_upper.to_f == upper.to_f
      end
    end

    def empty_overlay_signals
      {
        section: "",
        metric: "",
        year: "",
        lower: "",
        upper: ""
      }
    end

    def resolve_metric_finder_query(value)
      value.to_s.strip.tr("\u0000", "")[0, 80]
    end

    def resolve_metric_finder_cursor(value)
      value.to_s.strip[0, 240]
    end

    def resolve_metric_finder_shortlist!
      query = @metric_finder_query.to_s.downcase

      if query.blank?
        @metric_finder_shortlist = []
        @metric_finder_cursor_value = ""
        @metric_finder_cursor_index = 0
        return
      end

      ranked = @metric_finder_options.each_with_index.filter_map do |option, index|
        match = metric_shortlist_match_details(option:, query:)
        next unless match

        [
          match.fetch(:score),
          METRIC_FINDER_SECTION_RANK.fetch(option[:section].to_s, 99),
          index,
          option.merge(match_reason: match.fetch(:reason))
        ]
      end

      shortlist = ranked
        .sort_by { |entry| entry[0..2] }
        .first(METRIC_SHORTLIST_LIMIT)
        .map(&:last)

      @metric_finder_shortlist = shortlist

      preferred_cursor = if @requested_metric_finder_cursor.present? && shortlist.any? { |option| option[:value] == @requested_metric_finder_cursor }
        @requested_metric_finder_cursor
      elsif @active_metric_finder_value.present? && shortlist.any? { |option| option[:value] == @active_metric_finder_value }
        @active_metric_finder_value
      else
        shortlist.first&.dig(:value).to_s
      end

      @metric_finder_cursor_value = preferred_cursor.to_s
      @metric_finder_cursor_index = shortlist.find_index { |option| option[:value] == @metric_finder_cursor_value } || 0
    end

    def metric_shortlist_match_details(option:, query:)
      metric_label = option[:metric_label].to_s.downcase
      context_label = option[:context_label].to_s.downcase
      full_label = option[:label].to_s.downcase

      return { score: 0, reason: "exact" } if [metric_label, context_label, full_label].include?(query)
      return { score: 1, reason: "prefix" } if metric_label.start_with?(query)

      metric_tokens = metric_label.split(/[^a-z0-9%]+/)
      return { score: 2, reason: "prefix" } if metric_tokens.any? { |token| token.start_with?(query) }
      return { score: 3, reason: "context" } if context_label.start_with?(query)
      return { score: 4, reason: "context" } if [metric_label, context_label, full_label].any? { |value| value.include?(query) }

      nil
    end

    def build_metric_finder_options
      options = []
      selected_year_label = helpers.format_year_label(@selected_year)

      SYSTEM_METRIC_DEFINITIONS.each do |metric_key, definition|
        selected_value = @selected_system_values_row&.[](metric_key)
        options << {
          section: "system",
          section_label: METRIC_FINDER_SECTION_LABELS.fetch("system"),
          metric_label: definition.fetch(:label),
          context_label: selected_year_label,
          value: metric_finder_value(
            section: "system",
            metric: metric_key,
            year: @selected_year,
            lower: "",
            upper: "",
            anchor_id: system_row_anchor(@selected_year)
          ),
          label: "#{definition.fetch(:label)} · #{selected_year_label} · #{format_metric_value(selected_value, definition.fetch(:kind))}"
        }
      end

      @selected_tax_rate_rows.each do |row|
        lower = row["lower_limit"]
        upper = row["upper_limit"]
        lower_token = lower.present? ? format("%.0f", lower.to_f) : ""
        upper_token = upper.present? ? format("%.0f", upper.to_f) : ""

        lower_label = helpers.format_compact_currency(lower)
        upper_label = upper.present? ? helpers.format_compact_currency(upper) : "∞"
        bracket_label = "#{lower_label}–#{upper_label}"

        TAX_METRIC_DEFINITIONS.each do |metric_key, definition|
          options << {
            section: "tax",
            section_label: METRIC_FINDER_SECTION_LABELS.fetch("tax"),
            metric_label: definition.fetch(:label),
            context_label: "#{bracket_label} · #{selected_year_label}",
            value: metric_finder_value(
              section: "tax",
              metric: metric_key,
              year: @selected_year,
              lower: lower_token,
              upper: upper_token,
              anchor_id: tax_row_anchor(@selected_year, lower: lower_token, upper: upper_token)
            ),
            label: "#{definition.fetch(:label)} · #{bracket_label} · #{selected_year_label}"
          }
        end
      end

      @selected_salary_scale_rows.each do |row|
        yos = row["years_of_service"].to_i
        value = row["minimum_salary_amount"]

        options << {
          section: "minimum",
          section_label: METRIC_FINDER_SECTION_LABELS.fetch("minimum"),
          metric_label: "Minimum Salary",
          context_label: "YOS #{yos} · #{selected_year_label}",
          value: metric_finder_value(
            section: "minimum",
            metric: "minimum_salary_amount",
            year: @selected_year,
            lower: yos,
            upper: "",
            anchor_id: minimum_row_anchor(@selected_year, yos:)
          ),
          label: "YOS #{yos} · #{selected_year_label} · #{format_metric_value(value, :currency)}"
        }
      end

      @selected_rookie_scale_rows.each do |row|
        pick = row["pick_number"].to_i

        ROOKIE_METRIC_DEFINITIONS.each do |metric_key, definition|
          value = row[metric_key]

          options << {
            section: "rookie",
            section_label: METRIC_FINDER_SECTION_LABELS.fetch("rookie"),
            metric_label: definition.fetch(:label),
            context_label: "Pick #{pick} · #{selected_year_label}",
            value: metric_finder_value(
              section: "rookie",
              metric: metric_key,
              year: @selected_year,
              lower: pick,
              upper: "",
              anchor_id: rookie_row_anchor(@selected_year, pick:)
            ),
            label: "Pick #{pick} · #{definition.fetch(:label)} · #{selected_year_label} · #{format_metric_value(value, definition.fetch(:kind))}"
          }
        end
      end

      options
    end

    def metric_finder_value_for_overlay(overlay_signals)
      section = overlay_signals.fetch(:section, "").to_s
      metric = overlay_signals.fetch(:metric, "").to_s
      year = overlay_signals.fetch(:year, "").to_s
      lower = overlay_signals.fetch(:lower, "").to_s
      upper = overlay_signals.fetch(:upper, "").to_s

      return "" if section.blank? || metric.blank? || year.blank?

      anchor_id = case section
      when "system"
        system_row_anchor(year)
      when "tax"
        tax_row_anchor(year, lower:, upper:)
      when "minimum"
        minimum_row_anchor(year, yos: lower)
      when "rookie"
        rookie_row_anchor(year, pick: lower)
      end

      return "" if anchor_id.blank?

      candidate = metric_finder_value(section:, metric:, year:, lower:, upper:, anchor_id:)
      @metric_finder_options.any? { |option| option[:value] == candidate } ? candidate : ""
    end

    def metric_finder_value(section:, metric:, year:, lower:, upper:, anchor_id:)
      [ section, metric, year.to_s, lower.to_s, upper.to_s, anchor_id.to_s ].join("|")
    end

    def system_row_anchor(year)
      "sv-row-system-#{year.to_i}"
    end

    def tax_row_anchor(year, lower:, upper:)
      lower_token = lower.to_s.presence || "0"
      upper_token = upper.to_s.presence || "inf"
      "sv-row-tax-#{year.to_i}-#{lower_token}-#{upper_token}"
    end

    def minimum_row_anchor(year, yos:)
      "sv-row-minimum-#{year.to_i}-yos-#{yos.to_i}"
    end

    def rookie_row_anchor(year, pick:)
      "sv-row-rookie-#{year.to_i}-pick-#{pick.to_i}"
    end

    def build_quick_metric_cards
      cards = []

      [
        ["Cap", "salary_cap_amount"],
        ["Tax", "tax_level_amount"],
        ["Apron 1", "tax_apron_amount"],
        ["NT MLE", "non_taxpayer_mid_level_amount"]
      ].each do |label, metric|
        definition = SYSTEM_METRIC_DEFINITIONS.fetch(metric)
        selected_value = @selected_system_values_row&.[](metric)
        baseline_value = @baseline_system_values_row&.[](metric)
        delta = numeric_delta(selected_value, baseline_value)

        cards << {
          section: "system",
          metric:,
          label:,
          year: @selected_year,
          lower: "",
          upper: "",
          value_label: format_metric_value(selected_value, definition.fetch(:kind)),
          delta_label: format_metric_delta(delta, definition.fetch(:kind)),
          delta_variant: delta_variant(delta)
        }
      end

      top_bracket = @selected_tax_rate_rows.max_by { |row| row["lower_limit"].to_f }
      if top_bracket.present?
        metric = "tax_rate_non_repeater"
        definition = TAX_METRIC_DEFINITIONS.fetch(metric)

        lower = top_bracket["lower_limit"]
        upper = top_bracket["upper_limit"]

        baseline_bracket = tax_row_for_bracket(@baseline_tax_rate_rows, lower: lower.to_f, upper: upper&.to_f)
        delta = numeric_delta(top_bracket[metric], baseline_bracket&.[](metric))

        lower_label = helpers.format_compact_currency(lower)
        upper_label = upper.present? ? helpers.format_compact_currency(upper) : "∞"

        cards << {
          section: "tax",
          metric:,
          label: "Top NR #{lower_label}–#{upper_label}",
          year: @selected_year,
          lower: lower.present? ? format("%.0f", lower.to_f) : "",
          upper: upper.present? ? format("%.0f", upper.to_f) : "",
          value_label: format_metric_value(top_bracket[metric], definition.fetch(:kind)),
          delta_label: format_metric_delta(delta, definition.fetch(:kind)),
          delta_variant: delta_variant(delta)
        }
      end

      cards
    end

    def format_metric_value(value, kind)
      return "—" if value.nil?

      case kind
      when :currency
        helpers.format_compact_currency(value)
      when :rate
        "#{format("%.2f", value.to_f)}x"
      when :percentage
        "#{format("%.1f", value.to_f * 100.0)}%"
      else
        value.to_s
      end
    end

    def format_metric_delta(delta, kind)
      return "n/a" if delta.nil?

      case kind
      when :currency
        return "±$0K" if delta.to_f.zero?

        prefix = delta.to_f.positive? ? "+" : "-"
        "#{prefix}#{helpers.format_compact_currency(delta.to_f.abs)}"
      when :rate
        return "±0.00x" if delta.to_f.zero?

        prefix = delta.to_f.positive? ? "+" : ""
        "#{prefix}#{format("%.2f", delta.to_f)}x"
      when :percentage
        return "±0.0pp" if delta.to_f.zero?

        prefix = delta.to_f.positive? ? "+" : ""
        "#{prefix}#{format("%.1f", delta.to_f * 100.0)}pp"
      else
        delta.to_s
      end
    end

    def delta_variant(delta)
      return "muted" if delta.nil?
      return "positive" if delta.to_f.positive?
      return "negative" if delta.to_f.negative?

      "neutral"
    end

    def build_section_shift_cards
      minimum_selected = minimum_salary_row(@selected_salary_scale_rows)
      minimum_baseline = minimum_salary_row(@baseline_salary_scale_rows)
      rookie_selected = rookie_pick_one_row(@selected_rookie_scale_rows)
      rookie_baseline = rookie_pick_one_row(@baseline_rookie_scale_rows)

      [
        build_shift_card(
          key: "system",
          label: "System",
          metric_label: "Cap",
          delta: numeric_delta(@selected_system_values_row&.[]("salary_cap_amount"), @baseline_system_values_row&.[]("salary_cap_amount")),
          formatter: :currency
        ),
        build_shift_card(
          key: "tax",
          label: "Tax",
          metric_label: "Top NR",
          delta: numeric_delta(top_tax_rate(@selected_tax_rate_rows, "tax_rate_non_repeater"), top_tax_rate(@baseline_tax_rate_rows, "tax_rate_non_repeater")),
          formatter: :rate
        ),
        build_shift_card(
          key: "minimum",
          label: "Minimum",
          metric_label: "YOS 0",
          delta: numeric_delta(minimum_selected&.[]("minimum_salary_amount"), minimum_baseline&.[]("minimum_salary_amount")),
          formatter: :currency
        ),
        build_shift_card(
          key: "rookie",
          label: "Rookie",
          metric_label: "Pick 1",
          delta: numeric_delta(rookie_selected&.[]("salary_year_1"), rookie_baseline&.[]("salary_year_1")),
          formatter: :currency
        )
      ]
    end

    def build_shift_card(key:, label:, metric_label:, delta:, formatter:)
      {
        key:,
        label:,
        metric_label:,
        delta_label: format_shift_delta(delta, formatter),
        variant: shift_variant(delta)
      }
    end

    def top_tax_rate(rows, column)
      rows.map { |row| row[column] }.compact.map(&:to_f).max
    end

    def minimum_salary_row(rows)
      rows.min_by { |row| row["years_of_service"].to_i }
    end

    def rookie_pick_one_row(rows)
      rows.find { |row| row["pick_number"].to_i == 1 } || rows.min_by { |row| row["pick_number"].to_i }
    end

    def numeric_delta(selected_value, baseline_value)
      return nil if selected_value.nil? || baseline_value.nil?

      selected_value.to_f - baseline_value.to_f
    end

    def format_shift_delta(delta, formatter)
      return "n/a" if delta.nil?

      case formatter
      when :currency
        return "±$0K" if delta.zero?

        prefix = delta.positive? ? "+" : "-"
        "#{prefix}#{helpers.format_compact_currency(delta.abs)}"
      when :rate
        prefix = delta.positive? ? "+" : ""
        "#{prefix}#{format("%.2f", delta)}x"
      else
        delta.to_s
      end
    end

    def shift_variant(delta)
      return "muted" if delta.nil?
      return "positive" if delta.positive?
      return "negative" if delta.negative?

      "neutral"
    end
  end
end
