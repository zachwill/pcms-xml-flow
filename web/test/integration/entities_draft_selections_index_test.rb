require "test_helper"

class EntitiesDraftSelectionsIndexTest < ActionDispatch::IntegrationTest
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
      if sql.include?("SELECT DISTINCT draft_year") && sql.include?("FROM pcms.draft_selections")
        ActiveRecord::Result.new(["draft_year"], [[2026], [2025], [2024]])
      elsif sql.include?("FROM pcms.teams") && sql.include?("team_name NOT LIKE 'Non-NBA%'")
        ActiveRecord::Result.new(
          ["team_code", "team_name"],
          [
            ["BOS", "Boston Celtics"],
            ["POR", "Portland Trail Blazers"]
          ]
        )
      elsif sql.include?("FROM pcms.draft_selections ds") && sql.include?("WHERE ds.transaction_id = 777001")
        ActiveRecord::Result.new(selection_overlay_columns, [selection_overlay_row])
      elsif sql.include?("FROM pcms.salary_book_warehouse sbw") && sql.include?("WHERE sbw.player_id = 203507")
        ActiveRecord::Result.new(
          ["team_code", "team_id", "team_name"],
          [["POR", 1_610_612_757, "Portland Trail Blazers"]]
        )
      elsif sql.include?("FROM pcms.draft_pick_trades dpt") && sql.include?("SELECT\n          dpt.id")
        ActiveRecord::Result.new(
          ["id", "trade_id", "trade_date", "from_team_code", "to_team_code", "original_team_code", "is_swap", "is_future", "is_conditional", "conditional_type_lk"],
          [[91001, 88001, "2025-02-07", "BOS", "POR", "BOS", false, true, true, "TOP4"]]
        )
      elsif sql.include?("WITH selection_rows AS") && sql.include?("LIMIT 260")
        rows = if sql.include?("ds.draft_year = 2025")
          [selection_index_row_secondary]
        else
          [selection_index_row_primary, selection_index_row_trade_active]
        end

        if sql.include?("selection_rows.trade_id IS NOT NULL OR selection_rows.provenance_trade_count > 0")
          rows = rows.select { |row| row[10].present? || row[12].to_i.positive? }
        elsif sql.include?("selection_rows.trade_id IS NOT NULL")
          rows = rows.select { |row| row[10].present? }
        end

        rows = rows.select { |row| row[12].to_i >= 2 } if sql.include?("selection_rows.provenance_trade_count >= 2")

        ActiveRecord::Result.new(selection_index_columns, rows)
      elsif sql.include?("FROM \"slugs\"")
        slug_columns = sql.include?("\"slugs\".\"entity_id\"") ? ["entity_id", "slug"] : ["slug"]
        ActiveRecord::Result.new(slug_columns, [])
      else
        ActiveRecord::Result.new([], [])
      end
    end

    private

    def selection_index_columns
      [
        "transaction_id", "draft_year", "draft_round", "pick_number", "player_id", "player_name",
        "drafting_team_id", "drafting_team_code", "drafting_team_name", "transaction_date", "trade_id",
        "transaction_type_lk", "provenance_trade_count", "has_trade", "provenance_priority_score"
      ]
    end

    def selection_index_row_primary
      [
        777001, 2026, 1, 12, 203507, "Prospect One",
        1_610_612_738, "BOS", "Boston Celtics", "2026-06-25", 88001,
        "DDRFT", 2, 1, 3
      ]
    end

    def selection_index_row_trade_active
      [
        777003, 2026, 2, 35, 203509, "Prospect Three",
        1_610_612_738, "BOS", "Boston Celtics", "2026-06-25", nil,
        "DDRFT", 1, 0, 1
      ]
    end

    def selection_index_row_secondary
      [
        777002, 2025, 2, 40, 203508, "Prospect Two",
        1_610_612_757, "POR", "Portland Trail Blazers", "2025-06-27", nil,
        "DDRFT", 0, 0, 0
      ]
    end

    def selection_overlay_columns
      [
        "transaction_id", "draft_year", "draft_round", "pick_number", "player_id", "player_name",
        "drafting_team_id", "drafting_team_code", "drafting_team_name", "transaction_date", "trade_id",
        "transaction_type_lk", "transaction_description_lk"
      ]
    end

    def selection_overlay_row
      [
        777001, 2026, 1, 12, 203507, "Prospect One",
        1_610_612_738, "BOS", "Boston Celtics", "2026-06-25", 88001,
        "DDRFT", "Drafted"
      ]
    end
  end

  setup do
    host! "localhost"
  end

  test "draft selections index renders workbench shell with provenance severity legend and flex rows" do
    with_fake_connection do
      get "/draft-selections", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="commandbar"'
      assert_includes response.body, 'id="draft-selections-search-input"'
      assert_includes response.body, 'id="draft-selections-year-select"'
      assert_includes response.body, 'id="draft-selections-team-select"'
      assert_includes response.body, 'id="draft-selections-sort-select"'
      assert_includes response.body, 'id="draft-selections-lens-select"'
      assert_includes response.body, 'id="draft-selections-flex-header"'
      assert_includes response.body, "Provenance severity legend"
      assert_includes response.body, "Deep chain"
      assert_includes response.body, "With trade"
      refute_includes response.body, 'entity-table min-w-full text-xs'
      assert_includes response.body, 'id="maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_match(%r{<option value="/draft-selections" selected>Draft Selections</option>}, response.body)
    end
  end

  test "draft selections sidebar overlay includes provenance pivots and clear endpoint resets overlay" do
    with_fake_connection do
      get "/draft-selections/sidebar/777001", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Open draft-selection page"
      assert_includes response.body, "/draft-selections/777001"
      assert_includes response.body, "/transactions/777001"
      assert_includes response.body, "/trades/88001"

      get "/draft-selections/sidebar/clear", headers: modern_headers

      assert_response :success
      assert_equal '<div id="rightpanel-overlay"></div>', response.body.strip
    end
  end

  test "draft selections refresh preserves selected overlay when row remains visible" do
    with_fake_connection do
      get "/draft-selections/sse/refresh", params: {
        q: "",
        year: "2026",
        round: "all",
        team: "",
        sort: "provenance",
        lens: "all",
        selected_id: "777001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="draft-selections-maincanvas"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Open draft-selection page"
      assert_includes response.body, '"draftselectionsort":"provenance"'
      assert_includes response.body, '"draftselectionlens":"all"'
      assert_includes response.body, '"overlaytype":"selection"'
      assert_includes response.body, '"overlayid":"777001"'
    end
  end

  test "draft selections refresh clears selected overlay when row is filtered out" do
    with_fake_connection do
      get "/draft-selections/sse/refresh", params: {
        q: "",
        year: "2025",
        round: "all",
        team: "",
        sort: "trade",
        lens: "with_trade",
        selected_id: "777001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '<div id="rightpanel-overlay"></div>'
      assert_includes response.body, '"draftselectionsort":"trade"'
      assert_includes response.body, '"draftselectionlens":"with_trade"'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
    end
  end

  test "draft selections with-trade lens keeps provenance-active rows without direct trade id" do
    with_fake_connection do
      get "/draft-selections/sse/refresh", params: {
        q: "",
        year: "2026",
        round: "all",
        team: "",
        sort: "provenance",
        lens: "with_trade",
        selected_id: ""
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="draft-selections-flex-header"'
      assert_includes response.body, "Prospect Three"
      assert_includes response.body, "With trade"
      refute_includes response.body, 'entity-table min-w-full text-xs'
      assert_includes response.body, '"draftselectionlens":"with_trade"'
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
