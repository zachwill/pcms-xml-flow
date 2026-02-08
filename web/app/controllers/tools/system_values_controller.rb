module Tools
  class SystemValuesController < ApplicationController
    CURRENT_SALARY_YEAR = 2025
    DEFAULT_WINDOW_YEARS = 2

    # GET /tools/system-values
    def show
      @available_years = fetch_available_years
      @selected_year = resolve_selected_year(@available_years)
      @from_year, @to_year = resolve_year_range(@available_years, @selected_year)

      @league_system_values = fetch_league_system_values(@from_year, @to_year)
      @league_tax_rates = fetch_league_tax_rates(@from_year, @to_year)
      @league_salary_scales = fetch_league_salary_scales(@from_year, @to_year)
      @rookie_scale_amounts = fetch_rookie_scale_amounts(@from_year, @to_year)
    rescue ActiveRecord::StatementInvalid => e
      @boot_error = e.message
      @available_years = []
      @selected_year = CURRENT_SALARY_YEAR
      @from_year = CURRENT_SALARY_YEAR
      @to_year = CURRENT_SALARY_YEAR
      @league_system_values = []
      @league_tax_rates = []
      @league_salary_scales = []
      @rookie_scale_amounts = []
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
        FROM (
          SELECT salary_year FROM pcms.league_system_values WHERE league_lk = 'NBA'
          UNION
          SELECT salary_year FROM pcms.league_tax_rates WHERE league_lk = 'NBA'
          UNION
          SELECT salary_year FROM pcms.league_salary_scales WHERE league_lk = 'NBA'
          UNION
          SELECT salary_year FROM pcms.rookie_scale_amounts WHERE league_lk = 'NBA' AND salary_year >= 1900
        ) years
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

    def resolve_year_range(available_years, selected_year)
      return [selected_year, selected_year] if available_years.empty?

      min_year = available_years.min
      max_year = available_years.max

      default_from = [selected_year - DEFAULT_WINDOW_YEARS, min_year].max
      default_to = [selected_year + DEFAULT_WINDOW_YEARS, max_year].min

      from_year = parse_year_param(params[:from_year]) || default_from
      to_year = parse_year_param(params[:to_year]) || default_to

      from_year = from_year.clamp(min_year, max_year)
      to_year = to_year.clamp(min_year, max_year)

      if from_year > to_year
        from_year, to_year = to_year, from_year
      end

      [from_year, to_year]
    end

    def fetch_league_system_values(from_year, to_year)
      conn.exec_query(<<~SQL).to_a
        SELECT
          salary_year,
          salary_cap_amount,
          tax_level_amount,
          tax_apron_amount,
          tax_apron2_amount,
          minimum_team_salary_amount,
          maximum_salary_25_pct,
          maximum_salary_30_pct,
          maximum_salary_35_pct,
          non_taxpayer_mid_level_amount,
          taxpayer_mid_level_amount,
          room_mid_level_amount,
          bi_annual_amount,
          tpe_dollar_allowance,
          max_trade_cash_amount,
          international_player_payment_limit,
          refreshed_at
        FROM (
          SELECT
            salary_year,
            salary_cap_amount,
            tax_level_amount,
            tax_apron_amount,
            tax_apron2_amount,
            minimum_team_salary_amount,
            maximum_salary_25_pct,
            maximum_salary_30_pct,
            maximum_salary_35_pct,
            non_taxpayer_mid_level_amount,
            taxpayer_mid_level_amount,
            room_mid_level_amount,
            bi_annual_amount,
            tpe_dollar_allowance,
            max_trade_cash_amount,
            international_player_payment_limit,
            ingested_at AS refreshed_at
          FROM pcms.league_system_values
          WHERE league_lk = 'NBA'
            AND salary_year BETWEEN #{conn.quote(from_year)} AND #{conn.quote(to_year)}
        ) values_rows
        ORDER BY salary_year
      SQL
    end

    def fetch_league_tax_rates(from_year, to_year)
      conn.exec_query(<<~SQL).to_a
        SELECT
          salary_year,
          lower_limit,
          upper_limit,
          tax_rate_non_repeater,
          tax_rate_repeater,
          base_charge_non_repeater,
          base_charge_repeater
        FROM pcms.league_tax_rates
        WHERE league_lk = 'NBA'
          AND salary_year BETWEEN #{conn.quote(from_year)} AND #{conn.quote(to_year)}
        ORDER BY salary_year, lower_limit
      SQL
    end

    def fetch_league_salary_scales(from_year, to_year)
      conn.exec_query(<<~SQL).to_a
        SELECT
          salary_year,
          years_of_service,
          minimum_salary_amount
        FROM pcms.league_salary_scales
        WHERE league_lk = 'NBA'
          AND salary_year BETWEEN #{conn.quote(from_year)} AND #{conn.quote(to_year)}
        ORDER BY salary_year, years_of_service
      SQL
    end

    def fetch_rookie_scale_amounts(from_year, to_year)
      conn.exec_query(<<~SQL).to_a
        SELECT
          salary_year,
          pick_number,
          salary_year_1,
          salary_year_2,
          option_amount_year_3,
          option_amount_year_4,
          option_pct_year_3,
          option_pct_year_4,
          is_active
        FROM pcms.rookie_scale_amounts
        WHERE league_lk = 'NBA'
          AND salary_year >= 1900
          AND salary_year BETWEEN #{conn.quote(from_year)} AND #{conn.quote(to_year)}
        ORDER BY salary_year, pick_number
      SQL
    end
  end
end
