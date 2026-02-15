require "test_helper"

class SalaryBookQueriesTest < ActiveSupport::TestCase
  class FakeConnection
    attr_reader :queries

    def initialize(results)
      @results = results
      @queries = []
    end

    def quote(value)
      value.is_a?(Numeric) ? value.to_s : "'#{value}'"
    end

    def exec_query(sql)
      @queries << sql
      @results.shift || ActiveRecord::Result.new([], [])
    end
  end

  test "team_index_rows executes team warehouse query and returns rows" do
    result = ActiveRecord::Result.new(
      %w[team_code team_name conference_name team_id],
      [["POR", "Portland Trail Blazers", "Western", 25]]
    )
    connection = FakeConnection.new([result])

    queries = SalaryBookQueries.new(connection:)
    rows = queries.team_index_rows(2025)

    assert_equal 1, rows.length
    assert_equal "POR", rows.first["team_code"]
    assert_includes connection.queries.first, "FROM pcms.team_salary_warehouse tsw"
    assert_includes connection.queries.first, "WHERE tsw.salary_year = 2025"
  end

  test "tankathon_payload returns row list and metadata keys" do
    result = ActiveRecord::Result.new(
      %w[team_code season_year season_label standing_date lottery_rank],
      [["POR", 2025, "2025-26", Date.new(2026, 2, 12), 3]]
    )
    connection = FakeConnection.new([result])

    queries = SalaryBookQueries.new(connection:)
    payload = queries.tankathon_payload("2025")

    assert_equal "POR", payload[:rows].first["team_code"]
    assert_equal 2025, payload[:season_year]
    assert_equal "2025-26", payload[:season_label]
    assert_equal Date.new(2026, 2, 12), payload[:standing_date]
    assert_includes connection.queries.first, "FROM nba.standings s"
  end
end
