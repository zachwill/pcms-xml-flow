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

        if (match = where_clause.match(/tw\.player_name ILIKE '([^']*)'/))
          pattern = match[1].gsub("''", "'").downcase.delete("%")
          rows = rows.select do |row|
            row["player_name"].to_s.downcase.include?(pattern) || row["player_id"].to_s.include?(pattern)
          end
        end

        rows = rows.sort_by { |row| [row["team_code"], row["player_name"]] }

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

  test "two-way utility renders risk controls and sidebar shell" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        intent: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="commandbar"'
      assert_includes response.body, 'id="two-way-intent-input"'
      assert_includes response.body, 'id="two-way-team-select"'
      assert_includes response.body, "Player intent"
      assert_includes response.body, "Risk lens"
      assert_includes response.body, 'id="maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Compare board"
      assert_includes response.body, ">Pin A</button>"
      assert_includes response.body, ">Pin B</button>"
    end
  end

  test "two-way utility refresh renders compare board risk-source context from compare params" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        compare_a: "1001",
        compare_b: "1002"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '"comparea":"1001"'
      assert_includes response.body, '"compareb":"1002"'
      assert_includes response.body, "Warning Wing vs Critical Prospect delta"
      assert_includes response.body, "Risk source: hard limit · critical threshold posture (≤10 left)."
      assert_includes response.body, "Risk source: hard limit · warning threshold posture (≤20 left)."
      assert_includes response.body, "Signal basis: both players are hard limit."
      assert_includes response.body, "Remaining games (hard-limit)"
      assert_includes response.body, "Signing context"
    end
  end

  test "two-way utility refresh delta flags estimate-aware basis when either slot uses estimates" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        compare_a: "1001",
        compare_b: "1003"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "Estimate Guard vs Critical Prospect delta"
      assert_includes response.body, "Signal basis: Critical Prospect is hard limit; Estimate Guard is estimated limit."
      assert_includes response.body, "Remaining games (estimate-aware)"
      assert_includes response.body, "Risk source: estimated limit · above warning threshold"
    end
  end

  test "two-way utility sidebar endpoint returns player drill-in pivots" do
    with_fake_connection do
      get "/tools/two-way-utility/sidebar/1001", params: { conference: "all", team: "", risk: "all" }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Usage trend"
      assert_includes response.body, "Open player page"
      assert_includes response.body, "Open team page"
      assert_includes response.body, "Open agent page"
      assert_includes response.body, ">Pin A</button>"
      assert_includes response.body, ">Pin B</button>"
      assert_includes response.body, "/tools/two-way-utility/sse/refresh?conference=all&amp;team=&amp;risk=all&amp;intent="
      assert_includes response.body, "compare_action=pin&amp;compare_slot=a&amp;player_id=1001"
      assert_includes response.body, "compare_action=pin&amp;compare_slot=b&amp;player_id=1001"
      assert_includes response.body, "compare_action=clear_slot&amp;compare_slot=a"
      assert_includes response.body, "compare_action=clear_slot&amp;compare_slot=b"
      assert_includes response.body, "$comparea === '1001'"
      assert_includes response.body, "$compareb === '1001'"
    end
  end

  test "two-way utility commandbar refresh keeps selected-id and intent context in request params" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        intent: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, "selected_id="
      assert_includes response.body, "overlaytype === &#39;player&#39; ? $overlayid : &#39;&#39;"
      assert_includes response.body, "compare_a="
      assert_includes response.body, "compare_b="
      assert_includes response.body, "intent="
      assert_includes response.body, "$twintent"
    end
  end

  test "two-way utility refresh applies intent filter and keeps intent highlights in grouped rows" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        intent: "Warning"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="commandbar"'
      assert_includes response.body, "Warning Wing"
      assert_not_includes response.body, "Critical Prospect"
      assert_not_includes response.body, "Estimate Guard"
      assert_includes response.body, "Intent matches"
      assert_includes response.body, "INTENT"
      assert_includes response.body, 'id="two-way-intent-shortlist"'
      assert_includes response.body, "↑/↓ pick · Enter opens overlay"
      assert_includes response.body, "ArrowDown"
      assert_includes response.body, '"twintent":"Warning"'
      assert_includes response.body, '"twintentcursor":"1002"'
      assert_includes response.body, '"twintentcursorindex":0'
    end
  end

  test "two-way utility refresh keeps overlay selection when intent still includes selected row" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        intent: "Warning",
        selected_id: "1002"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, '"overlaytype":"player"'
      assert_includes response.body, '"overlayid":"1002"'
      assert_includes response.body, '"twintent":"Warning"'
    end
  end

  test "two-way utility refresh endpoint returns ordered multi-region sse patches" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "Western",
        team: "POR",
        risk: "critical"
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
      assert_includes response.body, '"twrisk":"critical"'
      assert_includes response.body, '"twintent":""'
      assert_includes response.body, '"twintentcursor":""'
      assert_includes response.body, '"twintentcursorindex":0'
      assert_includes response.body, '"comparea":""'
      assert_includes response.body, '"compareb":""'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
    end
  end

  test "two-way utility compare pin action updates compare slots without losing overlay context" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        selected_id: "1002",
        compare_a: "",
        compare_b: "",
        compare_action: "pin",
        compare_slot: "a",
        player_id: "1001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Critical Prospect"
      assert_includes response.body, '"comparea":"1001"'
      assert_includes response.body, '"compareb":""'
      assert_includes response.body, '"overlaytype":"player"'
      assert_includes response.body, '"overlayid":"1002"'
    end
  end

  test "two-way utility compare clear_slot action keeps selected overlay stable" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "",
        risk: "all",
        selected_id: "1001",
        compare_a: "1001",
        compare_b: "1002",
        compare_action: "clear_slot",
        compare_slot: "a"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '"comparea":""'
      assert_includes response.body, '"compareb":"1002"'
      assert_includes response.body, '"overlaytype":"player"'
      assert_includes response.body, '"overlayid":"1001"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Clear A"
      assert_includes response.body, "Pin B"
    end
  end

  test "two-way utility refresh preserves selected overlay when player remains visible" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
        conference: "all",
        team: "POR",
        risk: "warning",
        selected_id: "1002"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Warning Wing"
      assert_includes response.body, '"overlaytype":"player"'
      assert_includes response.body, '"overlayid":"1002"'
      assert_includes response.body, "Selected"
    end
  end

  test "two-way utility refresh clears selected overlay when player is filtered out" do
    with_fake_connection do
      get "/tools/two-way-utility/sse/refresh", params: {
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
