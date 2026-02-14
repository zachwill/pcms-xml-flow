require "test_helper"

class EntitiesDraftPicksShowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    host! "localhost"
  end

  test "draft pick show renders protections and trade chain as rule lanes + chain map" do
    with_stubbed_draft_pick_show do
      get "/draft-picks/por/2028/1", headers: modern_headers

      assert_response :success
      assert_includes response.body, "id=\"maincanvas\""
      assert_includes response.body, "data-signals=\"{ rulelane: 'all' }\""

      protections = section_fragment(response.body, "protections")
      assert protections.present?
      assert_no_match(/<table/i, protections)
      assert_includes protections, "Rule lanes"
      assert_includes protections, "Rule filters"
      assert_includes protections, "All rules"
      assert_includes protections, "Conditional protections"
      assert_includes protections, "Swap rights"
      assert_includes protections, "Counterparty route"
      assert_includes protections, "Original owner context"
      assert_includes protections, "conditional"
      assert_includes protections, "swap"
      assert_includes protections, "url.searchParams.set('rule_lane', 'swap')"
      assert_match(%r{href="/teams/lal"}, protections)
      assert_match(%r{href="/teams/mia"}, protections)
      assert_match(%r{href="/trades/88001"}, protections)

      trade_chain = section_fragment(response.body, "trade-chain")
      assert trade_chain.present?
      assert_no_match(/<table/i, trade_chain)
      assert_includes trade_chain, "Chain map"
      assert_includes trade_chain, "id=\"rule-hop-map\""
      assert_includes trade_chain, "id=\"chain-hop-1\""
      assert_includes trade_chain, "Active rule filter highlights matching hops in the chain map."
      assert_includes trade_chain, "$rulelane === 'conditional'"
      assert_includes trade_chain, "$rulelane === 'swap'"
      assert_includes trade_chain, "$rulelane === 'flagged'"
      assert_includes trade_chain, "Conditional hops"
      assert_includes trade_chain, "Swap hops"
      assert_includes trade_chain, "Direct hops"
      assert_includes trade_chain, "Original owner"
      assert_includes trade_chain, "Trade pivot"
      assert_includes trade_chain, "From → To"
      assert_match(%r{href="/teams/bos"}, trade_chain)
      assert_match(%r{href="/teams/por"}, trade_chain)
      assert_match(%r{href="/trades/88002"}, trade_chain)
      assert_match(%r{href="/trades/88003"}, trade_chain)
    end
  end

  test "draft pick show bootstraps rule_lane query into filter state" do
    with_stubbed_draft_pick_show do
      get "/draft-picks/por/2028/1?rule_lane=swap", headers: modern_headers

      assert_response :success
      assert_includes response.body, "data-signals=\"{ rulelane: 'swap' }\""
      assert_includes response.body, "data-show=\"$rulelane === &#39;all&#39; || $rulelane === &#39;swap&#39;\""
      assert_includes response.body, "data-show=\"$rulelane !== 'all'\""

      get "/draft-picks/por/2028/1?rule_lane=unknown", headers: modern_headers

      assert_response :success
      assert_includes response.body, "data-signals=\"{ rulelane: 'all' }\""
    end
  end

  private

  def section_fragment(body, section_id)
    body[/<section id="#{Regexp.escape(section_id)}"[\s\S]*?<\/section>/]
  end

  def with_stubbed_draft_pick_show
    controller_class = Entities::DraftPicksController

    controller_class.class_eval do
      alias_method :__draft_picks_show_test_original_show__, :show

      define_method :show do
        @draft_pick_group = {
          "team_code" => "POR",
          "draft_year" => 2028,
          "draft_round" => 1
        }

        @team = {
          "team_id" => 1_610_612_757,
          "team_code" => "POR",
          "team_name" => "Portland Trail Blazers",
          "conference_name" => "Western"
        }

        @assets = [
          {
            "asset_slot" => 1,
            "sub_asset_slot" => 1,
            "asset_type" => "PICK",
            "display_text" => "2028 1st round pick (Top-4 protected)",
            "raw_part" => "Top-4 protected",
            "counterparty_team_code" => "LAL",
            "counterparty_team_codes" => "{LAL,MIA}",
            "via_team_codes" => "{BOS}",
            "effective_endnote_ids" => "{501}",
            "primary_endnote_id" => 501,
            "is_conditional" => true,
            "is_swap" => false,
            "is_forfeited" => false,
            "needs_review" => false,
            "endnote_explanation" => "Converts to two seconds if not conveyed by 2029."
          },
          {
            "asset_slot" => 2,
            "sub_asset_slot" => 1,
            "asset_type" => "SWAP",
            "display_text" => "Swap rights with MIA",
            "raw_part" => "Swap rights",
            "counterparty_team_code" => "MIA",
            "counterparty_team_codes" => "{MIA}",
            "via_team_codes" => "{}",
            "effective_endnote_ids" => "{}",
            "primary_endnote_id" => nil,
            "is_conditional" => false,
            "is_swap" => true,
            "is_forfeited" => false,
            "needs_review" => false,
            "endnote_explanation" => nil
          },
          {
            "asset_slot" => 3,
            "sub_asset_slot" => 1,
            "asset_type" => "PICK",
            "display_text" => "Unprotected incoming pick",
            "raw_part" => "Unprotected",
            "counterparty_team_code" => "BOS",
            "counterparty_team_codes" => "{BOS}",
            "via_team_codes" => "{}",
            "effective_endnote_ids" => "{}",
            "primary_endnote_id" => nil,
            "is_conditional" => false,
            "is_swap" => false,
            "is_forfeited" => false,
            "needs_review" => false,
            "endnote_explanation" => nil
          },
          {
            "asset_slot" => 4,
            "sub_asset_slot" => 1,
            "asset_type" => "PICK",
            "display_text" => "Potential forfeiture per league ruling",
            "raw_part" => "Potential forfeiture",
            "counterparty_team_code" => nil,
            "counterparty_team_codes" => "{}",
            "via_team_codes" => "{}",
            "effective_endnote_ids" => "{}",
            "primary_endnote_id" => nil,
            "is_conditional" => false,
            "is_swap" => false,
            "is_forfeited" => true,
            "needs_review" => true,
            "endnote_explanation" => nil
          }
        ]

        @trade_chain_rows = [
          {
            "id" => 9901,
            "trade_id" => 88_001,
            "trade_date" => "2026-07-07",
            "from_team_id" => 1_610_612_738,
            "from_team_code" => "BOS",
            "to_team_id" => 1_610_612_757,
            "to_team_code" => "POR",
            "original_team_id" => 1_610_612_738,
            "original_team_code" => "BOS",
            "is_swap" => false,
            "is_future" => true,
            "is_conditional" => true,
            "conditional_type_lk" => "TOP4"
          },
          {
            "id" => 9902,
            "trade_id" => 88_002,
            "trade_date" => "2027-02-09",
            "from_team_id" => 1_610_612_757,
            "from_team_code" => "POR",
            "to_team_id" => 1_610_612_744,
            "to_team_code" => "MIA",
            "original_team_id" => 1_610_612_738,
            "original_team_code" => "BOS",
            "is_swap" => true,
            "is_future" => false,
            "is_conditional" => false,
            "conditional_type_lk" => nil
          },
          {
            "id" => 9903,
            "trade_id" => 88_003,
            "trade_date" => "2028-06-21",
            "from_team_id" => 1_610_612_744,
            "from_team_code" => "MIA",
            "to_team_id" => 1_610_612_757,
            "to_team_code" => "POR",
            "original_team_id" => 1_610_612_738,
            "original_team_code" => "BOS",
            "is_swap" => false,
            "is_future" => false,
            "is_conditional" => false,
            "conditional_type_lk" => nil
          }
        ]

        @teams_by_code = {
          "BOS" => { "team_id" => 1_610_612_738, "team_code" => "BOS", "team_name" => "Boston Celtics" },
          "POR" => { "team_id" => 1_610_612_757, "team_code" => "POR", "team_name" => "Portland Trail Blazers" },
          "LAL" => { "team_id" => 1_610_612_744, "team_code" => "LAL", "team_name" => "Los Angeles Lakers" },
          "MIA" => { "team_id" => 1_610_612_744, "team_code" => "MIA", "team_name" => "Miami Heat" }
        }

        @endnotes = [
          {
            "endnote_id" => 501,
            "trade_id" => 88_001,
            "trade_date" => "2026-07-07",
            "explanation" => "Converts to two seconds if not conveyed by 2029.",
            "conveyance_text" => nil
          }
        ]

        @endnotes_by_id = { 501 => @endnotes.first }
        @referenced_endnote_ids = [501]

        render :show, layout: false
      end
    end

    yield
  ensure
    controller_class.class_eval do
      if method_defined?(:__draft_picks_show_test_original_show__)
        alias_method :show, :__draft_picks_show_test_original_show__
        remove_method :__draft_picks_show_test_original_show__
      end
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
