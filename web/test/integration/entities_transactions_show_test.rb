require "test_helper"

class EntitiesTransactionsShowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    host! "localhost"
  end

  test "transaction show renders causal timeline lanes with team/player/trade pivots" do
    with_stubbed_transaction_show do
      get "/transactions/700001", headers: modern_headers

      assert_response :success

      timeline = section_fragment(response.body, "timeline")
      trade_context = section_fragment(response.body, "trade-context")

      assert timeline.present?
      assert trade_context.present?

      assert_no_match(/<table/i, timeline)
      assert_no_match(/<table/i, trade_context)

      assert_includes timeline, "id=\"causal-timeline\""
      assert_includes timeline, "Causal timeline"
      assert_includes timeline, "Phase filters"
      assert_includes timeline, "Facts"
      assert_includes timeline, "Parties"
      assert_includes timeline, "Ledger"
      assert_includes timeline, "Artifacts"
      assert_includes timeline, "1 · Transaction facts"
      assert_includes timeline, "2 · Parties + routing"
      assert_includes timeline, "3 · Ledger deltas"
      assert_includes timeline, "4 · Cap artifacts"
      assert_includes timeline, "Show raw rows"
      assert_includes timeline, "Raw transaction row"
      assert_includes timeline, "Raw party row"
      assert_includes timeline, "Raw ledger row"
      assert_includes timeline, "Raw budget row"
      assert_includes timeline, "Cap Δ"
      assert_includes timeline, "Tax Δ"
      assert_includes timeline, "Apron Δ"
      assert_includes timeline, "Exception usage"
      assert_includes timeline, "Dead money"
      assert_includes timeline, "Budget snapshot"

      assert_match(/data-signals="\{ timelinephase: 'all',/, timeline)
      assert_match(/data-show="\$timelinephase === 'all' \|\| \$timelinephase === 'facts'"/, timeline)
      assert_match(/data-show="\$timelinephase === 'all' \|\| \$timelinephase === 'parties'"/, timeline)
      assert_match(/data-show="\$timelinephase === 'all' \|\| \$timelinephase === 'ledger'"/, timeline)
      assert_match(/data-show="\$timelinephase === 'all' \|\| \$timelinephase === 'artifacts'"/, timeline)

      assert_match(%r{href="/players/101"}, timeline)
      assert_match(%r{href="/teams/}, timeline)
      assert_match(%r{href="/trades/9001"}, timeline)
      assert_match(%r{href="/transactions/700001"}, timeline)

      assert_includes trade_context, "Other transactions in this trade"
      assert_match(%r{href="/transactions/700002"}, trade_context)

      assert_includes response.body, "Route POR → BOS"
      assert_includes response.body, "Linked trade"
    end
  end

  test "transaction show seeds timeline phase from query and normalizes invalid values" do
    with_stubbed_transaction_show do
      get "/transactions/700001?phase=ledger", headers: modern_headers

      assert_response :success
      timeline = section_fragment(response.body, "timeline")
      assert timeline.present?
      assert_match(/data-signals="\{ timelinephase: 'ledger',/, timeline)

      get "/transactions/700001?phase=not-a-phase", headers: modern_headers

      assert_response :success
      timeline = section_fragment(response.body, "timeline")
      assert timeline.present?
      assert_match(/data-signals="\{ timelinephase: 'all',/, timeline)
    end
  end

  private

  def section_fragment(body, section_id)
    body[/<section id="#{Regexp.escape(section_id)}"[\s\S]*?<\/section>/]
  end

  def with_stubbed_transaction_show
    controller_class = Entities::TransactionsController

    controller_class.class_eval do
      alias_method :__transactions_show_test_original_show__, :show

      define_method :show do
        @transaction = {
          "transaction_id" => 700_001,
          "transaction_date" => Date.new(2025, 7, 6),
          "transaction_type_lk" => "SIGN",
          "transaction_description_lk" => "Taxpayer mid-level signing",
          "trade_id" => 9_001,
          "player_id" => 101,
          "player_name" => "Flow Guard",
          "from_team_id" => 1_610_612_757,
          "from_team_code" => "POR",
          "from_team_name" => "Portland Trail Blazers",
          "to_team_id" => 1_610_612_738,
          "to_team_code" => "BOS",
          "to_team_name" => "Boston Celtics",
          "rights_team_id" => nil,
          "rights_team_code" => nil,
          "rights_team_name" => nil,
          "sign_and_trade_team_id" => nil,
          "sign_and_trade_team_code" => nil,
          "sign_and_trade_team_name" => nil
        }

        @ledger_entries = [
          {
            "transaction_ledger_entry_id" => 1,
            "ledger_date" => "2025-07-06",
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "team_name" => "Portland Trail Blazers",
            "transaction_type_lk" => "SIGN",
            "transaction_description_lk" => "Outgoing cap room",
            "cap_change" => -4_500_000,
            "tax_change" => -2_000_000,
            "apron_change" => -1_500_000,
            "mts_change" => -300_000
          },
          {
            "transaction_ledger_entry_id" => 2,
            "ledger_date" => "2025-07-06",
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "team_name" => "Boston Celtics",
            "transaction_type_lk" => "SIGN",
            "transaction_description_lk" => "Incoming contract",
            "cap_change" => 4_500_000,
            "tax_change" => 3_200_000,
            "apron_change" => 1_500_000,
            "mts_change" => 450_000
          }
        ]

        @draft_selection = {
          "draft_round" => 2,
          "pick_number" => 44
        }

        @trade = {
          "trade_id" => 9_001,
          "team_count" => 2,
          "player_line_item_count" => 3,
          "pick_line_item_count" => 1
        }

        @trade_transactions = [
          {
            "transaction_id" => 700_002,
            "transaction_date" => Date.new(2025, 7, 6),
            "transaction_type_lk" => "WAIVE",
            "transaction_description_lk" => "Salary matching cleanup",
            "player_id" => 102,
            "player_name" => "Depth Wing",
            "from_team_code" => "BOS",
            "to_team_code" => "POR"
          }
        ]

        @endnotes = [
          {
            "endnote_id" => 44,
            "status_lk" => "ACTIVE",
            "explanation" => "Conditional top-45 protection on outbound second-round pick.",
            "conveyance_text" => nil,
            "protections_text" => nil,
            "is_swap" => false,
            "is_conditional" => true
          }
        ]

        @cap_exception_usage_rows = [
          {
            "effective_date" => "2025-07-06",
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "exception_type_lk" => "TMLE",
            "exception_type_label" => "Taxpayer Mid-Level Exception",
            "change_amount" => -4_500_000,
            "remaining_exception_amount" => 7_200_000
          }
        ]

        @cap_dead_money_rows = [
          {
            "salary_year" => 2026,
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "cap_value" => 1_000_000,
            "tax_value" => 1_250_000,
            "apron_value" => 1_000_000
          }
        ]

        @cap_budget_snapshot_rows = [
          {
            "salary_year" => 2025,
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "budget_group_lk" => "ROSTER",
            "budget_group_label" => "Rostered salaries",
            "cap_amount" => 4_500_000,
            "tax_amount" => 6_200_000,
            "apron_amount" => 4_500_000
          }
        ]

        render :show, layout: false
      end
    end

    yield
  ensure
    controller_class.class_eval do
      if method_defined?(:__transactions_show_test_original_show__)
        alias_method :show, :__transactions_show_test_original_show__
        remove_method :__transactions_show_test_original_show__
      end
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
