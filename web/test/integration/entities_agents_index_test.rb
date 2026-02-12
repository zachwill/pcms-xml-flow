require "test_helper"

class EntitiesAgentsIndexTest < ActionDispatch::IntegrationTest
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
      if sql.include?("FROM pcms.agents_warehouse w") && sql.include?("WHERE w.agent_id = 11")
        ActiveRecord::Result.new(agent_overlay_columns, [agent_overlay_row])
      elsif sql.include?("FROM pcms.agents_warehouse w") && sql.include?("WHERE w.agent_id = 99")
        ActiveRecord::Result.new(agent_overlay_columns, [])
      elsif sql.include?("FROM pcms.salary_book_warehouse sbw") && sql.include?("WHERE sbw.agent_id = 11")
        ActiveRecord::Result.new(agent_clients_columns, [agent_client_row])
      elsif sql.include?("FROM pcms.agents_warehouse w")
        rows = sql.include?("COALESCE(w.client_count, 0) > 0") ? [agent_row_secondary] : [agent_row_primary, agent_row_secondary]
        ActiveRecord::Result.new(agent_directory_columns, rows)
      elsif sql.include?("FROM pcms.agencies_warehouse w")
        ActiveRecord::Result.new(agency_directory_columns, [agency_row])
      elsif sql.include?("FROM \"slugs\"")
        slug_columns = sql.include?("\"slugs\".\"entity_id\"") ? ["entity_id", "slug"] : ["slug"]
        ActiveRecord::Result.new(slug_columns, [])
      else
        ActiveRecord::Result.new([], [])
      end
    end

    private

    def agent_directory_columns
      [
        "agent_id", "full_name", "agency_id", "agency_name", "is_active", "is_certified",
        "client_count", "standard_count", "two_way_count", "team_count",
        "book_total", "book_total_percentile", "cap_2025_total", "cap_2026_total", "cap_2027_total", "total_salary_from_2025",
        "max_contract_count", "rookie_scale_count", "min_contract_count",
        "no_trade_count", "trade_kicker_count", "trade_restricted_count",
        "expiring_in_window", "expiring_2025", "expiring_2026", "expiring_2027",
        "player_option_count", "team_option_count",
        "client_count_percentile", "team_count_percentile", "standard_count_percentile", "two_way_count_percentile", "max_contract_count_percentile"
      ]
    end

    def agent_row_primary
      [
        11, "Alpha Agent", 501, "Summit Sports", true, true,
        3, 2, 1, 2,
        45_000_000, 0.88, 45_000_000, 42_000_000, 39_000_000, 126_000_000,
        1, 1, 0,
        1, 0, 1,
        1, 1, 0, 0,
        1, 0,
        0.86, 0.55, 0.7, 0.5, 0.6
      ]
    end

    def agent_row_secondary
      [
        22, "Beta Agent", 777, "Northwest Hoops", true, false,
        1, 1, 0, 1,
        8_500_000, 0.2, 8_500_000, 7_900_000, 0, 16_400_000,
        0, 0, 1,
        0, 0, 0,
        0, 0, 0, 0,
        0, 0,
        0.15, 0.1, 0.2, 0.05, 0.05
      ]
    end

    def agency_directory_columns
      [
        "agency_id", "agency_name", "is_active", "agent_count", "client_count", "standard_count", "two_way_count", "team_count",
        "book_total", "book_total_percentile", "cap_2025_total", "cap_2026_total", "cap_2027_total", "total_salary_from_2025",
        "max_contract_count", "rookie_scale_count", "min_contract_count", "no_trade_count", "trade_kicker_count", "trade_restricted_count",
        "expiring_in_window", "expiring_2025", "expiring_2026", "expiring_2027", "player_option_count", "team_option_count",
        "agent_count_percentile", "client_count_percentile", "max_contract_count_percentile"
      ]
    end

    def agency_row
      [
        501, "Summit Sports", true, 2, 4, 3, 1, 3,
        52_000_000, 0.7, 52_000_000, 48_000_000, 44_000_000, 144_000_000,
        1, 1, 1, 1, 0, 1,
        1, 1, 0, 0, 1, 0,
        0.5, 0.75, 0.4
      ]
    end

    def agent_overlay_columns
      [
        "agent_id", "full_name", "agency_id", "agency_name", "is_active", "is_certified",
        "client_count", "standard_count", "two_way_count", "team_count",
        "cap_2025_total", "cap_2026_total", "cap_2027_total", "total_salary_from_2025",
        "max_contract_count", "rookie_scale_count", "min_contract_count",
        "no_trade_count", "trade_kicker_count", "trade_restricted_count",
        "expiring_2025", "expiring_2026", "expiring_2027",
        "player_option_count", "team_option_count", "prior_year_nba_now_free_agent_count",
        "cap_2025_total_percentile", "cap_2026_total_percentile", "cap_2027_total_percentile",
        "client_count_percentile", "max_contract_count_percentile", "team_count_percentile", "standard_count_percentile", "two_way_count_percentile"
      ]
    end

    def agent_overlay_row
      [
        11, "Alpha Agent", 501, "Summit Sports", true, true,
        3, 2, 1, 2,
        45_000_000, 42_000_000, 39_000_000, 126_000_000,
        1, 1, 0,
        1, 0, 1,
        1, 0, 0,
        1, 0, 0,
        0.86, 0.8, 0.75,
        0.86, 0.6, 0.55, 0.7, 0.5
      ]
    end

    def agent_clients_columns
      [
        "player_id", "player_name", "team_code", "team_id", "team_name",
        "cap_2025", "cap_2026", "cap_2027", "total_salary_from_2025",
        "is_two_way", "is_trade_restricted_now", "is_no_trade", "is_trade_bonus", "is_min_contract",
        "option_2026", "option_2027", "option_2028", "years_of_service"
      ]
    end

    def agent_client_row
      [
        1, "Alpha Guard", "POR", 1_610_612_757, "Portland Trail Blazers",
        24_000_000, 26_000_000, 0, 50_000_000,
        false, false, false, false, false,
        "PO", nil, nil, 5
      ]
    end
  end

  setup do
    host! "localhost"
  end

  test "agents index renders workbench controls and overlay-aware rows" do
    with_fake_connection do
      get "/agents", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="agent-directory-kind-agents"'
      assert_includes response.body, 'id="maincanvas"'
      assert_includes response.body, "$overlaytype === 'agent'"
    end
  end

  test "agents refresh preserves selected overlay when selected row remains visible" do
    with_fake_connection do
      get "/agents/sse/refresh", params: {
        kind: "agents",
        active_only: "0",
        certified_only: "0",
        with_clients: "0",
        with_book: "0",
        with_restrictions: "0",
        with_expiring: "0",
        year: "2025",
        sort: "book",
        dir: "desc",
        selected_type: "agent",
        selected_id: "11"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="agents-maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Open agent page"
      assert_includes response.body, '"overlaytype":"agent"'
      assert_includes response.body, '"overlayid":"11"'
    end
  end

  test "agents refresh clears selected overlay when row no longer matches filters" do
    with_fake_connection do
      get "/agents/sse/refresh", params: {
        kind: "agents",
        active_only: "0",
        certified_only: "0",
        with_clients: "1",
        with_book: "0",
        with_restrictions: "0",
        with_expiring: "0",
        year: "2025",
        sort: "book",
        dir: "desc",
        selected_type: "agent",
        selected_id: "11"
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
