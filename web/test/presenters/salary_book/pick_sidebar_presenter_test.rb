require "test_helper"

module SalaryBook
  class PickSidebarPresenterTest < ActiveSupport::TestCase
    test "state derives ownership flow, trade history, and source rows" do
      picks = [
        {
          "asset_slot" => 1,
          "sub_asset_slot" => 1,
          "asset_type" => "TO",
          "is_swap" => true,
          "is_conditional" => false,
          "origin_team_code" => "NYK",
          "counterparty_team_codes" => "{LAL}",
          "via_team_codes" => "{PHX}",
          "description" => "2028 first-round pick (top-4 protected)",
          "endnote_explanation" => "Conveys if outside top 4.",
          "endnote_trade_date" => "2024-07-06"
        },
        {
          "asset_slot" => 1,
          "sub_asset_slot" => 2,
          "asset_type" => "TO",
          "is_swap" => false,
          "is_conditional" => true,
          "origin_team_code" => "",
          "counterparty_team_codes" => "{MIA}",
          "via_team_codes" => ["UTA"],
          "description" => "Turns into two seconds if not conveyed",
          "endnote_explanation" => "Roll-over provision.",
          "endnote_trade_date" => "2023-06-30"
        }
      ]

      presenter = SalaryBook::PickSidebarPresenter.new(
        team_code: "BOS",
        year: 2028,
        round: 1,
        salary_year: 2025,
        picks: picks,
        team_meta: { "team_name" => "Boston Celtics", "team_id" => 1610612738 },
        team_meta_by_code: {
          "BOS" => { "team_id" => 1610612738 },
          "NYK" => { "team_id" => 1610612752 },
          "LAL" => { "team_id" => 1610612747 },
          "MIA" => { "team_id" => 1610612748 },
          "PHX" => { "team_id" => 1610612756 },
          "UTA" => { "team_id" => 1610612762 }
        },
        helpers: helper_context
      )

      state = presenter.state

      assert_equal 1, state.fetch(:round_i)
      assert_equal "To", state.fetch(:flow_label)
      assert_equal "Multi", state.fetch(:flow_value)
      assert_equal ["NYK", "LAL", "MIA"], state.fetch(:origin_codes)
      assert_equal ["PHX", "UTA"], state.fetch(:via_codes)
      assert_equal false, state.fetch(:is_own)
      assert_equal true, state.fetch(:is_swap)
      assert_equal true, state.fetch(:is_conditional)
      assert_equal "Traded Away", state.fetch(:status_badge)[:label]
      assert_equal 2, state.fetch(:trade_date_count)
      assert_equal "2 events", state.fetch(:trade_history_summary)

      source_rows = state.fetch(:source_rows)
      assert_equal 2, source_rows.size
      assert_equal "1.1", source_rows.first.fetch(:slot)
      assert_equal "swap", source_rows.first.fetch(:flags_text)
      assert_equal "conditional", source_rows.last.fetch(:flags_text)

      click_expr = presenter.switch_team_onclick("nyk")
      assert_includes click_expr, "team: 'NYK'"
      assert_includes click_expr, "year: '2025'"
    end

    private

    def helper_context
      Class.new do
        include SalaryBookHelper
      end.new
    end
  end
end
