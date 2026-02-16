require "test_helper"

module SalaryBook
  class PlayerSidebarPresenterTest < ActiveSupport::TestCase
    test "state computes next decision and status chips" do
      player = {
        "player_id" => 123,
        "player_name" => "Example Player",
        "team_code" => "BOS",
        "team_id" => 1610612738,
        "team_name" => "Boston Celtics",
        "agent_name" => "Agent Name",
        "agent_id" => 55,
        "years_of_service" => 4,
        "is_two_way" => false,
        "cap_2025" => 20_000_000,
        "cap_2026" => 22_000_000,
        "cap_2027" => 0,
        "option_2026" => "PLYR",
        "is_trade_bonus" => true,
        "trade_bonus_percent" => 15,
        "is_no_trade" => true,
        "epm_value" => 3.2,
        "epm_percentile" => 92
      }

      presenter = SalaryBook::PlayerSidebarPresenter.new(player: player, helpers: helper_context)
      state = presenter.state

      assert_equal "PO 26-27", state.fetch(:next_decision_label)
      assert_equal "option_po", state.fetch(:next_decision_variant)
      assert_equal "text-blue-600 dark:text-blue-400", state.fetch(:header_contract_classes)
      assert_equal true, state.fetch(:team_switchable)
      assert_equal true, state.fetch(:epm_has_percentile)

      labels = state.fetch(:status_chips).map { |chip| chip[:label] }
      assert_includes labels, "TK 15%"
      assert_includes labels, "No-Trade"
    end

    private

    def helper_context
      Class.new do
        include SalaryBookHelper
      end.new
    end
  end
end
