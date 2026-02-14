require "test_helper"

class EntitiesTeamsShowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    host! "localhost"
  end

  test "team bootstrap renders activity, two-way, and apron provenance as causal flow lanes" do
    with_stubbed_team_workspace_data do
      get "/teams/por/sse/bootstrap", headers: modern_headers

      assert_response :success

      activity = section_fragment(response.body, "activity")
      two_way = section_fragment(response.body, "two-way")
      apron = section_fragment(response.body, "apron-provenance")

      assert activity.present?
      assert two_way.present?
      assert apron.present?

      assert_no_match(/<table/i, activity)
      assert_no_match(/<table/i, two_way)
      assert_no_match(/<table/i, apron)

      assert_includes activity, "Event → cap/tax/apron consequence lanes"
      assert_includes activity, "Exception mechanism → remaining runway lanes"
      assert_includes activity, "Hover/focus Txn links to cross-highlight apron rows"
      assert_includes activity, "Txn #7001"
      assert_includes activity, "Cap Δ"
      assert_includes activity, "Apron Δ"
      assert_match(%r{href="/players/101"}, activity)
      assert_match(%r{href="/transactions/7001"}, activity)
      assert_match(/\$txhoverid[^\n]*7001/, activity)
      assert_match(/data-on:mouseenter="\$txhoverid = '7001'"/, activity)

      assert_includes two_way, "Capacity posture lane"
      assert_includes two_way, "Watchlist usage → remaining lanes"
      assert_includes two_way, "Urgent"
      assert_includes two_way, "Open Two-Way Utility"
      assert_match(%r{href="/tools/two-way-utility\?team=POR"}, two_way)

      assert_includes apron, "Trigger reason → apron level → active constraints"
      assert_includes apron, "Hover/focus A1/A2 transaction links to cross-highlight activity lanes"
      assert_includes apron, "A1 #7001"
      assert_includes apron, "Aggregated salary in trades"
      assert_includes apron, "Constraint count"
      assert_match(/\$txhoverid[^\n]*7001/, apron)
      assert_match(/data-on:mouseenter="\$txhoverid = '7001'"/, apron)

      assert_includes response.body, "id=\"rightpanel-base\""
    end
  end

  private

  def section_fragment(body, section_id)
    body[/<section id="#{Regexp.escape(section_id)}"[\s\S]*?<\/section>/]
  end

  def with_stubbed_team_workspace_data
    controller_class = Entities::TeamsSseController

    controller_class.class_eval do
      alias_method :__teams_show_test_original_resolve_team_from_slug!, :resolve_team_from_slug!
      alias_method :__teams_show_test_original_load_team_workspace_data!, :load_team_workspace_data!

      define_method :resolve_team_from_slug! do |_slug, redirect_on_canonical_miss: true|
        @team_id = 1_610_612_757
        @team_slug = "por"
        @team = {
          "team_id" => @team_id,
          "team_code" => "POR",
          "team_name" => "Portland Trail Blazers",
          "conference_name" => "Western",
          "city" => "Portland",
          "division_name" => "Northwest"
        }
      end

      define_method :load_team_workspace_data! do
        @team_salary_rows = [
          {
            "salary_year" => 2025,
            "cap_total" => 153_500_000,
            "cap_total_hold" => 154_200_000,
            "tax_total" => 167_900_000,
            "salary_cap_amount" => 141_000_000,
            "tax_level_amount" => 172_000_000,
            "tax_apron_amount" => 179_000_000,
            "tax_apron2_amount" => 190_000_000,
            "room_under_tax" => 4_100_000,
            "room_under_apron1" => -1_200_000,
            "room_under_apron2" => 10_800_000,
            "is_taxpayer" => true,
            "is_repeater_taxpayer" => false,
            "is_subject_to_apron" => true,
            "apron_level_lk" => "APRON1",
            "roster_row_count" => 14,
            "fa_row_count" => 2,
            "two_way_row_count" => 2,
            "luxury_tax_owed" => 2_500_000
          },
          {
            "salary_year" => 2026,
            "cap_total" => 149_000_000,
            "cap_total_hold" => 149_800_000,
            "tax_total" => 162_000_000,
            "salary_cap_amount" => 146_000_000,
            "tax_level_amount" => 178_000_000,
            "tax_apron_amount" => 185_000_000,
            "tax_apron2_amount" => 196_000_000,
            "room_under_tax" => 16_000_000,
            "room_under_apron1" => 23_000_000,
            "room_under_apron2" => 34_000_000,
            "is_taxpayer" => false,
            "is_repeater_taxpayer" => false,
            "is_subject_to_apron" => false,
            "apron_level_lk" => "NONE",
            "roster_row_count" => 12,
            "fa_row_count" => 3,
            "two_way_row_count" => 1,
            "luxury_tax_owed" => 0
          }
        ]

        @roster = []
        @cap_holds = []
        @exceptions = []
        @dead_money = []
        @draft_assets = []

        @recent_ledger_entries = [
          {
            "ledger_date" => "2025-07-08",
            "salary_year" => 2025,
            "transaction_id" => 7001,
            "trade_id" => nil,
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "transaction_type_lk" => "SIGN",
            "transaction_description_lk" => "Taxpayer mid-level signing",
            "cap_change" => 4_500_000,
            "tax_change" => 7_100_000,
            "apron_change" => 4_500_000
          },
          {
            "ledger_date" => "2025-12-15",
            "salary_year" => 2025,
            "transaction_id" => 7002,
            "trade_id" => 901,
            "player_id" => 102,
            "player_name" => "Depth Wing",
            "transaction_type_lk" => "TRADE",
            "transaction_description_lk" => "Incoming salary aggregation",
            "cap_change" => -2_200_000,
            "tax_change" => -3_000_000,
            "apron_change" => -2_200_000
          }
        ]

        @exception_usage_rows = [
          {
            "effective_date" => "2025-07-08",
            "exception_action_lk" => "USE",
            "transaction_type_lk" => "SIGN",
            "transaction_id" => 7001,
            "trade_id" => nil,
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "exception_type_lk" => "TMLE",
            "change_amount" => -4_500_000,
            "remaining_exception_amount" => 7_800_000
          }
        ]

        @apron_provenance_rows = [
          {
            "salary_year" => 2025,
            "is_subject_to_apron" => true,
            "subject_to_apron_reason_lk" => "NTMLE",
            "subject_to_apron_reason_label" => "Non-taxpayer MLE used",
            "apron_level_lk" => "APRON1",
            "apron1_transaction_id" => 7001,
            "apron2_transaction_id" => nil,
            "constraint_count" => 2,
            "constraint_lines" => "Aggregated salary in trades\nCannot sign waived buyout player above threshold"
          },
          {
            "salary_year" => 2026,
            "is_subject_to_apron" => false,
            "subject_to_apron_reason_lk" => nil,
            "subject_to_apron_reason_label" => nil,
            "apron_level_lk" => "NONE",
            "apron1_transaction_id" => nil,
            "apron2_transaction_id" => nil,
            "constraint_count" => 0,
            "constraint_lines" => nil
          }
        ]

        @two_way_capacity_row = {
          "current_contract_count" => 14,
          "open_standard_slots" => 1,
          "games_remaining" => 31,
          "under_15_games_count" => 19,
          "under_15_games_remaining" => 12,
          "context_games_remaining" => 12
        }

        @two_way_watchlist_rows = [
          {
            "player_id" => 201,
            "player_name" => "Two Way Lead",
            "game_date_est" => "2026-01-05",
            "games_on_active_list" => 47,
            "active_list_games_limit" => 50,
            "remaining_games" => 3,
            "standard_nba_contracts_on_team" => 14
          },
          {
            "player_id" => 202,
            "player_name" => "Two Way Wing",
            "game_date_est" => "2026-01-07",
            "games_on_active_list" => 49,
            "active_list_games_limit" => 50,
            "remaining_games" => 1,
            "standard_nba_contracts_on_team" => 14
          }
        ]
      end
    end

    yield
  ensure
    controller_class.class_eval do
      if method_defined?(:__teams_show_test_original_resolve_team_from_slug!)
        alias_method :resolve_team_from_slug!, :__teams_show_test_original_resolve_team_from_slug!
        remove_method :__teams_show_test_original_resolve_team_from_slug!
      end

      if method_defined?(:__teams_show_test_original_load_team_workspace_data!)
        alias_method :load_team_workspace_data!, :__teams_show_test_original_load_team_workspace_data!
        remove_method :__teams_show_test_original_load_team_workspace_data!
      end
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
