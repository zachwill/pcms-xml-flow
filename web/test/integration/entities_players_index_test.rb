require "test_helper"

class EntitiesPlayersIndexTest < ActionDispatch::IntegrationTest
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
      if sql.include?("FROM pcms.teams") && sql.include?("team_name NOT LIKE 'Non-NBA%'")
        ActiveRecord::Result.new(
          [ "team_code", "team_name" ],
          [
            [ "BOS", "Boston Celtics" ],
            [ "POR", "Portland Trail Blazers" ]
          ]
        )
      elsif sql.include?("FROM pcms.salary_book_warehouse sbw") && sql.include?("WHERE sbw.player_id = 1")
        ActiveRecord::Result.new(
          [
            "player_id", "player_name", "team_code", "team_id", "team_name",
            "agent_id", "agent_name", "is_two_way", "is_trade_restricted_now", "is_no_trade",
            "cap_2025", "cap_2026", "cap_2027", "total_salary_from_2025",
            "years_of_service", "player_status_lk", "player_status_name"
          ],
          [
            [ 1, "Alpha Guard", "POR", 1610612757, "Portland Trail Blazers", 1001, "Rich Agent", false, true, false, 25000000, 26000000, 27000000, 50000000, 5, "ACTIVE", "Active" ]
          ]
        )
      elsif sql.include?("FROM pcms.salary_book_warehouse sbw")
        ActiveRecord::Result.new(
          [
            "player_id", "player_name", "team_code", "team_id", "team_name",
            "agent_id", "agent_name", "is_two_way", "is_trade_restricted_now", "is_no_trade",
            "cap_2025", "total_salary_from_2025", "years_of_service", "player_status_lk", "player_status_name"
          ],
          [
            [ 1, "Alpha Guard", "POR", 1610612757, "Portland Trail Blazers", 1001, "Rich Agent", false, true, false, 25000000, 50000000, 5, "ACTIVE", "Active" ],
            [ 2, "Beta Wing", "BOS", 1610612738, "Boston Celtics", 1002, "Dana Agent", true, false, false, 9500000, 28000000, 2, "ACTIVE", "Active" ]
          ]
        )
      else
        ActiveRecord::Result.new([], [])
      end
    end
  end

  setup do
    host! "localhost"
  end

  test "players index renders workbench commandbar and sidebar base" do
    with_fake_connection do
      get "/players", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="players-search-input"'
      assert_includes response.body, 'id="maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
    end
  end

  test "players refresh uses one sse response for multi-region patches" do
    with_fake_connection do
      get "/players/sse/refresh", params: {
        q: "",
        team: "ALL",
        status: "all",
        sort: "cap_desc"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, "id=\"maincanvas\""
      assert_includes response.body, "id=\"rightpanel-base\""
      assert_includes response.body, "id=\"rightpanel-overlay\""
      assert_includes response.body, "event: datastar-patch-signals"
    end
  end

  test "players sidebar returns overlay and clear endpoint empties overlay" do
    with_fake_connection do
      get "/players/sidebar/1", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "/players/1"

      get "/players/sidebar/clear", headers: modern_headers

      assert_response :success
      assert_equal '<div id="rightpanel-overlay"></div>', response.body.strip
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
