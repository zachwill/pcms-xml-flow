require "test_helper"

module SalaryBook
  class AgentSidebarPresenterTest < ActiveSupport::TestCase
    test "state exposes rollup flags and next marker prefers option over non-guaranteed" do
      rollup = {
        "total_count" => 8,
        "standard_count" => 7,
        "two_way_count" => 1,
        "team_count" => 6,
        "no_trade_count" => 1,
        "trade_kicker_count" => 2,
        "trade_restricted_count" => 1,
        "player_option_count" => 2,
        "team_option_count" => 1,
        "prior_year_nba_now_free_agent_count" => 1
      }

      presenter = SalaryBook::AgentSidebarPresenter.new(
        agent: { "agent_id" => 77, "name" => "Rich Paul", "agency_name" => "Klutch" },
        rollup: rollup,
        helpers: helper_context
      )

      state = presenter.state
      assert_equal "RP", state.fetch(:initials)
      assert_equal true, state.fetch(:has_options)
      assert_equal true, state.fetch(:has_restrictions)
      assert_equal true, state.fetch(:has_prior_year_now_fa)

      client = {
        "display_first_name" => "John",
        "display_last_name" => "Doe",
        "is_two_way" => false,
        "cap_2025" => 10_000_000,
        "cap_2026" => 11_000_000,
        "cap_2027" => 12_000_000,
        "cap_2028" => 0,
        "option_2027" => "TEAM",
        "is_non_guaranteed_2027" => true
      }

      marker = presenter.next_contract_marker(client)
      assert_equal "TO 27", marker[:label]
      assert_equal "text-purple-600 dark:text-purple-400", marker[:classes]
      assert_equal "Doe, John", presenter.client_row_name(client)
      assert_equal 33_000_000, presenter.total_contract_value(client)
    end

    private

    def helper_context
      Class.new do
        include SalaryBookHelper
      end.new
    end
  end
end
