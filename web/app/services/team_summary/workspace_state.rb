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

    def build(step_direction: nil, selected_override_team_code: nil)
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

      @selected_team_code = resolve_team_code(params[:selected])
      @selected_team_code = resolve_team_code(selected_override_team_code) if selected_override_team_code.present?

      step_selected_team!(step_direction) if step_direction.present?

      hydrate_selected_row!
      @state_params = build_state_params
      build_sidebar_summary!

      {
        boot_error: nil,
        available_years: @available_years,
        selected_year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort,
        rows: @rows,
        rows_by_code: @rows_by_code,
        pressure_counts: @pressure_counts,
        sidebar_summary: @sidebar_summary,
        selected_team_code: @selected_team_code,
        selected_row: @selected_row,
        state_params: @state_params
      }
    end

    def fallback(error:)
      empty_pressure_counts = {
        "all" => 0,
        "over_cap" => 0,
        "over_tax" => 0,
        "over_apron1" => 0,
        "over_apron2" => 0
      }

      {
        boot_error: error.to_s,
        available_years: [],
        selected_year: current_salary_year,
        conference: "all",
        pressure: "all",
        sort: "pressure_desc",
        rows: [],
        rows_by_code: {},
        pressure_counts: empty_pressure_counts,
        sidebar_summary: {
          row_count: 0,
          eastern_count: 0,
          western_count: 0,
          over_cap_count: 0,
          over_tax_count: 0,
          over_apron1_count: 0,
          over_apron2_count: 0,
          pressure_counts: empty_pressure_counts,
          active_pressure_lens: "all",
          active_pressure_label: "All teams",
          active_pressure_count: 0,
          active_sort_label: "Pressure first",
          luxury_tax_total: 0,
          filters: [],
          top_rows: []
        },
        selected_team_code: nil,
        selected_row: nil,
        state_params: {
          year: current_salary_year,
          conference: "all",
          pressure: "all",
          sort: "pressure_desc"
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
        when "pressure"
          "pressure_desc"
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
      sort_sql.key?(normalized) ? normalized : "pressure_desc"
    end

    def resolve_team_code(value)
      code = value.to_s.strip.upcase
      code.match?(/\A[A-Z]{3}\z/) ? code : nil
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

    def hydrate_selected_row!
      selected_code = resolve_team_code(@selected_team_code)
      if selected_code.blank?
        @selected_team_code = nil
        @selected_row = nil
        return
      end

      @selected_row = @rows_by_code[selected_code]

      if @selected_row.blank?
        lookup_rows = fetch_rows_by_team_codes(year: @selected_year, team_codes: [selected_code])
        @selected_row = lookup_rows[selected_code]
      end

      unless @selected_row.present?
        @selected_team_code = nil
        @selected_row = nil
        return
      end

      @selected_team_code = selected_code
    end

    def build_state_params
      {
        year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort,
        selected: @selected_team_code.presence
      }.compact
    end

    def build_sidebar_summary!
      rows = Array(@rows)
      @pressure_counts = build_pressure_counts(rows)

      active_filters = []
      active_filters << "Conference: #{@conference}" unless @conference == "all"
      active_filters << "Pressure: #{pressure_lens_label(@pressure)}" unless @pressure == "all"
      active_filters << "Sort: #{sort_lens_label(@sort)}" unless @sort == "pressure_desc"

      top_rows = rows.first(14)
      if @selected_row.present? && top_rows.none? { |row| row["team_code"].to_s == @selected_row["team_code"].to_s }
        top_rows = [@selected_row] + top_rows.first(13)
      end

      @sidebar_summary = {
        row_count: rows.size,
        eastern_count: rows.count { |row| row["conference_name"] == "Eastern" },
        western_count: rows.count { |row| row["conference_name"] == "Western" },
        over_cap_count: @pressure_counts["over_cap"],
        over_tax_count: @pressure_counts["over_tax"],
        over_apron1_count: @pressure_counts["over_apron1"],
        over_apron2_count: @pressure_counts["over_apron2"],
        pressure_counts: @pressure_counts,
        active_pressure_lens: @pressure,
        active_pressure_label: pressure_lens_label(@pressure),
        active_pressure_count: @pressure_counts[@pressure],
        active_sort_label: sort_lens_label(@sort),
        luxury_tax_total: rows.sum { |row| row["luxury_tax_owed"].to_f },
        filters: active_filters,
        top_rows: top_rows
      }
    end

    def pressure_lens_label(lens)
      case lens
      when "over_tax" then "Over tax"
      when "over_apron1" then "Over Apron 1"
      when "over_apron2" then "Over Apron 2"
      else "All teams"
      end
    end

    def sort_lens_label(lens)
      case lens
      when "cap_space_asc" then "Cap space (lowest first)"
      when "cap_space_desc" then "Cap space (highest first)"
      when "tax_overage_asc" then "Tax overage (lowest first)"
      when "tax_overage_desc" then "Tax overage (highest first)"
      when "team_asc" then "Team A→Z"
      else "Pressure first"
      end
    end

    def build_pressure_counts(rows)
      scoped_rows = Array(rows)

      {
        "all" => scoped_rows.size,
        "over_cap" => scoped_rows.count { |row| pressure_rank_for_row(row) >= 1 },
        "over_tax" => scoped_rows.count { |row| pressure_rank_for_row(row) >= 2 },
        "over_apron1" => scoped_rows.count { |row| pressure_rank_for_row(row) >= 3 },
        "over_apron2" => scoped_rows.count { |row| pressure_rank_for_row(row) >= 4 }
      }
    end

    def pressure_rank_for_row(row)
      row["pressure_rank"].to_i
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
  end
end
