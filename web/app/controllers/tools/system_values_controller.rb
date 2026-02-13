module Tools
  class SystemValuesController < ApplicationController
    CURRENT_SALARY_YEAR = 2025
    DEFAULT_WINDOW_YEARS = 2
    DEFAULT_BASELINE_OFFSET_YEARS = 1

    # GET /tools/system-values
    def show
      @available_years = fetch_available_years
      @selected_year = resolve_selected_year(@available_years)
      @baseline_year = resolve_baseline_year(@available_years, @selected_year)
      @from_year, @to_year = resolve_year_range(@available_years, @selected_year)

      @league_system_values = fetch_league_system_values(@from_year, @to_year)
      @league_tax_rates = fetch_league_tax_rates(@from_year, @to_year)
      @league_salary_scales = fetch_league_salary_scales(@from_year, @to_year)
      @rookie_scale_amounts = fetch_rookie_scale_amounts(@from_year, @to_year)

      @selected_system_values_row = fetch_league_system_values(@selected_year, @selected_year).first
      @baseline_system_values_row = fetch_league_system_values(@baseline_year, @baseline_year).first

      @selected_tax_rate_rows = fetch_league_tax_rates(@selected_year, @selected_year)
      @baseline_tax_rate_rows = fetch_league_tax_rates(@baseline_year, @baseline_year)

      @selected_salary_scale_rows = fetch_league_salary_scales(@selected_year, @selected_year)
      @baseline_salary_scale_rows = fetch_league_salary_scales(@baseline_year, @baseline_year)

      @selected_rookie_scale_rows = fetch_rookie_scale_amounts(@selected_year, @selected_year)
      @baseline_rookie_scale_rows = fetch_rookie_scale_amounts(@baseline_year, @baseline_year)

      @section_shift_cards = build_section_shift_cards
    rescue ActiveRecord::StatementInvalid => e
      @boot_error = e.message
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
      @section_shift_cards = []
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
