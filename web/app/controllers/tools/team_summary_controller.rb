module Tools
  class TeamSummaryController < ApplicationController
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
      @available_years = fetch_available_years
      @selected_year = resolve_selected_year(@available_years)
      @conference = resolve_conference_from_params
      @pressure = resolve_pressure(params[:pressure])
      @sort = resolve_sort_from_params

      @rows = fetch_team_summary_rows(
        year: @selected_year,
        conference: @conference,
        pressure: @pressure,
        sort: @sort
      )
    rescue ActiveRecord::StatementInvalid => e
      @boot_error = e.message
      @available_years = []
      @selected_year = CURRENT_SALARY_YEAR
      @conference = "all"
      @pressure = "all"
      @sort = "cap_space_desc"
      @rows = []
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

    def fetch_team_summary_rows(year:, conference:, pressure:, sort:)
      where_clauses = [
        "tsw.salary_year = #{conn.quote(year)}",
        "t.league_lk = 'NBA'",
        "t.team_name NOT LIKE 'Non-NBA%'"
      ]

      if conference != "all"
        where_clauses << "t.conference_name = #{conn.quote(conference)}"
      end

      case pressure
      when "over_tax"
        where_clauses << "COALESCE(tsw.room_under_tax, 0) < 0"
      when "over_apron1"
        where_clauses << "COALESCE(tsw.room_under_apron1, 0) < 0"
      when "over_apron2"
        where_clauses << "COALESCE(tsw.room_under_apron2, 0) < 0"
      end

      order_sql = SORT_SQL.fetch(sort)

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
