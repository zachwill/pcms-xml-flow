module SystemValues
  class WorkspaceState
    def initialize(
      queries:,
      params:,
      current_salary_year:,
      default_window_years:,
      default_baseline_offset_years:,
      section_visibility_param_definitions:
    )
      @queries = queries
      @params = params
      @current_salary_year = current_salary_year
      @default_window_years = default_window_years
      @default_baseline_offset_years = default_baseline_offset_years
      @section_visibility_param_definitions = section_visibility_param_definitions
    end

    def build
      @available_years = queries.fetch_available_years
      @selected_year = resolve_selected_year(@available_years)
      @baseline_year = resolve_baseline_year(@available_years, @selected_year)
      @from_year, @to_year = resolve_year_range(@available_years, @selected_year)

      @league_system_values = queries.fetch_league_system_values(@from_year, @to_year)
      @league_tax_rates = queries.fetch_league_tax_rates(@from_year, @to_year)
      @league_salary_scales = queries.fetch_league_salary_scales(@from_year, @to_year)
      @rookie_scale_amounts = queries.fetch_rookie_scale_amounts(@from_year, @to_year)

      @selected_system_values_row = @league_system_values.find { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_system_values_row = @league_system_values.find { |row| row["salary_year"].to_i == @baseline_year.to_i }

      @selected_tax_rate_rows = @league_tax_rates.select { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_tax_rate_rows = @league_tax_rates.select { |row| row["salary_year"].to_i == @baseline_year.to_i }

      @selected_salary_scale_rows = @league_salary_scales.select { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_salary_scale_rows = @league_salary_scales.select { |row| row["salary_year"].to_i == @baseline_year.to_i }

      @selected_rookie_scale_rows = @rookie_scale_amounts.select { |row| row["salary_year"].to_i == @selected_year.to_i }
      @baseline_rookie_scale_rows = @rookie_scale_amounts.select { |row| row["salary_year"].to_i == @baseline_year.to_i }

      # Fallback queries only when selected/baseline years were intentionally excluded by range.
      @selected_system_values_row ||= queries.fetch_league_system_values(@selected_year, @selected_year).first
      @baseline_system_values_row ||= queries.fetch_league_system_values(@baseline_year, @baseline_year).first
      @selected_tax_rate_rows = queries.fetch_league_tax_rates(@selected_year, @selected_year) if @selected_tax_rate_rows.empty?
      @baseline_tax_rate_rows = queries.fetch_league_tax_rates(@baseline_year, @baseline_year) if @baseline_tax_rate_rows.empty?
      @selected_salary_scale_rows = queries.fetch_league_salary_scales(@selected_year, @selected_year) if @selected_salary_scale_rows.empty?
      @baseline_salary_scale_rows = queries.fetch_league_salary_scales(@baseline_year, @baseline_year) if @baseline_salary_scale_rows.empty?
      @selected_rookie_scale_rows = queries.fetch_rookie_scale_amounts(@selected_year, @selected_year) if @selected_rookie_scale_rows.empty?
      @baseline_rookie_scale_rows = queries.fetch_rookie_scale_amounts(@baseline_year, @baseline_year) if @baseline_rookie_scale_rows.empty?

      resolve_section_visibility!
      build_state_payload(boot_error: nil)
    end

    def fallback(error:)
      @available_years = []
      @selected_year = current_salary_year
      @baseline_year = current_salary_year
      @from_year = current_salary_year
      @to_year = current_salary_year
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
      build_state_payload(boot_error: error.to_s)
    end

    private

    attr_reader :queries, :params, :current_salary_year, :default_window_years,
      :default_baseline_offset_years, :section_visibility_param_definitions

    def parse_year_param(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def resolve_selected_year(available_years)
      return current_salary_year if available_years.empty?

      requested = parse_year_param(params[:year])
      return requested if requested && available_years.include?(requested)

      return current_salary_year if available_years.include?(current_salary_year)

      available_years.max
    end

    def resolve_baseline_year(available_years, selected_year)
      return selected_year if available_years.empty?

      requested = parse_year_param(params[:baseline_year])
      return requested if requested && available_years.include?(requested)

      preferred = selected_year - default_baseline_offset_years
      return preferred if available_years.include?(preferred)

      return selected_year if available_years.include?(selected_year)

      available_years.min
    end

    def resolve_year_range(available_years, selected_year)
      return [selected_year, selected_year] if available_years.empty?

      min_year = available_years.min
      max_year = available_years.max

      default_from = [selected_year - default_window_years, min_year].max
      default_to = [selected_year + default_window_years, max_year].min

      from_year = parse_year_param(params[:from_year]) || default_from
      to_year = parse_year_param(params[:to_year]) || default_to

      from_year = from_year.clamp(min_year, max_year)
      to_year = to_year.clamp(min_year, max_year)

      if from_year > to_year
        from_year, to_year = to_year, from_year
      end

      [from_year, to_year]
    end

    def resolve_section_visibility!
      @show_system_values = parse_visibility_param(params[section_visibility_param_definitions.fetch(:showsystemvalues)])
      @show_tax_rates = parse_visibility_param(params[section_visibility_param_definitions.fetch(:showtaxrates)])
      @show_salary_scales = parse_visibility_param(params[section_visibility_param_definitions.fetch(:showsalaryscales)])
      @show_rookie_scales = parse_visibility_param(params[section_visibility_param_definitions.fetch(:showrookiescales)])
    end

    def build_state_payload(boot_error:)
      @state_params = {
        year: @selected_year,
        baseline_year: @baseline_year,
        from_year: @from_year,
        to_year: @to_year
      }.merge(visibility_state_params)

      {
        boot_error: boot_error,
        available_years: @available_years,
        selected_year: @selected_year,
        baseline_year: @baseline_year,
        from_year: @from_year,
        to_year: @to_year,
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
        show_system_values: @show_system_values,
        show_tax_rates: @show_tax_rates,
        show_salary_scales: @show_salary_scales,
        show_rookie_scales: @show_rookie_scales,
        state_params: @state_params
      }
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
  end
end
