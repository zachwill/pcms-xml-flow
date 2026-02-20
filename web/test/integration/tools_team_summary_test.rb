require "test_helper"

class ToolsTeamSummaryTest < ActionDispatch::IntegrationTest
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
      if sql.include?("FROM pcms.team_salary_warehouse tsw") && sql.include?("JOIN pcms.teams t")
        rows = sample_rows

        if (year_match = sql.match(/tsw\.salary_year\s*=\s*(\d{4})/))
          rows = rows.select { |row| row[4].to_i == year_match[1].to_i }
        end

        if (conference_match = sql.match(/t\.conference_name\s*=\s*'([^']+)'/))
          rows = rows.select { |row| row[3].to_s == conference_match[1].to_s }
        end

        rows = rows.select { |row| row[15].to_f < 0 } if sql.match?(/WHERE[\s\S]*COALESCE\(tsw\.room_under_tax, 0\) < 0/)
        rows = rows.select { |row| row[16].to_f < 0 } if sql.match?(/WHERE[\s\S]*COALESCE\(tsw\.room_under_apron1, 0\) < 0/)
        rows = rows.select { |row| row[17].to_f < 0 } if sql.match?(/WHERE[\s\S]*COALESCE\(tsw\.room_under_apron2, 0\) < 0/)

        if sql.include?("tsw.team_code IN (")
          codes = sql.scan(/'([A-Z]{3})'/).flatten
          rows = rows.select { |row| codes.include?(row[0]) }
        end

        return ActiveRecord::Result.new(columns, rows)
      end

      ActiveRecord::Result.new([], [])
    end

    private

    def columns
      [
        "team_code", "team_name", "team_id", "conference_name", "salary_year",
        "cap_total", "cap_total_hold", "tax_total", "apron_total",
        "salary_cap_amount", "tax_level_amount", "tax_apron_amount", "tax_apron2_amount",
        "cap_space", "tax_overage", "room_under_tax", "room_under_apron1", "room_under_apron2",
        "is_taxpayer", "is_repeater_taxpayer", "is_subject_to_apron", "apron_level_lk",
        "roster_row_count", "two_way_row_count", "pressure_bucket", "pressure_rank", "luxury_tax_owed", "refreshed_at"
      ]
    end

    def sample_rows
      [
        [
          "BOS", "Boston Celtics", 1610612738, "Eastern", 2025,
          196_000_000, 197_000_000, 214_000_000, 214_000_000,
          141_000_000, 172_000_000, 179_000_000, 190_000_000,
          -56_000_000, 42_000_000, -42_000_000, -35_000_000, -24_000_000,
          true, true, true, "APRON2",
          15, 2, "over_apron2", 4, 84_000_000, Time.current
        ],
        [
          "POR", "Portland Trail Blazers", 1610612757, "Western", 2025,
          129_000_000, 130_000_000, 133_000_000, 133_000_000,
          141_000_000, 172_000_000, 179_000_000, 190_000_000,
          11_000_000, -39_000_000, 39_000_000, 46_000_000, 57_000_000,
          false, false, false, "NONE",
          14, 3, "under_cap", 0, 0, Time.current
        ],
        [
          "LAL", "Los Angeles Lakers", 1610612747, "Western", 2025,
          170_000_000, 171_000_000, 178_000_000, 178_000_000,
          141_000_000, 172_000_000, 179_000_000, 190_000_000,
          -30_000_000, 6_000_000, -6_000_000, 1_000_000, 12_000_000,
          true, false, true, "APRON1",
          15, 1, "over_apron1", 3, 14_000_000, Time.current
        ]
      ]
    end
  end

  setup do
    host! "localhost"
  end

  test "team summary renders sorting-first workspace and sidebar summary" do
    with_fake_connection do
      get "/team-summary", params: { selected: "BOS" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Workspace snapshot"
      assert_includes response.body, "Pressure board"
      assert_includes response.body, "Pressure First"
      assert_not_includes response.body, "Slot A"
      assert_not_includes response.body, 'id="team-summary-compare-strip"'
    end
  end

  test "team summary sidebar endpoint returns drill-in overlay with pressure signals" do
    with_fake_connection do
      get "/team-summary/sidebar/BOS", params: {
        year: "2025",
        conference: "all",
        pressure: "all",
        sort: "pressure_desc",
        selected: "BOS"
      }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Pressure signals"
      assert_includes response.body, "Open Salary Book at BOS"
    end
  end

  test "team summary overlay exposes next and prev stepping controls" do
    with_fake_connection do
      get "/team-summary/sidebar/LAL", params: {
        year: "2025",
        conference: "all",
        pressure: "all",
        sort: "team_asc",
        selected: "LAL"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, "Browse in current view"
      assert_includes response.body, "3 / 3"
      assert_includes response.body, "data-team-summary-step-prev"
      assert_includes response.body, "data-team-summary-step-next"
      assert_includes response.body, "/team-summary/sse/step?"
      assert_includes response.body, "direction=prev"
      assert_includes response.body, "direction=next"
      assert_includes response.body, "$tsyear"
      assert_includes response.body, "$tspressure"
      assert_includes response.body, "$tssortmetric"
      assert_not_includes response.body, "compare_a="
      assert_not_includes response.body, "compare_b="
    end
  end

  test "team summary commandbar includes conference and sorting controls" do
    with_fake_connection do
      get "/team-summary", headers: modern_headers

      assert_response :success
      assert_includes response.body, "name=\"conference_east\""
      assert_includes response.body, "name=\"conference_west\""
      assert_includes response.body, "name=\"sort_metric\""
      assert_includes response.body, "Pressure First"
      assert_includes response.body, "/team-summary/sse/refresh?"
      assert_includes response.body, "/team-summary/sidebar/"
    end
  end

  test "team summary refresh endpoint returns ordered multi-region sse patches" do
    with_fake_connection do
      get "/team-summary/sse/refresh", params: {
        year: "2025",
        conference: "all",
        pressure: "all",
        sort: "pressure_desc",
        selected: "BOS"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, "selector #maincanvas"
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_not_includes response.body, "team-summary-compare-strip"
      assert_includes response.body, "event: datastar-patch-signals"
      assert_includes response.body, '"selectedteam":"BOS"'
      assert_includes response.body, '"tssortmetric":"pressure"'
    end
  end

  test "team summary step endpoint advances overlay selection in current ordering" do
    with_fake_connection do
      get "/team-summary/sse/step", params: {
        year: "2025",
        conference: "all",
        pressure: "all",
        sort: "team_asc",
        selected: "BOS",
        direction: "next"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Portland Trail Blazers"
      assert_includes response.body, "event: datastar-patch-signals"
      assert_includes response.body, '"selectedteam":"POR"'
      assert_includes response.body, '"tssortmetric":"team"'
      assert_includes response.body, '"tssortasc":false'
      assert_includes response.body, '"tsconferenceeast":true'
      assert_includes response.body, '"tsconferencewest":true'
    end
  end

  test "legacy compare endpoint is no longer routable" do
    with_fake_connection do
      get "/team-summary/sse/compare", headers: modern_headers

      assert_response :not_found
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
