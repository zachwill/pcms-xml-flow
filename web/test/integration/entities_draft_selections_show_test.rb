require "test_helper"

class EntitiesDraftSelectionsShowTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    host! "localhost"
  end

  test "draft selection show renders provenance lane filters with team exposure summary and pivots" do
    with_stubbed_draft_selection_show do
      get "/draft-selections/draft-2028-r1-p8-flow-guard", headers: modern_headers

      assert_response :success
      assert_match(%r{id="entity-nav-draft_selections"[^>]*bg-primary text-primary-foreground border-primary shadow-sm}, response.body)
      assert_match(%r{<option value="/draft-selections" selected>Draft Selections</option>}, response.body)

      provenance = section_fragment(response.body, "provenance")
      assert provenance.present?

      assert_no_match(/<table/i, provenance)

      assert_includes provenance, "id=\"provenance-lanes\""
      assert_includes provenance, "Team exposure summary"
      assert_includes provenance, "Lane filters"
      assert_includes provenance, "Filter chain rows by hop depth or flag type."
      assert_includes provenance, "Deepest hop"
      assert_includes provenance, "P3"
      assert_includes provenance, "BOS · 5x"
      assert_includes provenance, "POR · 2x"
      assert_includes provenance, "LAL · 2x"
      assert_includes provenance, "provenance_lens"
      assert_includes provenance, "$provenancelens === 'deep'"
      assert_includes provenance, "deep"
      assert_includes provenance, "conditional"
      assert_includes provenance, "swap"
      assert_includes provenance, "From → To"
      assert_includes provenance, "Trade pivot"

      assert_match(%r{href="/trades/88001"}, provenance)
      assert_match(%r{href="/trades/88002"}, provenance)
      assert_match(%r{href="/transactions/777001"}, provenance)
      assert_match(%r{href="/teams/bos"}, provenance)
      assert_match(%r{href="/teams/por"}, provenance)
    end
  end

  private

  def section_fragment(body, section_id)
    body[/<section id="#{Regexp.escape(section_id)}"[\s\S]*?<\/section>/]
  end

  def with_stubbed_draft_selection_show
    controller_class = Entities::DraftSelectionsController

    controller_class.class_eval do
      alias_method :__draft_selections_show_test_original_show__, :show

      define_method :show do
        @draft_selection_id = 777_001
        @draft_selection_slug = "draft-2028-r1-p8-flow-guard"
        @draft_selection = {
          "transaction_id" => 777_001,
          "draft_year" => 2028,
          "draft_round" => 1,
          "pick_number" => 8,
          "player_id" => 101,
          "drafting_team_id" => 1_610_612_738,
          "drafting_team_code" => "BOS",
          "draft_amount" => nil,
          "transaction_date" => "2028-06-22",
          "trade_id" => 88_003,
          "transaction_type_lk" => "DDRFT",
          "transaction_description_lk" => "Drafted",
          "player_name" => "Flow Guard",
          "team_name" => "Boston Celtics"
        }

        @current_team = {
          "team_code" => "POR",
          "team_id" => 1_610_612_757,
          "team_name" => "Portland Trail Blazers"
        }

        @pick_provenance_rows = [
          {
            "id" => 91_001,
            "trade_id" => 88_001,
            "trade_date" => "2026-07-07",
            "draft_year" => 2028,
            "draft_round" => 1,
            "from_team_id" => 1_610_612_738,
            "from_team_code" => "BOS",
            "to_team_id" => 1_610_612_757,
            "to_team_code" => "POR",
            "original_team_id" => 1_610_612_738,
            "original_team_code" => "BOS",
            "is_swap" => false,
            "is_future" => true,
            "is_conditional" => true,
            "conditional_type_lk" => "TOP4",
            "is_draft_year_plus_two" => false
          },
          {
            "id" => 91_002,
            "trade_id" => 88_002,
            "trade_date" => "2027-02-08",
            "draft_year" => 2028,
            "draft_round" => 1,
            "from_team_id" => 1_610_612_757,
            "from_team_code" => "POR",
            "to_team_id" => 1_610_612_764,
            "to_team_code" => "LAL",
            "original_team_id" => 1_610_612_738,
            "original_team_code" => "BOS",
            "is_swap" => true,
            "is_future" => false,
            "is_conditional" => false,
            "conditional_type_lk" => nil,
            "is_draft_year_plus_two" => false
          },
          {
            "id" => 91_003,
            "trade_id" => nil,
            "trade_date" => "2028-06-20",
            "draft_year" => 2028,
            "draft_round" => 1,
            "from_team_id" => 1_610_612_764,
            "from_team_code" => "LAL",
            "to_team_id" => 1_610_612_738,
            "to_team_code" => "BOS",
            "original_team_id" => 1_610_612_738,
            "original_team_code" => "BOS",
            "is_swap" => false,
            "is_future" => false,
            "is_conditional" => false,
            "conditional_type_lk" => nil,
            "is_draft_year_plus_two" => false
          }
        ]

        render :show, layout: false
      end
    end

    yield
  ensure
    controller_class.class_eval do
      if method_defined?(:__draft_selections_show_test_original_show__)
        alias_method :show, :__draft_selections_show_test_original_show__
        remove_method :__draft_selections_show_test_original_show__
      end
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
