module TeamSummary
  class WorkspaceState
    def initialize(
      params:,
      request_query_parameters:,
      queries:,
      current_salary_year:,
      available_salary_years:,
      sort_sql:
    )
      @params = params
      @request_query_parameters = request_query_parameters || {}
      @queries = queries
      @current_salary_year = current_salary_year
      @available_salary_years = available_salary_years
      @sort_sql = sort_sql
    end

    def build(apply_compare_action: false, step_direction: nil, selected_override_team_code: nil)
      @available_years = fetch_available_years
      @selected_year = resolve_selected_year(@available_years)
      @conference = resolve_conference_from_params
      @pressure = resolve_pressure(params[:pressure])
      @sort = resolve_sort_from_params

      @rows = queries.fetch_rows(
        year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort,
        sort_sql: sort_sql
      )
      @rows_by_code = @rows.index_by { |row| row["team_code"] }
      @team_picker_by_conference = build_team_picker_by_conference(year: @selected_year)

      @compare_a_code = resolve_team_code(params[:compare_a])
      @compare_b_code = resolve_team_code(params[:compare_b])
      normalize_compare_slots!

      @selected_team_code = resolve_team_code(params[:selected])
      @selected_team_code = resolve_team_code(selected_override_team_code) if selected_override_team_code.present?

      apply_compare_action! if apply_compare_action
      step_selected_team!(step_direction) if step_direction.present?

      hydrate_sidebar_payload!
      @state_params = build_state_params

      {
        boot_error: nil,
        available_years: @available_years,
        selected_year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort,
        rows: @rows,
        rows_by_code: @rows_by_code,
        team_picker_by_conference: @team_picker_by_conference,
        compare_a_code: @compare_a_code,
        compare_b_code: @compare_b_code,
        compare_a_row: @compare_a_row,
        compare_b_row: @compare_b_row,
        selected_team_code: @selected_team_code,
        selected_row: @selected_row,
        state_params: @state_params
      }
    end

    def fallback(error:)
      {
        boot_error: error.to_s,
        available_years: [],
        selected_year: current_salary_year,
        conference: "all",
        pressure: "all",
        sort: "cap_space_desc",
        rows: [],
        rows_by_code: {},
        team_picker_by_conference: { "Eastern" => [], "Western" => [] },
        compare_a_code: nil,
        compare_b_code: nil,
        compare_a_row: nil,
        compare_b_row: nil,
        selected_team_code: nil,
        selected_row: nil,
        state_params: {
          year: current_salary_year,
          conference: "all",
          pressure: "all",
          sort: "cap_space_desc"
        }
      }
    end

    private

    attr_reader :params, :request_query_parameters, :queries, :current_salary_year, :available_salary_years, :sort_sql

    def parse_year_param(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def fetch_available_years
      available_salary_years
    end

    def resolve_selected_year(available_years)
      return current_salary_year if available_years.empty?

      requested = parse_year_param(params[:year])
      return requested if requested && available_years.include?(requested)

      return current_salary_year if available_years.include?(current_salary_year)

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
      sort_sql.key?(normalized) ? normalized : "cap_space_desc"
    end

    def resolve_team_code(value)
      code = value.to_s.strip.upcase
      code.match?(/\A[A-Z]{3}\z/) ? code : nil
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

    def step_selected_team!(direction)
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

    def hydrate_sidebar_payload!
      lookup_codes = [@selected_team_code, @compare_a_code, @compare_b_code].compact.uniq
      lookup_rows_by_code = {}

      lookup_codes.each do |code|
        row = @rows_by_code[code]
        lookup_rows_by_code[code] = row if row.present?
      end

      missing_codes = lookup_codes - lookup_rows_by_code.keys
      if missing_codes.any?
        lookup_rows_by_code.merge!(fetch_rows_by_team_codes(year: @selected_year, team_codes: missing_codes))
      end

      @compare_a_row = @compare_a_code.present? ? lookup_rows_by_code[@compare_a_code] : nil
      @compare_b_row = @compare_b_code.present? ? lookup_rows_by_code[@compare_b_code] : nil

      @compare_a_code = nil if @compare_a_code.present? && @compare_a_row.blank?
      @compare_b_code = nil if @compare_b_code.present? && @compare_b_row.blank?
      normalize_compare_slots!

      @selected_row = @selected_team_code.present? ? lookup_rows_by_code[@selected_team_code] : nil
      @selected_team_code = nil unless @selected_row.present?
    end

    def build_state_params
      {
        year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort,
        selected: @selected_team_code.presence,
        compare_a: @compare_a_code.presence,
        compare_b: @compare_b_code.presence
      }.compact
    end

    def apply_compare_action!
      compare_action_param = params[:compare_action].presence || request_query_parameters["action"]
      compare_slot_param = params[:compare_slot].presence || request_query_parameters["slot"]

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

      rows = queries.fetch_rows(
        year: year,
        conference: "all",
        pressure: "all",
        sort: "team_asc",
        sort_sql: sort_sql,
        team_codes: codes,
        apply_filters: false
      )

      rows_by_code = rows.index_by { |row| row["team_code"] }
      codes.each_with_object({}) do |code, acc|
        acc[code] = rows_by_code[code] if rows_by_code.key?(code)
      end
    end

    def build_team_picker_by_conference(year:)
      rows = queries.fetch_rows(
        year: year,
        conference: "all",
        pressure: "all",
        sort: "team_asc",
        sort_sql: sort_sql,
        apply_filters: false
      )

      picker = { "Eastern" => [], "Western" => [] }

      rows.each do |row|
        code = resolve_team_code(row["team_code"])
        next if code.blank?

        conference = row["conference_name"].to_s
        next unless picker.key?(conference)

        picker[conference] << {
          code: code,
          name: row["team_name"].presence || code
        }
      end

      picker
    end
  end
end
