require "test_helper"

class ToolsTwoWayUtilityTest < ActionDispatch::IntegrationTest
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
      if sql.include?("FROM pcms.two_way_utility_warehouse tw")
        rows = two_way_rows

        if (match = sql.match(/tw\.player_id\s*=\s*'?([0-9]+)'?/))
          rows = rows.select { |row| row["player_id"].to_i == match[1].to_i }
        end

        where_sql = sql.split("WHERE").last.to_s
        where_clause = where_sql.split("ORDER BY").first.to_s

        if (match = where_clause.match(/tw\.conference_name\s*=\s*'([^']+)'/))
          rows = rows.select { |row| row["conference_name"] == match[1] }
        end

        if (match = where_clause.match(/tw\.team_code\s*=\s*'([A-Z]{3})'/))
          rows = rows.select { |row| row["team_code"] == match[1] }
        end

        if where_clause.include?("COALESCE(tw.remaining_active_list_games, 999) <= 10")
          rows = rows.select { |row| row["remaining_active_list_games"].to_i <= 10 }
        elsif where_clause.include?("COALESCE(tw.remaining_active_list_games, 999) <= 20")
          rows = rows.select { |row| row["remaining_active_list_games"].to_i <= 20 }
        elsif where_clause.include?("COALESCE(tw.active_list_games_limit_is_estimate, false) = true")
          rows = rows.select { |row| row["active_list_games_limit_is_estimate"] }
        end

        rows = rows.sort_by { |row| [row["team_code"], row["player_name"]] }
        return to_result(rows)
      end

      if sql.include?("FROM nba.standings s")
        rows = standings_rows

        if (match = sql.match(/IN \(([^\)]+)\)/))
          requested_codes = match[1].scan(/'([A-Z]{3})'/).flatten
          rows = rows.select { |row| requested_codes.include?(row["team_code"]) } if requested_codes.any?
        end

        return to_result(rows)
      end

      if sql.include?("FROM pcms.teams") && sql.include?("conference_name")
        return to_result(team_rows)
      end

      if sql.include?("FROM pcms.team_two_way_capacity")
        return to_result(capacity_rows)
      end

      ActiveRecord::Result.new([], [])
    end

    private

    def to_result(rows)
      return ActiveRecord::Result.new([], []) if rows.empty?

      columns = rows.first.keys
      ActiveRecord::Result.new(columns, rows.map { |row| columns.map { |column| row[column] } })
    end

    def two_way_rows
      @two_way_rows ||= [
        {
          "team_code" => "BOS",
          "team_name" => "Boston Celtics",
          "conference_name" => "Eastern",
          "team_current_contract_count" => 15,
          "team_games_remaining_context" => 28,
          "team_is_under_15_contracts" => false,
          "team_two_way_contract_count" => 2,
          "player_id" => 1001,
          "player_name" => "Critical Prospect",
          "years_of_service" => 1,
          "games_on_active_list" => 40,
          "active_list_games_limit" => 50,
          "remaining_active_list_games" => 10,
          "active_list_games_limit_is_estimate" => false,
          "signing_date" => "2025-09-01",
          "last_game_date_est" => "2026-02-10",
          "age" => 21.4,
          "cap_2025" => 0,
          "cap_2026" => 2_100_000,
          "agent_id" => 501,
          "agent_name" => "Risk Agent",
          "agency_name" => "Risk Agency",
          "is_two_way" => true,
          "is_trade_consent_required_now" => false,
          "is_trade_restricted_now" => false,
          "is_poison_pill" => false,
          "is_no_trade" => false,
          "is_trade_bonus" => false,
          "trade_bonus_percent" => nil,
          "option_2026" => "NONE",
          "is_non_guaranteed_2026" => false,
          "pct_cap_2025" => 0.0
        },
        {
          "team_code" => "POR",
          "team_name" => "Portland Trail Blazers",
          "conference_name" => "Western",
          "team_current_contract_count" => 14,
          "team_games_remaining_context" => 34,
          "team_is_under_15_contracts" => true,
          "team_two_way_contract_count" => 3,
          "player_id" => 1002,
          "player_name" => "Warning Wing",
          "years_of_service" => 2,
          "games_on_active_list" => 33,
          "active_list_games_limit" => 50,
          "remaining_active_list_games" => 17,
          "active_list_games_limit_is_estimate" => false,
          "signing_date" => "2025-10-11",
          "last_game_date_est" => "2026-02-09",
          "age" => 23.0,
          "cap_2025" => 0,
          "cap_2026" => 2_050_000,
          "agent_id" => 502,
          "agent_name" => "Portland Agent",
          "agency_name" => "Northwest Hoops",
          "is_two_way" => true,
          "is_trade_consent_required_now" => false,
          "is_trade_restricted_now" => false,
          "is_poison_pill" => false,
          "is_no_trade" => false,
          "is_trade_bonus" => false,
          "trade_bonus_percent" => nil,
          "option_2026" => "NONE",
          "is_non_guaranteed_2026" => false,
          "pct_cap_2025" => 0.0
        },
        {
          "team_code" => "LAL",
          "team_name" => "Los Angeles Lakers",
          "conference_name" => "Western",
          "team_current_contract_count" => 15,
          "team_games_remaining_context" => 30,
          "team_is_under_15_contracts" => false,
          "team_two_way_contract_count" => 1,
          "player_id" => 1003,
          "player_name" => "Estimate Guard",
          "years_of_service" => 1,
          "games_on_active_list" => 24,
          "active_list_games_limit" => 45,
          "remaining_active_list_games" => 21,
          "active_list_games_limit_is_estimate" => true,
          "signing_date" => "2025-12-03",
          "last_game_date_est" => "2026-02-01",
          "age" => 22.2,
          "cap_2025" => 0,
          "cap_2026" => 1_950_000,
          "agent_id" => 503,
          "agent_name" => "Estimate Agent",
          "agency_name" => "West Court",
          "is_two_way" => true,
          "is_trade_consent_required_now" => false,
          "is_trade_restricted_now" => false,
          "is_poison_pill" => false,
          "is_no_trade" => false,
          "is_trade_bonus" => false,
          "trade_bonus_percent" => nil,
          "option_2026" => "NONE",
          "is_non_guaranteed_2026" => false,
          "pct_cap_2025" => 0.0
        }
      ]
    end

    def standings_rows
      @standings_rows ||= [
        { "team_code" => "BOS", "record" => "41-19" },
        { "team_code" => "POR", "record" => "26-28" },
        { "team_code" => "LAL", "record" => "34-24" }
      ]
    end

    def team_rows
      @team_rows ||= [
        { "team_id" => 1610612738, "team_code" => "BOS", "team_name" => "Boston Celtics", "conference_name" => "Eastern" },
        { "team_id" => 1610612757, "team_code" => "POR", "team_name" => "Portland Trail Blazers", "conference_name" => "Western" },
        { "team_id" => 1610612747, "team_code" => "LAL", "team_name" => "Los Angeles Lakers", "conference_name" => "Western" }
      ]
    end

    def capacity_rows
      @capacity_rows ||= [
        { "team_code" => "BOS", "team_current_contract_count" => 15, "team_games_remaining_context" => 28, "team_is_under_15_contracts" => false },
        { "team_code" => "POR", "team_current_contract_count" => 14, "team_games_remaining_context" => 34, "team_is_under_15_contracts" => true },
        { "team_code" => "LAL", "team_current_contract_count" => 15, "team_games_remaining_context" => 30, "team_is_under_15_contracts" => false }
      ]
    end
  end

  setup do
    host! "localhost"
  end

  test "two-way utility refresh renders team-button commandbar and simplified sidebar" do
    with_fake_connection do
      get "/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="commandbar"'
      assert_includes response.body, "Eastern"
      assert_includes response.body, "Western"
      assert_not_includes response.body, "Scope"
      assert_includes response.body, 'title="Boston Celtics"'
      assert_includes response.body, 'title="Portland Trail Blazers"'
      assert_not_includes response.body, 'id="two-way-intent-input"'
      assert_not_includes response.body, 'id="two-way-team-select"'
      assert_not_includes response.body, "Compare board"
      assert_not_includes response.body, ">Pin A</button>"
      assert_includes response.body, 'id="maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Team pressure"
      assert_includes response.body, "Quick risk queue"
      assert_includes response.body, "41-19"
      assert_includes response.body, "26-28"
    end
  end

  test "two-way utility show uses simplified signal model" do
    with_fake_connection do
      get "/two-way-utility", params: {
        conference: "all",
        team: "",
        risk: "all"
      }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="two-way-utility-workspace"'
      assert_includes response.body, '"twconference":"all"'
      assert_includes response.body, '"twteam":""'
      assert_includes response.body, '"twrisk":"all"'
      assert_not_includes response.body, "twintent"
      assert_not_includes response.body, "comparea"
      assert_not_includes response.body, "compareb"
      assert_not_includes response.body, "Cmd/Ctrl+K"
    end
  end

  test "two-way utility refresh endpoint returns ordered multi-region sse patches" do
    with_fake_connection do
      get "/two-way-utility/sse/refresh", params: {
        conference: "Western",
        team: "POR",
        risk: "warning"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, 'id="commandbar"'
      assert_includes response.body, 'id="maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "event: datastar-patch-signals"
      assert_includes response.body, '"twconference":"Western"'
      assert_includes response.body, '"twteam":"POR"'
      assert_includes response.body, '"twrisk":"warning"'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
      assert_not_includes response.body, "twintent"
      assert_not_includes response.body, "comparea"
      assert_not_includes response.body, "compareb"
    end
  end

  test "two-way utility sidebar endpoint returns player drill-in without compare controls" do
    with_fake_connection do
      get "/two-way-utility/sidebar/1001", params: { conference: "all", team: "", risk: "all" }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Usage trend"
      assert_includes response.body, "Open player page"
      assert_includes response.body, "Open team page"
      assert_includes response.body, "Open agent page"
      assert_not_includes response.body, ">Pin A</button>"
      assert_not_includes response.body, ">Pin B</button>"
      assert_not_includes response.body, "compare_action="
    end
  end

  test "two-way utility team filter scopes rows to selected team" do
    with_fake_connection do
      get "/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "POR",
        risk: "all"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "Warning Wing"
      assert_not_includes response.body, "Critical Prospect"
      assert_not_includes response.body, "Estimate Guard"
      assert_includes response.body, '"twteam":"POR"'
    end
  end

  test "two-way utility refresh preserves and clears overlay selection based on visibility" do
    with_fake_connection do
      get "/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "POR",
        risk: "warning",
        selected_id: "1002"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '"overlaytype":"player"'
      assert_includes response.body, '"overlayid":"1002"'
      assert_includes response.body, "Warning Wing"

      get "/two-way-utility/sse/refresh", params: {
        conference: "Eastern",
        team: "BOS",
        risk: "critical",
        selected_id: "1002"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-overlay"></div>'
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
