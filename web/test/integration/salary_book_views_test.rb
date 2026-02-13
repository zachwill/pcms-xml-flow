require "test_helper"

class SalaryBookViewsTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  class FakeConnection
    TEAM_ROWS = [
      ["ATL", "Atlanta Hawks", "Eastern", 1],
      ["BOS", "Boston Celtics", "Eastern", 2],
      ["BKN", "Brooklyn Nets", "Eastern", 3],
      ["CHA", "Charlotte Hornets", "Eastern", 4],
      ["CHI", "Chicago Bulls", "Eastern", 5],
      ["CLE", "Cleveland Cavaliers", "Eastern", 6],
      ["DAL", "Dallas Mavericks", "Western", 7],
      ["DEN", "Denver Nuggets", "Western", 8],
      ["DET", "Detroit Pistons", "Eastern", 9],
      ["GSW", "Golden State Warriors", "Western", 10],
      ["HOU", "Houston Rockets", "Western", 11],
      ["IND", "Indiana Pacers", "Eastern", 12],
      ["LAC", "LA Clippers", "Western", 13],
      ["LAL", "Los Angeles Lakers", "Western", 14],
      ["MEM", "Memphis Grizzlies", "Western", 15],
      ["MIA", "Miami Heat", "Eastern", 16],
      ["MIL", "Milwaukee Bucks", "Eastern", 17],
      ["MIN", "Minnesota Timberwolves", "Western", 18],
      ["NOP", "New Orleans Pelicans", "Western", 19],
      ["NYK", "New York Knicks", "Eastern", 20],
      ["OKC", "Oklahoma City Thunder", "Western", 21],
      ["ORL", "Orlando Magic", "Eastern", 22],
      ["PHI", "Philadelphia 76ers", "Eastern", 23],
      ["PHX", "Phoenix Suns", "Western", 24],
      ["POR", "Portland Trail Blazers", "Western", 25],
      ["SAC", "Sacramento Kings", "Western", 26],
      ["SAS", "San Antonio Spurs", "Western", 27],
      ["TOR", "Toronto Raptors", "Eastern", 28],
      ["UTA", "Utah Jazz", "Western", 29],
      ["WAS", "Washington Wizards", "Eastern", 30]
    ].freeze

    STANDINGS_COLUMNS = %w[
      team_code
      team_name
      team_id
      team_tricode
      conference
      conference_rank
      league_rank
      wins
      losses
      win_pct
      record
      l10
      current_streak_text
      conference_games_back
      league_games_back
      diff_pts_per_game
      season_year
      season_label
      standing_date
      lottery_rank
    ].freeze

    STANDINGS_ROWS = [
      ["SAC", "Sacramento Kings", 26, "SAC", "West", 15, 30, 12, 43, 0.218, "12-43", "0-10", "L 13", 29.5, 29.5, -10.2, 2025, "2025-26", Date.new(2026, 2, 12), 1],
      ["WAS", "Washington Wizards", 30, "WAS", "East", 15, 29, 14, 39, 0.264, "14-39", "4-6", "L 3", 26.0, 26.0, -11.0, 2025, "2025-26", Date.new(2026, 2, 12), 2],
      ["POR", "Portland Trail Blazers", 25, "POR", "West", 9, 17, 26, 28, 0.481, "26-28", "4-6", "W 3", 15.0, 15.0, -1.9, 2025, "2025-26", Date.new(2026, 2, 12), 3]
    ].freeze

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
      if sql.include?("FROM pcms.team_salary_warehouse tsw")
        return ActiveRecord::Result.new(%w[team_code team_name conference_name team_id], TEAM_ROWS)
      end

      if sql.include?("FROM nba.standings s")
        return ActiveRecord::Result.new(STANDINGS_COLUMNS, STANDINGS_ROWS)
      end

      # Salary Book player queries can safely return empty rows for these tests.
      if sql.include?("FROM pcms.salary_book_warehouse sbw")
        return ActiveRecord::Result.new([], [])
      end

      ActiveRecord::Result.new([], [])
    end
  end

  setup do
    host! "localhost"
  end

  test "salary book page can boot directly into injuries view" do
    with_fake_connection do
      get "/tools/salary-book", params: { view: "injuries", team: "POR", year: "2025" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, "activeview: 'injuries'"
      assert_includes response.body, 'id="salarybook-team-frame"'
      assert_includes response.body, "salarybook-sand-loader"
      assert_includes response.body, "salarybook-sand-grid"
      assert_includes response.body, 'id="view-injuries"'
      assert_includes response.body, 'value="injuries"'
    end
  end

  test "salary book page can boot directly into tankathon view" do
    with_fake_connection do
      get "/tools/salary-book", params: { view: "tankathon", team: "POR", year: "2025" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, "activeview: 'tankathon'"
      assert_includes response.body, 'id="salarybook-team-frame"'
      assert_includes response.body, 'id="salarybook-standings-table"'
      assert_includes response.body, 'id="view-tankathon"'
      assert_includes response.body, 'value="tankathon"'
      assert_includes response.body, "Tankathon"
      assert_includes response.body, "nba.standings"
    end
  end

  test "injuries frame endpoint returns patchable loading frame" do
    with_fake_connection do
      get "/tools/salary-book/frame", params: { view: "injuries", team: "POR", year: "2025" }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="salarybook-team-frame"'
      assert_includes response.body, "salarybook-sand-loader"
      assert_includes response.body, "salarybook-sand-grid"
      assert_includes response.body, "salarybook-sand-dot-16"
    end
  end

  test "tankathon frame endpoint returns patchable standings frame" do
    with_fake_connection do
      get "/tools/salary-book/frame", params: { view: "tankathon", team: "POR", year: "2025" }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="salarybook-team-frame"'
      assert_includes response.body, 'id="salarybook-standings-table"'
      assert_includes response.body, "Switch to POR"
      assert_includes response.body, "nba.standings"
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
