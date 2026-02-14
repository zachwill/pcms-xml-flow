require "test_helper"

class EntitiesPlayersShowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    host! "localhost"
  end

  test "player bootstrap contract dossier sections render as dense flex lanes" do
    with_stubbed_player_workspace_data do
      get "/players/lebron-james/sse/bootstrap", headers: modern_headers

      assert_response :success

      next_decisions = section_fragment(response.body, "next-decisions")
      contract_history = section_fragment(response.body, "contract-history")
      guarantees = section_fragment(response.body, "guarantees")
      incentives = section_fragment(response.body, "incentives")
      ledger = section_fragment(response.body, "ledger")

      assert next_decisions.present?
      assert contract_history.present?
      assert guarantees.present?
      assert incentives.present?
      assert ledger.present?

      assert_no_match(/<table/i, next_decisions)
      assert_no_match(/<table/i, contract_history)
      assert_no_match(/<table/i, guarantees)
      assert_no_match(/<table/i, incentives)
      assert_no_match(/<table/i, ledger)

      assert_includes next_decisions, "Next decisions"
      assert_includes next_decisions, "PO decision window"
      assert_includes next_decisions, "Potential free-agency branch"
      assert_includes next_decisions, "Partial guarantee trigger"
      assert_includes next_decisions, "Midseason guarantee"
      assert_includes next_decisions, "Team LAL"
      assert_includes next_decisions, "Txn #5001"
      assert_includes next_decisions, "Trade #901"

      assert_includes contract_history, "Contract chronology lanes"
      assert_includes contract_history, "No-Trade"
      assert_includes contract_history, "Trade Bonus"

      assert_includes guarantees, "Guarantee horizon lanes"
      assert_includes guarantees, "FULL"
      assert_includes guarantees, "PARTIAL"
      assert_includes guarantees, "PO"

      assert_includes incentives, "Bonus event lanes"
      assert_includes incentives, "Likely"
      assert_includes incentives, "Unlikely"

      assert_includes ledger, "Cap + tax + apron impact lanes"
      assert_includes ledger, "Cap Δ"
      assert_includes ledger, "Tax Δ"
      assert_includes ledger, "Apron Δ"

      assert_includes response.body, "Jump to next decisions"
      assert_includes response.body, "Decision rail"
      assert_includes response.body, "entity-cell-two-line"
      assert_includes next_decisions, "decision_lens=urgent#next-decisions"
      assert_includes next_decisions, "decision_lens=upcoming#next-decisions"
      assert_includes next_decisions, "decision_lens=later#next-decisions"
    end
  end

  test "player next decisions lens query filters the decision rail" do
    with_stubbed_player_workspace_data do
      get "/players/lebron-james/sse/bootstrap?decision_lens=upcoming", headers: modern_headers

      assert_response :success

      next_decisions = section_fragment(response.body, "next-decisions")
      assert next_decisions.present?

      assert_includes next_decisions, "Potential free-agency branch"
      assert_includes next_decisions, "decision_lens=upcoming#next-decisions"
      assert_includes next_decisions, "/players/lebron-james#next-decisions"
      assert_includes next_decisions, "Team LAL"
      assert_includes next_decisions, "Txn #5001"
      assert_includes next_decisions, "Trade #901"

      refute_includes next_decisions, "PO decision window"
      refute_includes next_decisions, "Partial guarantee trigger"
      refute_includes next_decisions, "Midseason guarantee"
    end
  end

  private

  def section_fragment(body, section_id)
    body[/<section id="#{Regexp.escape(section_id)}"[\s\S]*?<\/section>/]
  end

  def with_stubbed_player_workspace_data
    controller_class = Entities::PlayersController

    controller_class.class_eval do
      alias_method :__players_show_test_original_load_player_workspace_data!, :load_player_workspace_data!

      define_method :load_player_workspace_data! do
        @player = {
          "person_id" => @player_id,
          "first_name" => "LeBron",
          "last_name" => "James",
          "uniform_number" => "23",
          "years_of_service" => 21,
          "birth_date" => "1984-12-30",
          "height" => 81,
          "weight" => 250,
          "draft_year" => 2003,
          "draft_round" => 1,
          "draft_pick" => 1,
          "draft_team_code" => "CLE",
          "player_status_lk" => "ACTIVE",
          "player_status_name" => "Active",
          "person_team_code" => "LAL",
          "person_team_id" => 1_610_612_747
        }

        @salary_book_row = {
          "team_code" => "LAL",
          "team_id" => 1_610_612_747,
          "team_name" => "Los Angeles Lakers",
          "agent_id" => 9_001,
          "agent_name" => "Rich Paul",
          "agency_id" => 12,
          "agency_name" => "Klutch Sports",
          "contract_id" => 7_001,
          "version_number" => 3,
          "cap_2025" => 48_000_000,
          "cap_2026" => 51_000_000,
          "cap_2027" => 0,
          "cap_2028" => 0,
          "cap_2029" => 0,
          "cap_2030" => 0,
          "total_salary_from_2025" => 99_000_000,
          "option_2026" => "PO",
          "option_2027" => nil,
          "is_trade_consent_required_now" => true,
          "is_trade_restricted_now" => true,
          "is_no_trade" => true,
          "is_trade_bonus" => true,
          "trade_bonus_percent" => 15,
          "is_poison_pill" => false,
          "is_two_way" => false,
          "is_min_contract" => false,
          "player_consent_end_date" => "2026-06-30",
          "trade_restriction_end_date" => "2025-12-15",
          "guaranteed_amount_2025" => 48_000_000,
          "guaranteed_amount_2026" => 20_000_000,
          "guaranteed_amount_2027" => 0,
          "guaranteed_amount_2028" => 0,
          "guaranteed_amount_2029" => 0,
          "guaranteed_amount_2030" => 0,
          "is_fully_guaranteed_2025" => true,
          "is_fully_guaranteed_2026" => false,
          "is_fully_guaranteed_2027" => false,
          "is_fully_guaranteed_2028" => false,
          "is_fully_guaranteed_2029" => false,
          "is_fully_guaranteed_2030" => false,
          "is_partially_guaranteed_2025" => false,
          "is_partially_guaranteed_2026" => true,
          "is_partially_guaranteed_2027" => false,
          "is_partially_guaranteed_2028" => false,
          "is_partially_guaranteed_2029" => false,
          "is_partially_guaranteed_2030" => false,
          "is_non_guaranteed_2025" => false,
          "is_non_guaranteed_2026" => false,
          "is_non_guaranteed_2027" => true,
          "is_non_guaranteed_2028" => false,
          "is_non_guaranteed_2029" => false,
          "is_non_guaranteed_2030" => false
        }

        @draft_selection = {
          "transaction_id" => 100,
          "draft_year" => 2003,
          "draft_round" => 1,
          "pick_number" => 1,
          "drafting_team_code" => "CLE"
        }

        @team_history_rows = [
          {
            "team_code" => "CLE",
            "team_id" => 1_610_612_739,
            "team_name" => "Cleveland Cavaliers",
            "start_date" => "2003-06-26",
            "last_date" => "2010-07-08"
          },
          {
            "team_code" => "LAL",
            "team_id" => 1_610_612_747,
            "team_name" => "Los Angeles Lakers",
            "start_date" => "2018-07-01",
            "last_date" => "2025-02-01"
          }
        ]

        @salary_book_yearly_rows = []

        @contract_chronology_rows = [
          {
            "contract_id" => 7_001,
            "version_count" => 3,
            "latest_version_number" => 3,
            "signing_date" => "2024-07-06",
            "contract_end_date" => "2027-06-30",
            "start_year" => 2025,
            "min_version_start_year" => 2025,
            "signing_team_id" => 1_610_612_747,
            "signing_team_code" => "LAL",
            "sign_and_trade_to_team_id" => nil,
            "sign_and_trade_to_team_code" => nil,
            "signed_method_lk" => "FA_SIGN",
            "signed_method_label" => "Free agent signing",
            "exception_type_lk" => "BIRD",
            "exception_type_label" => "Bird",
            "is_sign_and_trade" => false,
            "record_status_lk" => "ACTIVE"
          }
        ]

        @contract_version_rows = [
          {
            "contract_id" => 7_001,
            "version_number" => 3,
            "version_date" => "2024-07-06",
            "start_salary_year" => 2025,
            "contract_length" => 2,
            "contract_type_lk" => "VET",
            "contract_type_label" => "Veteran",
            "record_status_lk" => "ACTIVE",
            "is_rookie_scale_extension" => false,
            "is_veteran_extension" => true,
            "is_exhibit_10" => false,
            "is_poison_pill" => false,
            "is_trade_bonus" => true,
            "is_no_trade" => true,
            "is_protected_contract" => true,
            "is_full_protection" => false
          }
        ]

        @salary_rows = []

        @protection_rows = [
          {
            "salary_year" => 2026,
            "protection_amount" => 20_000_000,
            "effective_protection_amount" => 16_000_000,
            "has_conditional" => true,
            "coverage_codes" => "SKILL, INJURY",
            "row_count" => 2
          }
        ]

        @protection_condition_rows = [
          {
            "condition_id" => 321,
            "salary_year" => 2026,
            "amount" => 5_000_000,
            "earned_type_lk" => "DATE",
            "earned_date" => "2026-01-10",
            "clause_name" => "Midseason guarantee",
            "criteria_description" => nil
          }
        ]

        @bonus_rows = [
          {
            "bonus_id" => 1,
            "salary_year" => 2025,
            "bonus_type_lk" => "PLAYOFF",
            "is_likely" => true,
            "bonus_amount" => 1_500_000,
            "earned_lk" => "TEAM",
            "paid_by_date" => "2025-07-15",
            "clause_name" => "Playoff berth",
            "criteria_description" => nil
          },
          {
            "bonus_id" => 2,
            "salary_year" => 2026,
            "bonus_type_lk" => "MVP",
            "is_likely" => false,
            "bonus_amount" => 2_000_000,
            "earned_lk" => "IND",
            "paid_by_date" => "2026-07-15",
            "clause_name" => nil,
            "criteria_description" => "MVP award"
          }
        ]

        @bonus_max_rows = [
          {
            "salary_year" => 2026,
            "bonus_type_lk" => "MVP",
            "is_likely" => false,
            "max_amount" => 2_000_000
          }
        ]

        @payment_schedule_rows = [
          {
            "payment_schedule_id" => 88,
            "salary_year" => 2026,
            "payment_amount" => 20_000_000,
            "schedule_type_lk" => "STANDARD",
            "payment_type_lk" => "BASE",
            "is_default_schedule" => true,
            "detail_count" => 12,
            "first_payment_date" => "2025-11-01",
            "last_payment_date" => "2026-10-01"
          }
        ]

        @ledger_entries = [
          {
            "ledger_date" => "2025-02-06",
            "salary_year" => 2025,
            "transaction_id" => 5001,
            "trade_id" => 901,
            "transaction_type_lk" => "TRADE",
            "transaction_description_lk" => "Incoming via trade",
            "team_id" => 1_610_612_747,
            "team_code" => "LAL",
            "team_name" => "Los Angeles Lakers",
            "cap_change" => 3_000_000,
            "tax_change" => 4_000_000,
            "apron_change" => 2_000_000
          },
          {
            "ledger_date" => "2025-07-15",
            "salary_year" => 2025,
            "transaction_id" => 5002,
            "trade_id" => nil,
            "transaction_type_lk" => "SIGN",
            "transaction_description_lk" => "Re-sign",
            "team_id" => 1_610_612_747,
            "team_code" => "LAL",
            "team_name" => "Los Angeles Lakers",
            "cap_change" => -1_250_000,
            "tax_change" => -800_000,
            "apron_change" => -500_000
          }
        ]
      end
    end

    yield
  ensure
    controller_class.class_eval do
      if method_defined?(:__players_show_test_original_load_player_workspace_data!)
        alias_method :load_player_workspace_data!, :__players_show_test_original_load_player_workspace_data!
        remove_method :__players_show_test_original_load_player_workspace_data!
      end
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
