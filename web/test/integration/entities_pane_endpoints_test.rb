require "test_helper"

class EntitiesPaneEndpointsTest < ActionDispatch::IntegrationTest
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
      if sql.include?("SELECT DISTINCT draft_year FROM pcms.draft_selections")
        ActiveRecord::Result.new([ "draft_year" ], [ [ 2027 ], [ 2026 ], [ 2025 ] ])
      elsif sql.include?("FROM pcms.teams") && sql.include?("team_name NOT LIKE 'Non-NBA%'")
        ActiveRecord::Result.new(
          [ "team_code", "team_name" ],
          [
            [ "BOS", "Boston Celtics" ],
            [ "POR", "Portland Trail Blazers" ],
            [ "LAL", "Los Angeles Lakers" ]
          ]
        )
      elsif sql.include?("STRING_AGG(v.display_text, '; ' ORDER BY v.asset_slot, v.sub_asset_slot) AS cell_text")
        ActiveRecord::Result.new(
          [
            "team_code", "team_name", "draft_year", "draft_round", "cell_text",
            "has_outgoing", "has_swap", "has_conditional", "has_forfeited", "provenance_trade_count"
          ],
          [
            [ "BOS", "Boston Celtics", 2027, 1, "To POR: top-4 protected", true, false, true, false, 2 ],
            [ "LAL", "Los Angeles Lakers", 2027, 2, "Own", false, true, false, false, 1 ]
          ]
        )
      elsif sql.include?("WITH picks AS") && sql.include?("FROM pcms.vw_draft_pick_assets v")
        ActiveRecord::Result.new(
          [
            "draft_year", "draft_round", "original_team_code", "current_team_code",
            "original_team_name", "current_team_name", "is_swap", "has_conditional",
            "has_forfeited", "protections_summary", "pick_status"
          ],
          [
            [ 2027, 1, "BOS", "POR", "Boston Celtics", "Portland Trail Blazers", false, true, false, "Top-4 protected to POR", "Conditional" ],
            [ 2027, 2, "LAL", "LAL", "Los Angeles Lakers", "Los Angeles Lakers", true, false, false, nil, "Own" ]
          ]
        )
      elsif sql.include?("FROM pcms.draft_selections ds") && sql.include?("WHERE ds.transaction_id = 777001")
        ActiveRecord::Result.new(
          [
            "transaction_id", "draft_year", "draft_round", "pick_number", "player_id",
            "player_name", "drafting_team_id", "drafting_team_code", "drafting_team_name",
            "transaction_date", "trade_id", "transaction_type_lk"
          ],
          [
            [ 777001, 2026, 1, 12, 203507, "Prospect One", 1610612738, "BOS", "Boston Celtics", "2026-06-25", 88001, "DDRFT" ]
          ]
        )
      elsif sql.include?("FROM pcms.draft_selections ds") && sql.include?("WHERE ds.draft_year = 2027") && sql.include?("AND ds.draft_round = 1")
        ActiveRecord::Result.new(
          [ "transaction_id", "player_id", "pick_number", "transaction_date" ],
          [ [ 777001, 203507, 12, "2026-06-25" ] ]
        )
      elsif sql.include?("FROM pcms.draft_selections ds")
        ActiveRecord::Result.new(
          [
            "transaction_id", "draft_year", "draft_round", "pick_number", "player_id",
            "player_name", "drafting_team_id", "drafting_team_code", "drafting_team_name",
            "transaction_date", "trade_id", "transaction_type_lk"
          ],
          [
            [ 777001, 2026, 1, 12, 203507, "Prospect One", 1610612738, "BOS", "Boston Celtics", "2026-06-25", 88001, "DDRFT" ]
          ]
        )
      elsif sql.include?("WITH pick AS") && sql.include?("FROM pcms.vw_draft_pick_assets v")
        ActiveRecord::Result.new(
          [
            "draft_year", "draft_round", "original_team_code", "current_team_code",
            "is_swap", "has_conditional", "has_forfeited", "protections_summary",
            "pick_status", "original_team_name", "current_team_name"
          ],
          [
            [ 2027, 1, "BOS", "POR", false, true, false, "Top-4 protected to POR", "Conditional", "Boston Celtics", "Portland Trail Blazers" ]
          ]
        )
      elsif sql.include?("FROM pcms.vw_draft_pick_assets") && sql.include?("ORDER BY asset_slot, sub_asset_slot")
        ActiveRecord::Result.new(
          [
            "asset_slot", "sub_asset_slot", "asset_type", "display_text", "raw_part",
            "counterparty_team_code", "is_swap", "is_conditional", "is_forfeited",
            "endnote_explanation", "trade_id"
          ],
          [
            [ 1, 1, "TO", "To POR: top-4 protected", "To POR", "POR", false, true, false, "Conveys if outside top four", 88001 ],
            [ 2, 1, "OWN", "Own if not conveyed", "Own", nil, false, false, false, nil, nil ]
          ]
        )
      elsif sql.include?("FROM pcms.draft_pick_trades dpt")
        ActiveRecord::Result.new(
          [
            "id", "trade_id", "trade_date", "from_team_code", "to_team_code",
            "original_team_code", "is_swap", "is_future", "is_conditional", "conditional_type_lk"
          ],
          [
            [ 91001, 88001, "2025-02-07", "BOS", "POR", "BOS", false, true, true, "TOP4" ]
          ]
        )
      elsif sql.include?("WITH filtered_trades AS") && sql.include?("FROM pcms.trades tr")
        rows = if sql.include?("tt.team_code = 'LAL'")
          [
            [ 88002, "2025-01-15", nil, "Three-team balancing move", "LAL, DAL, HOU", 3, 1, 2, 1, 0, 4 ]
          ]
        elsif sql.include?("tt.team_code = 'BOS'")
          [
            [ 88001, "2025-02-07", "2025-02-08", "Deadline consolidation", "BOS, POR, ATL", 3, 2, 1, 1, 1, 5 ]
          ]
        else
          [
            [ 88001, "2025-02-07", "2025-02-08", "Deadline consolidation", "BOS, POR, ATL", 3, 2, 1, 1, 1, 5 ],
            [ 88002, "2025-01-15", nil, "Three-team balancing move", "LAL, DAL, HOU", 3, 1, 2, 1, 0, 4 ]
          ]
        end

        if sql.include?("ranked_trades.player_count >= 2 AND ranked_trades.player_count >= ranked_trades.pick_count + 1")
          rows = rows.select { |row| row[6].to_i >= 2 && row[6].to_i >= row[7].to_i + 1 }
        elsif sql.include?("ranked_trades.pick_count >= 2 AND ranked_trades.pick_count >= ranked_trades.player_count + 1")
          rows = rows.select { |row| row[7].to_i >= 2 && row[7].to_i >= row[6].to_i + 1 }
        elsif sql.include?("ranked_trades.cash_line_count > 0 OR ranked_trades.tpe_line_count > 0")
          rows = rows.select { |row| row[8].to_i.positive? || row[9].to_i.positive? }
        end

        ActiveRecord::Result.new(
          [ "trade_id", "trade_date", "trade_finalized_date", "trade_comments", "teams_involved", "team_count", "player_count", "pick_count", "cash_line_count", "tpe_line_count", "complexity_asset_count" ],
          rows
        )
      elsif sql.include?("FROM pcms.trades tr") && sql.include?("WHERE tr.trade_id = 88001") && sql.include?("AS teams_involved")
        ActiveRecord::Result.new(
          [ "trade_id", "trade_date", "trade_comments", "teams_involved", "team_count", "player_count", "pick_count", "cash_line_count", "tpe_line_count" ],
          [ [ 88001, "2025-02-07", "Deadline consolidation", "BOS, POR, ATL", 3, 2, 1, 1, 1 ] ]
        )
      elsif sql.include?("FROM pcms.trade_teams tt") && sql.include?("AS players_out")
        ActiveRecord::Result.new(
          [ "team_id", "team_code", "team_name", "seqno", "players_out", "players_in", "picks_out", "picks_in", "cash_out", "cash_in", "tpe_out", "tpe_in" ],
          [
            [ 1610612738, "BOS", "Boston Celtics", 1, 1, 1, 1, 0, 2500000, 0, 0, 1 ],
            [ 1610612757, "POR", "Portland Trail Blazers", 2, 1, 1, 0, 1, 0, 2500000, 0, 0 ],
            [ 1610612737, "ATL", "Atlanta Hawks", 3, 0, 0, 0, 0, 0, 0, 1, 0 ]
          ]
        )
      elsif sql.include?("FROM pcms.trade_team_details ttd") && sql.include?("ttd.trade_team_detail_id") && sql.include?("LIMIT 120")
        ActiveRecord::Result.new(
          [ "trade_team_detail_id", "team_code", "team_name", "seqno", "is_sent", "player_id", "player_name", "draft_pick_year", "draft_pick_round", "is_draft_pick_swap", "draft_pick_conditional_lk", "is_draft_year_plus_two", "trade_entry_lk", "cash_amount" ],
          [
            [ 1, "BOS", "Boston Celtics", 1, true, 1629001, "Alpha Guard", nil, nil, false, nil, false, "PLYR", 0 ],
            [ 2, "BOS", "Boston Celtics", 2, true, nil, nil, 2029, 1, false, "TOP4", false, "PICK", 0 ],
            [ 3, "POR", "Portland Trail Blazers", 1, false, 1629002, "Beta Wing", nil, nil, false, nil, false, "PLYR", 0 ],
            [ 4, "POR", "Portland Trail Blazers", 3, false, nil, nil, nil, nil, false, nil, false, "CASH", 2500000 ],
            [ 5, "ATL", "Atlanta Hawks", 1, false, nil, nil, nil, nil, false, nil, false, "TREX", 0 ]
          ]
        )
      elsif sql.include?("FROM pcms.transactions t") && sql.include?("WHERE t.trade_id = 88001") && sql.include?("LIMIT 24")
        ActiveRecord::Result.new(
          [ "transaction_id", "transaction_date", "transaction_type_lk", "player_id", "player_name" ],
          [
            [ 700001, "2025-02-07", "SIGN", 1629001, "Alpha Guard" ],
            [ 700003, "2025-02-07", "WAIVE", 1629002, "Beta Wing" ]
          ]
        )
      elsif sql.include?("WITH filtered_transactions AS") && sql.include?("FROM pcms.transactions t")
        sql_downcase = sql.downcase

        rows = [
          [ 700001, "2025-02-07", "SIGN", "Signed to rest-of-season deal", 88001, 1629001, "Alpha Guard", 1610612737, "ATL", "Atlanta Hawks", 1610612738, "BOS", "Boston Celtics", "MIN", "STD" ],
          [ 700002, "2025-02-06", "WAIVE", "Waived", nil, 1629002, "Beta Wing", 1610612757, "POR", "Portland Trail Blazers", nil, nil, nil, nil, nil ]
        ]

        rows = if sql.include?("(t.from_team_code = 'LAL' OR t.to_team_code = 'LAL')")
          []
        elsif sql.include?("(t.from_team_code = 'BOS' OR t.to_team_code = 'BOS')")
          rows.select { |row| row[8] == "BOS" || row[11] == "BOS" }
        elsif sql.include?("(t.from_team_code = 'POR' OR t.to_team_code = 'POR')")
          rows.select { |row| row[8] == "POR" || row[11] == "POR" }
        else
          rows
        end

        if sql_downcase.include?("%alpha%")
          rows = rows.select { |row| row[6].to_s.downcase.include?("alpha") || row[3].to_s.downcase.include?("alpha") }
        elsif sql_downcase.include?("%beta%")
          rows = rows.select { |row| row[6].to_s.downcase.include?("beta") || row[3].to_s.downcase.include?("beta") }
        elsif sql_downcase.include?("%700001%")
          rows = rows.select { |row| row[0].to_i == 700001 }
        elsif sql_downcase.include?("%boston%")
          rows = rows.select { |row| row[9].to_s.downcase.include?("boston") || row[12].to_s.downcase.include?("boston") }
        end

        ActiveRecord::Result.new(
          [
            "transaction_id", "transaction_date", "transaction_type_lk", "transaction_description_lk", "trade_id",
            "player_id", "player_name", "from_team_id", "from_team_code", "from_team_name",
            "to_team_id", "to_team_code", "to_team_name", "signed_method_lk", "contract_type_lk"
          ],
          rows
        )
      elsif sql.include?("COUNT(*)::integer AS ledger_row_count") && sql.include?("FROM pcms.ledger_entries le")
        ActiveRecord::Result.new(
          [ "ledger_row_count", "cap_change_total", "tax_change_total", "apron_change_total" ],
          [ [ 3, 2500000, -1800000, 1000000 ] ]
        )
      elsif sql.include?("FROM pcms.team_exception_usage teu") && sql.include?("AS exception_usage_count")
        ActiveRecord::Result.new(
          [ "exception_usage_count", "dead_money_count", "budget_snapshot_count" ],
          [ [ 1, 0, 2 ] ]
        )
      elsif sql.include?("GROUP BY tr.trade_id, tr.trade_date") && sql.include?("FROM pcms.trades tr")
        ActiveRecord::Result.new(
          [ "trade_id", "trade_date", "team_count", "player_line_item_count", "pick_line_item_count" ],
          [ [ 88001, "2025-02-07", 3, 2, 1 ] ]
        )
      elsif sql.include?("FROM pcms.transactions t") && sql.include?("WHERE t.transaction_id = 700001")
        ActiveRecord::Result.new(
          [
            "transaction_id", "transaction_date", "transaction_type_lk", "transaction_description_lk", "salary_year", "trade_id",
            "player_id", "player_name", "from_team_id", "from_team_code", "from_team_name",
            "to_team_id", "to_team_code", "to_team_name", "signed_method_lk", "contract_type_lk"
          ],
          [
            [ 700001, "2025-02-07", "SIGN", "Signed to rest-of-season deal", 2025, 88001, 1629001, "Alpha Guard", 1610612737, "ATL", "Atlanta Hawks", 1610612738, "BOS", "Boston Celtics", "MIN", "STD" ]
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

  test "drafts pane responds successfully without double render" do
    with_fake_connection do
      get "/drafts/pane", params: { view: "picks", year: "2027", round: "all", team: "", sort: "risk", lens: "at_risk" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="drafts-results"'
      assert_not_includes response.body, "DoubleRenderError"
    end
  end

  test "drafts index exposes commandbar ownership controls and sidebar base" do
    with_fake_connection do
      get "/drafts", params: { view: "picks", year: "2027", round: "all", team: "", sort: "risk", lens: "at_risk" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="draft-team-select"'
      assert_includes response.body, 'id="draft-year-select"'
      assert_includes response.body, 'id="draft-sort-select-picks"'
      assert_includes response.body, 'id="draft-lens-select"'
      assert_includes response.body, 'id="rightpanel-base"'
    end
  end

  test "drafts grid refresh surfaces ownership risk tiers before drill-in" do
    with_fake_connection do
      get "/drafts/sse/refresh", params: { view: "grid", year: "2027", round: "all", team: "", sort: "risk", lens: "all" }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="drafts-results"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Ownership risk legend"
      assert_includes response.body, "Grid risk tiers"
      assert_includes response.body, "Critical"
      assert_includes response.body, "At risk"
      assert_includes response.body, "R8"
      assert_includes response.body, "R3"
    end
  end

  test "drafts refresh uses one sse response for multi-region patches" do
    with_fake_connection do
      get "/drafts/sse/refresh", params: { view: "picks", year: "2027", round: "all", team: "", sort: "risk", lens: "critical" }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, 'id="drafts-results"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "event: datastar-patch-signals"
      assert_includes response.body, '"draftsort":"risk"'
      assert_includes response.body, '"draftlens":"critical"'
    end
  end

  test "drafts refresh preserves selected pick overlay and normalizes key for grid view" do
    with_fake_connection do
      get "/drafts/sse/refresh", params: {
        view: "grid",
        year: "2027",
        round: "all",
        team: "",
        sort: "provenance",
        lens: "at_risk",
        selected_type: "pick",
        selected_key: "pick-BOS-2027-1"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "Ownership risk legend"
      assert_includes response.body, "Open canonical draft-pick page"
      assert_includes response.body, '"draftsort":"provenance"'
      assert_includes response.body, '"draftlens":"at_risk"'
      assert_includes response.body, '"overlaytype":"pick"'
      assert_includes response.body, '"overlaykey":"grid-BOS-2027-1"'
    end
  end

  test "drafts refresh preserves selected selection overlay when row remains visible" do
    with_fake_connection do
      get "/drafts/sse/refresh", params: {
        view: "selections",
        year: "2026",
        round: "all",
        team: "",
        sort: "risk",
        lens: "at_risk",
        selected_type: "selection",
        selected_key: "selection-777001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "Open canonical draft-selection page"
      assert_includes response.body, '"draftsort":"risk"'
      assert_includes response.body, '"draftlens":"at_risk"'
      assert_includes response.body, '"overlaytype":"selection"'
      assert_includes response.body, '"overlaykey":"selection-777001"'
    end
  end

  test "drafts refresh clears selected overlay when mode is incompatible" do
    with_fake_connection do
      get "/drafts/sse/refresh", params: {
        view: "selections",
        year: "2026",
        round: "all",
        team: "",
        selected_type: "pick",
        selected_key: "pick-BOS-2027-1"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '<div id="rightpanel-overlay"></div>'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlaykey":""'
    end
  end

  test "drafts sidebar pick and selection endpoints return overlays and clear works" do
    with_fake_connection do
      get "/drafts/sidebar/pick", params: { team: "BOS", year: "2027", round: "1" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Open canonical draft-pick page"

      get "/drafts/sidebar/selection/777001", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Open canonical draft-selection page"

      get "/drafts/sidebar/clear", headers: modern_headers

      assert_response :success
      assert_equal '<div id="rightpanel-overlay"></div>', response.body.strip
    end
  end

  test "trades pane responds successfully without double render" do
    with_fake_connection do
      get "/trades/pane", params: { daterange: "season", team: "" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="trades-results"'
      assert_not_includes response.body, "DoubleRenderError"
    end
  end

  test "trades index exposes team, complexity, and composition controls plus sidebar surfaces" do
    with_fake_connection do
      get "/trades", params: { daterange: "season", team: "" }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="trades-team-select"'
      assert_includes response.body, 'id="trades-sort-select"'
      assert_includes response.body, 'id="trades-lens-select"'
      assert_includes response.body, 'id="trades-composition-select"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
    end
  end

  test "trades refresh preserves selected overlay and patches sort/lens/composition signals" do
    with_fake_connection do
      get "/trades/sse/refresh", params: {
        daterange: "season",
        team: "",
        sort: "most_assets",
        lens: "complex",
        composition: "player_heavy",
        selected_type: "trade",
        selected_id: "88001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="trades-results"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Trade #88001"
      assert_includes response.body, '"tradesort":"most_assets"'
      assert_includes response.body, '"tradelens":"complex"'
      assert_includes response.body, '"tradecomposition":"player_heavy"'
      assert_includes response.body, '"overlaytype":"trade"'
      assert_includes response.body, '"overlayid":"88001"'
    end
  end

  test "trades refresh clears selected overlay when row no longer matches filters" do
    with_fake_connection do
      get "/trades/sse/refresh", params: {
        daterange: "season",
        team: "LAL",
        selected_type: "trade",
        selected_id: "88001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '<div id="rightpanel-overlay"></div>'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
    end
  end

  test "trades refresh clears selected overlay when composition filter removes selected row" do
    with_fake_connection do
      get "/trades/sse/refresh", params: {
        daterange: "season",
        composition: "pick_heavy",
        selected_type: "trade",
        selected_id: "88001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '<div id="rightpanel-overlay"></div>'
      assert_includes response.body, '"tradecomposition":"pick_heavy"'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
    end
  end

  test "trades sidebar endpoints return overlay and clear works" do
    with_fake_connection do
      get "/trades/sidebar/88001", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Team anatomy"
      assert_includes response.body, "Open canonical trade page"

      get "/trades/sidebar/clear", headers: modern_headers

      assert_response :success
      assert_equal '<div id="rightpanel-overlay"></div>', response.body.strip
    end
  end

  test "transactions pane responds successfully without double render" do
    with_fake_connection do
      get "/transactions/pane", params: {
        daterange: "season",
        team: "",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "0"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="transactions-results"'
      assert_not_includes response.body, "DoubleRenderError"
    end
  end

  test "transactions index exposes intent search plus filters and sidebar base" do
    with_fake_connection do
      get "/transactions", params: {
        q: "",
        daterange: "season",
        team: "",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "0"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="transactions-search-input"'
      assert_includes response.body, 'id="transactions-team-select"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
    end
  end

  test "transactions refresh uses one sse response for feed, sidebar, and query signals" do
    with_fake_connection do
      get "/transactions/sse/refresh", params: {
        q: "alpha",
        daterange: "season",
        team: "BOS",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "0"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, 'id="transactions-results"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "event: datastar-patch-signals"
      assert_includes response.body, '"txnquery":"alpha"'
      assert_includes response.body, 'title="Matched on: player"'
    end
  end

  test "transactions refresh shows team intent match provenance when team text drives query" do
    with_fake_connection do
      get "/transactions/sse/refresh", params: {
        q: "boston",
        daterange: "season",
        team: "BOS",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "0"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'title="Matched on: team"'
    end
  end

  test "transactions refresh preserves selected overlay when query still matches selected row" do
    with_fake_connection do
      get "/transactions/sse/refresh", params: {
        q: "alpha",
        daterange: "season",
        team: "BOS",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "0",
        selected_type: "transaction",
        selected_id: "700001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, 'id="transactions-results"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, "Transaction #700001"
      assert_includes response.body, '"txnquery":"alpha"'
      assert_includes response.body, '"overlaytype":"transaction"'
      assert_includes response.body, '"overlayid":"700001"'
    end
  end

  test "transactions refresh clears selected overlay when query removes selected row" do
    with_fake_connection do
      get "/transactions/sse/refresh", params: {
        q: "beta",
        daterange: "season",
        team: "BOS",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "0",
        selected_type: "transaction",
        selected_id: "700001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '<div id="rightpanel-overlay"></div>'
      assert_includes response.body, '"txnquery":"beta"'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
    end
  end

  test "transactions sidebar endpoints return overlay and clear works" do
    with_fake_connection do
      get "/transactions/sidebar/700001", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, "Open canonical transaction page"
      assert_includes response.body, "Open trade #88001"

      get "/transactions/sidebar/clear", headers: modern_headers

      assert_response :success
      assert_equal '<div id="rightpanel-overlay"></div>', response.body.strip
    end
  end

  test "trades index safely encodes team signal interpolation" do
    with_fake_connection do
      get "/trades", params: { daterange: "season", team: %q(AAA" onmouseover="X) }, headers: modern_headers

      assert_response :success

      root = css_select("#trades-workspace").first
      refute_nil root
      assert_nil root["onmouseover"]

      signals = root["data-signals"]
      assert_includes signals, "tradedaterange: \"season\""
      assert_includes signals, 'tradeteam: ""'
      assert_includes signals, 'tradesort: "newest"'
      assert_includes signals, 'tradelens: "all"'
      assert_includes signals, 'tradecomposition: "all"'
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
