require "test_helper"

class EntitiesTradesShowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    host! "localhost"
  end

  test "trade show renders team-centric out/in board and legal lanes without table scanning" do
    with_stubbed_trade_show do
      get "/trades/9001", headers: modern_headers

      assert_response :success

      leg_breakdown = section_fragment(response.body, "leg-breakdown")
      trade_groups = section_fragment(response.body, "trade-groups")

      assert leg_breakdown.present?
      assert trade_groups.present?

      assert_no_match(/<table/i, leg_breakdown)
      assert_no_match(/<table/i, trade_groups)

      assert_includes leg_breakdown, "Team-centric OUT/IN impact board"
      assert_includes leg_breakdown, "OUT"
      assert_includes leg_breakdown, "IN"
      assert_match(/Net (in|out|balanced)/i, leg_breakdown)
      assert_includes leg_breakdown, "Transaction pivots"

      assert_includes trade_groups, "Trade-group legal lanes"
      assert_includes trade_groups, "Signed method"
      assert_includes trade_groups, "Generated"
      assert_includes trade_groups, "Acquired"
      assert_includes trade_groups, "Team exception registry"

      assert_match(%r{href="/players/101"}, leg_breakdown)
      assert_match(%r{href="/draft-selections"}, leg_breakdown)
      assert_match(%r{href="/transactions/700001"}, leg_breakdown)
      assert_match(%r{href="/teams/}, leg_breakdown)
      assert_match(%r{href="#team-exception-5001"}, trade_groups)
    end
  end

  private

  def section_fragment(body, section_id)
    body[/<section id="#{Regexp.escape(section_id)}"[\s\S]*?<\/section>/]
  end

  def with_stubbed_trade_show
    controller_class = Entities::TradesController

    controller_class.class_eval do
      alias_method :__trades_show_test_original_show__, :show

      define_method :show do
        @trade = {
          "trade_id" => 9001,
          "trade_date" => Date.new(2025, 7, 6),
          "trade_finalized_date" => Date.new(2025, 7, 7),
          "record_status_lk" => "ACTIVE",
          "trade_comments" => "Three-team framework simplified for test coverage."
        }

        @trade_teams = [
          {
            "trade_team_id" => 1,
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "team_name" => "Boston Celtics",
            "seqno" => 1,
            "team_salary_change" => -4_500_000,
            "total_cash_received" => 1_500_000,
            "total_cash_sent" => 0,
            "player_line_item_count" => 1,
            "pick_line_item_count" => 1,
            "tpe_line_item_count" => 1
          },
          {
            "trade_team_id" => 2,
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "team_name" => "Portland Trail Blazers",
            "seqno" => 2,
            "team_salary_change" => 4_500_000,
            "total_cash_received" => 0,
            "total_cash_sent" => 1_500_000,
            "player_line_item_count" => 1,
            "pick_line_item_count" => 1,
            "tpe_line_item_count" => 0
          }
        ]

        @player_details = [
          {
            "trade_team_detail_id" => 11,
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "team_name" => "Boston Celtics",
            "seqno" => 1,
            "group_number" => 1,
            "is_sent" => true,
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "contract_id" => 7,
            "version_number" => 2,
            "is_sign_and_trade" => false,
            "is_trade_bonus" => true,
            "is_no_trade" => false,
            "is_player_consent" => false,
            "is_poison_pill" => false,
            "base_year_amount" => nil,
            "is_base_year" => false,
            "trade_entry_lk" => "PLR"
          },
          {
            "trade_team_detail_id" => 12,
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "team_name" => "Portland Trail Blazers",
            "seqno" => 2,
            "group_number" => 1,
            "is_sent" => false,
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "contract_id" => 7,
            "version_number" => 2,
            "is_sign_and_trade" => false,
            "is_trade_bonus" => false,
            "is_no_trade" => false,
            "is_player_consent" => false,
            "is_poison_pill" => false,
            "base_year_amount" => nil,
            "is_base_year" => false,
            "trade_entry_lk" => "PLR"
          }
        ]

        @pick_details = [
          {
            "trade_team_detail_id" => 21,
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "team_name" => "Boston Celtics",
            "seqno" => 3,
            "group_number" => 1,
            "is_sent" => true,
            "draft_pick_year" => 2028,
            "draft_pick_round" => 1,
            "is_draft_pick_future" => true,
            "is_draft_pick_swap" => false,
            "draft_pick_conditional_lk" => "Top-8 protected",
            "is_draft_year_plus_two" => false,
            "trade_entry_lk" => "PIK"
          },
          {
            "trade_team_detail_id" => 22,
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "team_name" => "Portland Trail Blazers",
            "seqno" => 4,
            "group_number" => 1,
            "is_sent" => false,
            "draft_pick_year" => 2028,
            "draft_pick_round" => 1,
            "is_draft_pick_future" => true,
            "is_draft_pick_swap" => false,
            "draft_pick_conditional_lk" => "Top-8 protected",
            "is_draft_year_plus_two" => false,
            "trade_entry_lk" => "PIK"
          }
        ]

        @cash_details = [
          {
            "trade_team_detail_id" => 31,
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "team_name" => "Portland Trail Blazers",
            "seqno" => 5,
            "group_number" => 1,
            "is_sent" => true,
            "trade_entry_lk" => "CASH",
            "cash_amount" => 1_500_000
          },
          {
            "trade_team_detail_id" => 32,
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "team_name" => "Boston Celtics",
            "seqno" => 6,
            "group_number" => 1,
            "is_sent" => false,
            "trade_entry_lk" => "CASH",
            "cash_amount" => 1_500_000
          }
        ]

        @draft_pick_trades = []

        @transactions = [
          {
            "transaction_id" => 700_001,
            "transaction_date" => Date.new(2025, 7, 6),
            "transaction_type_lk" => "TRADE",
            "transaction_description_lk" => "Primary trade leg",
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "from_team_id" => 1_610_612_738,
            "from_team_code" => "BOS",
            "from_team_name" => "Boston Celtics",
            "to_team_id" => 1_610_612_757,
            "to_team_code" => "POR",
            "to_team_name" => "Portland Trail Blazers",
            "contract_id" => 7,
            "version_number" => 2,
            "signed_method_lk" => "TRADE"
          }
        ]

        @endnotes = []

        @trade_group_rows = [
          {
            "trade_group_id" => 41,
            "trade_group_number" => 1,
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "team_name" => "Boston Celtics",
            "signed_method_lk" => "BIRD",
            "signed_method_label" => "Bird rights",
            "generated_team_exception_id" => 5001,
            "acquired_team_exception_id" => 5002,
            "generated_exception_type_lk" => "TPE",
            "generated_exception_type_label" => "Traded Player Exception",
            "acquired_exception_type_lk" => "ROOM",
            "acquired_exception_type_label" => "Room Exception",
            "trade_group_comments" => "BOS preserved a generated TPE."
          },
          {
            "trade_group_id" => 42,
            "trade_group_number" => 1,
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "team_name" => "Portland Trail Blazers",
            "signed_method_lk" => "CAP",
            "signed_method_label" => "Cap room",
            "generated_team_exception_id" => nil,
            "acquired_team_exception_id" => 5001,
            "generated_exception_type_lk" => nil,
            "generated_exception_type_label" => nil,
            "acquired_exception_type_lk" => "TPE",
            "acquired_exception_type_label" => "Traded Player Exception",
            "trade_group_comments" => "POR absorbed salary into room."
          }
        ]

        @trade_group_exception_rows = [
          {
            "team_exception_id" => 5001,
            "team_id" => 1_610_612_738,
            "team_code" => "BOS",
            "team_name" => "Boston Celtics",
            "salary_year" => 2026,
            "exception_type_lk" => "TPE",
            "exception_type_label" => "Traded Player Exception",
            "original_amount" => 9_000_000,
            "remaining_amount" => 7_200_000,
            "effective_date" => Date.new(2025, 7, 6),
            "expiration_date" => Date.new(2026, 7, 6),
            "trade_id" => 9001
          },
          {
            "team_exception_id" => 5002,
            "team_id" => 1_610_612_757,
            "team_code" => "POR",
            "team_name" => "Portland Trail Blazers",
            "salary_year" => 2026,
            "exception_type_lk" => "ROOM",
            "exception_type_label" => "Room Exception",
            "original_amount" => 8_000_000,
            "remaining_amount" => 6_500_000,
            "effective_date" => Date.new(2025, 7, 6),
            "expiration_date" => Date.new(2026, 7, 6),
            "trade_id" => 9001
          }
        ]

        render :show, layout: false
      end
    end

    yield
  ensure
    controller_class.class_eval do
      if method_defined?(:__trades_show_test_original_show__)
        alias_method :show, :__trades_show_test_original_show__
        remove_method :__trades_show_test_original_show__
      end
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
