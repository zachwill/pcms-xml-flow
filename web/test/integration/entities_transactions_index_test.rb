require "test_helper"

class EntitiesTransactionsIndexTest < ActionDispatch::IntegrationTest
  parallelize(workers: 1)

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  setup do
    host! "localhost"
  end

  test "transactions index renders impact knob and severity-first lanes" do
    with_stubbed_transactions_index do
      get "/transactions", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="transactions-impact-select"'
      assert_includes response.body, "Severity lane"
      assert_includes response.body, "Critical impact · dead money / Δ20M+"
      assert_includes response.body, 'id="transactions-severity-lanes"'
      assert_includes response.body, 'id="transactions-severity-lane-critical"'
      assert_includes response.body, 'id="transactions-scan-rail"'
      assert_includes response.body, "Severity + route scan rail"
      assert_includes response.body, "Dead-money rows or max Δ ≥ $20M / apron Δ ≥ $8M"
      assert_includes response.body, "Route cue"
      assert_includes response.body, "Critical impact"
      assert_includes response.body, "Max Δ"
      assert_includes response.body, "Severity quick feed"
      assert_includes response.body, "Cap"
      assert_includes response.body, "https://cdn.nba.com/headshots/nba/latest/1040x760/101.png"
      assert_includes response.body, "https://cdn.nba.com/logos/nba/1610612757/primary/L/logo.svg"
      assert_includes response.body, "https://cdn.nba.com/logos/nba/1610612738/primary/L/logo.svg"
      assert_includes response.body, 'id="rightpanel-base"'
    end
  end

  test "transactions refresh uses one sse response and keeps selected overlay when visible" do
    with_stubbed_transactions_index do
      get "/transactions/sse/refresh", params: {
        q: "",
        daterange: "season",
        team: "",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "1",
        impact: "critical",
        selected_type: "transaction",
        selected_id: "9001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, "event: datastar-patch-elements"
      assert_includes response.body, 'id="transactions-results"'
      assert_includes response.body, 'id="rightpanel-base"'
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, 'data-transaction-overlay-id="9001"'
      assert_includes response.body, "data-show=\"$overlaytype === 'transaction' && $overlayid === '9001'\""
      assert_includes response.body, "Severity + route scan rail"
      assert_includes response.body, "League-wide route perspective"
      assert_includes response.body, "Open transaction page"
      assert_includes response.body, "event: datastar-patch-signals"
      assert_includes response.body, '"txnimpact":"critical"'
      assert_includes response.body, '"overlaytype":"transaction"'
      assert_includes response.body, '"overlayid":"9001"'
    end
  end

  test "transactions refresh clears overlay when selected row is filtered out by impact lane" do
    with_stubbed_transactions_index do
      get "/transactions/sse/refresh", params: {
        q: "",
        daterange: "season",
        team: "",
        signings: "1",
        waivers: "1",
        extensions: "1",
        other: "1",
        impact: "low",
        selected_type: "transaction",
        selected_id: "9001"
      }, headers: modern_headers

      assert_response :success
      assert_includes response.media_type, "text/event-stream"
      assert_includes response.body, '<div id="rightpanel-overlay"></div>'
      assert_includes response.body, '"txnimpact":"low"'
      assert_includes response.body, '"overlaytype":"none"'
      assert_includes response.body, '"overlayid":""'
    end
  end

  test "transactions sidebar returns overlay visibility guard and clear endpoint empties overlay" do
    with_stubbed_transactions_index do
      get "/transactions/sidebar/9001", headers: modern_headers

      assert_response :success
      assert_includes response.body, 'id="rightpanel-overlay"'
      assert_includes response.body, 'data-transaction-overlay-id="9001"'
      assert_includes response.body, "data-show=\"$overlaytype === 'transaction' && $overlayid === '9001'\""
      assert_includes response.body, "Open canonical transaction page"

      get "/transactions/sidebar/clear", headers: modern_headers

      assert_response :success
      assert_equal '<div id="rightpanel-overlay"></div>', response.body.strip
    end
  end

  private

  def with_stubbed_transactions_index
    controller_class = TransactionsController

    controller_class.class_eval do
      alias_method :__transactions_index_test_original_index__, :index
      alias_method :__transactions_index_test_original_load_index_state__, :load_index_state!
      alias_method :__transactions_index_test_original_load_sidebar_payload__, :load_sidebar_transaction_payload

      define_method :index do
        load_index_state!
        render :index, layout: false
      end

      define_method :__transactions_index_test_rows__ do
        [
          {
            "transaction_id" => 9001,
            "transaction_date" => Date.new(2025, 7, 10),
            "transaction_type_lk" => "SIGN",
            "transaction_description_lk" => "Taxpayer mid-level signing",
            "trade_id" => nil,
            "player_id" => 101,
            "player_name" => "Flow Guard",
            "from_team_id" => 1_610_612_757,
            "from_team_code" => "POR",
            "from_team_name" => "Portland Trail Blazers",
            "to_team_id" => 1_610_612_738,
            "to_team_code" => "BOS",
            "to_team_name" => "Boston Celtics",
            "signed_method_lk" => "TMLE",
            "contract_type_lk" => "STANDARD",
            "ledger_row_count" => 3,
            "cap_change_total" => -22_000_000,
            "tax_change_total" => -18_000_000,
            "apron_change_total" => -8_500_000,
            "exception_usage_count" => 1,
            "dead_money_count" => 1,
            "budget_snapshot_count" => 0
          },
          {
            "transaction_id" => 9002,
            "transaction_date" => Date.new(2025, 7, 9),
            "transaction_type_lk" => "WAIVE",
            "transaction_description_lk" => "Waive-and-stretch cleanup",
            "trade_id" => nil,
            "player_id" => 102,
            "player_name" => "Depth Wing",
            "from_team_id" => 1_610_612_738,
            "from_team_code" => "BOS",
            "from_team_name" => "Boston Celtics",
            "to_team_id" => 1_610_612_757,
            "to_team_code" => "POR",
            "to_team_name" => "Portland Trail Blazers",
            "signed_method_lk" => "WAIVER",
            "contract_type_lk" => "STRETCH",
            "ledger_row_count" => 2,
            "cap_change_total" => -11_000_000,
            "tax_change_total" => -5_500_000,
            "apron_change_total" => -4_200_000,
            "exception_usage_count" => 1,
            "dead_money_count" => 0,
            "budget_snapshot_count" => 1
          },
          {
            "transaction_id" => 9003,
            "transaction_date" => Date.new(2025, 7, 8),
            "transaction_type_lk" => "EXTSN",
            "transaction_description_lk" => "Veteran extension",
            "trade_id" => nil,
            "player_id" => 103,
            "player_name" => "Starter Big",
            "from_team_id" => 1_610_612_757,
            "from_team_code" => "POR",
            "from_team_name" => "Portland Trail Blazers",
            "to_team_id" => 1_610_612_757,
            "to_team_code" => "POR",
            "to_team_name" => "Portland Trail Blazers",
            "signed_method_lk" => "BIRD",
            "contract_type_lk" => "EXTENSION",
            "ledger_row_count" => 1,
            "cap_change_total" => 3_250_000,
            "tax_change_total" => 1_400_000,
            "apron_change_total" => 0,
            "exception_usage_count" => 0,
            "dead_money_count" => 0,
            "budget_snapshot_count" => 1
          },
          {
            "transaction_id" => 9004,
            "transaction_date" => Date.new(2025, 7, 7),
            "transaction_type_lk" => "AMEND",
            "transaction_description_lk" => "Administrative contract amendment",
            "trade_id" => nil,
            "player_id" => nil,
            "player_name" => nil,
            "from_team_id" => 1_610_612_738,
            "from_team_code" => "BOS",
            "from_team_name" => "Boston Celtics",
            "to_team_id" => 1_610_612_738,
            "to_team_code" => "BOS",
            "to_team_name" => "Boston Celtics",
            "signed_method_lk" => nil,
            "contract_type_lk" => nil,
            "ledger_row_count" => 0,
            "cap_change_total" => 0,
            "tax_change_total" => 0,
            "apron_change_total" => 0,
            "exception_usage_count" => 0,
            "dead_money_count" => 0,
            "budget_snapshot_count" => 0
          }
        ]
      end

      define_method :load_index_state! do
        @daterange = params[:daterange].to_s.strip.presence || "season"
        @team = params[:team].to_s.strip.upcase.presence
        @team = nil unless @team&.match?(/\A[A-Z]{3}\z/)
        @query = params[:q].to_s.strip.gsub(/\s+/, " ").presence
        @signings = params[:signings] != "0"
        @waivers = params[:waivers] != "0"
        @extensions = params[:extensions] != "0"
        @other = params[:other] == "1"
        @impact = params[:impact].to_s.strip.presence || "all"
        @impact = "all" unless %w[all critical high medium low].include?(@impact)
        @selected_transaction_id = normalize_selected_transaction_id_param(params[:selected_id])

        @team_options = [
          { "team_code" => "BOS", "team_name" => "Boston Celtics" },
          { "team_code" => "POR", "team_name" => "Portland Trail Blazers" }
        ]

        rows = __transactions_index_test_rows__.map(&:dup)

        selected_types = []
        selected_types.concat(%w[SIGN RSIGN]) if @signings
        selected_types.concat(%w[WAIVE WAIVR]) if @waivers
        selected_types << "EXTSN" if @extensions

        if @other
          excluded = %w[SIGN RSIGN EXTSN WAIVE WAIVR TRADE]
          rows = rows.select do |row|
            selected_types.include?(row["transaction_type_lk"]) || !excluded.include?(row["transaction_type_lk"])
          end
        elsif selected_types.any?
          rows = rows.select { |row| selected_types.include?(row["transaction_type_lk"]) }
        else
          rows = []
        end

        if @team.present?
          rows = rows.select do |row|
            row["from_team_code"] == @team || row["to_team_code"] == @team
          end
        end

        annotate_transaction_severity!(rows: rows)

        if @query.present?
          query_value = @query.downcase
          rows = rows.select do |row|
            values = [
              row["transaction_id"],
              row["transaction_description_lk"],
              row["transaction_type_lk"],
              row["player_name"],
              row["from_team_code"],
              row["to_team_code"]
            ]

            matched = values.any? { |value| value.to_s.downcase.include?(query_value) }
            if matched
              row["intent_match_cue"] = "player"
              row["intent_match_title"] = "Matched on: player"
            end
            matched
          end
        end

        @transactions = rows.sort_by do |row|
          [normalize_transaction_date(row["transaction_date"]) || Date.new(1900, 1, 1), row["transaction_id"].to_i]
        end.reverse

        apply_impact_filter!
        @transactions = Array(@transactions).first(200)
        build_transaction_date_groups!
        build_transaction_severity_lanes!
        annotate_transaction_route_cues!(rows: @transactions, scoped_team_code: @team)
        build_transaction_scan_cues!
        build_sidebar_summary!(selected_transaction_id: @selected_transaction_id)
      end

      define_method :normalize_selected_transaction_id_param do |raw_value|
        value = Integer(raw_value, 10)
        value.positive? ? value : nil
      rescue ArgumentError, TypeError
        nil
      end

      define_method :normalize_transaction_date do |raw_value|
        return raw_value if raw_value.is_a?(Date)
        return raw_value.to_date if raw_value.respond_to?(:to_date)

        Date.parse(raw_value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      define_method :annotate_transaction_severity! do |rows:|
        Array(rows).each do |row|
          cap_delta = row["cap_change_total"].to_f.abs
          tax_delta = row["tax_change_total"].to_f.abs
          apron_delta = row["apron_change_total"].to_f.abs
          max_delta = [cap_delta, tax_delta, apron_delta].max

          severity_key = if row["dead_money_count"].to_i.positive? || max_delta >= 20_000_000 || apron_delta >= 8_000_000
            "critical"
          elsif row["exception_usage_count"].to_i.positive? || max_delta >= 10_000_000 || apron_delta >= 4_000_000
            "high"
          elsif row["ledger_row_count"].to_i.positive? || max_delta >= 2_000_000
            "medium"
          else
            "low"
          end

          row["impact_max_delta"] = max_delta
          row["severity_key"] = severity_key
          row["severity_label"] = {
            "critical" => "Critical impact",
            "high" => "High impact",
            "medium" => "Medium impact",
            "low" => "Low impact"
          }[severity_key]
        end
      end

      define_method :apply_impact_filter! do
        return if @impact == "all"

        @transactions = Array(@transactions).select do |row|
          row["severity_key"].to_s == @impact
        end
      end

      define_method :build_transaction_date_groups! do
        grouped_rows = Array(@transactions).group_by do |row|
          normalize_transaction_date(row["transaction_date"]) || Date.new(1900, 1, 1)
        end

        @transaction_date_groups = grouped_rows.sort_by { |(date, _rows)| date }.reverse.map do |(date, rows)|
          {
            key: date.to_s,
            headline: date.strftime("%b %-d, %Y"),
            subline: nil,
            relative_label: nil,
            row_count: rows.size,
            rows: rows
          }
        end
      end

      define_method :build_transaction_severity_lanes! do
        lane_meta = [
          ["critical", "Critical impact"],
          ["high", "High impact"],
          ["medium", "Medium impact"],
          ["low", "Low impact"]
        ]

        @transaction_severity_lanes = lane_meta.filter_map do |(key, headline)|
          lane_rows = Array(@transactions).select { |row| row["severity_key"].to_s == key }
          next if lane_rows.empty?

          date_groups = lane_rows.group_by do |row|
            normalize_transaction_date(row["transaction_date"]) || Date.new(1900, 1, 1)
          end.sort_by { |(date, _rows)| date }.reverse.map do |(date, rows)|
            {
              key: date.to_s,
              headline: date.strftime("%b %-d, %Y"),
              subline: nil,
              relative_label: nil,
              row_count: rows.size,
              rows: rows
            }
          end

          {
            key: key,
            headline: headline,
            subline: nil,
            row_count: lane_rows.size,
            date_groups: date_groups
          }
        end
      end

      define_method :build_sidebar_summary! do |selected_transaction_id:|
        counts_by_type = Array(@transactions).each_with_object(Hash.new(0)) do |row, counts|
          counts[row["transaction_type_lk"].to_s] += 1
        end

        filters = []
        filters << "#{@team} team scope" if @team.present?
        filters << "#{@impact.capitalize} impact" if @impact != "all"
        filters << "Query: #{@query}" if @query.present?

        quick_lanes = Array(@transaction_severity_lanes).map do |lane|
          lane_rows = Array(lane[:date_groups]).map do |group|
            group.merge(rows: Array(group[:rows]).first(2))
          end

          lane.merge(date_groups: lane_rows)
        end

        @sidebar_summary = {
          selected_transaction_id: selected_transaction_id,
          row_count: Array(@transactions).size,
          severity_lane_count: Array(@transaction_severity_lanes).size,
          signings_count: counts_by_type["SIGN"] + counts_by_type["RSIGN"],
          waivers_count: counts_by_type["WAIVE"] + counts_by_type["WAIVR"],
          extensions_count: counts_by_type["EXTSN"],
          other_count: Array(@transactions).count do |row|
            !%w[SIGN RSIGN WAIVE WAIVR EXTSN].include?(row["transaction_type_lk"].to_s)
          end,
          critical_count: Array(@transactions).count { |row| row["severity_key"] == "critical" },
          high_count: Array(@transactions).count { |row| row["severity_key"] == "high" },
          medium_count: Array(@transactions).count { |row| row["severity_key"] == "medium" },
          low_count: Array(@transactions).count { |row| row["severity_key"] == "low" },
          filters: filters,
          top_row_lanes: quick_lanes
        }
      end

      define_method :load_sidebar_transaction_payload do |transaction_id|
        row = __transactions_index_test_rows__.find { |candidate| candidate["transaction_id"].to_i == transaction_id.to_i }
        raise ActiveRecord::RecordNotFound unless row

        {
          transaction: row,
          ledger_summary: {
            "ledger_row_count" => row["ledger_row_count"],
            "cap_change_total" => row["cap_change_total"],
            "tax_change_total" => row["tax_change_total"],
            "apron_change_total" => row["apron_change_total"]
          },
          artifact_summary: {
            "exception_usage_count" => row["exception_usage_count"],
            "dead_money_count" => row["dead_money_count"],
            "budget_snapshot_count" => row["budget_snapshot_count"]
          },
          trade_summary: nil
        }
      end
    end

    yield
  ensure
    controller_class.class_eval do
      if method_defined?(:__transactions_index_test_original_index__)
        alias_method :index, :__transactions_index_test_original_index__
        remove_method :__transactions_index_test_original_index__
      end

      if method_defined?(:__transactions_index_test_original_load_index_state__)
        alias_method :load_index_state!, :__transactions_index_test_original_load_index_state__
        remove_method :__transactions_index_test_original_load_index_state__
      end

      if method_defined?(:__transactions_index_test_original_load_sidebar_payload__)
        alias_method :load_sidebar_transaction_payload, :__transactions_index_test_original_load_sidebar_payload__
        remove_method :__transactions_index_test_original_load_sidebar_payload__
      end

      remove_method :__transactions_index_test_rows__ if method_defined?(:__transactions_index_test_rows__)
    end
  end

  def modern_headers
    { "User-Agent" => MODERN_USER_AGENT }
  end
end
