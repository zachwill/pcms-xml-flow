require "test_helper"

class ToolsSystemValuesTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  class FakeConnection
    def quote(value)
      case value
      when nil
        "NULL"
      when Numeric
        value.to_s
      when true
        "TRUE"
      when false
        "FALSE"
      else
        "'#{value.to_s.gsub("'", "''")}'"
      end
    end

    def exec_query(sql)
      if sql.include?("SELECT DISTINCT salary_year")
        return ActiveRecord::Result.new(["salary_year"], [[2024], [2025], [2026]])
      end

      if sql.include?("FROM pcms.league_system_values")
        from_year, to_year = parse_year_bounds(sql)
        rows = league_system_values_rows.select { |row| within_range?(row["salary_year"], from_year, to_year) }
        return to_result(rows)
      end

      if sql.include?("FROM pcms.league_tax_rates")
        from_year, to_year = parse_year_bounds(sql)
        rows = league_tax_rate_rows.select { |row| within_range?(row["salary_year"], from_year, to_year) }
        rows = rows.sort_by { |row| [row["salary_year"], row["lower_limit"]] }
        return to_result(rows)
      end

      if sql.include?("FROM pcms.league_salary_scales")
        from_year, to_year = parse_year_bounds(sql)
        rows = league_salary_scale_rows.select { |row| within_range?(row["salary_year"], from_year, to_year) }
        rows = rows.sort_by { |row| [row["salary_year"], row["years_of_service"]] }
        return to_result(rows)
      end

      if sql.include?("FROM pcms.rookie_scale_amounts")
        from_year, to_year = parse_year_bounds(sql)
        rows = rookie_scale_rows.select { |row| within_range?(row["salary_year"], from_year, to_year) }
        rows = rows.sort_by { |row| [row["salary_year"], row["pick_number"]] }
        return to_result(rows)
      end

      ActiveRecord::Result.new([], [])
    end

    private

    def parse_year_bounds(sql)
      match = sql.match(/salary_year\s+BETWEEN\s+'?(\d{4})'?\s+AND\s+'?(\d{4})'?/)
      return [1900, 3000] unless match

      [match[1].to_i, match[2].to_i]
    end

    def within_range?(year, from_year, to_year)
      year.to_i >= from_year.to_i && year.to_i <= to_year.to_i
    end

    def to_result(rows)
      return ActiveRecord::Result.new([], []) if rows.empty?

      columns = rows.first.keys
      ActiveRecord::Result.new(columns, rows.map { |row| columns.map { |column| row[column] } })
    end

    def league_system_values_rows
      @league_system_values_rows ||= [
        {
          "salary_year" => 2024,
          "salary_cap_amount" => 141_000_000,
          "tax_level_amount" => 171_000_000,
          "tax_apron_amount" => 178_000_000,
          "tax_apron2_amount" => 188_000_000,
          "minimum_team_salary_amount" => 126_900_000,
          "maximum_salary_25_pct" => 35_250_000,
          "maximum_salary_30_pct" => 42_300_000,
          "maximum_salary_35_pct" => 49_350_000,
          "non_taxpayer_mid_level_amount" => 12_900_000,
          "taxpayer_mid_level_amount" => 8_000_000,
          "room_mid_level_amount" => 7_700_000,
          "bi_annual_amount" => 4_700_000,
          "tpe_dollar_allowance" => 7_500_000,
          "max_trade_cash_amount" => 6_000_000,
          "international_player_payment_limit" => 8_000_000,
          "refreshed_at" => Time.current
        },
        {
          "salary_year" => 2025,
          "salary_cap_amount" => 142_000_000,
          "tax_level_amount" => 172_000_000,
          "tax_apron_amount" => 179_000_000,
          "tax_apron2_amount" => 190_000_000,
          "minimum_team_salary_amount" => 127_800_000,
          "maximum_salary_25_pct" => 35_500_000,
          "maximum_salary_30_pct" => 42_600_000,
          "maximum_salary_35_pct" => 49_700_000,
          "non_taxpayer_mid_level_amount" => 13_100_000,
          "taxpayer_mid_level_amount" => 8_100_000,
          "room_mid_level_amount" => 7_900_000,
          "bi_annual_amount" => 4_800_000,
          "tpe_dollar_allowance" => 7_600_000,
          "max_trade_cash_amount" => 6_100_000,
          "international_player_payment_limit" => 8_100_000,
          "refreshed_at" => Time.current
        },
        {
          "salary_year" => 2026,
          "salary_cap_amount" => 150_000_000,
          "tax_level_amount" => 181_000_000,
          "tax_apron_amount" => 190_000_000,
          "tax_apron2_amount" => 201_000_000,
          "minimum_team_salary_amount" => 135_000_000,
          "maximum_salary_25_pct" => 37_500_000,
          "maximum_salary_30_pct" => 45_000_000,
          "maximum_salary_35_pct" => 52_500_000,
          "non_taxpayer_mid_level_amount" => 14_000_000,
          "taxpayer_mid_level_amount" => 8_900_000,
          "room_mid_level_amount" => 8_300_000,
          "bi_annual_amount" => 5_300_000,
          "tpe_dollar_allowance" => 8_000_000,
          "max_trade_cash_amount" => 6_700_000,
          "international_player_payment_limit" => 8_500_000,
          "refreshed_at" => Time.current
        }
      ]
    end

    def league_tax_rate_rows
      @league_tax_rate_rows ||= [
        {
          "salary_year" => 2024,
          "lower_limit" => 0,
          "upper_limit" => 5_000_000,
          "tax_rate_non_repeater" => 1.50,
          "tax_rate_repeater" => 2.50,
          "base_charge_non_repeater" => 0,
          "base_charge_repeater" => 0
        },
        {
          "salary_year" => 2024,
          "lower_limit" => 5_000_000,
          "upper_limit" => nil,
          "tax_rate_non_repeater" => 1.75,
          "tax_rate_repeater" => 2.75,
          "base_charge_non_repeater" => 7_500_000,
          "base_charge_repeater" => 12_500_000
        },
        {
          "salary_year" => 2025,
          "lower_limit" => 0,
          "upper_limit" => 5_000_000,
          "tax_rate_non_repeater" => 1.50,
          "tax_rate_repeater" => 2.50,
          "base_charge_non_repeater" => 0,
          "base_charge_repeater" => 0
        },
        {
          "salary_year" => 2025,
          "lower_limit" => 5_000_000,
          "upper_limit" => nil,
          "tax_rate_non_repeater" => 2.00,
          "tax_rate_repeater" => 3.00,
          "base_charge_non_repeater" => 8_500_000,
          "base_charge_repeater" => 13_500_000
        },
        {
          "salary_year" => 2026,
          "lower_limit" => 0,
          "upper_limit" => 5_000_000,
          "tax_rate_non_repeater" => 1.75,
          "tax_rate_repeater" => 2.75,
          "base_charge_non_repeater" => 0,
          "base_charge_repeater" => 0
        },
        {
          "salary_year" => 2026,
          "lower_limit" => 5_000_000,
          "upper_limit" => nil,
          "tax_rate_non_repeater" => 2.25,
          "tax_rate_repeater" => 3.25,
          "base_charge_non_repeater" => 9_000_000,
          "base_charge_repeater" => 14_000_000
        }
      ]
    end

    def league_salary_scale_rows
      @league_salary_scale_rows ||= [
        { "salary_year" => 2024, "years_of_service" => 0, "minimum_salary_amount" => 1_100_000 },
        { "salary_year" => 2024, "years_of_service" => 1, "minimum_salary_amount" => 1_800_000 },
        { "salary_year" => 2025, "years_of_service" => 0, "minimum_salary_amount" => 1_180_000 },
        { "salary_year" => 2025, "years_of_service" => 1, "minimum_salary_amount" => 1_900_000 },
        { "salary_year" => 2026, "years_of_service" => 0, "minimum_salary_amount" => 1_250_000 },
        { "salary_year" => 2026, "years_of_service" => 1, "minimum_salary_amount" => 1_980_000 }
      ]
    end

    def rookie_scale_rows
      @rookie_scale_rows ||= [
        {
          "salary_year" => 2024,
          "pick_number" => 1,
          "salary_year_1" => 10_000_000,
          "salary_year_2" => 10_500_000,
          "option_amount_year_3" => 11_000_000,
          "option_amount_year_4" => 12_000_000,
          "option_pct_year_3" => 1.10,
          "option_pct_year_4" => 1.20,
          "is_active" => true
        },
        {
          "salary_year" => 2025,
          "pick_number" => 1,
          "salary_year_1" => 10_600_000,
          "salary_year_2" => 11_100_000,
          "option_amount_year_3" => 11_700_000,
          "option_amount_year_4" => 12_600_000,
          "option_pct_year_3" => 1.10,
          "option_pct_year_4" => 1.20,
          "is_active" => true
        },
        {
          "salary_year" => 2026,
          "pick_number" => 1,
          "salary_year_1" => 11_000_000,
          "salary_year_2" => 11_600_000,
          "option_amount_year_3" => 12_200_000,
          "option_amount_year_4" => 13_200_000,
          "option_pct_year_3" => 1.10,
          "option_pct_year_4" => 1.20,
          "is_active" => true
        }
      ]
    end
  end

  setup do
    host! "localhost"
  end

  test "system values renders rightpanel targets, sse apply path, and rookie metric-cell drill-in wiring" do
    with_fake_connection do
      get "/tools/system-values", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2024",
        to_year: "2026"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "/tools/system-values/sse/refresh?"
      assert_includes response.body, "/tools/system-values/sidebar/metric?"
      assert_includes response.body, "Comparing 26-27 against 24-25 baseline"
      assert_includes response.body, "$svoverlaysection='minimum'; $svoverlaymetric='minimum_salary_amount'"
      assert_includes response.body, "$svoverlaylower='0'"
      assert_includes response.body, "$svoverlaysection='rookie'; $svoverlaymetric='salary_year_1'"
      assert_includes response.body, "$svoverlaysection='rookie'; $svoverlaymetric='option_amount_year_4'"
      assert_includes response.body, "$svoverlaysection='rookie'; $svoverlaymetric='option_pct_year_3'"
      assert_includes response.body, "$svoverlaylower='1'"
    end
  end

  test "system values sidebar metric endpoint renders selected vs baseline drill-in" do
    with_fake_connection do
      get "/tools/system-values/sidebar/metric", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2024",
        to_year: "2026",
        overlay_section: "system",
        overlay_metric: "salary_cap_amount",
        overlay_year: "2026"
      }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "League System Values"
      assert_includes response.body, "Salary Cap"
      assert_includes response.body, "Source table: pcms.league_system_values"
      assert_includes response.body, "Open Team Summary"
      assert_not_includes response.body, "Tax step interpretation"
    end
  end

  test "system values tax sidebar drill-in renders bracket step interpretation notes" do
    with_fake_connection do
      get "/tools/system-values/sidebar/metric", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2024",
        to_year: "2026",
        overlay_section: "tax",
        overlay_metric: "tax_rate_non_repeater",
        overlay_year: "2026",
        overlay_lower: "5000000",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "League Tax Rates"
      assert_includes response.body, "Tax Rate (Non-Repeater)"
      assert_includes response.body, "Tax step interpretation"
      assert_includes response.body, "Brackets are incremental"
      assert_includes response.body, "Tax due at this step = base charge + (amount in bracket × rate)."
      assert_includes response.body, "Source table: pcms.league_tax_rates"
    end
  end

  test "system values minimum salary sidebar drill-in renders yos baseline context" do
    with_fake_connection do
      get "/tools/system-values/sidebar/metric", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2024",
        to_year: "2026",
        overlay_section: "minimum",
        overlay_metric: "minimum_salary_amount",
        overlay_year: "2026",
        overlay_lower: "1",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "League Salary Scales"
      assert_includes response.body, "Minimum Salary"
      assert_includes response.body, "YOS 1"
      assert_includes response.body, "Source table: pcms.league_salary_scales"
      assert_includes response.body, "Open canonical System Values view"
      assert_not_includes response.body, "Tax step interpretation"
    end
  end

  test "system values rookie scale sidebar drill-in renders pick baseline context for selected rookie metric" do
    with_fake_connection do
      get "/tools/system-values/sidebar/metric", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2024",
        to_year: "2026",
        overlay_section: "rookie",
        overlay_metric: "option_amount_year_4",
        overlay_year: "2026",
        overlay_lower: "1",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Rookie Scale Amounts"
      assert_includes response.body, "Option Year 4 Amount"
      assert_includes response.body, "Pick 1"
      assert_includes response.body, "Pick scale detail"
      assert_includes response.body, "Year 1 Salary"
      assert_includes response.body, "border-amber-500/70"
      assert_includes response.body, "Source table: pcms.rookie_scale_amounts"
      assert_not_includes response.body, "Tax step interpretation"
    end
  end

  test "system values refresh endpoint returns ordered multi-region sse patches" do
    with_fake_connection do
      get "/tools/system-values/sse/refresh", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2024",
        to_year: "2026",
        overlay_section: "tax",
        overlay_metric: "tax_rate_non_repeater",
        overlay_year: "2026",
        overlay_lower: "5000000",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, "selector #commandbar"
      assert_includes response.body, "selector #maincanvas"
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Tax step interpretation"
      assert_includes response.body, "event: datastar-patch-signals"
      assert_includes response.body, '"svoverlaysection":"tax"'
      assert_includes response.body, '"svoverlaymetric":"tax_rate_non_repeater"'
      assert_includes response.body, '"svyear":"2026"'
    end
  end

  test "system values refresh preserves minimum overlay when yos row remains in range" do
    with_fake_connection do
      get "/tools/system-values/sse/refresh", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2025",
        to_year: "2026",
        overlay_section: "minimum",
        overlay_metric: "minimum_salary_amount",
        overlay_year: "2026",
        overlay_lower: "1",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, 'Source table: pcms.league_salary_scales'
      assert_includes response.body, '"svoverlaysection":"minimum"'
      assert_includes response.body, '"svoverlaymetric":"minimum_salary_amount"'
      assert_includes response.body, '"svoverlayyear":"2026"'
      assert_includes response.body, '"svoverlaylower":"1"'
    end
  end

  test "system values refresh clears minimum overlay state when focused row is out of range" do
    with_fake_connection do
      get "/tools/system-values/sse/refresh", params: {
        year: "2026",
        baseline_year: "2025",
        from_year: "2025",
        to_year: "2026",
        overlay_section: "minimum",
        overlay_metric: "minimum_salary_amount",
        overlay_year: "2024",
        overlay_lower: "1",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-overlay"></div>'
      assert_includes response.body, '"svoverlaysection":""'
      assert_includes response.body, '"svoverlaymetric":""'
      assert_includes response.body, '"svoverlayyear":""'
      assert_includes response.body, '"svoverlaylower":""'
    end
  end

  test "system values refresh preserves rookie overlay metric when pick row remains in range" do
    with_fake_connection do
      get "/tools/system-values/sse/refresh", params: {
        year: "2026",
        baseline_year: "2024",
        from_year: "2025",
        to_year: "2026",
        overlay_section: "rookie",
        overlay_metric: "option_pct_year_4",
        overlay_year: "2026",
        overlay_lower: "1",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, 'Option Year 4 %'
      assert_includes response.body, 'Source table: pcms.rookie_scale_amounts'
      assert_includes response.body, '"svoverlaysection":"rookie"'
      assert_includes response.body, '"svoverlaymetric":"option_pct_year_4"'
      assert_includes response.body, '"svoverlayyear":"2026"'
      assert_includes response.body, '"svoverlaylower":"1"'
    end
  end

  test "system values refresh clears rookie overlay state when focused pick row is out of range" do
    with_fake_connection do
      get "/tools/system-values/sse/refresh", params: {
        year: "2026",
        baseline_year: "2025",
        from_year: "2025",
        to_year: "2026",
        overlay_section: "rookie",
        overlay_metric: "salary_year_1",
        overlay_year: "2024",
        overlay_lower: "1",
        overlay_upper: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-overlay"></div>'
      assert_includes response.body, '"svoverlaysection":""'
      assert_includes response.body, '"svoverlaymetric":""'
      assert_includes response.body, '"svoverlayyear":""'
      assert_includes response.body, '"svoverlaylower":""'
    end
  end

  private

  def with_fake_connection
    fake_connection = FakeConnection.new
    singleton = class << ActiveRecord::Base; self; end

    singleton.alias_method :__test_original_connection__, :connection
    singleton.define_method(:connection) { fake_connection }

    yield
  ensure
    if singleton.method_defined?(:__test_original_connection__)
      singleton.alias_method :connection, :__test_original_connection__
      singleton.remove_method :__test_original_connection__
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
