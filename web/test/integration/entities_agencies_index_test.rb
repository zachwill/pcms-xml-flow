require "test_helper"

class EntitiesAgenciesIndexTest < ActionDispatch::IntegrationTest
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
      if sql.include?("FROM pcms.agencies_warehouse w") && sql.include?("WHERE w.agency_id = 501")
        ActiveRecord::Result.new(agency_overlay_columns, [agency_overlay_row])
      elsif sql.include?("FROM pcms.agencies_warehouse w") && sql.include?("WHERE w.agency_id = 777")
        ActiveRecord::Result.new(agency_overlay_columns, [agency_overlay_row_inactive])
      elsif sql.include?("FROM pcms.agents_warehouse w") && sql.include?("WHERE w.agency_id = 501")
        ActiveRecord::Result.new(top_agents_columns, [top_agent_row])
      elsif sql.include?("FROM pcms.agents a") && sql.include?("WHERE a.agency_id = 501")
        ActiveRecord::Result.new(top_clients_columns, [top_client_row])
      elsif sql.include?("FROM pcms.agencies_warehouse w")
        rows = [agency_index_row, agency_index_row_inactive]

        if sql.include?("COALESCE(w.is_active, true) = false")
          rows = rows.select { |row| row[2] == false }
        elsif sql.include?("COALESCE(w.is_active, true) = true")
          rows = rows.select { |row| row[2] == true }
        end

        if sql.match?(/COALESCE\(w\.cap_\d{4}_total, 0\) > 0/)
          rows = rows.select { |row| row[8].to_i.positive? }
        end

        if sql.include?("(COALESCE(w.no_trade_count, 0) + COALESCE(w.trade_kicker_count, 0) + COALESCE(w.trade_restricted_count, 0)) > 0")
          rows = rows.select { |row| (row[17].to_i + row[18].to_i + row[19].to_i).positive? }
        end

        ActiveRecord::Result.new(agency_index_columns, rows)
      elsif sql.include?("FROM \"slugs\"")
        slug_columns = sql.include?("\"slugs\".\"entity_id\"") ? ["entity_id", "slug"] : ["slug"]
        ActiveRecord::Result.new(slug_columns, [])
      else
        ActiveRecord::Result.new([], [])
      end
    end

    private

    def agency_index_columns
      [
        "agency_id", "agency_name", "is_active",
        "agent_count", "client_count", "standard_count", "two_way_count", "team_count",
        "book_total", "book_total_percentile", "cap_2025_total", "cap_2026_total", "cap_2027_total", "total_salary_from_2025",
        "max_contract_count", "rookie_scale_count", "min_contract_count",
        "no_trade_count", "trade_kicker_count", "trade_restricted_count",
        "expiring_in_window", "expiring_2025", "expiring_2026", "expiring_2027",
        "player_option_count", "team_option_count",
        "agent_count_percentile", "client_count_percentile", "max_contract_count_percentile"
      ]
    end

    def agency_index_row
      [
        501, "Summit Sports", true,
        2, 4, 3, 1, 3,
        52_000_000, 0.7, 52_000_000, 48_000_000, 44_000_000, 144_000_000,
        1, 1, 1,
        1, 0, 1,
        1, 1, 0, 0,
        1, 0,
        0.5, 0.75, 0.4
      ]
    end

    def agency_index_row_inactive
      [
        777, "Dormant Group", false,
        1, 1, 1, 0, 1,
        7_500_000, 0.2, 7_500_000, 0, 0, 7_500_000,
        0, 0, 1,
        0, 0, 0,
        0, 0, 0, 0,
        0, 0,
        0.2, 0.1, 0.05
      ]
    end

    def agency_overlay_columns
      [
        "agency_id", "agency_name", "is_active", "agent_count", "client_count", "standard_count", "two_way_count", "team_count",
        "cap_2025_total", "cap_2026_total", "cap_2027_total", "total_salary_from_2025",
        "max_contract_count", "rookie_scale_count", "min_contract_count",
        "no_trade_count", "trade_kicker_count", "trade_restricted_count",
        "expiring_2025", "expiring_2026", "expiring_2027",
        "player_option_count", "team_option_count", "prior_year_nba_now_free_agent_count",
        "cap_2025_total_percentile", "cap_2026_total_percentile", "cap_2027_total_percentile",
        "client_count_percentile", "max_contract_count_percentile", "agent_count_percentile"
      ]
    end

    def agency_overlay_row
      [
        501, "Summit Sports", true, 2, 4, 3, 1, 3,
        52_000_000, 48_000_000, 44_000_000, 144_000_000,
        1, 1, 1,
        1, 0, 1,
        1, 0, 0,
        1, 0, 0,
        0.7, 0.62, 0.59,
        0.75, 0.4, 0.5
      ]
    end

    def agency_overlay_row_inactive
      [
        777, "Dormant Group", false, 1, 1, 1, 0, 1,
        7_500_000, 0, 0, 7_500_000,
        0, 0, 1,
        0, 0, 0,
        0, 0, 0,
        0, 0, 0,
        0.2, nil, nil,
        0.1, 0.05, 0.2
      ]
    end

    def top_agents_columns
      [
        "agent_id", "full_name", "client_count", "team_count", "cap_2025_total",
        "cap_2025_total_percentile", "client_count_percentile", "max_contract_count", "expiring_2025"
      ]
    end

    def top_agent_row
      [11, "Alpha Agent", 3, 2, 45_000_000, 0.88, 0.86, 1, 1]
    end

    def top_clients_columns
      [
        "player_id", "player_name", "team_code", "team_id", "team_name", "agent_id", "agent_name",
        "cap_2025", "total_salary_from_2025", "is_two_way"
      ]
    end

    def top_client_row
      [1, "Alpha Guard", "POR", 1_610_612_757, "Portland Trail Blazers", 11, "Alpha Agent", 24_000_000, 50_000_000, false]
    end
  end

  setup do
    host! "localhost"
  end

  test "agencies index renders workbench shell with discoverable knobs" do
    with_fake_connection do
      get "/agencies", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="commandbar"'
      assert_includes response.body, 'id="agencies-search-input"'
      assert_includes response.body, 'id="agencies-activity-active"'
      assert_includes response.body, 'id="agencies-activity-inactive_live_book"'
      assert_includes response.body, 'id="agencies-activity-live_book_risk"'
      assert_includes response.body, 'id="agencies-year-2025"'
      assert_includes response.body, 'id="maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
    end
  end

  test "agencies sidebar overlay includes canonical pivots and clear endpoint resets overlay" do
    with_fake_connection do
      get "/agencies/sidebar/501", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Open agency page"
      assert_includes response.body, "/agencies/501"
      assert_includes response.body, "/agents/11"

      get "/agencies/sidebar/clear", headers: modern_headers

      assert_response :success
      assert_equal '<div id="rightpanel-overlay"></div>', response.body.strip
    end
  end

  test "agencies refresh preserves selected overlay when posture lens still includes selected row" do
    with_fake_connection do
      get "/agencies/sse/refresh", params: {
        q: "",
        activity: "live_book_risk",
        year: "2025",
        sort: "book",
        dir: "desc",
        selected_id: "501"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="agencies-maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Open agency page"
      assert_includes response.body, '"overlaytype":"agency"'
      assert_includes response.body, '"overlayid":"501"'
    end
  end

  test "agencies refresh clears selected overlay when selected row no longer matches posture lens" do
    with_fake_connection do
      get "/agencies/sse/refresh", params: {
        q: "",
        activity: "live_book_risk",
        year: "2025",
        sort: "book",
        dir: "desc",
        selected_id: "777"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '<div id="rightpanel-overlay"></div>'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
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
