require "test_helper"

class SalaryBookComboboxTest < ActionDispatch::IntegrationTest
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
      return ActiveRecord::Result.new([], []) unless sql.include?("FROM pcms.salary_book_warehouse sbw")

      if sql.include?("ILIKE '%Nope%'")
        return ActiveRecord::Result.new([], [])
      end

      columns = %w[player_id player_name team_code agent_name age years_of_service cap_2025 is_two_way team_id]
      rows = [
        [2365, "Anfernee Simons", "POR", "Rich Paul", 26.1, 7, 25_892_857, false, 1_610_612_757],
        [1630542, "Shaedon Sharpe", "POR", "No agent", 22.4, 3, 6_346_680, false, 1_610_612_757]
      ]

      ActiveRecord::Result.new(columns, rows)
    end
  end

  setup do
    host! "localhost"
  end

  test "player combobox search returns popup fragment for global search" do
    with_fake_connection do
      get "/tools/salary-book/combobox/players/search", params: {
        q: "sim",
        limit: "12",
        seq: "7"
      }, headers: modern_headers

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_includes response.body, 'id="sbplayercb-popup"'
      assert_includes response.body, 'id="sbplayercb-status"'
      assert_includes response.body, 'id="sbplayercb-list"'
      assert_includes response.body, 'id="sbplayercb-option-0"'
      assert_includes response.body, 'data-seq="7"'
      assert_includes response.body, "Anfernee Simons"
    end
  end

  test "blank query defaults to active team roster" do
    with_fake_connection do
      get "/tools/salary-book/combobox/players/search", params: {
        team: "POR",
        q: "",
        limit: "12",
        seq: "3"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="sbplayercb-popup"'
      assert_includes response.body, 'id="sbplayercb-option-0"'
      assert_includes response.body, "team: POR"
      assert_includes response.body, "Anfernee Simons"
    end
  end

  test "blank query without team returns prompt state" do
    with_fake_connection do
      get "/tools/salary-book/combobox/players/search", params: {
        q: "",
        limit: "12",
        seq: "5"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="sbplayercb-popup"'
      assert_includes response.body, "Type to search players"
      assert_not_includes response.body, 'id="sbplayercb-option-0"'
    end
  end

  test "player combobox search returns empty state" do
    with_fake_connection do
      get "/tools/salary-book/combobox/players/search", params: {
        team: "POR",
        q: "Nope",
        limit: "12",
        seq: "3"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="sbplayercb-popup"'
      assert_includes response.body, "No players found"
    end
  end

  test "salary book page includes command palette root" do
    get "/tools/salary-book", headers: modern_headers

    assert_response :success
    assert_includes response.body, 'id="sbplayercmdk"'
    assert_includes response.body, 'data-combobox-cmdk'
    assert_includes response.body, "?team=' + encodeURIComponent($activeteam || '') + '&q='"
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
