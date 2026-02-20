class TransactionsController < ApplicationController
  ROUTE_CUE_ORDER = %w[outbound inbound team_to_team internal entry exit unmapped].freeze
  ROUTE_CUE_LABELS = {
    "outbound" => "Outbound",
    "inbound" => "Inbound",
    "team_to_team" => "Team→team",
    "internal" => "In-place",
    "entry" => "Entry",
    "exit" => "Exit",
    "unmapped" => "Unmapped"
  }.freeze
  SEVERITY_RULE_CUES = {
    "critical" => "Dead-money rows or max Δ ≥ $20M / apron Δ ≥ $8M",
    "high" => "Exception usage or max Δ ≥ $10M / apron Δ ≥ $4M",
    "medium" => "Ledger movement or max Δ ≥ $2M",
    "low" => "Low/no immediate financial movement"
  }.freeze

  # GET /transactions
  def index
    load_index_state!
    render :index
  end

  # GET /transactions/pane (Datastar partial refresh)
  def pane
    load_index_state!
    render partial: "transactions/results"
  end

  # GET /transactions/sidebar/base
  def sidebar_base
    load_index_state!
    render partial: "transactions/rightpanel_base"
  end

  # GET /transactions/sidebar/:id
  def sidebar
    transaction_id = Integer(params[:id])
    raise ActiveRecord::RecordNotFound if transaction_id <= 0

    render partial: "transactions/rightpanel_overlay_transaction", locals: load_sidebar_transaction_payload(transaction_id).merge(
      overlay_transaction_id: transaction_id.to_s
    )
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /transactions/sidebar/clear
  def sidebar_clear
    render partial: "transactions/rightpanel_clear"
  end

  # GET /transactions/:id
  def show
    id = Integer(params[:id])

    @transaction = queries.fetch_transaction(id)
    raise ActiveRecord::RecordNotFound unless @transaction

    @ledger_entries = queries.fetch_ledger_entries(id)
    @draft_selection = queries.fetch_draft_selection(id)

    @trade = nil
    @trade_transactions = []
    @endnotes = []

    if @transaction["trade_id"].present?
      trade_id = @transaction["trade_id"]
      @trade = queries.fetch_trade_summary(trade_id)
      @trade_transactions = queries.fetch_trade_transactions(trade_id)
      @endnotes = queries.fetch_endnotes(trade_id)
    end

    @cap_exception_usage_rows = queries.fetch_cap_exception_usage_rows(id)
    @cap_dead_money_rows = queries.fetch_cap_dead_money_rows(id)
    @cap_budget_snapshot_rows = queries.fetch_cap_budget_snapshot_rows(id)

    render :show
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def queries
    @queries ||= ::TransactionQueries.new(connection: ActiveRecord::Base.connection)
  end

  def load_index_state!
    state = ::Transactions::IndexWorkspaceState.new(
      params: params,
      queries: queries
    ).build

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end

    annotate_transaction_route_cues!(rows: @transactions, scoped_team_code: @team)
    build_transaction_scan_cues!
  end

  def load_sidebar_transaction_payload(transaction_id)
    transaction = queries.fetch_sidebar_transaction(transaction_id)
    raise ActiveRecord::RecordNotFound unless transaction

    ledger_summary = queries.fetch_sidebar_ledger_summary(transaction_id)
    artifact_summary = queries.fetch_sidebar_artifact_summary(transaction_id)

    trade_summary = if transaction["trade_id"].present?
      queries.fetch_sidebar_trade_summary(transaction["trade_id"])
    end

    {
      transaction:,
      ledger_summary:,
      artifact_summary:,
      trade_summary:
    }
  end

  def annotate_transaction_route_cues!(rows:, scoped_team_code:)
    normalized_scope_code = scoped_team_code.to_s.upcase.presence

    Array(rows).each do |row|
      cue = route_cue_for_transaction(row, scoped_team_code: normalized_scope_code)
      route_cue_payload = {
        key: cue[:key].to_s,
        label: cue[:label].to_s,
        detail: cue[:detail].to_s
      }

      row["route_cue"] = route_cue_payload
      row["route_cue_key"] = route_cue_payload[:key]
      row["route_cue_label"] = route_cue_payload[:label]
      row["route_cue_detail"] = route_cue_payload[:detail]
    end
  end

  def build_transaction_scan_cues!
    severity_lanes = resolved_transaction_severity_lanes
    route_scope_label = if @team.present?
      "#{@team} route perspective"
    else
      "League-wide route perspective"
    end

    route_summary_rows = summarize_route_cues(rows: @transactions)

    lane_scan_rows = severity_lanes.map do |lane|
      lane_rows = Array(lane[:date_groups]).flat_map { |group| Array(group[:rows]) }

      {
        key: lane[:key].to_s,
        headline: lane[:headline],
        row_count: lane[:row_count].to_i,
        rubric: severity_rule_rubric_for(lane[:key], fallback: lane[:subline]),
        route_cues: summarize_route_cues(rows: lane_rows).first(2)
      }
    end

    @transaction_results_payload = {
      severity_lanes: severity_lanes,
      lane_scan_rows: lane_scan_rows,
      route_summary_rows: route_summary_rows,
      route_scope_label: route_scope_label
    }

    # Keep existing ivars for compatibility with any sidebar/test code still reading them.
    @transaction_severity_lanes = severity_lanes
    @transaction_route_scope_label = route_scope_label
    @transaction_route_cues = route_summary_rows
    @transaction_lane_scan_rows = lane_scan_rows
  end

  def resolved_transaction_severity_lanes
    lanes = Array(@transaction_severity_lanes)
    return lanes if lanes.any?
    return [] if @transactions.blank?

    [{
      key: "all",
      headline: "All impact lanes",
      subline: nil,
      row_count: Array(@transactions).size,
      date_groups: Array(@transaction_date_groups)
    }]
  end

  def severity_rule_rubric_for(key, fallback: nil)
    SEVERITY_RULE_CUES[key.to_s] || fallback.to_s
  end

  def summarize_route_cues(rows:)
    counts = Hash.new(0)

    Array(rows).each do |row|
      cue_key = row["route_cue_key"].to_s.presence || "unmapped"
      counts[cue_key] += 1
    end

    counts.map do |cue_key, count|
      {
        key: cue_key,
        label: route_cue_label(cue_key),
        count: count.to_i
      }
    end.sort_by do |cue|
      [
        (ROUTE_CUE_ORDER.index(cue[:key]) || ROUTE_CUE_ORDER.length),
        -cue[:count].to_i,
        cue[:label]
      ]
    end
  end

  def route_cue_for_transaction(row, scoped_team_code:)
    from_code = row["from_team_code"].to_s.upcase.presence
    to_code = row["to_team_code"].to_s.upcase.presence

    if from_code.present? && to_code.present?
      if from_code == to_code
        return {
          key: "internal",
          label: route_cue_label("internal"),
          detail: "#{to_code} internal move"
        }
      end

      if scoped_team_code.present?
        if to_code == scoped_team_code
          return {
            key: "inbound",
            label: route_cue_label("inbound"),
            detail: "#{scoped_team_code} received from #{from_code}"
          }
        end

        if from_code == scoped_team_code
          return {
            key: "outbound",
            label: route_cue_label("outbound"),
            detail: "#{scoped_team_code} sent to #{to_code}"
          }
        end
      end

      return {
        key: "team_to_team",
        label: route_cue_label("team_to_team"),
        detail: "#{from_code} → #{to_code}"
      }
    end

    if to_code.present?
      return {
        key: scoped_team_code.present? && to_code == scoped_team_code ? "inbound" : "entry",
        label: route_cue_label(scoped_team_code.present? && to_code == scoped_team_code ? "inbound" : "entry"),
        detail: "→ #{to_code} (source team not tagged)"
      }
    end

    if from_code.present?
      return {
        key: scoped_team_code.present? && from_code == scoped_team_code ? "outbound" : "exit",
        label: route_cue_label(scoped_team_code.present? && from_code == scoped_team_code ? "outbound" : "exit"),
        detail: "#{from_code} → (destination not tagged)"
      }
    end

    {
      key: "unmapped",
      label: route_cue_label("unmapped"),
      detail: "No route teams tagged"
    }
  end

  def route_cue_label(cue_key)
    ROUTE_CUE_LABELS[cue_key.to_s] || ROUTE_CUE_LABELS["unmapped"]
  end

  def selected_overlay_visible?(overlay_type:, overlay_id:)
    return false unless overlay_type.to_s == "transaction"

    normalized_id = overlay_id.to_i
    return false if normalized_id <= 0

    Array(@transactions).any? { |row| row["transaction_id"].to_i == normalized_id }
  end
end
